package boltspark.editor;

import boltspark.editor.commands.CommandHistory;
import boltspark.editor.commands.CompositeCommand;
import boltspark.editor.commands.CreateObjectCommand;
import boltspark.editor.commands.DeleteObjectsCommand;
import boltspark.editor.commands.DuplicateObjectsCommand;
import boltspark.editor.commands.EditorCommand;
import boltspark.editor.commands.RenameObjectCommand;
import boltspark.editor.commands.ReparentObjectsCommand;
import boltspark.editor.commands.AddComponentCommand;
import boltspark.editor.commands.RemoveComponentCommand;
import boltspark.editor.commands.PrimitiveSettingsCommand;
import boltspark.editor.commands.TransformObjectCommand;
import boltspark.engine.Component;
import boltspark.engine.MeshRenderer;
import boltspark.engine.PrimitiveSettings;
import boltspark.engine.Transform;
import boltspark.project.StableId;

/** Renderer-independent owner of scene objects, hierarchy, selection, and history. */
class EditorSession {
    /** Registry order is stable for commands; hierarchy order lives in SceneHierarchy. */
    public final objects:Array<EditorObject> = [];
    public final selectedObjectIds:Array<Int> = [];
    public final history:CommandHistory;
    public final hierarchy:SceneHierarchy;
    public var selectedObjectId(default, null):Int = -1;
    public var onChanged:Null<Void->Void>;
    public var nextRuntimeId(get, never):Int;

    var nextObjectId:Int = 1;
    final objectsById:Map<Int, EditorObject> = [];
    final objectsByPersistentId:Map<String, EditorObject> = [];
    var clipboardObjects:Array<EditorObjectSnapshot> = [];
    var clipboardRootIds:Array<String> = [];

    public function new(historyCapacity:Int = 256) {
        history = new CommandHistory(historyCapacity);
        hierarchy = new SceneHierarchy(this);
    }

    public function addInitialObject(name:String, ?transform:EditorTransform,
            ?persistentId:String, ?components:Array<Component>,
            parentId:Int = -1, siblingIndex:Int = -1):EditorObject {
        // Resolve every fallible relationship before mutating the registry so
        // an invalid parent cannot leave an unreachable half-created object.
        var parent = parentId < 0 ? null : requireObject(parentId);
        var durableId = persistentId == null
            ? StableId.create("scene-object")
            : persistentId;
        if (findObjectByPersistentId(durableId) != null) {
            throw 'Duplicate editor object ID: ${durableId}';
        }
        var object = new EditorObject(nextObjectId, durableId,
            name, transform == null ? new EditorTransform() : transform,
            cloneComponents(components), this);
        nextObjectId++;
        registerObject(object, objects.length);
        var siblings = parent == null ? hierarchy.roots : parent.children;
        hierarchy.attach(object, parent,
            siblingIndex < 0 ? siblings.length : siblingIndex);
        notifyChanged();
        return object;
    }

    public function createObject(name:String, ?transform:EditorTransform,
            parentId:Int = -1, ?components:Array<Component>):EditorObject {
        var runtimeId = nextObjectId++;
        var parent = parentId < 0 ? null : requireObject(parentId);
        var siblings = parent == null ? hierarchy.roots : parent.children;
        var snapshot = new EditorObjectSnapshot(runtimeId,
            StableId.create("scene-object"), EditorObject.requireName(name),
            transform == null ? new EditorTransform() : transform,
            components, parent == null ? null : parent.persistentId, siblings.length);
        var before = captureSelection();
        var after = new EditorSelectionState([runtimeId], runtimeId);
        history.execute(new CreateObjectCommand(this, snapshot, objects.length,
            before, after));
        notifyChanged();
        return findObject(runtimeId);
    }

    public inline function createChild(parentId:Int, name:String,
            ?transform:EditorTransform,
            ?components:Array<Component>):EditorObject {
        return createObject(name, transform, parentId, components);
    }

