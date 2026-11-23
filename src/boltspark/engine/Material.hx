package boltspark.engine;

/** Lightweight assignable material definition applied to Heaps materials. */
class Material {
    /** Built-in ids follow the same `family:name` style as primitive meshes. */
    public static inline var DEFAULT_ID:String = "material:white";
    public static inline var ORANGE_ID:String = "material:orange";

    public final id:String;
    /** Mutable so a rename updates every live reference in place. */
    public var name:String;
    public var color:Int;
    public var shadows:Bool;
    public var culling:MaterialCulling;
    /** Optional albedo texture asset id (project-relative texture source). */
    public var albedoTexture:String;
    /** Project-relative source of a authored material document, "" for built-ins. */
    public var source:String;

    // Metallic/Smoothness PBR workflow (Unity Standard-style).
    public var metallic:Float;
    public var smoothness:Float;
    /** Where per-pixel smoothness comes from when a metallic map is bound:
     *  "metallicAlpha" (map alpha) or "albedoAlpha" (albedo alpha). */
    public var smoothnessSource:String;
    /** Metallic map: R = metallic, A = smoothness. "" for none. */
    public var metallicTexture:String;
    /** Tangent-space normal map. "" for none. */
    public var normalTexture:String;
    public var normalStrength:Float;
    /** Optional dedicated roughness map (G channel = roughness). Overrides
     *  the metallic/albedo smoothness source when assigned. "" for none. */
    public var roughnessTexture:String;
    /** Ambient occlusion map (R channel). "" for none. */
    public var occlusionTexture:String;
    public var occlusionStrength:Float;
    public var emissionColor:Int;
    public var emissionIntensity:Float;
    public var tilingX:Float;
    public var tilingY:Float;
    public var offsetX:Float;
    public var offsetY:Float;

    public static inline var SMOOTHNESS_METALLIC_ALPHA:String = "metallicAlpha";
    public static inline var SMOOTHNESS_ALBEDO_ALPHA:String = "albedoAlpha";

    static var sharedDefault:Null<Material>;
    static var sharedOrange:Null<Material>;
    static var registered:Array<Material> = [];
    /** Materials loaded from the current project's `type:"material"` records. */
    static var projectCatalog:Array<Material> = [];

    public function new(id:String, name:String, color:Int = 0xFFFFFF,
            shadows:Bool = false, culling:MaterialCulling = Back,
            ?albedoTexture:String, ?source:String) {
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
        this.culling = culling;
        this.albedoTexture = albedoTexture == null ? "" : albedoTexture;
        this.source = source == null ? "" : source;
        metallic = 0;
        smoothness = 0.5;
        smoothnessSource = SMOOTHNESS_METALLIC_ALPHA;
        metallicTexture = "";
        normalTexture = "";
        normalStrength = 1;
        roughnessTexture = "";
        occlusionTexture = "";
        occlusionStrength = 1;
        emissionColor = 0x000000;
        emissionIntensity = 1;
        tilingX = 1;
        tilingY = 1;
        offsetX = 0;
        offsetY = 0;
    }



    /** Neutral white default assigned to newly created primitives. */
    public static function defaultMaterial():Material {
        if (sharedDefault == null) {
            sharedDefault = new Material(DEFAULT_ID, "White Material",
                0xFFFFFF, false, Back);
        }
        return sharedDefault;
    }

    /** The original orange editor appearance, kept as a selectable asset. */
    public static function orangeMaterial():Material {
        if (sharedOrange == null) {
            sharedOrange = new Material(ORANGE_ID, "Orange Material",
                0xE58A3A, false, Back);
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
