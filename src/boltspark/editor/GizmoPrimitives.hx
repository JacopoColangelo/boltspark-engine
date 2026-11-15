package boltspark.editor;

/** Procedural solid geometry shared by the viewport transform handles. */
class GizmoPrimitives {
    public static function cylinderX(segments:Int):h3d.prim.Polygon {
        var points:Array<h3d.col.Point> = [];
        var indexes = new hxd.IndexBuffer();
        for (end in 0...2) for (segment in 0...segments) {
            var angle = segment / segments * Math.PI * 2;
            points.push(new h3d.col.Point(end, Math.cos(angle), Math.sin(angle)));
        }
        var startCenter = points.length;
        points.push(new h3d.col.Point(0, 0, 0));
        var endCenter = points.length;
        points.push(new h3d.col.Point(1, 0, 0));
        for (segment in 0...segments) {
            var next = (segment + 1) % segments;
            var a = segment;
            var b = next;
            var c = segments + segment;
            var d = segments + next;
            indexes.push(a); indexes.push(c); indexes.push(b);
            indexes.push(b); indexes.push(c); indexes.push(d);
            indexes.push(startCenter); indexes.push(b); indexes.push(a);
            indexes.push(endCenter); indexes.push(c); indexes.push(d);
        }
        return withNormals(points, indexes);
    }

    public static function coneX(segments:Int):h3d.prim.Polygon {
        var points:Array<h3d.col.Point> = [];
        var indexes = new hxd.IndexBuffer();
        for (segment in 0...segments) {
            var angle = segment / segments * Math.PI * 2;
            points.push(new h3d.col.Point(0, Math.cos(angle), Math.sin(angle)));
        }
        var tip = points.length;
        points.push(new h3d.col.Point(1, 0, 0));
        var center = points.length;
        points.push(new h3d.col.Point(0, 0, 0));
        for (segment in 0...segments) {
            var next = (segment + 1) % segments;
            indexes.push(segment); indexes.push(tip); indexes.push(next);
            indexes.push(center); indexes.push(next); indexes.push(segment);
        }
        return withNormals(points, indexes);
    }

    public static function quad():h3d.prim.Polygon {
        var points = [
            new h3d.col.Point(-0.5, -0.5, 0), new h3d.col.Point(0.5, -0.5, 0),
            new h3d.col.Point(0.5, 0.5, 0), new h3d.col.Point(-0.5, 0.5, 0)
        ];
        var indexes = new hxd.IndexBuffer();
        indexes.push(0); indexes.push(1); indexes.push(2);
        indexes.push(0); indexes.push(2); indexes.push(3);
        return withNormals(points, indexes);
    }

    /** Torus whose plane and normal match TransformGizmo's ring samples. */
    public static function axisTorus(axis:Int, radius:Float, tube:Float,
            majorSegments:Int, minorSegments:Int):h3d.prim.Polygon {
        var points:Array<h3d.col.Point> = [];
        var indexes = new hxd.IndexBuffer();
        var normal = axisVector(axis);
        var u = perpendicularU(axis);
        var v = perpendicularV(axis);
        for (major in 0...majorSegments) {
            var angle = major / majorSegments * Math.PI * 2;
            var ca = Math.cos(angle);
            var sa = Math.sin(angle);
            for (minor in 0...minorSegments) {
                var around = minor / minorSegments * Math.PI * 2;
                var radial = radius + Math.cos(around) * tube;
                var normalOffset = Math.sin(around) * tube;
                points.push(new h3d.col.Point(
                    u.x * ca * radial + v.x * sa * radial + normal.x * normalOffset,
                    u.y * ca * radial + v.y * sa * radial + normal.y * normalOffset,
                    u.z * ca * radial + v.z * sa * radial + normal.z * normalOffset));
            }
        }
        for (major in 0...majorSegments) {
            var nextMajor = (major + 1) % majorSegments;
            for (minor in 0...minorSegments) {
                var nextMinor = (minor + 1) % minorSegments;
                var a = major * minorSegments + minor;
                var b = nextMajor * minorSegments + minor;
                var c = major * minorSegments + nextMinor;
                var d = nextMajor * minorSegments + nextMinor;
                indexes.push(a); indexes.push(b); indexes.push(c);
                indexes.push(c); indexes.push(b); indexes.push(d);
            }
        }
        return withNormals(points, indexes);
    }

    static function withNormals(points:Array<h3d.col.Point>,
            indexes:hxd.IndexBuffer):h3d.prim.Polygon {
        var primitive = new h3d.prim.Polygon(points, indexes);
        primitive.addNormals();
        return primitive;
    }

    static function axisVector(axis:Int):h3d.Vector {
        return switch (axis) {
            case 0: new h3d.Vector(1, 0, 0);
            case 1: new h3d.Vector(0, 1, 0);
            default: new h3d.Vector(0, 0, 1);
        };
    }

    static function perpendicularU(axis:Int):h3d.Vector {
        return switch (axis) {
            case 0: new h3d.Vector(0, 1, 0);
            case 1, 2: new h3d.Vector(1, 0, 0);
            default: new h3d.Vector(1, 0, 0);
        };
    }

    static function perpendicularV(axis:Int):h3d.Vector {
        return switch (axis) {
            case 0, 1: new h3d.Vector(0, 0, 1);
            default: new h3d.Vector(0, 1, 0);
        };
    }
}
