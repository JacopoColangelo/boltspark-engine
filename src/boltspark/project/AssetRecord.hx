package boltspark.project;

class AssetRecord {
    public var id:String;
    public var type:String;
    public var source:String;
    public var importSettings:Dynamic;
    public var extraFields:Dynamic;

    public function new(id:String, type:String, source:String,
            ?importSettings:Dynamic, ?extraFields:Dynamic) {
        this.id = id;
        this.type = type;
        this.source = source;
        this.importSettings = importSettings == null ? {} : importSettings;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
