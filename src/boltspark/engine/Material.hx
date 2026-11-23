package boltspark.engine;

/** Lightweight assignable material definition applied to Heaps materials. */
class Material {
    /** Built-in ids follow the same `family:name` style as primitive meshes. */
    public static inline var DEFAULT_ID:String = "material:white";
    public static inline var ORANGE_ID:String = "material:orange";

    public final id:String;
    public final name:String;
    public var color:Int;
    public var shadows:Bool;
    public var specularAmount:Float;
    public var specularPower:Float;
    public var culling:MaterialCulling;
    /** Optional albedo texture asset id (project-relative texture source). */
    public var albedoTexture:String;
    /** Project-relative source of a authored material document, "" for built-ins. */
    public var source:String;

    static var sharedDefault:Null<Material>;
    static var sharedOrange:Null<Material>;
    static var registered:Array<Material> = [];
    /** Materials loaded from the current project's `type:"material"` records. */
    static var projectCatalog:Array<Material> = [];

    public function new(id:String, name:String, color:Int = 0xFFFFFF,
            shadows:Bool = false, specularAmount:Float = 0.18,
            specularPower:Float = 24,
            culling:MaterialCulling = Back, ?albedoTexture:String, ?source:String) {
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
        this.albedoTexture = albedoTexture == null ? "" : albedoTexture;
        this.source = source == null ? "" : source;
    }

    /** Neutral white default assigned to newly created primitives. */
    public static function defaultMaterial():Material {
        if (sharedDefault == null) {
            sharedDefault = new Material(DEFAULT_ID, "White Material",
                0xFFFFFF, false, 0.18, 24, Back);
        }
        return sharedDefault;
    }

    /** The original orange editor appearance, kept as a selectable asset. */
    public static function orangeMaterial():Material {
        if (sharedOrange == null) {
            sharedOrange = new Material(ORANGE_ID, "Orange Material",
                0xE58A3A, false, 0.18, 24, Back);
        }
        return sharedOrange;
    }

    /**
     * Register an additional reusable material asset. Both built-ins are
     * always available and returned first by `all()`.
     */
    public static function register(material:Material):Void {
        if (material == null || material.id == null
                || StringTools.trim(material.id).length == 0) {
            throw "Material registration requires a material with an ID";
        }
        if (material.id == DEFAULT_ID || material.id == ORANGE_ID) return;
        for (existing in registered) {
            if (existing.id == material.id) {
                throw 'Duplicate material id ${material.id}';
            }
        }
        registered.push(material);
    }

    /** Replace the project-authored materials (called on project load/close). */
    public static function setProjectMaterials(list:Array<Material>):Void {
        projectCatalog = list == null ? [] : list.copy();
    }

    public static function projectMaterials():Array<Material> {
        return projectCatalog.copy();
    }

    public static function findBySource(source:String):Null<Material> {
        if (source == null || source.length == 0) return null;
        for (material in projectCatalog) {
            if (material.source == source) return material;
        }
        return null;
    }

    /** Stable asset list for type-aware Inspector pickers. */
    public static function all():Array<Material> {
        var result = [defaultMaterial(), orangeMaterial()];
        for (material in registered) {
            if (material.id != DEFAULT_ID && material.id != ORANGE_ID) {
                result.push(material);
            }
        }
        for (material in projectCatalog) result.push(material);
        return result;
    }

    public static function find(id:String):Null<Material> {
        if (id == null) return null;
        // Legacy scene/manifest ids keep resolving to the new default so old
        // projects do not lose their material reference.
        if (id == DEFAULT_ID || id == "default" || id == "White Material"
            || id == "Default Material") {
            return defaultMaterial();
        }
        if (id == ORANGE_ID || id == "Orange Material") return orangeMaterial();
        for (material in registered) {
            if (material.id == id) return material;
        }
        for (material in projectCatalog) {
            if (material.id == id) return material;
        }
        return null;
    }
}
