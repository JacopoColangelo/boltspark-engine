package boltspark.editor;

/** One local-space edge of a primitive's visible outer contour. */
typedef SelectionOutlineEdge = {
    var a:h3d.Vector;
    var b:h3d.Vector;
}

typedef OutlineGeometry = {
    var positions:Array<h3d.Vector>;
    var indices:Array<Int>;
}

typedef OutlineTriangle = {
    var center:h3d.Vector;
    var normal:h3d.Vector;
}

typedef OutlineEdgeInfo = {
    var a:h3d.Vector;
    var b:h3d.Vector;
    var triangles:Array<Int>;
}

typedef CachedMesh = {
    var triangles:Array<OutlineTriangle>;
    var edges:Array<OutlineEdgeInfo>;
    var facing:Array<Bool>;
    var result:Array<SelectionOutlineEdge>;
}

/**
 * Computes the camera-dependent outer silhouette of any Heaps primitive.
 *
 * Only the object's visible contour is returned: an edge is drawn when it
 * separates a front-facing triangle from a back-facing one, or when it is the
 * border of an open surface. Edges shared by two front-facing triangles (the
 * cube's "inside" corners and every triangulation diagonal) are deliberately
 * omitted, so the result is an outline rather than a wireframe.
 *
 * Facing is evaluated in the primitive's local space with the camera position
 * transformed by the inverse world matrix. That keeps the classification exact
 * under any rotation, translation, non-uniform scale, or reflection without
 * needing a normal matrix.
 *
 * Geometry is obtained from (in order):
 *  1. `h3d.prim.Polygon` CPU points/indices (all built-in editor primitives);
 *  2. a shape registered via `registerGeometry()` (custom / imported meshes);
 *  3. the primitive's GPU vertex + index buffers, when the active driver can
 *     read them back.
 *
 * Geometry, triangles, and edge adjacency are cached per primitive; only the
 * front/back classification and contour emission run per frame.
 */
class SelectionOutlineEdges {
    /** Positions within 0.0001 world units collapse to the same endpoint. */
    static inline var POSITION_QUANTUM:Float = 10000.0;
    static final cache = new Map<h3d.prim.Primitive, CachedMesh>();
    static final registered = new Map<h3d.prim.Primitive, OutlineGeometry>();

    /**
     * Supply CPU geometry for a custom or imported primitive. Importers should
     * call this once with the same local-space triangles they upload to the
     * GPU; the outline then works without driver readback support (including
     * the project's DX12 target).
     */
    public static function registerGeometry(primitive:h3d.prim.Primitive,
            positions:Array<h3d.Vector>, ?indices:Array<Int>):Void {
        if (primitive == null || positions == null) {
            throw "Selection outline geometry requires a primitive and positions";
        }
        registered.set(primitive, {
            positions: positions,
            indices: indices == null ? [] : indices
        });
        cache.remove(primitive);
    }

    /**
     * Return the local-space outer contour of `primitive` as seen from
     * `localCamera` (the camera position expressed in the primitive's local
     * space). The returned array is owned by the cache and reused on the next
     * call for the same primitive, so draw it before requesting another mesh.
     */
    public static function silhouette(primitive:h3d.prim.Primitive,
            localCamera:h3d.Vector):Array<SelectionOutlineEdge> {
        if (primitive == null) return [];
        var cached = getCached(primitive);
        var triangles = cached.triangles;
        for (index in 0...triangles.length) {
            var triangle = triangles[index];
            cached.facing[index] =
                (localCamera.x - triangle.center.x) * triangle.normal.x
                + (localCamera.y - triangle.center.y) * triangle.normal.y
                + (localCamera.z - triangle.center.z) * triangle.normal.z > 0;
        }

        var result = cached.result;
        result.resize(0);
        for (edge in cached.edges) {
            var faces = edge.triangles;
            if (faces.length <= 1) {
                // Open-surface border: always part of the outer contour.
                result.push({ a: edge.a, b: edge.b });
                continue;
            }
            var front = cached.facing[faces[0]];
            var mixed = false;
            for (index in 1...faces.length) {
                if (cached.facing[faces[index]] != front) {
                    mixed = true;
                    break;
                }
            }
            // Front/back transition: the visible surface ends here.
            if (mixed) result.push({ a: edge.a, b: edge.b });
        }
        return result;
    }

    static function getCached(primitive:h3d.prim.Primitive):CachedMesh {
        var cached = cache.get(primitive);
        if (cached != null) return cached;

        var geometry = registered.get(primitive);
        if (geometry == null) geometry = readGeometry(primitive);
        var triangles:Array<OutlineTriangle> = [];
        var edges:Array<OutlineEdgeInfo> = [];
        if (geometry != null) {
            buildTriangles(geometry, triangles);
            buildAdjacency(geometry, edges);
        }
        cached = {
            triangles: triangles,
            edges: edges,
            facing: [for (_ in 0...triangles.length) false],
            result: []
        };
        cache.set(primitive, cached);
        return cached;
    }

    static function buildTriangles(geometry:OutlineGeometry,
            triangles:Array<OutlineTriangle>):Void {
        var positions = geometry.positions;
        var indices = geometry.indices;
        var triangleCount = Std.int((indices.length == 0
            ? positions.length : indices.length) / 3);
        for (triangle in 0...triangleCount) {
            var base = triangle * 3;
            var i0 = indices.length == 0 ? base : indices[base];
            var i1 = indices.length == 0 ? base + 1 : indices[base + 1];
            var i2 = indices.length == 0 ? base + 2 : indices[base + 2];
            if (i0 < 0 || i0 >= positions.length
                    || i1 < 0 || i1 >= positions.length
                    || i2 < 0 || i2 >= positions.length) continue;
            var a = positions[i0];
            var b = positions[i1];
            var c = positions[i2];
            var normal = b.sub(a).cross(c.sub(a));
            if (normal.lengthSq() <= 0.000000000001) continue;
            normal.normalize();
            triangles.push({
                center: new h3d.Vector((a.x + b.x + c.x) / 3,
                    (a.y + b.y + c.y) / 3, (a.z + b.z + c.z) / 3),
                normal: normal
            });
        }
    }

