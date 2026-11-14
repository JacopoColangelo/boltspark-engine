package boltspark.editor;

/**
 * Finite editor-world boundary shared by every transform command.
 *
 * Boltspark follows Unreal's centimetre-based world units, so an 800,000-unit
 * half extent gives a cube-shaped world from -8 km to +8 km on every axis.
 * Objects are constrained by their transformed geometry bounds, not only by
 * their pivot, and are clamped inside the world instead of being removed.
 */
class WorldBounds {
    public static inline var UNITS_PER_METRE:Float = 100.0;
    public static inline var HALF_EXTENT:Float = 8.0 * 1000.0 * UNITS_PER_METRE;
    public static inline var DIAMETER:Float = HALF_EXTENT * 2.0;

    /** Covers the farthest corner while the current editor camera is near the origin. */
    public static inline var CAMERA_FAR:Float = DIAMETER;

    static inline var EPSILON:Float = 0.001;
    static inline var SCALE_SEARCH_STEPS:Int = 48;
    static inline var SCALE_PROBE_LIMIT:Float = 1000000000.0;

    /** Clamp one world-space pivot coordinate to the finite world cube. */
    public static function clampCoordinate(value:Float):Float {
        if (!Math.isFinite(value)) {
            if (value < 0) return -HALF_EXTENT;
            if (value > 0) return HALF_EXTENT;
            return 0;
        }
        if (value < -HALF_EXTENT) return -HALF_EXTENT;
        if (value > HALF_EXTENT) return HALF_EXTENT;
        return value;
    }

    /** True when all transformed geometry lies inside the world boundary. */
    public static function containsObject(object:h3d.scene.Object):Bool {
        return containsBounds(object.getBounds());
    }

    /**
     * Move an object to the requested pivot, then shift it only as much as is
     * needed to keep its complete transformed bounds inside the world. The
     * previous position is restored if the object is too large to fit.
     */
    public static function placeInside(object:h3d.scene.Object,
            x:Float, y:Float, z:Float):Bool {
        var previousX = object.x;
        var previousY = object.y;
        var previousZ = object.z;
        object.setPosition(clampCoordinate(x), clampCoordinate(y), clampCoordinate(z));
        if (contain(object)) return true;
        object.setPosition(previousX, previousY, previousZ);
        return false;
    }

    /**
     * Shift the current transform into the world cube. Returns false without
     * changing the pivot when the transformed geometry is larger than the
     * world and therefore cannot fit at any position.
     */
    public static function contain(object:h3d.scene.Object):Bool {
        var bounds = object.getBounds();
        if (isEmpty(bounds)) return true;
        if (!isFinite(bounds)) return false;
        if (bounds.xMax - bounds.xMin > DIAMETER + EPSILON
                || bounds.yMax - bounds.yMin > DIAMETER + EPSILON
                || bounds.zMax - bounds.zMin > DIAMETER + EPSILON) {
            return false;
        }

        var dx = containmentOffset(bounds.xMin, bounds.xMax);
        var dy = containmentOffset(bounds.yMin, bounds.yMax);
        var dz = containmentOffset(bounds.zMin, bounds.zMax);
        if (dx != 0 || dy != 0 || dz != 0) {
            // Scene objects currently live directly under the identity scene
            // root, so local and world translation deltas are identical.
            object.setPosition(object.x + dx, object.y + dy, object.z + dz);
        }
        return containsObject(object);
    }

    /**
     * Find the closest scale on the path from the current value to `target`
     * whose complete transformed bounds still fit in the world. This avoids a
     * dimensionless scale-factor limit: primitive dimensions, rotation, and
     * distance from the origin all participate in the result.
     */
    public static function fitScale(object:h3d.scene.Object,
            targetX:Float, targetY:Float, targetZ:Float):h3d.Vector {
        var startX = object.scaleX;
        var startY = object.scaleY;
        var startZ = object.scaleZ;
        targetX = finiteScaleTarget(targetX, startX);
        targetY = finiteScaleTarget(targetY, startY);
        targetZ = finiteScaleTarget(targetZ, startZ);

        setScale(object, targetX, targetY, targetZ);
        if (containsObject(object)) {
            setScale(object, startX, startY, startZ);
            return new h3d.Vector(targetX, targetY, targetZ);
        }

        setScale(object, startX, startY, startZ);
        if (!containsObject(object)) {
            return new h3d.Vector(startX, startY, startZ);
        }

        // The world cube is convex and each transformed vertex is affine over
        // this interpolation, so the fitting values form one interval that
        // starts at t=0. Binary search its upper edge.
        var low = 0.0;
        var high = 1.0;
        for (_ in 0...SCALE_SEARCH_STEPS) {
            var middle = (low + high) * 0.5;
            setScale(object,
                startX + (targetX - startX) * middle,
                startY + (targetY - startY) * middle,
                startZ + (targetZ - startZ) * middle);
            if (containsObject(object)) low = middle else high = middle;
        }

        var result = new h3d.Vector(
            startX + (targetX - startX) * low,
            startY + (targetY - startY) * low,
            startZ + (targetZ - startZ) * low);
        setScale(object, startX, startY, startZ);
        return result;
    }

    public static function containsBounds(bounds:h3d.col.Bounds):Bool {
        if (isEmpty(bounds)) return true;
        return isFinite(bounds)
            && bounds.xMin >= -HALF_EXTENT - EPSILON
            && bounds.yMin >= -HALF_EXTENT - EPSILON
            && bounds.zMin >= -HALF_EXTENT - EPSILON
            && bounds.xMax <= HALF_EXTENT + EPSILON
            && bounds.yMax <= HALF_EXTENT + EPSILON
            && bounds.zMax <= HALF_EXTENT + EPSILON;
    }

    static inline function containmentOffset(minimum:Float, maximum:Float):Float {
        if (minimum < -HALF_EXTENT) return -HALF_EXTENT - minimum;
        if (maximum > HALF_EXTENT) return HALF_EXTENT - maximum;
        return 0;
    }

    static inline function isEmpty(bounds:h3d.col.Bounds):Bool {
        return bounds.xMax < bounds.xMin
            && bounds.yMax < bounds.yMin
            && bounds.zMax < bounds.zMin;
    }

    static inline function isFinite(bounds:h3d.col.Bounds):Bool {
        return Math.isFinite(bounds.xMin) && Math.isFinite(bounds.xMax)
            && Math.isFinite(bounds.yMin) && Math.isFinite(bounds.yMax)
            && Math.isFinite(bounds.zMin) && Math.isFinite(bounds.zMax);
    }

    static function finiteScaleTarget(value:Float, fallbackSign:Float):Float {
        if (Math.isFinite(value)) return value;
        if (value < 0 || (value != value && fallbackSign < 0)) return -SCALE_PROBE_LIMIT;
        return SCALE_PROBE_LIMIT;
    }

    static inline function setScale(object:h3d.scene.Object,
            x:Float, y:Float, z:Float):Void {
        object.scaleX = x;
        object.scaleY = y;
        object.scaleZ = z;
    }
}
