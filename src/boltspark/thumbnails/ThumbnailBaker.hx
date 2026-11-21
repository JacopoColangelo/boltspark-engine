package boltspark.thumbnails;

import boltspark.editor.HeapsMeshFactory;
import boltspark.engine.Mesh;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.PrimitiveSettings;
import h3d.mat.Data.TextureFlags;
import h3d.mat.Texture;
import hxd.PixelFormat;
import hxd.Pixels;

/**
 * Offline 3D mesh thumbnail baker for Boltspark's engine content.
 *
 * The baker is a BUILD-TIME tool only. It needs a live `h3d.Engine` (the
 * `BakeThumbnails` command supplies one through a tiny `hxd.App` host), but the
 * resulting bundles are self-contained: the game/editor never creates a 3D
 * scene, a light rig, or an offscreen target just to show a thumbnail.
 *
 * Anti-aliasing without MSAA (the DX12 backend cannot MSAA offscreen targets):
 *   1. The mesh is rendered into a 1024x1024 `[Target]` with a matching
 *      `Depth24Stencil8` buffer, using an isolated scene with a three-point
 *      studio rig, opposing bounce fills and a camera auto-framed from
 *      `mesh.getBounds()`. That is a 4x
 *      supersample relative to the ~256px the thumbnails are displayed at.
 *   2. A `h3d.pass.ScreenFx` 4x4 tent filter smooths diagonal silhouettes and
 *      specular highlights, then Heaps' FXAA pass removes the remaining edge
 *      stair-stepping. Both run at 1024x1024; no `multiSample` is used.
 *   3. The final target is read back with `Texture.capturePixels()`.
 *
 * The captured buffer is converted into a complete power-of-two mip chain.
 * Every downsample is performed in LINEAR light with PREMULTIPLIED alpha and
 * converted back to straight-alpha sRGB, which is what keeps transparent mesh
 * edges from acquiring dark halos. The chain is serialized as a versioned
 * bundle with PNG-compressed levels so it stays small enough to embed with
 * `hxd.Res.initEmbed()`.
 *
 * @see ThumbnailLoader for the runtime (zero-3D) side of the pipeline.
 */
class ThumbnailBaker {
    /** Edge length of the offscreen render target and of the base mip level. */
    public static inline var RESOLUTION:Int = 1024;

    /** Full chain: 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1. */
    public static inline var MIP_LEVELS:Int = 11;

    /** "BSMB" written as a little-endian Int32. */
    public static inline var BUNDLE_MAGIC:Int = 0x424D5342;
    public static inline var BUNDLE_VERSION:Int = 1;

    /** Mirrors boltspark.ui.Theme.CUBE_ORANGE, the default material swatch. */
    public static inline var DEFAULT_MATERIAL_COLOR:Int = 0xE58A3A;

    static final SRGB_TO_LINEAR:haxe.ds.Vector<Float> = buildSrgbToLinear();
    static final LINEAR_TO_SRGB:haxe.ds.Vector<Int> = buildLinearToSrgb();

    /**
     * Render and bake one engine mesh asset. `outputDirectory` is the folder
     * that receives `<bundleResourceName>.bundle`; it defaults to
     * `src/res/thumbnails/bundles` so the bundle is picked up by the embed
     * resource macro on the next build.
     *
     * @return the path of the written bundle.
     */
    public static function bakeMesh(mesh:Mesh, ?outputDirectory:String):String {
        return bakeMeshTinted(mesh, null, outputDirectory);
    }

    /**
     * Bake the default-material preview. It is a sphere rendered with the same
     * transparent offscreen path as the primitives, so the material card no
     * longer shows an opaque rectangle against the dark editor background.
     */
    public static function bakeDefaultMaterial(?outputDirectory:String):String {
        var path = bakeMeshTinted(PrimitiveMeshes.sphere(),
            DEFAULT_MATERIAL_COLOR, outputDirectory, "material");
        return path;
    }

