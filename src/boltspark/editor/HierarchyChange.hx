package boltspark.editor;

/** Exact before/after state for one reparent or sibling-order operation. */
class HierarchyChange {
    public final persistentId:String;
    public final previousParentId:Null<String>;
    public final previousSiblingIndex:Int;
    public final newParentId:Null<String>;
    public final newSiblingIndex:Int;
    public final previousLocalTransform:EditorTransform;
    public final newLocalTransform:EditorTransform;

    public function new(persistentId:String,
            previousParentId:Null<String>, previousSiblingIndex:Int,
            newParentId:Null<String>, newSiblingIndex:Int,
            previousLocalTransform:EditorTransform,
            newLocalTransform:EditorTransform) {
        this.persistentId = persistentId;
        this.previousParentId = previousParentId;
        this.previousSiblingIndex = previousSiblingIndex;
        this.newParentId = newParentId;
        this.newSiblingIndex = newSiblingIndex;
        this.previousLocalTransform = previousLocalTransform.clone();
        this.newLocalTransform = newLocalTransform.clone();
    }
}
