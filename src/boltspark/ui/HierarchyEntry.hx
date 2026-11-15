package boltspark.ui;

import boltspark.editor.EditorObjectKind;

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
    public final kind:EditorObjectKind;

    public function new(id:Int, name:String, persistentId:String = "",
            parentId:Int = -1, depth:Int = 0, hasChildren:Bool = false,
            kind:EditorObjectKind = Cube, childCount:Int = 0,
            siblingIndex:Int = 0) {
        this.id = id;
        this.persistentId = persistentId;
        this.name = name;
        this.parentId = parentId;
        this.depth = depth;
        this.hasChildren = hasChildren;
        this.childCount = childCount;
        this.siblingIndex = siblingIndex;
        this.kind = kind;
    }
}
