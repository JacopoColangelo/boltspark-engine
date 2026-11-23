package boltspark.editor;

import boltspark.engine.Mesh;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.PrimitiveSettings;

/**
 * Maps renderer-independent Mesh assets onto Heaps primitives.
 *
 * One primitive is cached per (asset id + geometry settings) pair, so every
 * renderer using the same mesh asset *and* settings shares one geometry buffer.
 * Renderer views still own their own `h3d.scene.Mesh` and material instance;
 * this factory never hands out scene objects, only reusable geometry.
 */
class HeapsMeshFactory {
    static final factories:Map<String, PrimitiveSettings->h3d.prim.Primitive> = [];
    static final cache:Map<String, h3d.prim.Primitive> = [];
    static var initialized:Bool = initializeBuiltIns();

    /** Legacy registration for meshes with no adjustable parameters. */
    public static function register(meshId:String,
            factory:Void->h3d.prim.Primitive):Void {
        registerParametric(meshId, function(_) return factory());
    }

    /** Register geometry that depends on PrimitiveSettings. */
    public static function registerParametric(meshId:String,
            factory:PrimitiveSettings->h3d.prim.Primitive):Void {
        if (meshId == null || StringTools.trim(meshId).length == 0
                || factory == null) {
            throw "Heaps mesh registration requires an ID and factory";
        }
        factories.set(meshId, factory);
        for (key in cache.keys()) {
            if (key.indexOf(meshId + "|") == 0) cache.remove(key);
        }
    }

    /** Drop cached geometry and factories for imported (mesh:) assets. */
    public static function clearImported():Void {
        for (id in factories.keys()) {
            if (StringTools.startsWith(id, "mesh:")) factories.remove(id);
        }
        for (key in cache.keys()) {
            if (StringTools.startsWith(key, "mesh:")) cache.remove(key);
        }
    }

    public static function resolve(mesh:Mesh,
            ?settings:PrimitiveSettings):h3d.prim.Primitive {
        ensureInitialized();
        if (mesh == null) throw "Cannot resolve a null Mesh";
        var effective = settings == null
            ? PrimitiveMeshes.defaultSettings(mesh.primitiveId)
            : settings;
        var key = mesh.id + "|" + effective.signature();
        var primitive = cache.get(key);
        if (primitive != null) return primitive;
        var factory = factories.get(mesh.id);
        if (factory == null) throw 'No Heaps primitive registered for Mesh ${mesh.id}';
        primitive = factory(effective);
        cache.set(key, primitive);
        return primitive;
    }

    static function initializeBuiltIns():Bool {
        registerParametric(PrimitiveMeshes.CUBE_ID, function(s) {
            var primitive = new h3d.prim.Cube(
                positive(s.width), positive(s.height), positive(s.depth), true);
            primitive.addUVs();
            primitive.addNormals();
            return primitive;
        });
        registerParametric(PrimitiveMeshes.SPHERE_ID, function(s) {
            var primitive = new h3d.prim.Sphere(positive(s.radius),
                clampInt(s.segments, 3, 64), clampInt(s.rings, 3, 48));
            primitive.addUVs();
            primitive.addNormals();
            return primitive;
        });
        registerParametric(PrimitiveMeshes.CYLINDER_ID, buildUprightCylinder);
        registerParametric(PrimitiveMeshes.CAPSULE_ID, function(s) {
            var primitive = new h3d.prim.Capsule(positive(s.radius),
                positive(s.height), clampInt(s.segments, 3, 48));
            rotateXToY(primitive);
            primitive.addUVs();
            return primitive;
        });
        registerParametric(PrimitiveMeshes.PLANE_ID, function(s) {
            return horizontalPlane(positive(s.width), positive(s.depth));
        });
        return true;
    }