    static function buildAdjacency(geometry:OutlineGeometry,
            edges:Array<OutlineEdgeInfo>):Void {
        var positions = geometry.positions;
        var indices = geometry.indices;
        var triangleCount = Std.int((indices.length == 0
            ? positions.length : indices.length) / 3);
        var byKey = new Map<String, OutlineEdgeInfo>();
        var faceIndex = 0;
        for (triangle in 0...triangleCount) {
            var base = triangle * 3;
            var i0 = indices.length == 0 ? base : indices[base];
            var i1 = indices.length == 0 ? base + 1 : indices[base + 1];
            var i2 = indices.length == 0 ? base + 2 : indices[base + 2];
            if (i0 < 0 || i0 >= positions.length
                    || i1 < 0 || i1 >= positions.length
                    || i2 < 0 || i2 >= positions.length) continue;
            // buildTriangles() skips degenerate faces, so keep face indices in
            // lockstep by recomputing the same validity test here.
            var a = positions[i0];
            var b = positions[i1];
            var c = positions[i2];
            if (b.sub(a).cross(c.sub(a)).lengthSq() <= 0.000000000001) continue;
            addFace(byKey, edges, a, b, faceIndex);
            addFace(byKey, edges, b, c, faceIndex);
            addFace(byKey, edges, c, a, faceIndex);
            faceIndex++;
        }
    }

    static function addFace(byKey:Map<String, OutlineEdgeInfo>,
            edges:Array<OutlineEdgeInfo>, a:h3d.Vector, b:h3d.Vector,
            faceIndex:Int):Void {
        var keyA = positionKey(a);
        var keyB = positionKey(b);
        if (keyA == keyB) return;
        var key = keyA < keyB ? keyA + "|" + keyB : keyB + "|" + keyA;
        var edge = byKey.get(key);
        if (edge == null) {
            edge = { a: a.clone(), b: b.clone(), triangles: [] };
            byKey.set(key, edge);
            edges.push(edge);
        }
        edge.triangles.push(faceIndex);
    }

    static function readGeometry(primitive:h3d.prim.Primitive):Null<OutlineGeometry> {
        var polygon = Std.downcast(primitive, h3d.prim.Polygon);
        if (polygon != null && polygon.points != null) {
            var positions = [for (p in polygon.points) new h3d.Vector(p.x, p.y, p.z)];
            var indices:Array<Int> = [];
            if (polygon.idx != null) {
                for (i in 0...polygon.idx.length) indices.push(polygon.idx[i]);
            }
            return { positions: positions, indices: indices };
        }
        return readBuffers(primitive);
    }

    /**
     * Generic GPU-buffer readback for arbitrary primitive types. Best-effort:
     * drivers that forbid readback (notably this project's DX12 driver) throw,
     * in which case callers can use `registerGeometry()` or get an empty
     * outline instead of a crash.
     */
    static function readBuffers(primitive:h3d.prim.Primitive):Null<OutlineGeometry> {
        try {
            var vertexBuffer = primitive.buffer;
            if (vertexBuffer == null || vertexBuffer.isDisposed()) return null;
            var format = vertexBuffer.format;
            var posInput = format.getInput("position");
            // InputFormat.DVec3 == 3 and Precision.F32 == 0 in Heaps'
            // BufferFormat; compare raw values because those enum abstracts
            // are not exported from their module.
            if (posInput == null || posInput.type.toInt() != 3
                    || posInput.precision.toInt() != 0) return null;
            var stride = format.stride;
            var vertexBytes = haxe.io.Bytes.alloc(
                vertexBuffer.vertices * vertexBuffer.format.strideBytes);
            vertexBuffer.readBytes(vertexBytes, 0, vertexBuffer.vertices);

            var positions:Array<h3d.Vector> = [];
            var offset = format.calculateInputOffset("position");
            for (index in 0...vertexBuffer.vertices) {
                var base = index * stride + offset;
                positions.push(new h3d.Vector(vertexBytes.getFloat(base),
                    vertexBytes.getFloat(base + 4), vertexBytes.getFloat(base + 8)));
            }

            var indices:Array<Int> = [];
            if (primitive.indexes != null) {
                var indexBuffer:h3d.Buffer = cast primitive.indexes;
                if (!indexBuffer.isDisposed() && indexBuffer.vertices > 0) {
                    var indexFormat = indexBuffer.format;
                    var indexInput = indexFormat.getInput("index");
                    var indexIs32 = indexInput != null
                        && indexInput.precision.toInt() == 0;
                    var indexBytes = haxe.io.Bytes.alloc(
                        indexBuffer.vertices * indexFormat.strideBytes);
                    indexBuffer.readBytes(indexBytes, 0, indexBuffer.vertices);
                    for (index in 0...indexBuffer.vertices) {
                        indices.push(indexIs32
                            ? indexBytes.getInt32(index * 4)
                            : indexBytes.getUInt16(index * 2));
                    }
                }
            }
            return { positions: positions, indices: indices };
        } catch (_:Dynamic) {
            return null;
        }
    }

    static inline function positionKey(p:h3d.Vector):String {
        return Math.round(p.x * POSITION_QUANTUM) + ":"
            + Math.round(p.y * POSITION_QUANTUM) + ":"
            + Math.round(p.z * POSITION_QUANTUM);
    }
}
