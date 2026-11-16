package;

import boltspark.editor.EditorTransform;
import boltspark.editor.GridSnapping;

/** Regression for a torus drag immediately following arbitrary arcball rotation. */
class RotationRingRepro {
    static inline var DEG_TO_RAD:Float = 0.017453292519943295;
    static inline var RAD_TO_DEG:Float = 57.29577951308232;
    static inline var EPSILON:Float = 0.000001;

    static function main():Void {
        verifyPostArcballWorldRing();
        verifyPostArcballLocalRing();
        verifyUnsnappedRing();
        Sys.println("[rotation-ring] post-arcball axis-angle snapping passed");
    }

    /**
     * This near-gimbal freeform orientation reproduced the old jitter: at raw
     * 51° and 52° the requested 15° snap bin is the same, yet independently
     * snapping decomposed Euler components changed orientation by 21.18°.
     */
    static function verifyPostArcballWorldRing():Void {
        var start = quaternion(EditorTransform.fromEditorEulerDegrees(
            -130, 92.5, 152));
        var axis = new h3d.Vector(0, 1, 0);
        var snapping = new GridSnapping();
        snapping.enableRotation = true;
        snapping.rotationIndex = 4; // 15 degrees.

        var at51 = snapping.snapAxisRotationIncremental(
            start, axis, 51 * DEG_TO_RAD);
        var at52 = snapping.snapAxisRotationIncremental(
            start, axis, 52 * DEG_TO_RAD);
        var at53 = snapping.snapAxisRotationIncremental(
            start, axis, 53 * DEG_TO_RAD);

        assertQuatEquivalent(at51, expected(start, axis, 45),
            "51-degree world-ring result left its axis-angle snap bin");
        assertQuatEquivalent(at52, expected(start, axis, 45),
            "52-degree world-ring result jittered inside its snap bin");
        assertQuatEquivalent(at51, at52,
            "unchanged world-ring snap bin changed orientation");
        assertQuatEquivalent(at53, expected(start, axis, 60),
            "53-degree world-ring result did not enter the next snap bin");
        assertNear(quaternionDistanceDegrees(at52, at53), 15, EPSILON,
            "world ring did not advance by exactly one snap step");
    }

    /** Local rings capture their object-rotated axis in world space. */
    static function verifyPostArcballLocalRing():Void {
        var start = quaternion(EditorTransform.fromEditorEulerDegrees(
            38.55, -73.88, 21.93));
        var localAxis = new h3d.Vector(0, 0, 1);
        var worldAxis = rotate(start, localAxis);
        var snapping = new GridSnapping();
        snapping.enableRotation = true;
        snapping.rotationIndex = 4;

        for (rawDegrees in [0.0, 7.0, 8.0, 22.0, 23.0, 37.0, 38.0, 52.0, 53.0]) {
            var snappedDegrees = GridSnapping.snapValue(rawDegrees, 15);
            var actual = snapping.snapAxisRotationIncremental(
                start, worldAxis, rawDegrees * DEG_TO_RAD);
            assertQuatEquivalent(actual, expected(start, worldAxis, snappedDegrees),
                'local-ring mismatch at raw ${rawDegrees} degrees');
        }
    }

    static function verifyUnsnappedRing():Void {
        var start = quaternion(EditorTransform.fromEditorEulerDegrees(
            -44, 117, 63));
        var axis = unit(0.31, -0.82, 0.48);
        var snapping = new GridSnapping();
        snapping.enableRotation = false;
        var rawDegrees = 13.25;
        var actual = snapping.snapAxisRotationIncremental(
            start, axis, rawDegrees * DEG_TO_RAD);
        assertQuatEquivalent(actual, expected(start, axis, rawDegrees),
            "disabled rotation snapping changed the torus result");
    }

    static function expected(start:h3d.Quat, axis:h3d.Vector,
            degrees:Float):h3d.Quat {
        var normalizedAxis = axis.clone();
        normalizedAxis.normalize();
        var increment = new h3d.Quat();
        increment.initRotateAxis(normalizedAxis.x, normalizedAxis.y,
            normalizedAxis.z, degrees * DEG_TO_RAD);
        var result = new h3d.Quat();
        result.multiply(increment, start);
        result.normalize();
        return result;
    }

    static function quaternion(transform:EditorTransform):h3d.Quat {
        var result = new h3d.Quat(transform.rotationX, transform.rotationY,
            transform.rotationZ, transform.rotationW);
        result.normalize();
        return result;
    }

    static function rotate(quat:h3d.Quat, vector:h3d.Vector):h3d.Vector {
        var tx = 2 * (quat.y * vector.z - quat.z * vector.y);
        var ty = 2 * (quat.z * vector.x - quat.x * vector.z);
        var tz = 2 * (quat.x * vector.y - quat.y * vector.x);
        return new h3d.Vector(
            vector.x + quat.w * tx + (quat.y * tz - quat.z * ty),
            vector.y + quat.w * ty + (quat.z * tx - quat.x * tz),
            vector.z + quat.w * tz + (quat.x * ty - quat.y * tx));
    }

    static function unit(x:Float, y:Float, z:Float):h3d.Vector {
        var result = new h3d.Vector(x, y, z);
        result.normalize();
        return result;
    }

    static function quaternionDistanceDegrees(a:h3d.Quat, b:h3d.Quat):Float {
        var dot = Math.abs(a.dot(b));
        if (dot > 1) dot = 1;
        return 2 * Math.acos(dot) * RAD_TO_DEG;
    }

    static function assertQuatEquivalent(actual:h3d.Quat, expected:h3d.Quat,
            message:String):Void {
        if (Math.abs(actual.dot(expected)) < 1 - EPSILON) {
            throw '${message}: actual=${actual}, expected=${expected}';
        }
    }

    static function assertNear(actual:Float, expected:Float, epsilon:Float,
            message:String):Void {
        if (Math.abs(actual - expected) > epsilon) {
            throw '${message}: expected=${expected}, actual=${actual}';
        }
    }
}
