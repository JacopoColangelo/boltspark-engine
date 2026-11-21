import boltspark.editor.HeapsMeshFactory;
import boltspark.editor.MeshPicking;
import boltspark.engine.PrimitiveMeshes;

/** Headless checks that viewport picking follows primitive geometry. */
class MeshPickingRepro {
    static function main():Void {
        testCapsuleBody();
        testGapBetweenTriangles();
        testUnindexedCube();
        Sys.println("[mesh-picking] geometry-accurate primitive picking passed");
    }

    static function testCapsuleBody():Void {
        // Heaps' built-in Capsule collider is a sphere at the centre, so the
        // cylindrical body is invisible to picking unless we use its triangles.
        var primitive = HeapsMeshFactory.resolve(PrimitiveMeshes.capsule(), null);
        var collider = MeshPicking.localCollider(primitive);
        assertTrue(collider != null, "capsule has no triangle collider");
        var ray = h3d.col.Ray.fromValues(0, 0.8, 5, 0, 0, -1);
        var hit = collider.rayIntersection(ray, true);
        assertTrue(hit > 0 && hit < 5, "capsule body did not intersect its geometry");
        var legacySphere = new h3d.col.Sphere(0, 0, 0, 0.5);
        assertTrue(legacySphere.rayIntersection(ray, true) < 0,
            "test ray should miss the legacy sphere collider");
    }

    static function testGapBetweenTriangles():Void {
        // An AABB covers the gap between these two strips; triangle picking
        // must correctly report a miss there.
        var points = [
            new h3d.col.Point(-2, 0, -2),
            new h3d.col.Point(-0.5, 0, -2),
            new h3d.col.Point(-0.5, 0, 2),
            new h3d.col.Point(-2, 0, 2),
            new h3d.col.Point(0.5, 0, -2),
            new h3d.col.Point(2, 0, -2),
            new h3d.col.Point(2, 0, 2),
            new h3d.col.Point(0.5, 0, 2)
        ];
        var indices = new hxd.IndexBuffer();
        indices.push(0); indices.push(1); indices.push(2);
        indices.push(0); indices.push(2); indices.push(3);
        indices.push(4); indices.push(5); indices.push(6);
        indices.push(4); indices.push(6); indices.push(7);
        var primitive = new h3d.prim.Polygon(points, indices);
        var collider = MeshPicking.localCollider(primitive);
        assertTrue(collider != null, "polygon has no triangle collider");

        var gapRay = h3d.col.Ray.fromValues(0, 5, 0, 0, -1, 0);
        assertTrue(collider.rayIntersection(gapRay, true) < 0,
            "picking hit the empty gap inside the bounding box");

        var stripRay = h3d.col.Ray.fromValues(-1, 5, 0, 0, -1, 0);
        assertTrue(collider.rayIntersection(stripRay, true) > 0,
            "picking missed geometry that is visibly present");

        var bounds = h3d.col.Bounds.fromPoints(
            new h3d.col.Point(-2, -1, -2), new h3d.col.Point(2, 1, 2));
        assertTrue(bounds.rayIntersection(gapRay, true) >= 0,
            "test ray should hit the bounding box");
    }

    static function testUnindexedCube():Void {
        // Cube.addUVs() unindexes its geometry, leaving idx null.
        var primitive = HeapsMeshFactory.resolve(PrimitiveMeshes.cube(), null);
        var polygon = Std.downcast(primitive, h3d.prim.Polygon);
        assertTrue(polygon != null && polygon.idx == null,
            "cube test expects unindexed geometry");
        var collider = MeshPicking.localCollider(primitive);
        assertTrue(collider != null, "cube has no triangle collider");
        var ray = h3d.col.Ray.fromValues(0, 0, 5, 0, 0, -1);
        assertTrue(collider.rayIntersection(ray, true) > 0,
            "cube front face was not pickable");
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
