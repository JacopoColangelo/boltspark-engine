package boltspark.engine;

/**
 * Runtime-only GPU half of the material texture pipeline. Loads full-resolution
 * imported images as `h3d.mat.Texture` objects for material albedo slots.
 * Heaps' `toTexture()` installs its own realloc hook for DX12 device resets.
 */
class MaterialTextureBindings {
    static var cache:Map<String, h3d.mat.Texture> = new Map();

    public static function get(id:String):Null<h3d.mat.Texture> {
        if (id == null || id.length == 0) return null;
        var cached = cache.get(id);
        if (cached != null) return cached;
        var asset = MaterialTextureLibrary.find(id);
        if (asset == null) return null;
        var path = MaterialTextureLibrary.resolvePath != null
            ? MaterialTextureLibrary.resolvePath(asset.source) : asset.source;
        try {
            if (path == null || !sys.FileSystem.exists(path)) return null;
            var entry = new hxd.fs.BytesFileSystem.BytesFileEntry(
                path, sys.io.File.getBytes(path));
            var texture = new hxd.res.Image(entry).toTexture();
            texture.filter = h3d.mat.Data.Filter.Linear;
            // PBR slots share one tiling/offset transform and repeat by design.
            texture.wrap = h3d.mat.Data.Wrap.Repeat;
            texture.setName("materialTexture:" + id);
            cache.set(id, texture);
            Sys.println('[material-texture] loaded id=${id} source=${asset.source}');
            return texture;
        } catch (e:Dynamic) {
            Sys.println('[material-texture] decode failed id=${id} error=${Std.string(e)}');
            return null;
        }
    }

    public static function clear():Void {
        for (texture in cache) {
            try {
                texture.dispose();
            } catch (e:Dynamic) {}
        }
        cache = new Map();
    }
}
