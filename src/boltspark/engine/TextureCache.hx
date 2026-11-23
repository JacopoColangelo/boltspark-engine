package boltspark.engine;

import h3d.mat.Data.Filter;
import h3d.mat.Data.Wrap;
import h3d.mat.Texture;
import hxd.PixelFormat;
import hxd.Pixels;

/**
 * Runtime cache for imported texture thumbnails.
 *
 * Images are decoded through Heaps' own `hxd.res.Image` (PNG/JPG/TGA), then
 * downsampled on the CPU before upload so a grid of cards never allocates a
 * full-resolution GPU texture for a 4K photo. Tiles are keyed by absolute file
 * path; `clear()` releases them when the project changes. Each texture keeps a
 * `realloc` callback so a DX12 device reset restores the same thumbnail bytes.
 *
 * `info()` is deliberately CPU-only: it works in headless tests without a live
 * `h3d.Engine`, where `toTexture()` cannot run. It is exercised as HashLink
 * bytecode rather than through `--interp`, which cannot type-check Heaps' 3D
 * texture types.
 */
class TextureCache {
    /** Longest edge of an uploaded thumbnail, in pixels. */
    public static inline var MAX_THUMB_SIZE:Int = 256;

    static final cache:Map<String, h2d.Tile> = new Map();

    /** Header-level image metadata. Returns null for unreadable/unknown files. */
    public static function info(path:String):Null<TextureInfo> {
        if (path == null || !sys.FileSystem.exists(path)) return null;
        try {
            var entry = new hxd.fs.BytesFileSystem.BytesFileEntry(
                path, sys.io.File.getBytes(path));
            var imageInfo = new hxd.res.Image(entry).getInfo();
            if (imageInfo.width <= 0 || imageInfo.height <= 0) return null;
            return {
                width: imageInfo.width,
                height: imageInfo.height,
                format: imageInfo.dataFormat.getName()
            };
        } catch (_:Dynamic) {
            return null;
        }
    }

    /** Cached thumbnail tile for an on-disk image, or null when decoding fails. */
    public static function get(path:String):Null<h2d.Tile> {
        if (path == null) return null;
        var cached = cache.get(path);
        if (cached != null) return cached;
        try {
            var entry = new hxd.fs.BytesFileSystem.BytesFileEntry(
                path, sys.io.File.getBytes(path));
            var image = new hxd.res.Image(entry);
            var info = image.getInfo();
            if (info.width <= 0 || info.height <= 0) return null;
            var size = thumbnailSize(info.width, info.height);
            var source = image.getPixels(RGBA);
            var pixels = downsample(source, size.width, size.height);
            source.dispose();

            var texture = new Texture(size.width, size.height, [], RGBA);
            texture.filter = Filter.Linear;
            texture.wrap = Wrap.Clamp;
            texture.setName("textureThumb:" + path);
            texture.uploadPixels(pixels);
            texture.realloc = function() texture.uploadPixels(pixels);
            var tile = h2d.Tile.fromTexture(texture);
            cache.set(path, tile);
            Sys.println('[texture-cache] tile path=${path} '
                + 'source=${info.width}x${info.height} thumb=${size.width}x${size.height}');
            return tile;
        } catch (e:Dynamic) {
            Sys.println('[texture-cache] decode failed path=${path} error=${Std.string(e)}');
            return null;
        }
    }

    /** Drop every cached tile and release its GPU texture. */
    public static function clear():Void {
        for (tile in cache) {
            var texture = tile.getTexture();
            if (texture != null) texture.dispose();
        }
        cache.clear();
    }

    static function thumbnailSize(width:Int, height:Int):{width:Int, height:Int} {
        if (width <= MAX_THUMB_SIZE && height <= MAX_THUMB_SIZE) {
            return { width: width, height: height };
        }
        var scale = MAX_THUMB_SIZE / Math.max(width, height);
        return {
            width: Std.int(Math.max(1, width * scale)),
            height: Std.int(Math.max(1, height * scale))
        };
    }

    /** Nearest-neighbour box sampling; avoids allocating a full-size copy. */
    static function downsample(source:Pixels, width:Int, height:Int):Pixels {
        if (source.width == width && source.height == height) {
            var copy = Pixels.alloc(width, height, RGBA);
            copy.bytes.blit(0, source.bytes, 0, width * height * 4);
            return copy;
        }
        var result = Pixels.alloc(width, height, RGBA);
        for (y in 0...height) {
            var sourceY = Std.int((y + 0.5) * source.height / height);
            if (sourceY >= source.height) sourceY = source.height - 1;
            for (x in 0...width) {
                var sourceX = Std.int((x + 0.5) * source.width / width);
                if (sourceX >= source.width) sourceX = source.width - 1;
                result.setPixel(x, y, source.getPixel(sourceX, sourceY));
            }
        }
        return result;
    }
}

/** Pure-CPU image description used by headless checks and diagnostics. */
typedef TextureInfo = {
    var width:Int;
    var height:Int;
    /** "PNG", "JPG", "TGA", ... as reported by Heaps. */
    var format:String;
};
