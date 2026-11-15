package boltspark.engine;

/** Renderer-independent assignable geometry asset identity. */
class Mesh {
    public final id:String;
    public final name:String;
    public final primitiveId:Null<String>;

    public function new(id:String, name:String, ?primitiveId:String) {
        if (id == null || StringTools.trim(id).length == 0) {
            throw "Mesh ID cannot be empty";
        }
        if (name == null || StringTools.trim(name).length == 0) {
            throw "Mesh name cannot be empty";
        }
        this.id = id;
        this.name = name;
        this.primitiveId = primitiveId;
    }
}