    /**
     * Create one empty parent and move the canonicalized selection beneath it
     * as one undo entry. The selected objects keep their exact world matrices.
     */
    public function createEmptyParent(ids:Array<Int>,
            name:String = "GameObject"):Null<EditorObject> {
        var roots = selectedTopLevel(ids);
        if (roots.length == 0) return createObject(name);

        var commonParent = roots[0].parent;
        var sameParent = true;
        for (object in roots) {
            if (object.parent != commonParent) {
                sameParent = false;
                commonParent = null;
                break;
            }
        }
        var parentSiblings = commonParent == null
            ? hierarchy.roots : commonParent.children;
        var insertion = parentSiblings.length;
        if (sameParent) {
            insertion = roots[0].siblingIndex;
            for (object in roots) insertion = Std.int(Math.min(insertion, object.siblingIndex));
        }

        var runtimeId = nextObjectId++;
        var persistentId = StableId.create("scene-object");
        var parentTransform = new EditorTransform();
        // Create at the end first. Keeping the temporary parent after every
        // original sibling lets the reparent command restore sparse selections
        // at their exact old indices before the create command removes it.
        // A final hierarchy change puts the group at the requested display
        // position. This matters for selections such as B + D in A/B/C/D.
        var parentAppendIndex = parentSiblings.length;
        var parentSnapshot = new EditorObjectSnapshot(runtimeId, persistentId,
            EditorObject.requireName(name), parentTransform, [],
            commonParent == null ? null : commonParent.persistentId,
            parentAppendIndex);
        var selectionBefore = captureSelection();
        var create = new CreateObjectCommand(this, parentSnapshot, objects.length,
            selectionBefore, selectionBefore);

        var changes:Array<HierarchyChange> = [];
        for (index in 0...roots.length) {
            var object = roots[index];
            // An identity group under the same parent has exactly the child's
            // old local space; retain its authored quaternion/sign channels
            // instead of needlessly decomposing an equivalent matrix.
            var local = sameParent
                ? object.transform.clone()
                : EditorTransform.fromMatrix(
                    hierarchy.worldMatrix(object), object.transform.value);
            changes.push(new HierarchyChange(object.persistentId,
                object.parent == null ? null : object.parent.persistentId,
                object.siblingIndex, persistentId, index,
                object.transform.value, local));
        }
        var selectionAfter = new EditorSelectionState([runtimeId], runtimeId);
        var reparent = new ReparentObjectsCommand(this, changes,
            selectionBefore, selectionAfter, "Create Empty Parent");
        var commands:Array<EditorCommand> = [create, reparent];
        if (sameParent) {
            var parentIndexAfterGrouping = parentAppendIndex - roots.length;
            if (parentIndexAfterGrouping != insertion) {
                var parentId = commonParent == null
                    ? null : commonParent.persistentId;
                var placement = new HierarchyChange(persistentId,
                    parentId, parentIndexAfterGrouping,
                    parentId, insertion, parentTransform, parentTransform);
                commands.push(new ReparentObjectsCommand(this, [placement],
                    selectionAfter, selectionAfter, "Place Empty Parent"));
            }
        }
        history.execute(new CompositeCommand("Create Empty Parent", commands));
        notifyChanged();
        return findObject(runtimeId);
    }

    /** Execute one subtree deletion command and return the top-level names. */
    public function deleteObjects(ids:Array<Int>):Array<String> {
        var roots = selectedTopLevel(ids);
        var names = [for (object in roots) object.name];
        if (roots.length == 0) return names;

        var removed:Map<Int, Bool> = [];
        for (root in roots) {
            for (object in hierarchy.subtree(root)) removed.set(object.id, true);
        }
        var snapshots:Array<IndexedEditorObjectSnapshot> = [];
        for (index in 0...objects.length) {
            if (!removed.exists(objects[index].id)) continue;
            snapshots.push(new IndexedEditorObjectSnapshot(index,
                EditorObjectSnapshot.capture(objects[index])));
        }
        var remaining = [for (object in hierarchy.flatten())
            if (!removed.exists(object.id)) object.id];
        var primary = remaining.length == 0 ? -1 : remaining[remaining.length - 1];
        history.execute(new DeleteObjectsCommand(this, snapshots,
            captureSelection(), new EditorSelectionState(
                primary < 0 ? [] : [primary], primary)));
        notifyChanged();
        return names;
    }

    public function duplicateObjects(ids:Array<Int>):Array<EditorObject> {
        var roots = selectedTopLevel(ids);
        if (roots.length == 0) return [];
        var source:Array<EditorObjectSnapshot> = [];
        var rootIds:Array<String> = [];
        for (root in roots) {
            rootIds.push(root.persistentId);
            for (object in hierarchy.subtree(root)) {
                source.push(EditorObjectSnapshot.capture(object));
            }
        }
        return executeClone(source, rootIds, -2, "Duplicate Objects");
    }