    static function bakeMeshTinted(mesh:Mesh, tint:Null<Int>,
            ?outputDirectory:String, ?fileNameBase:String):String {
        if (mesh == null) throw "ThumbnailBaker.bakeMesh requires a Mesh";
        var base = renderMesh(mesh, tint);
        var mips = generateMipChain(base, MIP_LEVELS);
        var directory = outputDirectory == null ? defaultOutputDirectory() : outputDirectory;
        var baseName = fileNameBase == null ? bundleResourceName(mesh.id) : fileNameBase;
        var fileName = baseName + ".bundle";
        var path = haxe.io.Path.join([directory, fileName]);
        serialize(fileNameBase == null ? mesh.id : "material", mips, path);
        return path;
    }

    /** Bake every built-in primitive thumbnail in one bake-command run. */
    public static function bakeEngineContent(?outputDirectory:String):Array<String> {
        var report:Array<String> = [];
        for (id in [
            PrimitiveMeshes.CUBE_ID,
            PrimitiveMeshes.SPHERE_ID,
            PrimitiveMeshes.CYLINDER_ID,
            PrimitiveMeshes.CAPSULE_ID,
            PrimitiveMeshes.PLANE_ID
        ]) {
            report.push(id + " -> " + bakeMesh(PrimitiveMeshes.find(id), outputDirectory));
        }
        report.push("material -> " + bakeDefaultMaterial(outputDirectory));
        return report;
    }

    /**
     * Halo-free mip generator. Pure CPU work: it does not touch the GPU and is
     * safe to call from an interpreter/unit test. Input is converted to RGBA;
     * the returned array owns its pixels. Each level is half the size of the
     * previous one, clamped at 1x1.
     */
    public static function generateMipChain(base:Pixels, ?levelCount:Int):Array<Pixels> {
        if (base == null || base.width <= 0 || base.height <= 0) {
            throw "ThumbnailBaker.generateMipChain requires a non-empty Pixels buffer";
        }
        var src = base.clone();
        if (src.format != RGBA) src.convert(RGBA);
        var levels = MIP_LEVELS;
        if (levelCount != null && levelCount > 0) levels = levelCount;
        var result:Array<Pixels> = [src];

        var w = src.width;
        var h = src.height;
        var level = 1;
        while (level < levels && (w > 1 || h > 1)) {
            var nw = w > 1 ? w >> 1 : 1;
            var nh = h > 1 ? h >> 1 : 1;
            var dst = downsampleLinearPremultiplied(src, nw, nh);
            result.push(dst);
            src = dst;
            w = nw;
            h = nh;
            level++;
        }
        return result;
    }

    /**
     * Write a versioned bundle: magic/version, the mesh key, the base size and
     * then one length-prefixed PNG per mip level (largest first). Mips are
     * cloned before encoding because `Pixels.toPNG()` mutates its input.
     */
    public static function serialize(key:String, mips:Array<Pixels>, path:String):Void {
        if (path == null || StringTools.trim(path).length == 0) {
            throw "ThumbnailBaker.serialize requires an output path";
        }
        var bytes = encodeBundle(key, mips);
        var directory = haxe.io.Path.directory(path);
        if (directory != null && directory.length > 0 && !sys.FileSystem.exists(directory)) {
            sys.FileSystem.createDirectory(directory);
        }
        sys.io.File.saveBytes(path, bytes);
    }

    /**
     * In-memory version of `serialize`, exposed so the mip chain and bundle can
     * be validated without writing files or creating a GPU context.
     */
    public static function encodeBundle(key:String, mips:Array<Pixels>):haxe.io.Bytes {
        if (mips == null || mips.length == 0) throw "Cannot serialize an empty mip chain";
        var out = new haxe.io.BytesOutput();
        out.writeInt32(BUNDLE_MAGIC);
        out.writeInt32(BUNDLE_VERSION);
        var keyBytes = haxe.io.Bytes.ofString(key == null ? "" : key);
        out.writeInt32(keyBytes.length);
        out.write(keyBytes);
        out.writeInt32(mips[0].width);
        out.writeInt32(mips.length);
        for (mip in mips) {
            var copy = mip.clone();
            var png = copy.toPNG(6);
            copy.dispose();
            out.writeInt32(png.length);
            out.write(png);
        }
        return out.getBytes();
    }

