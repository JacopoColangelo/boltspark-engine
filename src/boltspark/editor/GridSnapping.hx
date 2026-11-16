package boltspark.editor;

/**
 * Unreal Engine-style transform grid snapping manager.
 *
 * Holds the editor's snap configuration: three independent enable flags
 * (translation, rotation, scale) and the active step value for each, drawn
 * from the same preset ramps Unreal's viewport snap dropdowns expose. The
 * manager itself is UI-agnostic — the viewport toolbar mutates its flags and
 * indices, and the gizmo drag path and snap-to-grid command query it.
 *
 * Snapping conventions:
 *  - Gizmo drags snap INCREMENTALLY: the drag delta is quantized onto step
 *    multiples and re-applied to the transform captured at drag start, so
 *    enabling snapping or toggling a mode never jumps an object onto the
 *    grid (Unreal's gizmo snapping behavior). Snap-to-grid is the only
 *    absolute snap and is an explicit Ctrl+End command.
 *  - Translation deltas snap componentwise against the translation grid
 *    (units, matching Unreal's centimeter-based uu).
 *  - A rotation ring snaps its accumulated angle around the press-time world
 *    axis before that axis-angle increment is composed with the drag-start
 *    quaternion. This remains single-axis after an arbitrary arc-ball rotation
 *    and never depends on an Euler decomposition branch. The omni arc-ball is
 *    deliberately freeform and bypasses this manager.
 *  - Scale deltas snap componentwise against the scale step. A signed dead
 *    zone prevents singular zero scale while still allowing mirrored values.
 */
class GridSnapping {
    /** Mode identifiers shared by the manager and the viewport toolbar. */
    public static inline var MODE_TRANSLATION:Int = 0;
    public static inline var MODE_ROTATION:Int = 1;
    public static inline var MODE_SCALE:Int = 2;

    /** Translation snap grid in editor units (Unreal's uu/cm preset ramp). */
    public static final TRANSLATION_PRESETS:Array<Float> = [
        0.1, 0.25, 0.5, 1.0, 5.0, 10.0, 25.0, 50.0, 100.0, 500.0, 1000.0];

    /** Rotation snap increments in degrees (Unreal's preset ramp). */
    public static final ROTATION_PRESETS:Array<Float> = [
        0.5, 1.0, 5.0, 10.0, 15.0, 30.0, 45.0, 90.0, 180.0];

    /** Scale snap steps (Unreal's preset ramp). */
    public static final SCALE_PRESETS:Array<Float> = [
        0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0];

    /**
     * Independent enable flags, all defaulting to on: the toolbar opens with
     * Unreal's common working state where every mode snaps.
     */
    public var enableTranslation:Bool = true;
    public var enableRotation:Bool = true;
    public var enableScale:Bool = true;

    /**
     * Active preset indices. Defaults: 1-unit translation, 15-degree
     * rotation, 0.25 scale.
     */
    public var translationIndex:Int = 3;
    public var rotationIndex:Int = 4;
    public var scaleIndex:Int = 3;

    /** Smallest signed scale magnitude the editor allows. */
    public var scaleMinimum:Float = ScalePolicy.MIN_MAGNITUDE;

    /**
     * Hold-key override: while true, incremental translation snapping is
     * suspended without changing the enable flag, so releasing the key
     * restores the previous snapping state exactly.
     */
    public var holdTranslationOff:Bool = false;

    public function new() {}

    public var translationStep(get, never):Float;
    function get_translationStep():Float {
        return TRANSLATION_PRESETS[clampIndex(translationIndex, TRANSLATION_PRESETS.length)];
    }

    public var rotationStep(get, never):Float;
    function get_rotationStep():Float {
        return ROTATION_PRESETS[clampIndex(rotationIndex, ROTATION_PRESETS.length)];
    }

    public var scaleStep(get, never):Float;
    function get_scaleStep():Float {
        return SCALE_PRESETS[clampIndex(scaleIndex, SCALE_PRESETS.length)];
    }