    /** Copy complete selected subtrees into the session clipboard. */
    public function copyObjects(ids:Array<Int>):Bool {
        var roots = selectedTopLevel(ids);
        if (roots.length == 0) return false;
        clipboardObjects = [];
        clipboardRootIds = [];
        for (root in roots) {
            clipboardRootIds.push(root.persistentId);
            for (object in hierarchy.subtree(root)) {
                clipboardObjects.push(EditorObjectSnapshot.capture(object));
            }
        }
        return true;
    }

    /** Paste clipboard roots under `parentId`, or beside their originals. */
    public function pasteObjects(parentId:Int = -2):Array<EditorObject> {
        if (clipboardObjects.length == 0) return [];
        if (parentId >= 0) requireObject(parentId);
        return executeClone(clipboardObjects, clipboardRootIds,
            parentId, "Paste Objects");
    }

    /**
     * Reparent/reorder a canonicalized selection. `newSiblingIndex` is an
     * insertion position in the target's current child/root list.
     */
    public function reparentObjects(ids:Array<Int>, newParentId:Int,
            newSiblingIndex:Int, preserveWorld:Bool = true):Bool {
        var moved = selectedTopLevel(ids);
        if (moved.length == 0) return false;
        var newParent = newParentId < 0 ? null : requireObject(newParentId);
        for (object in moved) hierarchy.requireCanParent(object, newParent);

        var targetSiblings = newParent == null
            ? hierarchy.roots : newParent.children;
        var targetIndex = Std.int(Math.max(0,
            Math.min(newSiblingIndex, targetSiblings.length)));
        var removedBefore = 0;
        for (object in moved) {
            if (object.parent == newParent && object.siblingIndex < targetIndex) {
                removedBefore++;
            }
        }
        targetIndex -= removedBefore;

        var changes:Array<HierarchyChange> = [];
        for (index in 0...moved.length) {
            var object = moved[index];
            var after = preserveWorld && object.parent != newParent
                ? EditorTransform.fromMatrix(hierarchy.localMatrixForWorld(
                    object, hierarchy.worldMatrix(object), newParent), object.transform.value)
                : object.transform.clone();
            changes.push(new HierarchyChange(object.persistentId,
                object.parent == null ? null : object.parent.persistentId,
                object.siblingIndex,
                newParent == null ? null : newParent.persistentId,
                targetIndex + index, object.transform.value, after));
        }
        var changed = false;
        for (change in changes) {
            if (change.previousParentId != change.newParentId
                    || change.previousSiblingIndex != change.newSiblingIndex
                    || !change.previousLocalTransform.sameAs(change.newLocalTransform)) {
                changed = true;
                break;
            }
        }
        if (!changed) return false;

        var idsAfter = [for (object in moved) object.id];
        var primary = idsAfter.indexOf(selectedObjectId) >= 0
            ? selectedObjectId : idsAfter[idsAfter.length - 1];
        var label = newParent == null ? "Move Objects to Root"
            : 'Parent Objects to ${newParent.name}';
        history.execute(new ReparentObjectsCommand(this, changes,
            captureSelection(), new EditorSelectionState(idsAfter, primary), label));
        notifyChanged();
        return true;
    }

    public function unparentObjects(ids:Array<Int>,
            preserveWorld:Bool = true):Bool {
        var nested:Array<Int> = [];
        if (ids != null) {
            for (id in ids) {
                var object = findObject(id);
                if (object != null && object.parent != null
                        && nested.indexOf(id) < 0) nested.push(id);
            }
        }
        if (nested.length == 0) return false;
        return reparentObjects(nested, -1, hierarchy.roots.length, preserveWorld);
    }

