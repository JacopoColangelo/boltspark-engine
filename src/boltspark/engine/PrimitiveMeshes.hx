package boltspark.engine;

/**
 * Built-in geometry assets. Primitive identity is independent of GameObject
 * and of any renderer instance: these are reusable, shared asset references.
 * Imported static meshes can be registered here later (GLTF/FBX/OBJ) without
 * changing MeshRenderer or the Inspector.
 */
class PrimitiveMeshes {
    public static inline var CUBE_ID:String = "primitive:cube";
    public static inline var SPHERE_ID:String = "primitive:sphere";
    public static inline var CYLINDER_ID:String = "primitive:cylinder";
    public static inline var CAPSULE_ID:String = "primitive:capsule";
    public static inline var PLANE_ID:String = "primitive:plane";

    static var cubeMesh:Null<Mesh>;
    static var sphereMesh:Null<Mesh>;
    static var cylinderMesh:Null<Mesh>;
    static var capsuleMesh:Null<Mesh>;
    static var planeMesh:Null<Mesh>;
    /** Future imported static meshes register here; no scene nodes are created. */
    static var registered:Array<Mesh> = [];
    static var registeredById:Map<String, Mesh> = new Map();

    public static function cube():Mesh {
        if (cubeMesh == null) cubeMesh = built(CUBE_ID, "Cube", "cube");
        return cubeMesh;
    }

    public static function sphere():Mesh {
        if (sphereMesh == null) sphereMesh = built(SPHERE_ID, "Sphere", "sphere");
        return sphereMesh;
    }

    public static function cylinder():Mesh {
        if (cylinderMesh == null) cylinderMesh = built(CYLINDER_ID, "Cylinder", "cylinder");
        return cylinderMesh;
    }

    public static function capsule():Mesh {
        if (capsuleMesh == null) capsuleMesh = built(CAPSULE_ID, "Capsule", "capsule");
        return capsuleMesh;
    }

    public static function plane():Mesh {
        if (planeMesh == null) planeMesh = built(PLANE_ID, "Plane", "plane");
        return planeMesh;
    }

    /**
     * Register a reusable mesh asset (e.g. a future GLTF/FBX/OBJ import).
     * The renderer factory and Inspector picker then see it like a built-in.
     */
    public static function register(mesh:Mesh):Void {
        if (mesh == null || mesh.id == null
                || StringTools.trim(mesh.id).length == 0) {
            throw "Mesh registration requires a mesh with an ID";
        }
        if (registeredById.exists(mesh.id)) {
            throw 'Duplicate mesh id ${mesh.id}';
        }
        registered.push(mesh);
        registeredById.set(mesh.id, mesh);
    }

    /** Drop all imported meshes (called before reloading a project's assets). */
    public static function clearRegistered():Void {
        registered.resize(0);
        registeredById = new Map();
    }

    /** Stable asset list for type-aware Inspector pickers. */
    public static function all():Array<Mesh> {
        var result = [cube(), sphere(), cylinder(), capsule(), plane()];
        for (mesh in registered) result.push(mesh);
        return result;
    }

    public static function find(id:String):Null<Mesh> {
        var registeredMatch = registeredById.get(id);
        if (registeredMatch != null) return registeredMatch;
        return switch (id) {
            case CUBE_ID, "cube", "Primitive Cube": cube();
            case SPHERE_ID, "sphere", "Primitive Sphere": sphere();
            case CYLINDER_ID, "cylinder", "Primitive Cylinder": cylinder();
            case CAPSULE_ID, "capsule", "Primitive Capsule": capsule();
            case PLANE_ID, "plane", "Primitive Plane": plane();
            default: null;
        };
    }

    /** Default geometry settings for a primitive (by asset id or alias). */
    public static function defaultSettings(primitiveId:String):PrimitiveSettings {
        var result = new PrimitiveSettings();
        switch (normalize(primitiveId)) {
            case "sphere":
                result.segments = 16;
                result.rings = 12;
            case "cylinder":
                result.segments = 16;
                result.radius = 0.5;
                result.height = 1;
                result.capped = true;
            case "capsule":
                result.segments = 12;
                result.radius = 0.5;
                result.height = 1;
            case "plane":
                result.width = 1;
                result.depth = 1;
            default: // cube
                result.width = 1;
                result.height = 1;
                result.depth = 1;
        }
        return result;
    }

    /** Inspector controls exposed by a primitive asset, in display order. */
    public static function parameters(primitiveId:String):Array<PrimitiveParameter> {
        return switch (normalize(primitiveId)) {
            case "sphere": [
                PrimitiveParameter.integer("segments", "Sides", 3, 64),
                PrimitiveParameter.integer("rings", "Rings", 3, 48),
                PrimitiveParameter.number("radius", "Radius", 0.01, 8)
            ];
            case "cylinder": [
                PrimitiveParameter.integer("segments", "Sides", 3, 64),
                PrimitiveParameter.number("radius", "Radius", 0.01, 8),
                PrimitiveParameter.number("height", "Height", 0.01, 16),
                PrimitiveParameter.boolean("capped", "Capped")
            ];
            case "capsule": [
                PrimitiveParameter.integer("segments", "Sides", 3, 48),
                PrimitiveParameter.number("radius", "Radius", 0.01, 8),
                PrimitiveParameter.number("height", "Height", 0.01, 16)
            ];
            case "plane": [
                PrimitiveParameter.number("width", "Width", 0.01, 16),
                PrimitiveParameter.number("depth", "Depth", 0.01, 16)
            ];
            default: [
                PrimitiveParameter.number("width", "Width", 0.01, 16),
                PrimitiveParameter.number("height", "Height", 0.01, 16),
                PrimitiveParameter.number("depth", "Depth", 0.01, 16)
            ];
        };
    }

    static inline function normalize(id:String):String {
        return id == null ? "" : StringTools.replace(id, "primitive:", "");
    }

    static inline function built(id:String, name:String, primitiveId:String):Mesh {
        return new Mesh(id, name, primitiveId);
    }
}
