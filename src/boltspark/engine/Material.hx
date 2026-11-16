package boltspark.engine;

/** Lightweight assignable material definition applied to Heaps materials. */
class Material {
    public static inline var DEFAULT_ID:String = "default";

    public final id:String;
    public final name:String;
    public var color:Int;
    public var shadows:Bool;
    public var specularAmount:Float;
    public var specularPower:Float;
    public var culling:MaterialCulling;

    static var sharedDefault:Null<Material>;
    static var registered:Array<Material> = [];

    public function new(id:String, name:String, color:Int = 0xFFFFFF,
            shadows:Bool = false, specularAmount:Float = 0.18,
            specularPower:Float = 24,
            culling:MaterialCulling = Back) {
        if (id == null || StringTools.trim(id).length == 0) {
            throw "Material ID cannot be empty";
        }
        if (name == null || StringTools.trim(name).length == 0) {
            throw "Material name cannot be empty";
        }
        this.id = id;
        this.name = name;
        this.color = color;
        this.shadows = shadows;
        this.specularAmount = specularAmount;
        this.specularPower = specularPower;
        this.culling = culling;
    }

    /** Existing orange editor appearance, now represented as an asset. */
    public static function defaultMaterial():Material {
        if (sharedDefault == null) {
            sharedDefault = new Material(DEFAULT_ID, "Default Material",
                0xE58A3A, false, 0.18, 24, Back);
        }
        return sharedDefault;
    }

    /**
     * Register an additional reusable material asset. The Default Material is
     * always available and is returned first by `all()`.
     */
    public static function register(material:Material):Void {
        if (material == null || material.id == null
                || StringTools.trim(material.id).length == 0) {
            throw "Material registration requires a material with an ID";
        }
        if (material.id == DEFAULT_ID) return;
        for (existing in registered) {
            if (existing.id == material.id) {
                throw 'Duplicate material id ${material.id}';
            }
        }
        registered.push(material);
    }

    /** Stable asset list for type-aware Inspector pickers. */
    public static function all():Array<Material> {
        var result = [defaultMaterial()];
        for (material in registered) {
            if (material.id != DEFAULT_ID) result.push(material);
        }
        return result;
    }

    public static function find(id:String):Null<Material> {
        if (id == DEFAULT_ID || id == "Default Material") return defaultMaterial();
        for (material in registered) {
            if (material.id == id) return material;
        }
        return null;
    }

}