    public function canReparentObjects(ids:Array<Int>, newParentId:Int):Bool {
        var moved = selectedTopLevel(ids);
        if (moved.length == 0) return false;
        var newParent = newParentId < 0 ? null : findObject(newParentId);
        if (newParentId >= 0 && newParent == null) return false;
        for (object in moved) if (!hierarchy.canParent(object, newParent)) return false;
        return true;
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

    /** Set an object's local transform through history. */
    public function transformObject(id:Int, after:EditorTransform,
            description:String):Bool {
        var object = findObject(id);
        if (object == null) return false;
        return commitAppliedTransform(id, object.transform.value, after, description);
    }

    /** Set an object's world transform, deriving an exact local affine transform. */
    public function transformWorldObject(id:Int, world:EditorTransform,
            description:String):Bool {
        var object = findObject(id);
        if (object == null || world == null) return false;
        var local = hierarchy.localTransformForWorld(object, world, object.parent);
        return commitAppliedTransform(id, object.transform.value, local, description);
    }

    /** Attach a component through command history. */
    public function addComponent(id:Int, component:Component):Bool {
        var object = findObject(id);
        if (object == null || component == null
                || Std.isOfType(component, Transform)) return false;
        history.execute(new AddComponentCommand(this, object.persistentId,
            object.components.length, component));
        notifyChanged();
        return true;
    }

    /** Remove a non-Transform component through command history. */
    public function removeComponentAt(id:Int, componentIndex:Int):Bool {
        var object = findObject(id);
        if (object == null || componentIndex <= 0
                || componentIndex >= object.components.length) return false;
        history.execute(new RemoveComponentCommand(this, object.persistentId,
            componentIndex, object.components[componentIndex]));
        notifyChanged();
        return true;
    }

    /** Publish an already-validated custom component property edit. */
    public function componentEdited(id:Int):Bool {
        if (findObject(id) == null) return false;
        notifyChanged();
        return true;
    }

    public function commitAppliedTransform(id:Int, before:EditorTransform,
            after:EditorTransform, description:String):Bool {
        var object = findObject(id);
        if (object == null || before == null || after == null
                || before.sameAs(after)) return false;
        if (!after.isFiniteAndInvertible()) {
            throw 'Transform for ${object.persistentId} is singular or non-finite';
        }
        history.execute(new TransformObjectCommand(this, object.persistentId,
            before, after, description));
        notifyChanged();
        return true;
    }

    /**
     * Commit one shared transform gesture across several objects as a single
     * history entry. Arrays are parallel; no-op and invalid entries are
     * skipped so undo restores the exact prior state of every touched object.
     */
    public function commitAppliedTransforms(ids:Array<Int>,
            befores:Array<EditorTransform>, afters:Array<EditorTransform>,
            description:String):Bool {
        if (ids == null || befores == null || afters == null) return false;
        var commands:Array<EditorCommand> = [];
        for (index in 0...ids.length) {
            if (index >= befores.length || index >= afters.length) break;
            var object = findObject(ids[index]);
            var before = befores[index];
            var after = afters[index];
            if (object == null || before == null || after == null
                    || before.sameAs(after)) continue;
            if (!after.isFiniteAndInvertible()) {
                throw 'Transform for ${object.persistentId} is singular or non-finite';
            }
            commands.push(new TransformObjectCommand(this, object.persistentId,
                before, after, description));
        }
        if (commands.length == 0) return false;
        history.execute(commands.length == 1
            ? commands[0]
            : new CompositeCommand(description, commands));
        notifyChanged();
        return true;
    }

    /**
     * Undoable setter for one object's primitive settings. Used by
     * PrimitiveSettingsCommand for both execute and undo.
     */
    @:noCompletion public function commandPrimitiveSettings(
            persistentId:String, settings:PrimitiveSettings):Void {
        var renderer = requirePersistentObject(persistentId)
            .getComponent(MeshRenderer);
        if (renderer == null) {
            throw 'MeshRenderer for ${persistentId} is missing';
        }
        renderer.primitiveSettings = settings;
    }

    /**
     * Commit a validated primitive-settings edit as one history entry.
     * No-op when the values did not change.
     */
    public function commitPrimitiveSettings(id:Int, before:PrimitiveSettings,
            after:PrimitiveSettings, description:String):Bool {
        var object = findObject(id);
        if (object == null || before == null || after == null
                || object.getComponent(MeshRenderer) == null
                || before.sameAs(after)) return false;
        history.execute(new PrimitiveSettingsCommand(this, object.persistentId,
            before, after, description));
        notifyChanged();
        return true;
    }

    /**
     * Commit one shared settings gesture across several objects as a single
     * history entry, mirroring commitAppliedTransforms: arrays are parallel
     * and no-op or invalid entries are skipped.
     */
    public function commitAppliedPrimitiveSettings(ids:Array<Int>,
            befores:Array<PrimitiveSettings>, afters:Array<PrimitiveSettings>,
            description:String):Bool {
        if (ids == null || befores == null || afters == null) return false;
        var commands:Array<EditorCommand> = [];
        for (index in 0...ids.length) {
            if (index >= befores.length || index >= afters.length) break;
            var object = findObject(ids[index]);
            var before = befores[index];
            var after = afters[index];
            if (object == null || before == null || after == null
                    || object.getComponent(MeshRenderer) == null
                    || before.sameAs(after)) continue;
            commands.push(new PrimitiveSettingsCommand(this,
                object.persistentId, before, after, description));
        }
        if (commands.length == 0) return false;
        history.execute(commands.length == 1
            ? commands[0]
            : new CompositeCommand(description, commands));
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

    public function selectSubtree(id:Int):Void {
        var object = findObject(id);
        if (object == null) return;
        var ids = [for (entry in hierarchy.subtree(object)) entry.id];
        selectObjects(ids, id);
    }

    public function undo():Bool {
        if (!history.undo()) return false;
        hierarchy.validate();
        notifyChanged();
        return true;
    }

    public function redo():Bool {
        if (!history.redo()) return false;
        hierarchy.validate();
        notifyChanged();
        return true;
    }

    public function clearHistory():Void {
        history.clear();
        notifyChanged();
    }

    public inline function findObject(id:Int):Null<EditorObject> {
        return objectsById.get(id);
    }

    public inline function findObjectByPersistentId(id:String):Null<EditorObject> {
        return id == null ? null : objectsByPersistentId.get(id);
    }

    public function captureSelection():EditorSelectionState {
        return new EditorSelectionState(selectedObjectIds, selectedObjectId);
    }

    // Command implementation API. External callers use public operations so
    // every durable mutation enters history exactly once.
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
            var object = snapshot.restore(this);
            registerObject(object, entry.index);
            if (snapshot.id >= nextObjectId) nextObjectId = snapshot.id + 1;
        }

        // Parents now all exist. Insert in ascending sibling order so exact
        // indices are restored even when several adjacent objects return.
        var bySibling = snapshots.copy();
        bySibling.sort(function(a, b) {
            var parentA = a.object.parentPersistentId == null ? "" : a.object.parentPersistentId;
            var parentB = b.object.parentPersistentId == null ? "" : b.object.parentPersistentId;
            if (parentA < parentB) return -1;
            if (parentA > parentB) return 1;
            return a.object.siblingIndex - b.object.siblingIndex;
        });
        for (entry in bySibling) {
            var snapshot = entry.object;
            var object = requirePersistentObject(snapshot.persistentId);
            var parent = snapshot.parentPersistentId == null
                ? null : requirePersistentObject(snapshot.parentPersistentId);
            hierarchy.attach(object, parent, snapshot.siblingIndex);
        }
        hierarchy.validate();
        applySelection(selection);
    }

