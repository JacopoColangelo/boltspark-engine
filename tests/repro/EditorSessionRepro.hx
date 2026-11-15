import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;

/** Headless create/delete/rename/transform integration over CommandHistory. */
class EditorSessionRepro {
    static function main():Void {
        var session = new EditorSession(32);
        var changes = 0;
        var observedUndoLabel:Null<String> = null;
        var observedRedoLabel:Null<String> = null;
        session.onChanged = function() {
            changes++;
            observedUndoLabel = session.history.undoLabel;
            observedRedoLabel = session.history.redoLabel;
        };

        var root = session.addInitialObject("sampleCube");
        session.selectObject(root.id);
        assertTrue(!session.history.canUndo, "initial object entered history");

        var created = session.createObject("Cube2", new EditorTransform(3, 0, 4));
        var createdPersistentId = created.persistentId;
        assertTrue(session.objects.length == 2
            && session.selectedObjectId == created.id
            && observedUndoLabel == "Create Cube2", "create command failed");
        assertTrue(session.undo() && session.objects.length == 1
            && session.selectedObjectId == root.id
            && observedRedoLabel == "Create Cube2", "create undo failed");
        assertTrue(session.redo() && session.objects.length == 2
            && session.findObject(created.id).persistentId == createdPersistentId,
            "create redo did not preserve identity");

        assertTrue(session.renameObject(created.id, "Gameplay Cube"),
            "rename command was not recorded");
        assertTrue(session.findObject(created.id).name == "Gameplay Cube",
            "rename execute failed");
        assertTrue(session.undo() && session.findObject(created.id).name == "Cube2",
            "rename undo failed");
        assertTrue(session.redo()
            && session.findObject(created.id).name == "Gameplay Cube",
            "rename redo failed");

        var before = session.findObject(created.id).transform.clone();
        var after = before.clone();
        after.positionX = 12.5;
        after.rotationY = 0.382683432;
        after.rotationW = 0.923879533;
        after.rotationHintY = 45;
        after.rotationHintValid = true;
        after.scaleX = -2;
        assertTrue(session.commitAppliedTransform(created.id, before, after,
            "Transform Gameplay Cube"), "transform command was not recorded");
        assertTrue(session.findObject(created.id).transform.sameAs(after),
            "transform execute failed");
        assertTrue(session.undo()
            && session.findObject(created.id).transform.sameAs(before),
            "transform undo failed");
        assertTrue(session.redo()
            && session.findObject(created.id).transform.sameAs(after),
            "transform redo failed");

        session.selectObjects([root.id, created.id], created.id);
        var deletedNames = session.deleteObjects([created.id]);
        assertTrue(deletedNames.length == 1 && session.objects.length == 1
            && session.selectedObjectId == root.id, "delete execute failed");
        assertTrue(session.undo() && session.objects.length == 2
            && session.objects[1].persistentId == createdPersistentId
            && session.selectedObjectIds.length == 2
            && session.selectedObjectId == created.id,
            "delete undo did not restore order/selection/identity");
        assertTrue(session.redo() && session.findObject(created.id) == null,
            "delete redo failed");

        assertTrue(changes >= 12, "session did not publish model changes");
        Sys.println("[editor-session] create, delete, rename, transform, selection, undo, and redo passed");
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
