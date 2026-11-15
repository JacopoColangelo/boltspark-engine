package boltspark.ui;

/** Immutable hierarchy-row projection derived directly from SceneHierarchy. */
class HierarchyEntry {
    public final id:Int;
    public final persistentId:String;
    public final name:String;
    public final parentId:Int;
    public final depth:Int;
    public final hasChildren:Bool;
    public final childCount:Int;
    public final siblingIndex:Int;
    public final renderable:Bool;

    public function new(id:Int, name:String, persistentId:String = "",
            parentId:Int = -1, depth:Int = 0, hasChildren:Bool = false,
            renderable:Bool = false, childCount:Int = 0,
            siblingIndex:Int = 0) {
        this.id = id;
        this.persistentId = persistentId;
        this.name = name;
        this.parentId = parentId;
        this.depth = depth;
        this.hasChildren = hasChildren;
        this.childCount = childCount;
        this.siblingIndex = siblingIndex;
        this.renderable = renderable;
    }
}
