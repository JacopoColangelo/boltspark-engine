package boltspark.project;

class SceneDocument {
    public static inline var SCHEMA_VERSION:Int = 1;

    public var version:Int;
    public var id:String;
    public var name:String;
    public final entities:Array<SceneEntityData>;
    public var extraFields:Dynamic;

    public function new(id:String, name:String, ?entities:Array<SceneEntityData>,
            ?extraFields:Dynamic) {
        version = SCHEMA_VERSION;
        this.id = id;
        this.name = name;
        this.entities = entities == null ? [] : entities;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
