package boltspark.editor;

import boltspark.project.StableId;

/** Pure editor object model owned by EditorSession, independent of Heaps. */
class EditorObject {
    public final id:Int;
    public final persistentId:String;
    public var name:String;
    public var transform:EditorTransform;

    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform) {
        if (id < 1) throw "Editor object runtime ID must be positive";
        this.id = id;
        this.persistentId = StableId.require(persistentId,
            "editorObject.persistentId");
        this.name = requireName(name);
        this.transform = transform == null ? new EditorTransform() : transform.clone();
    }

    public static function requireName(value:String):String {
        if (value == null) throw "Editor object name cannot be null";
        var normalized = StringTools.trim(value);
        if (normalized.length == 0) throw "Editor object name cannot be empty";
        return normalized;
    }
}