    @:noCompletion public function commandRemoveObjects(
            persistentIds:Array<String>, selection:EditorSelectionState):Void {
        var removing:Map<String, Bool> = [];
        for (id in persistentIds) removing.set(id, true);
        for (id in persistentIds) {
            var object = findObjectByPersistentId(id);
            if (object == null) continue;
            for (child in object.children) {
                if (!removing.exists(child.persistentId)) {
                    throw 'Cannot remove ${object.persistentId} without child ${child.persistentId}';
                }
            }
        }
        // Detach only forest roots; descendants remain internally linked until
        // all registry entries have been removed.
        for (id in persistentIds) {
            var object = findObjectByPersistentId(id);
            if (object != null && (object.parent == null
                    || !removing.exists(object.parent.persistentId))) {
                hierarchy.detach(object);
            }
        }
        var index = objects.length - 1;
        while (index >= 0) {
            var object = objects[index];
            if (removing.exists(object.persistentId)) {
                object.destroy();
                objects.splice(index, 1);
                objectsById.remove(object.id);
                objectsByPersistentId.remove(object.persistentId);
                object.hierarchySetParent(null);
                object.children.resize(0);
                object.hierarchySetScene(null);
            }
            index--;
        }
        hierarchy.validate();
        applySelection(selection);
    }

