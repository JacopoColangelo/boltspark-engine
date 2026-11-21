package boltspark.engine;

/** Renderer-independent assignable geometry asset identity. */
class Mesh {
    public final id:String;
    public final name:String;
    public final primitiveId:Null<String>;
    /** Number of independent material slots this asset exposes. */
    public final materialSlots:Int;

    public function new(id:String, name:String, ?primitiveId:String,
            ?materialSlots:Int) {
        if (id == null || StringTools.trim(id).length == 0) {
            throw "Mesh ID cannot be empty";
        }
        if (name == null || StringTools.trim(name).length == 0) {
            throw "Mesh name cannot be empty";
        }
        this.id = id;
        this.name = name;
        this.primitiveId = primitiveId;
        this.materialSlots = materialSlots == null || materialSlots < 1
            ? 1 : materialSlots;
    }
}