    /**
     * Cylinder built directly in Y-up space: its axis is vertical, and the
     * circular ends are real caps by default (turn "Capped" off for a hollow
     * tube). Heaps' stock Cylinder is Z-up and has no caps.
     */
    static function buildUprightCylinder(s:PrimitiveSettings):h3d.prim.Primitive {
        var segments = clampInt(s.segments, 3, 64);
        var radius = positive(s.radius);
        var halfHeight = positive(s.height) * 0.5;
        var points:Array<h3d.col.Point> = [];
        var normals:Array<h3d.col.Point> = [];
        var indices = new hxd.IndexBuffer();

        for (index in 0...segments) {
            var angle0 = index / segments * Math.PI * 2;
            var angle1 = (index + 1) / segments * Math.PI * 2;
            var c0 = Math.cos(angle0);
            var s0 = Math.sin(angle0);
            var c1 = Math.cos(angle1);
            var s1 = Math.sin(angle1);
            var base = points.length;
            points.push(new h3d.col.Point(c0 * radius, -halfHeight, s0 * radius));
            points.push(new h3d.col.Point(c1 * radius, -halfHeight, s1 * radius));
            points.push(new h3d.col.Point(c0 * radius, halfHeight, s0 * radius));
            points.push(new h3d.col.Point(c1 * radius, halfHeight, s1 * radius));
            normals.push(new h3d.col.Point(c0, 0, s0));
            normals.push(new h3d.col.Point(c1, 0, s1));
            normals.push(new h3d.col.Point(c0, 0, s0));
            normals.push(new h3d.col.Point(c1, 0, s1));
            indices.push(base);
            indices.push(base + 2);
            indices.push(base + 1);
            indices.push(base + 1);
            indices.push(base + 2);
            indices.push(base + 3);
        }

        if (s.capped) {
            for (index in 0...segments) {
                var angle0 = index / segments * Math.PI * 2;
                var angle1 = (index + 1) / segments * Math.PI * 2;
                var c0 = Math.cos(angle0);
                var s0 = Math.sin(angle0);
                var c1 = Math.cos(angle1);
                var s1 = Math.sin(angle1);
                var top = points.length;
                points.push(new h3d.col.Point(0, halfHeight, 0));
                points.push(new h3d.col.Point(c0 * radius, halfHeight, s0 * radius));
                points.push(new h3d.col.Point(c1 * radius, halfHeight, s1 * radius));
                normals.push(new h3d.col.Point(0, 1, 0));
                normals.push(new h3d.col.Point(0, 1, 0));
                normals.push(new h3d.col.Point(0, 1, 0));
                // Cross((P1-P0),(P2-P0)) must point +Y: reverse the rim order.
                indices.push(top);
                indices.push(top + 2);
                indices.push(top + 1);

                var bottom = points.length;
                points.push(new h3d.col.Point(0, -halfHeight, 0));
                points.push(new h3d.col.Point(c0 * radius, -halfHeight, s0 * radius));
                points.push(new h3d.col.Point(c1 * radius, -halfHeight, s1 * radius));
                normals.push(new h3d.col.Point(0, -1, 0));
                normals.push(new h3d.col.Point(0, -1, 0));
                normals.push(new h3d.col.Point(0, -1, 0));
                indices.push(bottom);
                indices.push(bottom + 1);
                indices.push(bottom + 2);
            }
        }

        var primitive = new h3d.prim.Polygon(points, indices);
        primitive.normals = normals;
        primitive.addUVs();
        return primitive;
    }

    /** Build a Heaps primitive from a parsed, renderer-independent mesh file. */
    public static function fromGeometry(
            geometry:boltspark.assets.MeshGeometry):h3d.prim.Polygon {
        var points:Array<h3d.col.Point> = [];
        var normals:Array<h3d.col.Point> = [];
        var uvs:Array<h3d.prim.UV> = [];
        var vertexCount = Std.int(geometry.positions.length / 3);
        for (index in 0...vertexCount) {
            points.push(new h3d.col.Point(
                geometry.positions[index * 3],
                geometry.positions[index * 3 + 1],
                geometry.positions[index * 3 + 2]));
            normals.push(new h3d.col.Point(
                geometry.normals[index * 3],
                geometry.normals[index * 3 + 1],
                geometry.normals[index * 3 + 2]));
            uvs.push(new h3d.prim.UV(
                geometry.uvs[index * 2], geometry.uvs[index * 2 + 1]));
        }
        var indices = new hxd.IndexBuffer();
        for (index in geometry.indices) indices.push(index);
        var primitive = new h3d.prim.Polygon(points, indices);
        primitive.normals = normals;
        primitive.uvs = uvs;
        return primitive;
    }

    /** Rotate a Heaps polygon so its X axis becomes the editor's Y (up). */
    static function rotateXToY(primitive:h3d.prim.Polygon):Void {
        for (point in primitive.points) {
            var x = point.x;
            point.x = -point.y;
            point.y = x;
        }
        if (primitive.normals != null) {
            for (normal in primitive.normals) {
                var x = normal.x;
                normal.x = -normal.y;
                normal.y = x;
            }
        }
    }

    /** Unit plane on XZ (Y-up editor), sized from settings. */
    static function horizontalPlane(width:Float, depth:Float):h3d.prim.Primitive {
        var hw = width * 0.5;
        var hd = depth * 0.5;
        var points = [
            new h3d.col.Point(-hw, 0, -hd),
            new h3d.col.Point(hw, 0, -hd),
            new h3d.col.Point(-hw, 0, hd),
            new h3d.col.Point(hw, 0, hd)
        ];
        var indices = new hxd.IndexBuffer();
        indices.push(0);
        indices.push(2);
        indices.push(1);
        indices.push(1);
        indices.push(2);
        indices.push(3);
        var primitive = new h3d.prim.Polygon(points, indices);
        primitive.addUVs();
        primitive.addNormals();
        return primitive;
    }

    static inline function positive(value:Float):Float {
        return Math.max(0.01, Math.isFinite(value) ? value : 1);
    }

    static inline function clampInt(value:Int, min:Int, max:Int):Int {
        return value < min ? min : value > max ? max : value;
    }

    static inline function ensureInitialized():Void {
        if (!initialized) throw "Heaps mesh factory initialization failed";
    }
}