    public function isEnabled(mode:Int):Bool {
        return switch (mode) {
            case MODE_TRANSLATION: enableTranslation;
            case MODE_ROTATION: enableRotation;
            default: enableScale;
        };
    }

    /** Effective incremental translation snapping (enable flag minus hold key). */
    public var translationSnapActive(get, never):Bool;
    function get_translationSnapActive():Bool {
        return enableTranslation && !holdTranslationOff;
    }

    public function setEnabled(mode:Int, enabled:Bool):Void {
        switch (mode) {
            case MODE_TRANSLATION: enableTranslation = enabled;
            case MODE_ROTATION: enableRotation = enabled;
            default: enableScale = enabled;
        }
    }

    /** Number of presets a mode's dropdown shows. */
    public static function presetCount(mode:Int):Int {
        return switch (mode) {
            case MODE_TRANSLATION: TRANSLATION_PRESETS.length;
            case MODE_ROTATION: ROTATION_PRESETS.length;
            default: SCALE_PRESETS.length;
        };
    }

    public static function presetAt(mode:Int, index:Int):Float {
        return switch (mode) {
            case MODE_TRANSLATION: TRANSLATION_PRESETS[clampIndex(index, TRANSLATION_PRESETS.length)];
            case MODE_ROTATION: ROTATION_PRESETS[clampIndex(index, ROTATION_PRESETS.length)];
            default: SCALE_PRESETS[clampIndex(index, SCALE_PRESETS.length)];
        };
    }

    /** Currently active preset index for a mode. */
    public function presetIndex(mode:Int):Int {
        return switch (mode) {
            case MODE_TRANSLATION: translationIndex;
            case MODE_ROTATION: rotationIndex;
            default: scaleIndex;
        };
    }

    public function setPresetIndex(mode:Int, index:Int):Void {
        switch (mode) {
            case MODE_TRANSLATION: translationIndex = clampIndex(index, TRANSLATION_PRESETS.length);
            case MODE_ROTATION: rotationIndex = clampIndex(index, ROTATION_PRESETS.length);
            default: scaleIndex = clampIndex(index, SCALE_PRESETS.length);
        }
    }

    /** Active step magnitude for a mode. */
    public function stepFor(mode:Int):Float {
        return switch (mode) {
            case MODE_TRANSLATION: translationStep;
            case MODE_ROTATION: rotationStep;
            default: scaleStep;
        };
    }

    /** Snap one scalar onto the nearest step multiple. */
    public static function snapValue(value:Float, step:Float):Float {
        if (step <= 0) return value;
        return Math.round(value / step) * step;
    }

    /**
     * Absolute snap to the nearest translation grid point, independent of the
     * enable flag. Reserved for the explicit Ctrl+End snap-to-grid command;
     * drags always snap incrementally via snapPositionIncremental.
     */
    public function snapPositionToGrid(position:h3d.Vector):h3d.Vector {
        var step = translationStep;
        return new h3d.Vector(
            snapValue(position.x, step),
            snapValue(position.y, step),
            snapValue(position.z, step));
    }

