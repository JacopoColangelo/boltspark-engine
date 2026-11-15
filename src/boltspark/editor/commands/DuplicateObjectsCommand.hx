package boltspark.editor.commands;

import boltspark.editor.EditorSelectionState;
import boltspark.editor.EditorSession;
import boltspark.editor.IndexedEditorObjectSnapshot;

/** Restores/removes a complete cloned forest as one history operation. */
class DuplicateObjectsCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final objects:Array<IndexedEditorObjectSnapshot>;
    final persistentIds:Array<String>;
    final selectionBefore:EditorSelectionState;
    final selectionAfter:EditorSelectionState;
    final description:String;

    public function new(session:EditorSession,
            objects:Array<IndexedEditorObjectSnapshot>,
            selectionBefore:EditorSelectionState,
            selectionAfter:EditorSelectionState,
            description:String = "Duplicate Objects") {
        if (objects == null || objects.length == 0) {
            throw "Duplicate command requires at least one object";
        }
        this.session = session;
        this.objects = objects.copy();
        this.selectionBefore = selectionBefore;
        this.selectionAfter = selectionAfter;
        this.description = description;
        persistentIds = [for (entry in objects) entry.object.persistentId];
    }

    public function execute():Void {
        session.commandRestoreObjects(objects, selectionAfter);
    }

    public function undo():Void {
        session.commandRemoveObjects(persistentIds, selectionBefore);
    }

    inline function get_label():String return description;
}
