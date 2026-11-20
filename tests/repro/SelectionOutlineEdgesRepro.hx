import boltspark.editor.HeapsMeshFactory;
import boltspark.editor.SelectionOutlineEdges;
import boltspark.engine.PrimitiveMeshes;

/**
 * Headless coverage that the selection outline traces only the object's outer
 * silhouette (not a bounding cube and not a wireframe), works for built-in and
 * custom meshes, and caches geometry per shared primitive.
 */
class SelectionOutlineEdgesRepro {
    static function main():Void {
        testCubeSilhouette();
        testCurvedSilhouette();
        testCaching();
        testCustomMesh();
        Sys.println("[selection-outline-edges] cube/curved silhouettes, caching, "
            + "and custom meshes passed");
    }

    static function testCubeSilhouette():Void {
        var primitive = HeapsMeshFactory.resolve(PrimitiveMeshes.cube());
        // Looking square-on at +Z: only the front face is visible, so its
        // four borders are the whole contour (no triangulation diagonal).
        var front = SelectionOutlineEdges.silhouette(primitive,
            new h3d.Vector(0, 0, 4));
        assertTrue(front.length == 4,
            'cube front view had ${front.length} contour edges, expected 4');
        for (edge in front) {
            assertTrue(Math.abs(edge.a.z - 0.5) < 0.0001
                    && Math.abs(edge.b.z - 0.5) < 0.0001,
                'cube front contour left the visible face');
        }

        // Diagonal view exposes three faces; the contour is the six edges
        // where a visible face meets a hidden one, never the interior corners.
        var diagonal = SelectionOutlineEdges.silhouette(primitive,
            new h3d.Vector(4, 4, 4));
        assertTrue(diagonal.length == 6,
            'cube diagonal view had ${diagonal.length} contour edges, expected 6');
        for (edge in diagonal) assertCubeCorner(edge.a) && assertCubeCorner(edge.b);
    }

    static function testCurvedSilhouette():Void {
        var sphere = HeapsMeshFactory.resolve(PrimitiveMeshes.sphere());
        var contour = SelectionOutlineEdges.silhouette(sphere,
            new h3d.Vector(0, 0, 4));
        assertTrue(contour.length > 8,
            'sphere silhouette collapsed (${contour.length} edges)');
        // Every silhouette endpoint lies near the limb: its surface normal is
        // almost perpendicular to the view direction.
        for (edge in contour) {
            var normal = edge.a.clone();
            normal.normalize();
            var view = new h3d.Vector(0, 0, 4).sub(edge.a);
            view.normalize();
            assertTrue(Math.abs(normal.dot(view)) < 0.25,
                'sphere contour endpoint was not on the silhouette limb');
        }

        var plane = HeapsMeshFactory.resolve(PrimitiveMeshes.plane());
        var borders = SelectionOutlineEdges.silhouette(plane,
            new h3d.Vector(0, 4, 0));
        assertTrue(borders.length == 4,
            'plane outline had ${borders.length} edges, expected its 4 borders');
    }

    static function testCaching():Void {
        var primitive = HeapsMeshFactory.resolve(PrimitiveMeshes.capsule());
        var first = SelectionOutlineEdges.silhouette(primitive,
            new h3d.Vector(0, 0, 4));
        var second = SelectionOutlineEdges.silhouette(primitive,
            new h3d.Vector(0, 0, 4));
        assertTrue(first == second, "silhouette result was not cached per primitive");
        assertTrue(first.length > 8,
            'capsule silhouette collapsed (${first.length} edges)');
    }

    static function testCustomMesh():Void {
        // A non-Polygon primitive with no CPU points exercises the generic
        // registration path used by future imported/custom meshes.
        var primitive = new h3d.prim.Grid(1, 1, 1, 1);
        var half = 0.5;
        SelectionOutlineEdges.registerGeometry(primitive, [
            new h3d.Vector(-half, 0, -half),
            new h3d.Vector(half, 0, -half),
            new h3d.Vector(-half, 0, half),
            new h3d.Vector(half, 0, half)
        ], [0, 2, 1, 1, 2, 3]);
        var edges = SelectionOutlineEdges.silhouette(primitive,
            new h3d.Vector(0, 4, 0));
        assertTrue(edges.length == 4,
            'custom mesh outline had ${edges.length} edges, expected its 4 borders');
    }

    static function assertCubeCorner(p:h3d.Vector):Bool {
        var ok = Math.abs(Math.abs(p.x) - 0.5) < 0.0001
            && Math.abs(Math.abs(p.y) - 0.5) < 0.0001
            && Math.abs(Math.abs(p.z) - 0.5) < 0.0001;
        assertTrue(ok,
            'cube contour endpoint (${p.x}, ${p.y}, ${p.z}) was not a cube corner');
        return ok;
    }

    static function assertTrue(condition:Bool, message:String):Void {
        if (!condition) throw message;
    }
}
