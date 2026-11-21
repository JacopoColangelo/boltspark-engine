package boltspark.editor;

/**
 * Turns one drag of a shared transform gizmo into a per-object world transform.
 *
 * The gizmo itself lives at a single pivot (the primary object for a single
 * selection, the selection's average position for a multi-selection). Main
 * feeds this helper the pivot's world transform at drag start and its current
 * desired world transform; every selected object then receives the same
 * world-space delta:
 *
 *   Move   - translate by the pivot's position delta,
 *   Rotate - orbit the object's position around the pivot and pre-compose the
 *            pivot's rotation delta into its world rotation,
 *   Scale  - scale the object's offset from the pivot and its own scale by the
 *            pivot's per-axis scale ratios.
 *
 * This is deliberately renderer-independent (plain quaternion math, no h3d
 * types) so the shared-pivot rules can be verified in headless repros. Local
 * transforms, bounds containment, and command history remain Main/EditorSession
 * responsibilities.
 */
class SharedGizmoDelta {
    public static inline var MOVE:Int = 0;
    public static inline var ROTATE:Int = 1;
    public static inline var SCALE:Int = 2;

    static inline var EPSILON:Float = 0.000000001;

    /** Compose an authored local transform with its parent's world matrix. */
    public static function worldFromParent(localWorld:EditorTransform,
            parentWorld:Null<TransformMatrix>,
            ?hint:EditorTransform):EditorTransform {
        if (localWorld == null) throw "Local transform cannot be null";
        if (parentWorld == null) return localWorld.clone();
        return EditorTransform.fromMatrix(
            parentWorld.multiplied(localWorld.toMatrix()), hint);
    }

    /**
     * Convert a desired world transform into a local transform against the
     * parent's previewed world matrix. During a shared drag the session model
     * still holds the drag-start transform, so resolving against that stale
     * matrix would double-apply a selected parent's delta to its children.
     */
    public static function localForWorld(desiredWorld:EditorTransform,
            parentWorld:Null<TransformMatrix>,
            hint:EditorTransform):EditorTransform {
        if (desiredWorld == null) throw "Desired world transform cannot be null";
        if (parentWorld == null) return desiredWorld.clone();
        return EditorTransform.fromMatrix(
            parentWorld.inverse().multiplied(desiredWorld.toMatrix()), hint);
    }

    public static function apply(startWorld:EditorTransform,
            pivotStart:EditorTransform, pivotEnd:EditorTransform,
            mode:Int):EditorTransform {
        var result = startWorld.clone();
        if (startWorld == null || pivotStart == null || pivotEnd == null) return result;
        return switch (mode) {
            case MOVE: applyMove(result, pivotStart, pivotEnd);
            case ROTATE: applyRotate(result, pivotStart, pivotEnd);
            case SCALE: applyScale(result, pivotStart, pivotEnd);
            default: result;
        };
    }

    static function applyMove(result:EditorTransform,
            pivotStart:EditorTransform, pivotEnd:EditorTransform):EditorTransform {
        result.positionX += pivotEnd.positionX - pivotStart.positionX;
        result.positionY += pivotEnd.positionY - pivotStart.positionY;
        result.positionZ += pivotEnd.positionZ - pivotStart.positionZ;
        return result;
    }

    static function applyRotate(result:EditorTransform,
            pivotStart:EditorTransform, pivotEnd:EditorTransform):EditorTransform {
        var startQ = normalized(pivotStart.rotationX, pivotStart.rotationY,
            pivotStart.rotationZ, pivotStart.rotationW);
        var endQ = normalized(pivotEnd.rotationX, pivotEnd.rotationY,
            pivotEnd.rotationZ, pivotEnd.rotationW);
        // Delta that carries the pivot from its start to its current rotation.
        var delta = multiply(endQ, inverse(startQ));

        var dx = result.positionX - pivotStart.positionX;
        var dy = result.positionY - pivotStart.positionY;
        var dz = result.positionZ - pivotStart.positionZ;
        var rotated = rotateVector(delta, dx, dy, dz);
        result.positionX = pivotEnd.positionX + rotated.x;
        result.positionY = pivotEnd.positionY + rotated.y;
        result.positionZ = pivotEnd.positionZ + rotated.z;

        var objectQ = normalized(result.rotationX, result.rotationY,
            result.rotationZ, result.rotationW);
        var combined = normalizedMultiply(delta, objectQ);
        result.rotationX = combined.x;
        result.rotationY = combined.y;
        result.rotationZ = combined.z;
        result.rotationW = combined.w;
        // Object-local Euler hints describe a decomposed branch, not a stable
        // representation of an arbitrary composed quaternion.
        result.rotationHintValid = false;
        result.rotationHintX = 0;
        result.rotationHintY = 0;
        result.rotationHintZ = 0;
        return result;
    }

    static function applyScale(result:EditorTransform,
            pivotStart:EditorTransform, pivotEnd:EditorTransform):EditorTransform {
        var fx = ratio(pivotEnd.scaleX, pivotStart.scaleX);
        var fy = ratio(pivotEnd.scaleY, pivotStart.scaleY);
        var fz = ratio(pivotEnd.scaleZ, pivotStart.scaleZ);
        result.positionX = pivotEnd.positionX
            + (result.positionX - pivotStart.positionX) * fx;
        result.positionY = pivotEnd.positionY
            + (result.positionY - pivotStart.positionY) * fy;
        result.positionZ = pivotEnd.positionZ
            + (result.positionZ - pivotStart.positionZ) * fz;
        result.scaleX *= fx;
        result.scaleY *= fy;
        result.scaleZ *= fz;
        return result;
    }

    static inline function ratio(end:Float, start:Float):Float {
        return Math.abs(start) < EPSILON ? 1 : end / start;
    }

    static function normalized(x:Float, y:Float, z:Float, w:Float):Quat4 {
        var scale = Math.sqrt(x * x + y * y + z * z + w * w);
        if (!Math.isFinite(scale) || scale < EPSILON) return {x: 0, y: 0, z: 0, w: 1};
        return {x: x / scale, y: y / scale, z: z / scale, w: w / scale};
    }

    static function multiply(a:Quat4, b:Quat4):Quat4 {
        return {
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        };
    }

    static function normalizedMultiply(a:Quat4, b:Quat4):Quat4 {
        var q = multiply(a, b);
        return normalized(q.x, q.y, q.z, q.w);
    }

    /** Conjugate of a unit quaternion is its inverse. */
    static inline function inverse(q:Quat4):Quat4 {
        return {x: -q.x, y: -q.y, z: -q.z, w: q.w};
    }

    /** Rotate `v` by quaternion `q` (q * v * q^-1). */
    static function rotateVector(q:Quat4, x:Float, y:Float, z:Float):Quat4 {
        var tx = 2 * (q.y * z - q.z * y);
        var ty = 2 * (q.z * x - q.x * z);
        var tz = 2 * (q.x * y - q.y * x);
        return {
            x: x + q.w * tx + (q.y * tz - q.z * ty),
            y: y + q.w * ty + (q.z * tx - q.x * tz),
            z: z + q.w * tz + (q.x * ty - q.y * tx),
            w: 0
        };
    }
}

/** Tiny plain quaternion tuple; avoids coupling this math to h3d. */
private typedef Quat4 = {
    var x:Float;
    var y:Float;
    var z:Float;
    var w:Float;
};
