package boltspark.editor;

/** Object snapshot paired with its hierarchy order for deletion undo. */
class IndexedEditorObjectSnapshot {
    public final index:Int;
    public final object:EditorObjectSnapshot;

    public function new(index:Int, object:EditorObjectSnapshot) {
        this.index = index;
        this.object = object;
    }
}