    @:noCompletion public function commandApplyHierarchyChanges(
            changes:Array<HierarchyChange>, useNewState:Bool,
            selection:EditorSelectionState):Void {
        var objectsToMove:Array<EditorObject> = [];
        var parents:Array<Null<EditorObject>> = [];
        for (change in changes) {
            var object = requirePersistentObject(change.persistentId);
            var parentId = useNewState ? change.newParentId : change.previousParentId;
            var parent = parentId == null ? null : requirePersistentObject(parentId);
            hierarchy.requireCanParent(object, parent);
            objectsToMove.push(object);
            parents.push(parent);
        }
        for (object in objectsToMove) hierarchy.detach(object);

        var order = [for (index in 0...changes.length) index];
        order.sort(function(a, b) {
            var parentA = useNewState ? changes[a].newParentId : changes[a].previousParentId;
            var parentB = useNewState ? changes[b].newParentId : changes[b].previousParentId;
            var keyA = parentA == null ? "" : parentA;
            var keyB = parentB == null ? "" : parentB;
            if (keyA < keyB) return -1;
            if (keyA > keyB) return 1;
            var indexA = useNewState
                ? changes[a].newSiblingIndex : changes[a].previousSiblingIndex;
            var indexB = useNewState
                ? changes[b].newSiblingIndex : changes[b].previousSiblingIndex;
            return indexA - indexB;
        });
        for (changeIndex in order) {
            var change = changes[changeIndex];
            var object = objectsToMove[changeIndex];
            object.transform.setValue(useNewState
                ? change.newLocalTransform : change.previousLocalTransform);
            hierarchy.attach(object, parents[changeIndex], useNewState
                ? change.newSiblingIndex : change.previousSiblingIndex);
        }
        hierarchy.validate();
        applySelection(selection);
    }

    @:noCompletion public function commandRenameObject(
            persistentId:String, name:String):Void {
        requirePersistentObject(persistentId).name = EditorObject.requireName(name);
    }

    @:noCompletion public function commandTransformObject(
            persistentId:String, transform:EditorTransform):Void {
        requirePersistentObject(persistentId).transform.setValue(transform);
    }

    @:noCompletion public function commandInsertComponent(
            persistentId:String, index:Int, component:Component):Void {
        requirePersistentObject(persistentId).insertComponent(component, index);
    }

    @:noCompletion public function commandRemoveComponent(
            persistentId:String, index:Int):Void {
        requirePersistentObject(persistentId).removeComponentAt(index);
    }

    function executeClone(source:Array<EditorObjectSnapshot>,
            rootIds:Array<String>, explicitParentId:Int,
            description:String):Array<EditorObject> {
        var oldToNew:Map<String, String> = [];
        var oldToRuntime:Map<String, Int> = [];
        for (snapshot in source) {
            oldToNew.set(snapshot.persistentId, StableId.create("scene-object"));
            oldToRuntime.set(snapshot.persistentId, nextObjectId++);
        }
        var rootSet:Map<String, Bool> = [];
        for (id in rootIds) rootSet.set(id, true);
        var explicitParent = explicitParentId >= 0
            ? requireObject(explicitParentId) : null;
        var appendCounts:Map<String, Int> = [];
        // Reserve both existing names and names assigned earlier in this clone
        // operation. The latter matters when several selected roots share a
        // name because none of the snapshots are restored until the complete
        // command has been assembled.
        var reservedNames:Map<String, Bool> = [];
        for (object in objects) reservedNames.set(object.name, true);
        var cloned:Array<IndexedEditorObjectSnapshot> = [];
        var clonedRootRuntimeIds:Array<Int> = [];
        for (snapshot in source) {
            var isRoot = rootSet.exists(snapshot.persistentId);
            var parentId:Null<String>;
            var siblingIndex:Int;
            if (!isRoot && snapshot.parentPersistentId != null
                    && oldToNew.exists(snapshot.parentPersistentId)) {
                parentId = oldToNew.get(snapshot.parentPersistentId);
                siblingIndex = snapshot.siblingIndex;
            } else {
                if (explicitParentId >= -1) {
                    parentId = explicitParent == null ? null : explicitParent.persistentId;
                } else {
                    parentId = snapshot.parentPersistentId != null
                            && findObjectByPersistentId(snapshot.parentPersistentId) != null
                        ? snapshot.parentPersistentId : null;
                }
                var parent = parentId == null ? null : findObjectByPersistentId(parentId);
                var key = parentId == null ? "<root>" : parentId;
                var offset = appendCounts.exists(key) ? appendCounts.get(key) : 0;
                var siblings = parent == null ? hierarchy.roots : parent.children;
                siblingIndex = siblings.length + offset;
                appendCounts.set(key, offset + 1);
            }
            var runtimeId = oldToRuntime.get(snapshot.persistentId);
            var cloneName = snapshot.name;
            if (isRoot) {
                cloneName = uniqueDuplicateName(snapshot.name, reservedNames);
                reservedNames.set(cloneName, true);
            }
            var clone = new EditorObjectSnapshot(runtimeId,
                oldToNew.get(snapshot.persistentId),
                cloneName,
                snapshot.transform, snapshot.components, parentId, siblingIndex);
            cloned.push(new IndexedEditorObjectSnapshot(objects.length + cloned.length,
                clone));
            if (isRoot) clonedRootRuntimeIds.push(runtimeId);
        }
        var primary = clonedRootRuntimeIds.length == 0 ? -1
            : clonedRootRuntimeIds[clonedRootRuntimeIds.length - 1];
        history.execute(new DuplicateObjectsCommand(this, cloned,
            captureSelection(), new EditorSelectionState(clonedRootRuntimeIds, primary),
            description));
        notifyChanged();
        return [for (id in clonedRootRuntimeIds) findObject(id)];
    }

