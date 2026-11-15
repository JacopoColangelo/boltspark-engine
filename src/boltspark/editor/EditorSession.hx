package boltspark.editor;

import boltspark.editor.commands.CommandHistory;
import boltspark.editor.commands.CreateObjectCommand;
import boltspark.editor.commands.DeleteObjectsCommand;
import boltspark.editor.commands.RenameObjectCommand;
import boltspark.editor.commands.TransformObjectCommand;
import boltspark.project.StableId;

/**
 * Renderer-independent editor session: objects, selection, and command history.
 * Main mirrors these models into Heaps scene objects; project open/save can map
 * the same models without depending on renderer state.
 */
class EditorSession {
    public final objects:Array<EditorObject> = [];
    public final selectedObjectIds:Array<Int> = [];
    public final history:CommandHistory;
    public var selectedObjectId(default, null):Int = -1;
    public var onChanged:Null<Void->Void>;
    public var nextRuntimeId(get, never):Int;

    var nextObjectId:Int = 1;

    public function new(historyCapacity:Int = 256) {
        history = new CommandHistory(historyCapacity);
    }

    public function addInitialObject(name:String, ?transform:EditorTransform,
            ?persistentId:String):EditorObject {
        var durableId = persistentId == null
            ? StableId.create("scene-object")
            : persistentId;
        if (findObjectByPersistentId(durableId) != null) {
            throw 'Duplicate editor object ID: ${durableId}';
        }
        var object = new EditorObject(nextObjectId++, durableId,
            name, transform == null ? new EditorTransform() : transform);
        objects.push(object);
        notifyChanged();
        return object;
    }

    public function createObject(name:String, ?transform:EditorTransform):EditorObject {
        var runtimeId = nextObjectId++;
        var snapshot = new EditorObjectSnapshot(runtimeId,
            StableId.create("scene-object"), EditorObject.requireName(name),
            transform == null ? new EditorTransform() : transform);
        var before = captureSelection();
        var after = new EditorSelectionState([runtimeId], runtimeId);
        history.execute(new CreateObjectCommand(this, snapshot, objects.length,
            before, after));
        notifyChanged();
        return findObject(runtimeId);
    }

    /** Execute one deletion command and return the names captured by it. */
    public function deleteObjects(ids:Array<Int>):Array<String> {
        var requested = ids == null ? [] : ids;
        var snapshots:Array<IndexedEditorObjectSnapshot> = [];
        var names:Array<String> = [];
        for (index in 0...objects.length) {
            var object = objects[index];
            if (requested.indexOf(object.id) < 0) continue;
            snapshots.push(new IndexedEditorObjectSnapshot(index,
                EditorObjectSnapshot.capture(object)));
            names.push(object.name);
        }
        if (snapshots.length == 0) return names;

        var removed:Map<Int, Bool> = [];
        for (entry in snapshots) removed.set(entry.object.id, true);
        var remaining = [for (object in objects) if (!removed.exists(object.id)) object.id];
        var primary = remaining.length == 0 ? -1 : remaining[remaining.length - 1];
        history.execute(new DeleteObjectsCommand(this, snapshots,
            captureSelection(), new EditorSelectionState(
                primary < 0 ? [] : [primary], primary)));
        notifyChanged();
        return names;
    }

    public function renameObject(id:Int, name:String):Bool {
        var object = findObject(id);
        if (object == null) return false;
        var normalized = EditorObject.requireName(name);
        if (object.name == normalized) return false;
        history.execute(new RenameObjectCommand(this, object.persistentId,
            object.name, normalized));
        notifyChanged();
        return true;
    }

    public function transformObject(id:Int, after:EditorTransform,
            description:String):Bool {
        var object = findObject(id);
        if (object == null) return false;
        return commitAppliedTransform(id, object.transform, after, description);
    }

