package boltspark.editor.commands;

import boltspark.editor.EditorSelectionState;
import boltspark.editor.EditorSession;
import boltspark.editor.IndexedEditorObjectSnapshot;

class DeleteObjectsCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final objects:Array<IndexedEditorObjectSnapshot>;
    final persistentIds:Array<String>;
    final selectionBefore:EditorSelectionState;
    final selectionAfter:EditorSelectionState;

    public function new(session:EditorSession,
            objects:Array<IndexedEditorObjectSnapshot>,
            selectionBefore:EditorSelectionState,
            selectionAfter:EditorSelectionState) {
        this.session = session;
        this.objects = objects.copy();
        this.selectionBefore = selectionBefore;
        this.selectionAfter = selectionAfter;
        persistentIds = [for (entry in objects) entry.object.persistentId];
    }

    public function execute():Void {
        session.commandRemoveObjects(persistentIds, selectionAfter);
    }

    public function undo():Void {
        session.commandRestoreObjects(objects, selectionBefore);
    }

    function get_label():String {
        return objects.length == 1
            ? "Delete " + objects[0].object.name
            : 'Delete ${objects.length} Objects';
    }
}
