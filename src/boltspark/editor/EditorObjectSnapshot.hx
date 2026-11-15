package boltspark.editor;

/** Immutable-by-convention command snapshot of one editor object. */
class EditorObjectSnapshot {
    public final id:Int;
    public final persistentId:String;
    public final name:String;
    public final transform:EditorTransform;

    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform) {
        this.id = id;
        this.persistentId = persistentId;
        this.name = name;
        this.transform = transform.clone();
    }

    public static function capture(object:EditorObject):EditorObjectSnapshot {
        return new EditorObjectSnapshot(object.id, object.persistentId,
            object.name, object.transform);
    }

    public function restore():EditorObject {
        return new EditorObject(id, persistentId, name, transform);
    }
}