    function uniqueDuplicateName(source:String,
            reservedNames:Map<String, Bool>):String {
        var base = source;
        var suffix = 1;
        var numberedSuffix = ~/^(.*) \(([1-9][0-9]*)\)$/;
        if (numberedSuffix.match(source)) {
            base = numberedSuffix.matched(1);
            var sourceSuffix = Std.parseInt(numberedSuffix.matched(2));
            if (sourceSuffix != null) suffix = sourceSuffix + 1;
        }

        var candidate = base + " (" + suffix + ")";
        while (reservedNames.exists(candidate)) {
            suffix++;
            candidate = base + " (" + suffix + ")";
        }
        return candidate;
    }

    function selectedTopLevel(ids:Array<Int>):Array<EditorObject> {
        var requested:Array<EditorObject> = [];
        if (ids != null) {
            for (id in ids) {
                var object = findObject(id);
                if (object != null && requested.indexOf(object) < 0) requested.push(object);
            }
        }
        return hierarchy.topLevelSelection(requested);
    }

    function registerObject(object:EditorObject, index:Int):Void {
        if (findObject(object.id) != null
                || findObjectByPersistentId(object.persistentId) != null) {
            throw 'Duplicate editor object ${object.persistentId}';
        }
        var target = Std.int(Math.max(0, Math.min(index, objects.length)));
        objects.insert(target, object);
        objectsById.set(object.id, object);
        objectsByPersistentId.set(object.persistentId, object);
        object.hierarchySetScene(this);
    }

    function requireObject(id:Int):EditorObject {
        var object = findObject(id);
        if (object == null) throw 'Editor object no longer exists: ${id}';
        return object;
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
                ? -1 : selectedObjectIds[selectedObjectIds.length - 1]);
    }

    inline function get_nextRuntimeId():Int return nextObjectId;

    /** Run attached component lifecycles from the engine frame loop. */
    public function update(dt:Float):Void {
        for (object in objects.copy()) object.update(dt);
    }

    /** Destroy all components when the owning application/session shuts down. */
    public function destroy():Void {
        for (object in objects.copy()) object.destroy();
        objects.resize(0);
        objectsById.clear();
        objectsByPersistentId.clear();
        hierarchy.roots.resize(0);
        applySelection(new EditorSelectionState([], -1));
        history.clear();
    }

    static function cloneComponents(source:Null<Array<Component>>):Array<Component> {
        if (source == null) return [];
        return [for (component in source) {
            if (Std.isOfType(component, Transform)) {
                throw "Transform is created automatically and cannot be supplied twice";
            }
            component.cloneComponent();
        }];
    }

    function notifyChanged():Void {
        if (onChanged != null) onChanged();
    }
}