    /**
     * Record a transform already previewed by the renderer. Executing the
     * command applies `after` to the model; undo restores the exact preview
     * start, including quaternion and Euler-hint state.
     */
    public function commitAppliedTransform(id:Int, before:EditorTransform,
            after:EditorTransform, description:String):Bool {
        var object = findObject(id);
        if (object == null || before == null || after == null
                || before.sameAs(after)) return false;
        history.execute(new TransformObjectCommand(this, object.persistentId,
            before, after, description));
        notifyChanged();
        return true;
    }

    public function selectObject(id:Int):Void {
        selectObjects(id < 0 ? [] : [id], id);
    }

    public function selectObjects(ids:Array<Int>, primaryId:Int):Void {
        applySelection(new EditorSelectionState(ids, primaryId));
        notifyChanged();
    }

    public function undo():Bool {
        if (!history.undo()) return false;
        notifyChanged();
        return true;
    }

    public function redo():Bool {
        if (!history.redo()) return false;
        notifyChanged();
        return true;
    }

    public function clearHistory():Void {
        history.clear();
        notifyChanged();
    }

    public function findObject(id:Int):Null<EditorObject> {
        for (object in objects) if (object.id == id) return object;
        return null;
    }

    public function findObjectByPersistentId(id:String):Null<EditorObject> {
        for (object in objects) if (object.persistentId == id) return object;
        return null;
    }

    public function captureSelection():EditorSelectionState {
        return new EditorSelectionState(selectedObjectIds, selectedObjectId);
    }

    // Command implementation API. Callers outside editor command classes
    // should use the public operations above so all mutations enter history.
    @:noCompletion public function commandRestoreObjects(
            snapshots:Array<IndexedEditorObjectSnapshot>,
            selection:EditorSelectionState):Void {
        var ordered = snapshots.copy();
        ordered.sort(function(a, b) return a.index - b.index);
        for (entry in ordered) {
            var snapshot = entry.object;
            if (findObject(snapshot.id) != null
                    || findObjectByPersistentId(snapshot.persistentId) != null) {
                throw 'Cannot restore duplicate editor object ${snapshot.persistentId}';
            }
            var index = Std.int(Math.max(0, Math.min(entry.index, objects.length)));
            objects.insert(index, snapshot.restore());
            if (snapshot.id >= nextObjectId) nextObjectId = snapshot.id + 1;
        }
        applySelection(selection);
    }

    @:noCompletion public function commandRemoveObjects(
            persistentIds:Array<String>, selection:EditorSelectionState):Void {
        var index = objects.length - 1;
        while (index >= 0) {
            if (persistentIds.indexOf(objects[index].persistentId) >= 0) {
                objects.splice(index, 1);
            }
            index--;
        }
        applySelection(selection);
    }

    @:noCompletion public function commandRenameObject(
            persistentId:String, name:String):Void {
        var object = requirePersistentObject(persistentId);
        object.name = EditorObject.requireName(name);
    }

    @:noCompletion public function commandTransformObject(
            persistentId:String, transform:EditorTransform):Void {
        var object = requirePersistentObject(persistentId);
        object.transform = transform.clone();
    }

    function requirePersistentObject(id:String):EditorObject {
        var object = findObjectByPersistentId(id);
        if (object == null) throw 'Editor object no longer exists: ${id}';
        return object;
    }

    function applySelection(selection:EditorSelectionState):Void {
        selectedObjectIds.resize(0);
        if (selection != null) {
            for (id in selection.ids) {
                if (selectedObjectIds.indexOf(id) >= 0 || findObject(id) == null) continue;
                selectedObjectIds.push(id);
            }
        }
        selectedObjectId = selection != null
            && selectedObjectIds.indexOf(selection.primaryId) >= 0
            ? selection.primaryId
            : (selectedObjectIds.length == 0
                ? -1
                : selectedObjectIds[selectedObjectIds.length - 1]);
    }

    inline function get_nextRuntimeId():Int return nextObjectId;

    function notifyChanged():Void {
        if (onChanged != null) onChanged();
    }
}