    /** Deterministic, file-system safe name for a mesh id. */
    public static function bundleResourceName(id:String):String {
        if (id == null || StringTools.trim(id).length == 0) return "thumbnail";
        if (StringTools.startsWith(id, "primitive:")) {
            return StringTools.replace(id.substring("primitive:".length), ":", "_");
        }
        var safe = ~/[^A-Za-z0-9_-]+/g.replace(id, "_");
        if (safe.length == 0) safe = "thumbnail";
        return safe + "_" + hex32(hash(id));
    }

    static function defaultOutputDirectory():String {
        return haxe.io.Path.join([Sys.getCwd(), "src", "res", "thumbnails", "bundles"]);
    }

    // ------------------------------------------------------------------
    // GPU side
    // ------------------------------------------------------------------

    static function renderMesh(mesh:Mesh, ?tint:Int):Pixels {
        var engine = h3d.Engine.getCurrent();
        if (engine == null) {
            throw "Thumbnail baking requires a live h3d.Engine (run the BakeThumbnails command)";
        }

        var primitive = HeapsMeshFactory.resolve(mesh, bakeSettings(mesh));
        var scene = new h3d.scene.Scene();
        setupStudioLights(scene);

        var sceneMesh = new h3d.scene.Mesh(primitive, scene);
        sceneMesh.name = "ThumbnailSource_" + mesh.id;
        sceneMesh.material.name = "ThumbnailMaterial";
        // Shadow maps and a strong specular lobe add noise/self-shadowing to a
        // tiny bake; a clean diffuse studio look reads better at 60-190px.
        sceneMesh.material.shadows = false;
        sceneMesh.material.specularAmount = 0.08;
        // Vector4.setColor reads alpha from the high byte, so force opaque.
        if (tint != null) sceneMesh.material.color.setColor(tint | 0xFF000000);
        frameCamera(scene.camera, sceneMesh.getBounds());

        var sceneTarget = new Texture(RESOLUTION, RESOLUTION, [TextureFlags.Target]);
        sceneTarget.setName("thumbnailSceneTarget");
        var depth = new Texture(RESOLUTION, RESOLUTION,
            [TextureFlags.Target], hxd.PixelFormat.Depth24Stencil8);
        depth.setName("thumbnailDepthBuffer");
        sceneTarget.depthBuffer = depth;

        var aaTarget = new Texture(RESOLUTION, RESOLUTION, [TextureFlags.Target]);
        aaTarget.setName("thumbnailTentTarget");
        var finalTarget = new Texture(RESOLUTION, RESOLUTION, [TextureFlags.Target]);
        finalTarget.setName("thumbnailFxaaTarget");

        var tent = new h3d.pass.ScreenFx(new TentDownsampleShader());
        var fxaa = new h3d.pass.FXAA();

        scene.setOutputTarget(engine, sceneTarget);
        engine.clear(0x00000000, 1.0);
        scene.render(engine);
        scene.setOutputTarget();

        tent.shader.source = sceneTarget;
        tent.shader.texel.set(1 / RESOLUTION, 1 / RESOLUTION);
        engine.pushTarget(aaTarget);
        tent.render();
        engine.popTarget();

        engine.pushTarget(finalTarget);
        fxaa.apply(aaTarget);
        engine.popTarget();

        var pixels = finalTarget.capturePixels();
        if (pixels.format != RGBA) pixels.convert(RGBA);

        fxaa.dispose();
        tent.dispose();
        finalTarget.dispose();
        aaTarget.dispose();
        depth.dispose();
        sceneTarget.dispose();
        scene.remove();
        return pixels;
    }

    /**
     * Bake-time geometry is denser than the in-editor default so curved assets
     * (especially the sphere) don't read as low-poly at thumbnail scale.
     */
    static function bakeSettings(mesh:Mesh):PrimitiveSettings {
        var settings = PrimitiveMeshes.defaultSettings(mesh.primitiveId);
        settings.segments = 64;
        settings.rings = 48;
        return settings;
    }

