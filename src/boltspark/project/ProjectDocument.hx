package boltspark.project;

class ProjectDocument {
    public static inline var SCHEMA_VERSION:Int = 1;

    public var version:Int;
    public var id:String;
    public var name:String;
    public var defaultSceneId:Null<String>;
    public final assets:Array<AssetRecord>;
    public var extraFields:Dynamic;

    public function new(id:String, name:String, ?defaultSceneId:String,
            ?assets:Array<AssetRecord>, ?extraFields:Dynamic) {
        version = SCHEMA_VERSION;
        this.id = id;
        this.name = name;
        this.defaultSceneId = defaultSceneId;
        this.assets = assets == null ? [] : assets;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
