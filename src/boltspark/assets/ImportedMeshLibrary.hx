package boltspark.assets;

import haxe.crypto.Sha256;

/**
 * Parses project mesh documents into renderer-independent geometry. GPU/engine
 * registration is injected by `ImportedMeshBinding` at startup, so this module
 * (and ProjectSession which calls it) stays headless-testable.
 */
class ImportedMeshLibrary {
    /**
     * Stable mesh id derived from a project-relative source. Hashing keeps the
     * id short enough for Inspector/picker rows while remaining deterministic
     * across save/load, unlike a random StableId.
     */
    public static function idFor(source:String):String {
        var normalized = source.split("\\").join("/");
        return "mesh:" + Sha256.encode(normalized).substr(0, 16);
    }

    static var geometries:Map<String, MeshGeometry> = new Map();

    /** Called once per parsed mesh at runtime (registers with the engine). */
    public static var onRegister:Null<String->MeshGeometry->Void> = null;
    /** Called before a refresh or on clear to drop stale engine registrations. */
    public static var onClear:Null<Void->Void> = null;

    /**
     * Rebuild the parsed mesh catalog. `entries` is (asset id, source) pairs and
     * `resolvePath` maps a project-relative source to an absolute path. Returns
     * the number of meshes that parsed successfully.
     */
    public static function refresh(
            entries:Array<{ id:String, source:String }>,
            resolvePath:String->String):Int {
        geometries = new Map();
        if (onClear != null) onClear();
        var loaded = 0;
        for (entry in entries) {
            var path = resolvePath(entry.source);
            if (path == null || !sys.FileSystem.exists(path)) continue;
            try {
                var geometry = MeshParser.parse(path, new haxe.io.Path(entry.source).file);
                var id = idFor(entry.source);
                geometries.set(id, geometry);
                if (onRegister != null) onRegister(id, geometry);
                loaded++;
                Sys.println('[mesh-library] loaded source=${entry.source} '
                    + 'vertices=${Std.int(geometry.positions.length / 3)} '
                    + 'triangles=${Std.int(geometry.indices.length / 3)}');
            } catch (e:Dynamic) {
                Sys.println('[mesh-library] parse failed source=${entry.source} '
                    + 'error=${Std.string(e)}');
            }
        }
        return loaded;
    }

    public static function all():Array<MeshGeometry> {
        var result:Array<MeshGeometry> = [];
        for (geometry in geometries) result.push(geometry);
        return result;
    }

    public static function find(id:String):Null<MeshGeometry> return geometries.get(id);

    public static function clear():Void {
        geometries = new Map();
        if (onClear != null) onClear();
    }
}