    /**
     * Incremental translation snapping: quantize the drag delta onto step
     * multiples and re-apply it to the drag-start position. The object never
     * teleports onto the grid when snapping turns on or a drag begins.
     *
     * Pass the object's rotation quaternion as `localRotation` while the
     * gizmo is in Local space: the world delta is then expressed on the
     * object's local axes, those components are snapped against the grid,
     * and the result is mapped back to world space — so movement quantizes
     * along the object's own axes, not the world grid. In World space (or
     * with no rotation given) the delta snaps componentwise directly.
     */
    public function snapPositionIncremental(start:h3d.Vector, target:h3d.Vector,
            ?localRotation:h3d.Quat):h3d.Vector {
        if (!translationSnapActive) return target;
        var step = translationStep;
        var dx = target.x - start.x;
        var dy = target.y - start.y;
        var dz = target.z - start.z;
        var snappedX:Float;
        var snappedY:Float;
        var snappedZ:Float;
        if (localRotation == null) {
            snappedX = snapValue(dx, step);
            snappedY = snapValue(dy, step);
            snappedZ = snapValue(dz, step);
        } else {
            // Local axes from the object rotation (pure rotation, so they are
            // orthonormal): project the world delta onto each axis, snap the
            // local components, and rebuild the world delta.
            var basis = localRotation.toMatrix();
            var axisX = new h3d.Vector(1, 0, 0).transformed(basis);
            var axisY = new h3d.Vector(0, 1, 0).transformed(basis);
            var axisZ = new h3d.Vector(0, 0, 1).transformed(basis);
            var localX = snapValue(
                dx * axisX.x + dy * axisX.y + dz * axisX.z, step);
            var localY = snapValue(
                dx * axisY.x + dy * axisY.y + dz * axisY.z, step);
            var localZ = snapValue(
                dx * axisZ.x + dy * axisZ.y + dz * axisZ.z, step);
            snappedX = axisX.x * localX + axisY.x * localY + axisZ.x * localZ;
            snappedY = axisX.y * localX + axisY.y * localY + axisZ.y * localZ;
            snappedZ = axisX.z * localX + axisY.z * localY + axisZ.z * localZ;
        }
        return new h3d.Vector(
            start.x + snappedX,
            start.y + snappedY,
            start.z + snappedZ);
    }

    /** Quantize one accumulated ring angle without decomposing orientation. */
    public function snapRotationDeltaRadians(deltaRadians:Float):Float {
        return enableRotation
            ? degToRad(snapValue(radToDeg(deltaRadians), rotationStep))
            : deltaRadians;
    }

    /**
     * Apply an optionally snapped torus rotation to an arbitrary drag-start
     * orientation. `worldAxis` is captured when the drag begins. In Local mode
     * it is already the selected local axis transformed by `start`; therefore
     * premultiplication has the same result as a local postmultiplication while
     * avoiding any Euler conversion.
     */
    public function snapAxisRotationIncremental(start:h3d.Quat,
            worldAxis:h3d.Vector, deltaRadians:Float):h3d.Quat {
        var axisLengthSq = worldAxis.lengthSq();
        if (!Math.isFinite(axisLengthSq) || axisLengthSq <= 0.000000000001) {
            throw "Rotation ring axis must be finite and non-zero";
        }
        var inverseLength = 1 / Math.sqrt(axisLengthSq);
        var increment = new h3d.Quat();
        increment.initRotateAxis(
            worldAxis.x * inverseLength,
            worldAxis.y * inverseLength,
            worldAxis.z * inverseLength,
            snapRotationDeltaRadians(deltaRadians));
        var result = new h3d.Quat();
        result.multiply(increment, start);
        result.normalize();
        return result;
    }

    /**
     * Incremental scale snapping: quantize each per-axis scale delta onto the
     * scale step and re-apply it to the drag-start scale. Results preserve
     * their sign; values snapped onto zero use the unsnapped target's side of
     * the origin and are moved to the editor's minimum magnitude.
     */
    public function snapScaleIncremental(startX:Float, startY:Float, startZ:Float,
            targetX:Float, targetY:Float, targetZ:Float):h3d.Vector {
        if (!enableScale) return new h3d.Vector(targetX, targetY, targetZ);
        var step = scaleStep;
        var snappedX = startX + snapValue(targetX - startX, step);
        var snappedY = startY + snapValue(targetY - startY, step);
        var snappedZ = startZ + snapValue(targetZ - startZ, step);
        return new h3d.Vector(
            ScalePolicy.clamp(snappedX, targetX == 0 ? startX : targetX, scaleMinimum),
            ScalePolicy.clamp(snappedY, targetY == 0 ? startY : targetY, scaleMinimum),
            ScalePolicy.clamp(snappedZ, targetZ == 0 ? startZ : targetZ, scaleMinimum));
    }

    static function clampIndex(index:Int, count:Int):Int {
        if (count <= 0) return 0;
        return index < 0 ? 0 : (index >= count ? count - 1 : index);
    }

    public static inline function radToDeg(radians:Float):Float {
        return radians * 180 / Math.PI;
    }

    public static inline function degToRad(degrees:Float):Float {
        return degrees * Math.PI / 180;
    }
}
