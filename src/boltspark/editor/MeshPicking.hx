package boltspark.editor;

/**
 * Geometry-accurate ray picking for scene meshes.
 *
 * Heaps' stock colliders are only approximations for some built-in primitives:
 * a Cube uses its AABB and a Capsule uses a single sphere at its centre, so a
 * click on the capsule body (or anywhere the silhouette differs from the
 * collider) either misses or selects the wrong object. All editor primitives
 * keep CPU triangles on their `h3d.prim.Polygon`, so build a real triangle
 * collider from those and reuse Heaps' tested ray math.
 */
class MeshPicking {
    /** Primitives are shared by the mesh factory, so one collider per is enough. */
    static final colliders:Map<h3d.prim.Primitive, h3d.col.Collider> = [];

    /** World-space ray distance, or -1 when the ray misses the mesh. */
    public static function rayIntersection(mesh:h3d.scene.Mesh,
            ray:h3d.col.Ray):Float {
        var primitive = mesh.primitive;
        if (primitive == null) return -1;
        var local = localCollider(primitive);
        if (local == null) {
            // Imported geometry without CPU triangles keeps the old behaviour.
            local = mesh.getLocalCollider();
            if (local == null) return -1;
        }
        return new h3d.col.ObjectCollider(mesh, local).rayIntersection(ray, true);
    }

    /**
     * Triangle collider in primitive-local space, or null when the primitive
     * exposes no usable CPU geometry. Public for headless geometry checks.
     */
    public static function localCollider(
            primitive:h3d.prim.Primitive):Null<h3d.col.Collider> {
        var cached = colliders.get(primitive);
        if (cached != null) return cached;
        var polygon = Std.downcast(primitive, h3d.prim.Polygon);
        if (polygon == null || polygon.points == null || polygon.points.length < 3) {
            return null;
        }
        var pointCount = polygon.points.length;
        var positions = new haxe.ds.Vector<hxd.impl.Float32>(pointCount * 3);
        for (index in 0...pointCount) {
            var point = polygon.points[index];
            positions[index * 3] = point.x;
            positions[index * 3 + 1] = point.y;
            positions[index * 3 + 2] = point.z;
        }
        // addUVs() unindexes some primitives (notably the cube), leaving idx
        // null. Sequential indices still describe the exact same triangles.
        var indexed = polygon.idx != null;
        var indexCount = indexed ? polygon.idx.length : pointCount;
        if (indexCount < 3 || indexCount % 3 != 0) return null;
        var indices = new haxe.ds.Vector<Int>(indexCount);
        for (index in 0...indexCount) {
            indices[index] = indexed ? polygon.idx[index] : index;
        }
        var collider = new h3d.col.Polygon();
        collider.addBuffers(positions, indices);
        colliders.set(primitive, collider);
        return collider;
    }
}