    /** Three-point studio rig plus opposing bounce fills. */
    static function setupStudioLights(scene:h3d.scene.Scene):Void {
        var lightSystem = Std.downcast(scene.lightSystem, h3d.scene.fwd.LightSystem);
        if (lightSystem != null) {
            lightSystem.ambientLight.set(0.48, 0.50, 0.54);
            lightSystem.perPixelLighting = true;
        }

        // Three-point rig (key / fill / rim) plus three low bounce fills on the
        // opposite hemisphere. The extra fills keep any face of a rotating
        // imported mesh from going fully black while the asset is baked.
        // Key points at the framing camera from the upper-right of screen;
        // DirLight stores the travel direction, so this vector is its inverse.
        var key = new h3d.scene.fwd.DirLight(new h3d.Vector(0.10, -0.67, -0.74), scene);
        key.color.set(0.26, 0.25, 0.23);
        key.enableSpecular = true;

        // Subdued fill from the lower-left keeps the shadow side readable.
        var fill = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.7, 0.20, -0.5), scene);
        fill.color.set(0.12, 0.14, 0.18);

        var rim = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.6, 1.0, 0.2), scene);
        rim.color.set(0.14, 0.16, 0.21);
        rim.enableSpecular = true;

        var bounceA = new h3d.scene.fwd.DirLight(new h3d.Vector(0.6, -1.0, -0.2), scene);
        bounceA.color.set(0.10, 0.10, 0.10);
        var bounceB = new h3d.scene.fwd.DirLight(new h3d.Vector(0.9, 0.1, -0.9), scene);
        bounceB.color.set(0.09, 0.09, 0.10);
        var bounceC = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.9, 0.1, 0.9), scene);
        bounceC.color.set(0.09, 0.09, 0.10);
    }

    /** Fit a perspective camera around the mesh's absolute bounds. */
    static function frameCamera(camera:h3d.Camera, bounds:h3d.col.Bounds):Void {
        var sphere = bounds.toSphere();
        var radius = Math.max(0.001, sphere.r);
        var fovY = 30 * Math.PI / 180;
        var distance = radius / Math.sin(fovY * 0.5) * 1.05;
        var direction = new h3d.Vector(1.0, 0.62, 1.25).normalized();

        camera.fovY = 30;
        camera.screenRatio = 1;
        camera.up.set(0, 1, 0);
        camera.zNear = Math.max(0.001, distance * 0.01);
        camera.zFar = distance + radius * 4 + 10;
        camera.target.set(sphere.x, sphere.y, sphere.z);
        camera.pos.set(sphere.x + direction.x * distance,
            sphere.y + direction.y * distance,
            sphere.z + direction.z * distance);
        camera.update();
    }

    // ------------------------------------------------------------------
    // CPU side: halo-free filtering
    // ------------------------------------------------------------------

    /**
     * Average a 2x2 footprint with a separable 4x4 tent filter implemented in
     * premultiplied LINEAR space, then unpremultiply and re-encode sRGB.
     * Transparent texels contribute coverage but no color, so an alpha edge
     * keeps its own hue instead of blending against black.
     */
    static function downsampleLinearPremultiplied(src:Pixels, outW:Int, outH:Int):Pixels {
        var dst = Pixels.alloc(outW, outH, RGBA);
        var sw = src.width;
        var sh = src.height;
        var sbytes:hxd.impl.UncheckedBytes = src.bytes;
        var dbytes:hxd.impl.UncheckedBytes = dst.bytes;
        var soffset = src.offset;
        var doffset = dst.offset;

        for (y in 0...outH) {
            var y0 = Std.int(Math.min(sh - 1, y * 2));
            var y1 = Std.int(Math.min(sh - 1, y0 + 1));
            for (x in 0...outW) {
                var x0 = Std.int(Math.min(sw - 1, x * 2));
                var x1 = Std.int(Math.min(sw - 1, x0 + 1));

                var pr = 0.0;
                var pg = 0.0;
                var pb = 0.0;
                var pa = 0.0;

                pr += tap(sbytes, soffset, sw, x0, y0, 0, 3);
                pg += tap(sbytes, soffset, sw, x0, y0, 1, 3);
                pb += tap(sbytes, soffset, sw, x0, y0, 2, 3);
                pa += tap(sbytes, soffset, sw, x0, y0, 3, 3);

                pr += tap(sbytes, soffset, sw, x1, y0, 0, 3);
                pg += tap(sbytes, soffset, sw, x1, y0, 1, 3);
                pb += tap(sbytes, soffset, sw, x1, y0, 2, 3);
                pa += tap(sbytes, soffset, sw, x1, y0, 3, 3);

                pr += tap(sbytes, soffset, sw, x0, y1, 0, 3);
                pg += tap(sbytes, soffset, sw, x0, y1, 1, 3);
                pb += tap(sbytes, soffset, sw, x0, y1, 2, 3);
                pa += tap(sbytes, soffset, sw, x0, y1, 3, 3);

                pr += tap(sbytes, soffset, sw, x1, y1, 0, 3);
                pg += tap(sbytes, soffset, sw, x1, y1, 1, 3);
                pb += tap(sbytes, soffset, sw, x1, y1, 2, 3);
                pa += tap(sbytes, soffset, sw, x1, y1, 3, 3);

                pr *= 0.25;
                pg *= 0.25;
                pb *= 0.25;
                pa *= 0.25;

                var p = doffset + ((x + y * outW) << 2);
                dbytes[p + 3] = Math.round(pa * 255);
                if (pa <= 0.00001) {
                    dbytes[p] = 0;
                    dbytes[p + 1] = 0;
                    dbytes[p + 2] = 0;
                } else {
                    dbytes[p] = encodeSrgb(pr / pa);
                    dbytes[p + 1] = encodeSrgb(pg / pa);
                    dbytes[p + 2] = encodeSrgb(pb / pa);
                }
            }
        }
        return dst;
    }

    /** Contribution of one RGBA texel to a premultiplied-linear sum. */
    static inline function tap(bytes:hxd.impl.UncheckedBytes, offset:Int,
            width:Int, x:Int, y:Int, channel:Int, alphaChannel:Int):Float {
        var p = offset + ((x + y * width) << 2);
        if (channel == alphaChannel) return bytes[p + 3] / 255;
        var linear = SRGB_TO_LINEAR[bytes[p + channel]];
        return linear * (bytes[p + 3] / 255);
    }

    static inline function encodeSrgb(linear:Float):Int {
        var v = linear < 0 ? 0 : linear > 1 ? 1 : linear;
        return LINEAR_TO_SRGB[Std.int(v * 1023)];
    }

    static function buildSrgbToLinear():haxe.ds.Vector<Float> {
        var table = new haxe.ds.Vector<Float>(256);
        for (i in 0...256) {
            var c = i / 255;
            table[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        }
        return table;
    }

    static function buildLinearToSrgb():haxe.ds.Vector<Int> {
        var table = new haxe.ds.Vector<Int>(1024);
        for (i in 0...1024) {
            var v = i / 1023;
            var s = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
            var byte = Math.round(s * 255);
            table[i] = byte < 0 ? 0 : byte > 255 ? 255 : byte;
        }
        return table;
    }

    static function hash(value:String):Int {
        var h = 0x811C9DC5;
        for (i in 0...value.length) {
            h ^= value.charCodeAt(i);
            h = h * 0x01000193;
        }
        return h;
    }

    static function hex32(value:Int):String {
        var result = "";
        var v = value;
        for (i in 0...8) {
            result = String.fromCharCode("0123456789abcdef".charCodeAt(v & 15)) + result;
            v >>>= 4;
        }
        return result;
    }
}

/**
 * 4x4 tent resolve pass. Runs in a `h3d.pass.ScreenFx`, so it never allocates
 * an MSAA target and works on the DX12 offscreen path. Alpha is filtered
 * together with color so FXAA sees the same coverage the mesh produced.
 */
private class TentDownsampleShader extends h3d.shader.ScreenShader {
    static var SRC = {
        @param var source : Sampler2D;
        @param var texel : Vec2;

        final offsets : Array<Float, 4> = [ -1.5, -0.5, 0.5, 1.5 ];
        final weights : Array<Float, 4> = [ 1.0, 3.0, 3.0, 1.0 ];

        function fragment() {
            var sum = vec4(0.0, 0.0, 0.0, 0.0);
            @unroll for (y in 0...4) {
                @unroll for (x in 0...4) {
                    var weight = weights[x] * weights[y] * 0.015625; // /64
                    sum += source.get(input.uv + vec2(offsets[x], offsets[y]) * texel) * weight;
                }
            }
            pixelColor = sum;
        }
    };
}
