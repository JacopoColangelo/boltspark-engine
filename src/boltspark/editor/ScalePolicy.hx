package boltspark.editor;

/** Shared signed-scale safety policy used by inspector edits, snapping, and gizmos. */
class ScalePolicy {
    public static inline var MIN_MAGNITUDE:Float = 0.01;
    // This is only a finite-number safety ceiling. Spatial size is constrained
    // from transformed geometry by WorldBounds, never by this scale factor.
    public static inline var MAX_SAFE_MAGNITUDE:Float = 1000000000.0;

    /**
     * Clamp scale without discarding its sign. Exact/near zero values use the
     * supplied fallback sign so transforms never become singular while a drag
     * can still cross the origin and mirror the object.
     */
    public static function clamp(value:Float, fallbackSign:Float = 1,
            minMagnitude:Float = MIN_MAGNITUDE,
            maxMagnitude:Float = MAX_SAFE_MAGNITUDE):Float {
        var minimum = Math.max(0.000001, minMagnitude);
        var maximum = Math.max(minimum, maxMagnitude);
        if (!Math.isFinite(value)) {
            return (value < 0 || (value != value && fallbackSign < 0))
                ? -maximum
                : maximum;
        }
        if (value > maximum) return maximum;
        if (value < -maximum) return -maximum;
        if (value >= minimum || value <= -minimum) return value;
        return (value < 0 || (value == 0 && fallbackSign < 0))
            ? -minimum
            : minimum;
    }

    /** A sign-preserving denominator protected from zero. */
    public static function nonZero(value:Float, fallbackSign:Float = 1,
            minMagnitude:Float = MIN_MAGNITUDE):Float {
        var minimum = Math.max(0.000001, minMagnitude);
        if (value >= minimum || value <= -minimum) return value;
        return (value < 0 || (value == 0 && fallbackSign < 0))
            ? -minimum
            : minimum;
    }

    public static inline function isMirrored(x:Float, y:Float, z:Float):Bool {
        return x * y * z < 0;
    }
}
