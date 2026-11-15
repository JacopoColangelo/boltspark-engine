package boltspark.editor;

/** Immutable-by-convention command snapshot of one editor object. */
class EditorObjectSnapshot {
    public final id:Int;
    public final persistentId:String;
    public final name:String;
    public final transform:EditorTransform;
    public final kind:EditorObjectKind;
    public final parentPersistentId:Null<String>;
    public final siblingIndex:Int;

    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform, kind:EditorObjectKind = Cube,
            ?parentPersistentId:String, siblingIndex:Int = 0) {
        this.id = id;
        this.persistentId = persistentId;
        this.name = name;
        this.transform = transform.clone();
        this.kind = kind;
        this.parentPersistentId = parentPersistentId;
        this.siblingIndex = siblingIndex;
    }

    public static function capture(object:EditorObject):EditorObjectSnapshot {
        return new EditorObjectSnapshot(object.id, object.persistentId,
            object.name, object.transform, object.kind,
            object.parent == null ? null : object.parent.persistentId,
            object.siblingIndex);
    }

    public function restore(?scene:EditorSession):EditorObject {
        return new EditorObject(id, persistentId, name, transform, kind, scene);
    }
}
