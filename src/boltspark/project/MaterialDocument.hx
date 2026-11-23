package boltspark.project;

/** Versioned, project-authored material asset. Mirrors SceneDocument. */
class MaterialDocument {
    public static inline var SCHEMA_VERSION:Int = 1;

    public var version:Int;
    public var id:String;
    public var name:String;
    public var baseColor:Int;
    /** Project-relative source of an imported texture, or "" for none. */
    public var albedoTexture:String;
    public var specularAmount:Float;
    public var specularPower:Float;
    public var culling:String;
    public var shadows:Bool;
    public var extraFields:Dynamic;

    public function new(id:String, name:String, ?baseColor:Int,
            ?albedoTexture:String, ?specularAmount:Float, ?specularPower:Float,
            ?culling:String, ?shadows:Bool, ?extraFields:Dynamic) {
        version = SCHEMA_VERSION;
        this.id = id;
        this.name = name;
        this.baseColor = baseColor == null ? 0xFFFFFF : baseColor;
        this.albedoTexture = albedoTexture == null ? "" : albedoTexture;
        this.specularAmount = specularAmount == null ? 0.18 : specularAmount;
        this.specularPower = specularPower == null ? 24 : specularPower;
        this.culling = culling == null ? "back" : culling;
        this.shadows = shadows == null ? false : shadows;
        this.extraFields = extraFields == null ? {} : extraFields;
    }
}
