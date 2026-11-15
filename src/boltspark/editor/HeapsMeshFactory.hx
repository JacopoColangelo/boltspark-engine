package boltspark.editor;

import boltspark.engine.Mesh;
import boltspark.engine.PrimitiveMeshes;

/** Maps renderer-independent Mesh assets onto the existing Heaps primitives. */
class HeapsMeshFactory {
    static final factories:Map<String, Void->h3d.prim.Primitive> = [];
    static final cache:Map<String, h3d.prim.Primitive> = [];
    static var initialized:Bool = initializeBuiltIns();

    public static function register(meshId:String,
            factory:Void->h3d.prim.Primitive):Void {
        if (meshId == null || StringTools.trim(meshId).length == 0
                || factory == null) {
            throw "Heaps mesh registration requires an ID and factory";
        }
        factories.set(meshId, factory);
        cache.remove(meshId);
    }

    public static function resolve(mesh:Mesh):h3d.prim.Primitive {
        ensureInitialized();
        if (mesh == null) throw "Cannot resolve a null Mesh";
        var primitive = cache.get(mesh.id);
        if (primitive != null) return primitive;
        var factory = factories.get(mesh.id);
        if (factory == null) throw 'No Heaps primitive registered for Mesh ${mesh.id}';
        primitive = factory();
        cache.set(mesh.id, primitive);
        return primitive;
    }

    static function initializeBuiltIns():Bool {
        register(PrimitiveMeshes.CUBE_ID, function() {
            var primitive = new h3d.prim.Cube(1, 1, 1, true);
            primitive.addUVs();
            primitive.addNormals();
            return primitive;
        });
        return true;
    }

    static inline function ensureInitialized():Void {
        if (!initialized) throw "Heaps mesh factory initialization failed";
    }
}
