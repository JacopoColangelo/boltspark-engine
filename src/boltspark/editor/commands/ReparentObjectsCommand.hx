package boltspark.editor.commands;

import boltspark.editor.EditorSelectionState;
import boltspark.editor.EditorSession;
import boltspark.editor.HierarchyChange;

/** One deterministic hierarchy move, including multi-object drag/drop. */
class ReparentObjectsCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final changes:Array<HierarchyChange>;
    final selectionBefore:EditorSelectionState;
    final selectionAfter:EditorSelectionState;
    final description:String;

    public function new(session:EditorSession, changes:Array<HierarchyChange>,
            selectionBefore:EditorSelectionState,
            selectionAfter:EditorSelectionState,
            description:String) {
        if (changes == null || changes.length == 0) {
            throw "Reparent command requires at least one object";
        }
        this.session = session;
        this.changes = changes.copy();
        this.selectionBefore = selectionBefore;
        this.selectionAfter = selectionAfter;
        this.description = description;
    }

    public function execute():Void {
        session.commandApplyHierarchyChanges(changes, true, selectionAfter);
    }

    public function undo():Void {
        session.commandApplyHierarchyChanges(changes, false, selectionBefore);
    }

    inline function get_label():String return description;
}
