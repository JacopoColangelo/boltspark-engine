import boltspark.engine.TextureCache;
import haxe.io.Path;

/**
 * CPU-only coverage for the imported-texture decode path. This repro runs as
 * HashLink bytecode (not `--interp`) because Heaps' `hxd.res.Image` references
 * `h3d.mat.Texture`, which the Haxe interpreter cannot type-check. No engine
 * or GPU is created: only `getInfo()` is asserted, never `toTexture()`.
 */
class TextureCacheRepro {
    static var checks:Int = 0;

    static function main():Void {
        var root = Path.join([Sys.getCwd(), "bin", "test-results", "texture-cache-repro"]);
        if (!sys.FileSystem.exists(root)) sys.FileSystem.createDirectory(root);
        var path = Path.join([root, "Info Probe.png"]);
        writeTinyPng(path, 4, 2, 29);

        var info = TextureCache.info(path);
        assertTrue(info != null, "texture cache reads image headers headlessly");
        assertTrue(info.width == 4 && info.height == 2,
            "texture cache reports the real image dimensions");
        assertTrue(info.format == "PNG", "texture cache reports the decoded format");
        assertTrue(TextureCache.info(Path.join([root, "missing.png"])) == null,
            "texture cache returns null for a missing file");

        sys.io.File.saveContent(Path.join([root, "garbage.jpg"]), "not an image");
        assertTrue(TextureCache.info(Path.join([root, "garbage.jpg"])) == null,
            "texture cache rejects undecodable image bytes");
        Sys.println('[texture-cache-repro] all ${checks} checks passed');
    }

    static function assertTrue(condition:Bool, message:String):Void {
        checks++;
        if (!condition) throw 'TextureCacheRepro: ${message}';
    }

    static function writeTinyPng(path:String, width:Int, height:Int, seed:Int):Void {
        var bytes = haxe.io.Bytes.alloc(width * height * 4);
        for (index in 0...width * height) {
            bytes.set(index * 4, (index * 37 + seed) & 0xFF);
            bytes.set(index * 4 + 1, (index * 71 + seed) & 0xFF);
            bytes.set(index * 4 + 2, (index * 13 + seed) & 0xFF);
            bytes.set(index * 4 + 3, 0xFF);
        }
        var output = new haxe.io.BytesOutput();
        new format.png.Writer(output).write(format.png.Tools.build32BGRA(width, height, bytes));
        sys.io.File.saveBytes(path, output.getBytes());
    }
}
