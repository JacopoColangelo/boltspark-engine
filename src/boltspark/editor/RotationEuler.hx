package boltspark.editor;

/**
 * Converts quaternion rotations to the editor's X/Y/Z degree convention
 * without switching abruptly between equivalent Euler representations.
 */
class RotationEuler {
    static inline var RAD_TO_DEG:Float = 57.29577951308232;
    static inline var GIMBAL_EPSILON:Float = 1e-6;

    /**
     * Return editor Euler degrees (editor X/Z map to engine Z/X). When a
     * reference is supplied, choose and unwrap the equivalent representation
     * nearest that reference instead of Heaps' smallest-magnitude branch.
     */
    public static function degrees(quat:h3d.Quat,
            ?reference:h3d.Vector):h3d.Vector {
        if (reference == null) {
            var canonical = quat.toEuler();
            return new h3d.Vector(
                canonical.z * RAD_TO_DEG,
                canonical.y * RAD_TO_DEG,
                canonical.x * RAD_TO_DEG);
        }

        var matrix = quat.toMatrix();
        var cy = Math.sqrt(matrix._11 * matrix._11 + matrix._12 * matrix._12);
        if (cy > GIMBAL_EPSILON) {
            var first = candidateNear(
                Math.atan2(matrix._23, matrix._33) * RAD_TO_DEG,
                Math.atan2(-matrix._13, cy) * RAD_TO_DEG,
                Math.atan2(matrix._12, matrix._11) * RAD_TO_DEG,
                reference);
            var second = candidateNear(
                Math.atan2(-matrix._23, -matrix._33) * RAD_TO_DEG,
                Math.atan2(-matrix._13, -cy) * RAD_TO_DEG,
                Math.atan2(-matrix._12, -matrix._11) * RAD_TO_DEG,
                reference);
            return distanceSq(first, reference) <= distanceSq(second, reference)
                ? first
                : second;
        }

        // At exact gimbal lock only engine X -/+ engine Z is observable.
        // Preserve the closest distribution of those two angles around the
        // previous hint while satisfying that observable relation exactly.
        var engineY = Math.atan2(-matrix._13, cy) * RAD_TO_DEG;
        var sign = engineY >= 0 ? 1.0 : -1.0;
        var relation = Math.atan2(-matrix._32, matrix._22) * RAD_TO_DEG;
        var referenceEngineX = reference.z;
        var referenceEngineZ = reference.x;
        var referenceRelation = referenceEngineX - sign * referenceEngineZ;
        relation = nearestEquivalent(relation, referenceRelation);
        var correction = relation - referenceRelation;
        var engineX = referenceEngineX + correction * 0.5;
        var engineZ = referenceEngineZ - sign * correction * 0.5;
        return new h3d.Vector(
            engineZ,
            nearestEquivalent(engineY, reference.y),
            engineX);
    }

    /** Unreal-style displayed Rotator range: (-180, 180]. */
    public static function normalizedDegrees(value:Float):Float {
        var normalized = value % 360;
        if (normalized > 180) normalized -= 360;
        if (normalized <= -180) normalized += 360;
        // Do not expose a distracting negative zero in numeric fields.
        return Math.abs(normalized) < 1e-10 ? 0 : normalized;
    }

    /** Normalize an editor Euler triplet for Details/Inspector presentation. */
    public static function normalized(degrees:h3d.Vector):h3d.Vector {
        return new h3d.Vector(
            normalizedDegrees(degrees.x),
            normalizedDegrees(degrees.y),
            normalizedDegrees(degrees.z));
    }

    /** Build one editor-space candidate and unwrap it around the hint. */
    static function candidateNear(engineX:Float, engineY:Float, engineZ:Float,
            reference:h3d.Vector):h3d.Vector {
        return new h3d.Vector(
            nearestEquivalent(engineZ, reference.x),
            nearestEquivalent(engineY, reference.y),
            nearestEquivalent(engineX, reference.z));
    }

    /** Add full turns until `value` is the representation nearest reference. */
    static function nearestEquivalent(value:Float, reference:Float):Float {
        return value + Math.floor((reference - value) / 360 + 0.5) * 360;
    }

    static inline function distanceSq(a:h3d.Vector, b:h3d.Vector):Float {
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var dz = a.z - b.z;
        return dx * dx + dy * dy + dz * dz;
    }
}
