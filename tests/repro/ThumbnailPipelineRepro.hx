import boltspark.thumbnails.ThumbnailBaker;
import boltspark.thumbnails.ThumbnailLoader;
import hxd.PixelFormat;
import hxd.Pixels;

/**
 * Headless coverage for the offline thumbnail pipeline's CPU half: halo-free
 * premultiplied mip generation and versioned PNG-bundle round-tripping. No GPU
 * context is required, so this runs under `--interp`.
 */
class ThumbnailPipelineRepro {
    static function main():Void {
        testChainSizes();
        testNoDarkHalos();
        testBundleRoundTrip();
        testBundleValidation();
        Sys.println("[thumbnail-pipeline] mip chain, halo-free filtering, "
            + "bundle round-trip and validation passed");
    }

    static function testChainSizes():Void {
        var base = Pixels.alloc(64, 64, PixelFormat.RGBA);
        var chain = ThumbnailBaker.generateMipChain(base, 7);
        assertTrue(chain.length == 7, "expected seven mip levels");
        var expected = [64, 32, 16, 8, 4, 2, 1];
        for (i in 0...chain.length) {
            assertTrue(chain[i].width == expected[i] && chain[i].height == expected[i],
                'bad mip size at level $i: ${chain[i].width}x${chain[i].height}');
        }
        base.dispose();
        for (level in chain) level.dispose();
    }

    static function testNoDarkHalos():Void {
        // Opaque green on the left, fully transparent black on the right.
        var base = Pixels.alloc(64, 64, PixelFormat.RGBA);
        for (y in 0...64) {
            for (x in 0...64) {
                var p = (x + y * 64) * 4;
                base.bytes.set(p, 0);
                base.bytes.set(p + 1, 255);
                base.bytes.set(p + 2, 0);
                base.bytes.set(p + 3, x < 31 ? 255 : 0);
            }
        }

        var chain = ThumbnailBaker.generateMipChain(base, 3);
        var edge = chain[1]; // 32x32; odd source edge straddles output x=15.
        var checked = 0;
        for (y in 0...edge.height) {
            var c = edge.getPixel(15, y);
            var a = (c >>> 24) & 0xFF;
            if (a <= 0 || a >= 255) continue;
            checked++;
            var r = c & 0xFF;
            var g = (c >>> 8) & 0xFF;
            var b = (c >>> 16) & 0xFF;
            // Straight-alpha storage must retain the source hue: averaging in
            // premultiplied linear space prevents the black side from darkening.
            assertTrue(r < 40 && g > 200 && b < 40,
                'dark halo at edge: alpha=$a rgba=($r,$g,$b,$a)');
        }
        assertTrue(checked > 0, "no partially covered edge pixels were produced");

        base.dispose();
        for (level in chain) level.dispose();
    }

    static function testBundleRoundTrip():Void {
        var base = Pixels.alloc(32, 32, PixelFormat.RGBA);
        for (y in 0...32) {
            for (x in 0...32) {
                var p = (x + y * 32) * 4;
                base.bytes.set(p, x * 8);
                base.bytes.set(p + 1, y * 8);
                base.bytes.set(p + 2, 128);
                base.bytes.set(p + 3, 255);
            }
        }
        var chain = ThumbnailBaker.generateMipChain(base, 6);
        var bytes = ThumbnailBaker.encodeBundle("primitive:test", chain);
        var decoded = ThumbnailLoader.decodeMips(bytes);
        assertTrue(decoded.length == chain.length, "bundle mip count changed");
        for (i in 0...chain.length) {
            assertTrue(decoded[i].width == chain[i].width, 'mip $i width changed');
            assertTrue(decoded[i].height == chain[i].height, 'mip $i height changed');
            var expected = chain[i].getPixel(0, 0);
            var actual = decoded[i].getPixel(0, 0);
            assertTrue(expected == actual,
                'mip $i pixel changed: ${StringTools.hex(expected, 8)} != ${StringTools.hex(actual, 8)}');
        }
        base.dispose();
        for (level in chain) level.dispose();
        for (level in decoded) level.dispose();
    }

    static function testBundleValidation():Void {
        var bad = haxe.io.Bytes.ofString("not a thumbnail bundle at all");
        var threw = false;
        try {
            ThumbnailLoader.decodeMips(bad);
        } catch (e:Dynamic) {
            threw = true;
        }
        assertTrue(threw, "invalid bundle was accepted");
    }

    static function assertTrue(condition:Bool, message:String):Void {
        if (!condition) throw "[thumbnail-pipeline] " + message;
    }
}
