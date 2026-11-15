package boltspark.editor.commands;

import boltspark.editor.EditorObjectSnapshot;
import boltspark.editor.EditorSelectionState;
import boltspark.editor.EditorSession;
import boltspark.editor.IndexedEditorObjectSnapshot;

class CreateObjectCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final object:IndexedEditorObjectSnapshot;
    final selectionBefore:EditorSelectionState;
    final selectionAfter:EditorSelectionState;

    public function new(session:EditorSession, object:EditorObjectSnapshot,
            index:Int, selectionBefore:EditorSelectionState,
            selectionAfter:EditorSelectionState) {
        this.session = session;
        this.object = new IndexedEditorObjectSnapshot(index, object);
        this.selectionBefore = selectionBefore;
        this.selectionAfter = selectionAfter;
    }

    public function execute():Void {
        session.commandRestoreObjects([object], selectionAfter);
    }

    public function undo():Void {
        session.commandRemoveObjects([object.object.persistentId], selectionBefore);
    }

    inline function get_label():String return "Create " + object.object.name;
}
