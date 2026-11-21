package boltspark.thumbnails;

import h3d.mat.Data.MipMap;
import h3d.mat.Data.TextureFlags;
import h3d.mat.Texture;
import hxd.PixelFormat;
import hxd.Pixels;

/**
 * Runtime loader for offline-baked mesh thumbnails.
 *
 * This class never creates a 3D scene, camera, light, or offscreen target. It
 * only decodes PNG-compressed mip levels from a bundle, uploads them into one
 * `[MipMapped, ManualMipMapGen]` texture with Linear/trilinear filtering, and
 * wraps the texture in an `h2d.Tile`. Dragging the thumbnail-size slider then
 * picks the right pre-filtered level with no shimmer and no runtime 3D work.
 *
 * Bundles are produced by `ThumbnailBaker`. They are looked up by resource name
 * under `res/thumbnails/bundles/` (embedded with `hxd.Res.initEmbed()`), so a
 * missing cache is a simple null result that callers can fall back from.
 */
class ThumbnailLoader {
    static final cache:Map<String, h2d.Tile> = new Map();

    /**
     * Cached, resource-backed lookup. `cacheKey` identifies the asset in the UI
     * (e.g. `primitive:cube`); `resourceName` is the bundle file name without
     * its extension under `res/thumbnails/bundles/`. When omitted it is derived from
     * the cache key with `ThumbnailBaker.bundleResourceName()`.
     *
     * @return null when no bundle exists, so callers can keep a legacy fallback.
     */
    public static function get(cacheKey:String, ?resourceName:String):Null<h2d.Tile> {
        if (cacheKey == null) return null;
        var tile = cache.get(cacheKey);
        if (tile != null) return tile;
        var name = resourceName == null ? ThumbnailBaker.bundleResourceName(cacheKey) : resourceName;
        try {
            tile = fromResource(name);
        } catch (e:Dynamic) {
            return null;
        }
        if (tile != null) cache.set(cacheKey, tile);
        return tile;
    }

    /** Load one embedded bundle by its file name (without `.bundle`). */
    public static function fromResource(resourceName:String):h2d.Tile {
        var resource = hxd.Res.load("thumbnails/bundles/" + resourceName + ".bundle");
        return fromBytes(resource.entry.getBytes());
    }

    /** Load one bundle from an arbitrary on-disk path. */
    public static function fromFile(path:String):h2d.Tile {
        return fromBytes(sys.io.File.getBytes(path));
    }

    /**
     * Decode a bundle and upload every level into a trilinearly filtered
     * texture. Mip 0 is the 1024x1024 anti-aliased render; the remaining levels
     * were generated in linear premultiplied space by the baker.
     */
    public static function fromBytes(bytes:haxe.io.Bytes):h2d.Tile {
        var mips = decodeMips(bytes);
        var size = mips[0].width;
        var texture = new Texture(size, size,
            [TextureFlags.MipMapped, TextureFlags.ManualMipMapGen], RGBA);

        // Heaps only derives the full chain from the base size; a bundle may
        // legitimately carry fewer levels, so tell the driver the exact count.
        // This mirrors hxd.res.Image's own manual-mip loading path.
        @:privateAccess texture.customMipLevels = mips.length;

        texture.filter = h3d.mat.Data.Filter.Linear;
        texture.mipMap = MipMap.Linear;
        texture.wrap = h3d.mat.Data.Wrap.Clamp;
        texture.setName("thumbnailMips");

        uploadAll(texture, mips);

        // Keep the encoded bundle alive so a DX12 device reset can restore the
        // exact same pre-filtered levels instead of showing an empty texture.
        texture.realloc = function() {
            uploadAll(texture, decodeMips(bytes));
        };

        return h2d.Tile.fromTexture(texture);
    }

    /**
     * Pure CPU bundle decoder. Kept public so the mip data can be validated in
     * an interpreter test without needing a live `h3d.Engine`. The returned
     * array owns its `hxd.Pixels`; level 0 is first.
     */
    public static function decodeMips(bytes:haxe.io.Bytes):Array<Pixels> {
        if (bytes == null) throw "Thumbnail bundle is null";
        var input = new haxe.io.BytesInput(bytes);
        try {
            if (input.readInt32() != ThumbnailBaker.BUNDLE_MAGIC) {
                throw "Not a Boltspark thumbnail bundle";
            }
            var version = input.readInt32();
            if (version != ThumbnailBaker.BUNDLE_VERSION) {
                throw 'Unsupported thumbnail bundle version $version';
            }
            var keyLength = input.readInt32();
            if (keyLength < 0 || keyLength > 4096) {
                throw "Invalid thumbnail bundle key length";
            }
            input.readString(keyLength);
            var size = input.readInt32();
            var mipCount = input.readInt32();
            if (size <= 0 || mipCount <= 0 || mipCount > 16) {
                throw "Invalid thumbnail bundle layout";
            }

            var result:Array<Pixels> = [];
            for (mip in 0...mipCount) {
                var expected = size >> mip;
                if (expected == 0) expected = 1;
                var pngLength = input.readInt32();
                if (pngLength <= 0 || pngLength > bytes.length) {
                    throw "Invalid thumbnail mip size at level " + mip;
                }
                var pngBytes = input.read(pngLength);
                var pixels = decodePng(pngBytes, expected);
                if (pixels.width != expected || pixels.height != expected) {
                    pixels.dispose();
                    throw 'Thumbnail mip $mip size mismatch';
                }
                result.push(pixels);
            }
            return result;
        } catch (e:haxe.io.Eof) {
            throw "Truncated thumbnail bundle";
        }
    }

    /**
     * Drop every cached tile and release its texture. UI owners that keep their
     * own tile cache (for example `PrimitiveThumbnails`) should clear it too.
     */
    public static function clear():Void {
        for (tile in cache) {
            var texture = tile.getTexture();
            if (texture != null) texture.dispose();
        }
        cache.clear();
    }

    static function uploadAll(texture:Texture, mips:Array<Pixels>):Void {
        for (i in 0...mips.length) {
            texture.uploadPixels(mips[i], i);
            mips[i].dispose();
        }
    }

    static function decodePng(bytes:haxe.io.Bytes, expectedSize:Int):Pixels {
        var reader = new format.png.Reader(new haxe.io.BytesInput(bytes));
        reader.checkCRC = false;
        var data = reader.read();
        var header = format.png.Tools.getHeader(data);
        if (header.width != expectedSize || header.height != expectedSize) {
            throw 'Unexpected PNG size ${header.width}x${header.height}';
        }
        var bgra = haxe.io.Bytes.alloc(expectedSize * expectedSize * 4);
        format.png.Tools.extract32(data, bgra, false);
        var pixels = new Pixels(expectedSize, expectedSize, bgra, PixelFormat.BGRA);
        pixels.convert(RGBA);
        return pixels;
    }
}
