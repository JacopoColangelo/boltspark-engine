package boltspark.editor;

/** Runtime selection snapshot restored by structural undo/redo commands. */
class EditorSelectionState {
    public final ids:Array<Int>;
    public final primaryId:Int;

    public function new(ids:Array<Int>, primaryId:Int) {
        this.ids = ids == null ? [] : ids.copy();
        this.primaryId = primaryId;
    }
}
