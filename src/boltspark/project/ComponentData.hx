package boltspark.project;

/** Versioned generic component envelope; component payload schemas evolve separately. */
class ComponentData {
    public var type:String;
    public var version:Int;
    public var data:Dynamic;
    public var extraFields:Dynamic;

    public function new(type:String, version:Int = 1, ?data:Dynamic,
            ?extraFields:Dynamic) {
        this.type = type;
        this.version = version;
        this.data = data == null ? {} : data;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
