package boltspark.editor;

/**
 * Editor-only free-fly camera controller (Unreal/Godot/Blender-style viewport
 * navigation).
 *
 * The controller is owned by the editor viewport bootstrap, never by the
 * gameplay scene: it drives the Heaps scene camera directly while editing and
 * holds no scene-graph objects. Navigation state (position, yaw, pitch) is
 * derived from the camera once at startup and rewritten into pos/target every
 * frame, which keeps the view roll-free (up is always world +Y) and pitch
 * clamped.
 *
 * Movement is frame-rate independent: while RMB free-look is active, a
 * desired velocity is built from the WASDQE key state each frame and the
 * actual velocity converges on it with exponential smoothing scaled by delta
 * time. Hovering the viewport alone never enables fly navigation.
 *
 * Pointer gestures are fed as viewport-local pixel deltas (y grows downward):
 *  - RMB look:    yaw += dx, pitch -= dy (FPS free-look).
 *  - Wheel hover: dolly forward/backward without entering fly mode.
 *  - MMB pan:     the world follows the cursor, scaled by pivot distance.
 *  - Alt+LMB orbit: the camera swings around the navigation pivot; the pivot
 *    depth is captured once so the orbit never jumps, using Unreal-style
 *    tumble direction.
 */
class EditorCameraController {
    /** Camera gesture kinds shared with the editor shell input layer. */
    public static inline var GESTURE_LOOK:Int = 0;
    public static inline var GESTURE_PAN:Int = 1;
    public static inline var GESTURE_ORBIT:Int = 2;

    public static inline var DEG_TO_RAD:Float = 0.017453292519943295; // Math.PI / 180
    public static inline var DEFAULT_FOCUS_DURATION:Float = 0.35;

    // Tunables. All are plain fields so future editor settings can bind them.

    /** Degrees of view rotation per pixel of mouse movement. */
    public var lookSensitivity:Float = 0.22;
    /** Multiplicative speed change per mouse-wheel step. */
    public var wheelStep:Float = 1.15;
    /** Fraction of base movement speed travelled by one hover-wheel step. */
    public var wheelDollyScale:Float = 0.2;
    /** Smallest useful hover-wheel movement in world units. */
    public var minWheelDolly:Float = 0.25;
    public var minSpeed:Float = 0.25;
    public var maxSpeed:Float = 512.0;
    /** Temporary Shift boost / Ctrl precision multipliers. */
    public var shiftBoost:Float = 2.0;
    public var ctrlPrecision:Float = 0.25;
    /** Exponential velocity smoothing rate (1/s); higher snaps faster. */
    public var moveSmoothing:Float = 14.0;
    /** Pitch clamp in degrees. */
    public var pitchLimit:Float = 89.0;
    /** Default base movement speed in world units per second. */
    public var defaultSpeed:Float = 10.0;
    /** Margin around an object framed by the Focus Selection command. */
    public var focusPadding:Float = 1.2;
    /** Empty or point-like objects still receive a useful focus frame. */
    public var minimumFocusRadius:Float = 0.5;
    /**
     * Seconds used by Focus Selection. The duration is deliberately independent
     * of travel distance so framing an object across the full editor world is
     * just as responsive as framing a nearby object.
     */
    public var focusDuration:Float = DEFAULT_FOCUS_DURATION;

    /** Set by Main from live editor-shell focus state. */
    public var viewportFocused:Bool = false;
    /** Main disables keyboard navigation while a gizmo drag owns the pointer. */
    public var keyboardEnabled:Bool = true;

    final camera:h3d.Camera;
    final position = new h3d.Vector();
    final velocity = new h3d.Vector();
    final orbitPivot = new h3d.Vector();
    final desiredVelocity = new h3d.Vector();
    final scratchForward = new h3d.Vector();
    final scratchRight = new h3d.Vector();
    final scratchUp = new h3d.Vector();
    final focusStart = new h3d.Vector();
    final focusDestination = new h3d.Vector();

    var yawRad:Float = 0;
    var pitchRad:Float = 0;
    var baseSpeed:Float = 10.0;
    var viewportWidth:Float = 1200.0;
    var viewportHeight:Float = 675.0;
    /** True only between an accepted RMB press and its matching release. */
    var lookActive:Bool = false;
    var orbiting:Bool = false;
    var orbitDistance:Float = 10.0;
    var focusActive:Bool = false;
    var focusElapsed:Float = 0.0;
    var activeFocusDuration:Float = 0.0;

    public function new(camera:h3d.Camera) {
        this.camera = camera;
        baseSpeed = defaultSpeed;
        syncFromCamera();
    }

    /**
     * Adopt the camera's current position and view direction as the
     * navigation state; the initial framing comes from scene setup.
     */
    public function syncFromCamera():Void {
        cancelFocusTransition();
        position.set(camera.pos.x, camera.pos.y, camera.pos.z);
        var fx = camera.target.x - camera.pos.x;
        var fy = camera.target.y - camera.pos.y;
        var fz = camera.target.z - camera.pos.z;
        var length = Math.sqrt(fx * fx + fy * fy + fz * fz);
        if (length > 0.000001) {
            fx /= length;
            fy /= length;
            fz /= length;
        } else {
            fx = 0;
            fy = 0;
            fz = -1;
        }
        pitchRad = Math.asin(fy < -1 ? -1 : fy > 1 ? 1 : fy);
        yawRad = Math.atan2(-fx, -fz);
        velocity.set(0, 0, 0);
    }

    public function setViewportSize(width:Float, height:Float):Void {
        if (width > 1) viewportWidth = width;
        if (height > 1) viewportHeight = height;
    }

    public function baseSpeedValue():Float {
        return baseSpeed;
    }

    /**
     * 0 = normal, 1 = Shift boost, 2 = Ctrl precision. Ctrl wins when both
     * are held so precision movement stays predictable. Modifiers are camera
     * controls only during an active RMB free-look session.
     */
    public function modifierState():Int {
        if (!navigationActive()) return 0;
        if (hxd.Key.isDown(hxd.Key.CTRL)) return 2;
        return hxd.Key.isDown(hxd.Key.SHIFT) ? 1 : 0;
    }

    /** Effective speed for the viewport overlay (base speed with modifiers). */
    public function effectiveSpeed():Float {
        return switch (modifierState()) {
            case 2: baseSpeed * ctrlPrecision;
            case 1: baseSpeed * shiftBoost;
            default: baseSpeed;
        };
    }

    /** Compact label for the viewport speed overlay. */
    public function speedLabel():String {
        var value = effectiveSpeed();
        var text = value >= 100 ? Std.string(Std.int(Math.round(value)))
            : Std.string(Math.round(value * 10) / 10);
        return 'SPEED ${text} U/S';
    }

    /**
     * Mouse wheel: a positive delta is a downward step (Heaps/Windows
     * normalization), which lowers speed; an upward step raises it.
     */
    public function adjustSpeedForWheel(delta:Float):Void {
        if (delta == 0 || !navigationActive()) return;
        baseSpeed *= delta > 0 ? 1 / wheelStep : wheelStep;
        if (baseSpeed < minSpeed) baseSpeed = minSpeed;
        if (baseSpeed > maxSpeed) baseSpeed = maxSpeed;
    }

    /**
     * Wheel over an idle hovered viewport: scroll up moves into the scene and
     * scroll down moves out. This is intentionally independent of RMB flight,
     * where the same wheel continues to adjust movement speed instead.
     */
    public function dollyForWheel(delta:Float):Void {
        if (delta == 0 || !viewportFocused || !keyboardEnabled
                || lookActive || orbiting) return;
        cancelFocusTransition();
        stopMovement();
        var forward = forwardVector();
        var step = Math.max(minWheelDolly, baseSpeed * wheelDollyScale);
        var distance = -delta * step;
        position.x += forward.x * distance;
        position.y += forward.y * distance;
        position.z += forward.z * distance;
        clampPosition();
        applyCamera();
    }

    /**
     * Smoothly frame a world-space sphere while preserving the current view
     * direction. The tighter of the horizontal and vertical FOVs determines
     * distance. Interpolation uses normalized time instead of world-unit speed,
     * keeping focus responsive even when the object is kilometres away.
     */
    public function focusOn(center:h3d.Vector, radius:Float):Bool {
        if (center == null || !Math.isFinite(center.x)
                || !Math.isFinite(center.y) || !Math.isFinite(center.z)
                || !Math.isFinite(radius)) return false;
        stopMovement();
        orbiting = false;
        var safeRadius = Math.max(minimumFocusRadius, Math.abs(radius));
        var halfHorizontal = EditorViewport.VIEW_FOV_DEG * 0.5 * DEG_TO_RAD;
        var aspect = viewportWidth / Math.max(1, viewportHeight);
        var halfVertical = Math.atan(Math.tan(halfHorizontal) / aspect);
        var limitingHalfFov = Math.min(halfHorizontal, halfVertical);
        var distance = safeRadius * focusPadding
            / Math.max(0.000001, Math.sin(limitingHalfFov));
        var forward = forwardVector();
        focusStart.set(position.x, position.y, position.z);
        focusDestination.set(
            WorldBounds.clampCoordinate(center.x - forward.x * distance),
            WorldBounds.clampCoordinate(center.y - forward.y * distance),
            WorldBounds.clampCoordinate(center.z - forward.z * distance));
        orbitPivot.set(center.x, center.y, center.z);
        var dx = focusDestination.x - center.x;
        var dy = focusDestination.y - center.y;
        var dz = focusDestination.z - center.z;
        orbitDistance = Math.sqrt(dx * dx + dy * dy + dz * dz);
        focusElapsed = 0.0;
        activeFocusDuration = Math.isFinite(focusDuration)
            ? Math.max(0.0, focusDuration)
            : DEFAULT_FOCUS_DURATION;
        var travelX = focusDestination.x - focusStart.x;
        var travelY = focusDestination.y - focusStart.y;
        var travelZ = focusDestination.z - focusStart.z;
        var travelSquared = travelX * travelX + travelY * travelY
            + travelZ * travelZ;
        focusActive = activeFocusDuration > 0.0 && travelSquared > 0.000000000001;
        if (!focusActive) {
            position.set(focusDestination.x, focusDestination.y,
                focusDestination.z);
            applyCamera();
        }
        return true;
    }

    /**
     * Smoothly frame the union of several world-space bounds, used when more
     * than one object is selected. Objects without render geometry should be
     * supplied as degenerate point bounds, so they still influence the frame.
     */
    public function focusOnBounds(boundsList:Array<h3d.col.Bounds>):Bool {
        if (boundsList == null || boundsList.length == 0) return false;
        var union = new h3d.col.Bounds();
        var any = false;
        for (bounds in boundsList) {
            if (bounds == null || !focusBoundsUsable(bounds)) continue;
            union.add(bounds);
            any = true;
        }
        if (!any || union.isEmpty()) return false;
        var center = new h3d.Vector(
            (union.xMin + union.xMax) * 0.5,
            (union.yMin + union.yMax) * 0.5,
            (union.zMin + union.zMax) * 0.5);
        var halfX = (union.xMax - union.xMin) * 0.5;
        var halfY = (union.yMax - union.yMin) * 0.5;
        var halfZ = (union.zMax - union.zMin) * 0.5;
        return focusOn(center, Math.sqrt(halfX * halfX + halfY * halfY
            + halfZ * halfZ));
    }

    static function focusBoundsUsable(bounds:h3d.col.Bounds):Bool {
        return Math.isFinite(bounds.xMin) && Math.isFinite(bounds.xMax)
            && Math.isFinite(bounds.yMin) && Math.isFinite(bounds.yMax)
            && Math.isFinite(bounds.zMin) && Math.isFinite(bounds.zMax)
            && bounds.xMax >= bounds.xMin && bounds.yMax >= bounds.yMin
            && bounds.zMax >= bounds.zMin;
    }

    /** True while Focus Selection owns camera placement. */
    public function isFocusTransitionActive():Bool {
        return focusActive;
    }

    /** Stop a focus flight at its current position. */
    public function cancelFocusTransition():Void {
        focusActive = false;
        focusElapsed = 0.0;
        activeFocusDuration = 0.0;
    }

    // ------------------------------------------------------------------
    // Pointer gestures (deltas are viewport pixels; y grows downward)
    // ------------------------------------------------------------------

    public function beginLook():Void {
        cancelFocusTransition();
        lookActive = true;
    }

    public function addLookDelta(dx:Float, dy:Float):Void {
        cancelFocusTransition();
        yawRad += dx * lookSensitivity * DEG_TO_RAD;
        pitchRad = clampPitch(pitchRad - dy * lookSensitivity * DEG_TO_RAD);
    }

    public function endLook():Void {
        lookActive = false;
        stopMovement();
    }

    public function beginPan():Void {
        cancelFocusTransition();
        // Anchor the pan depth like an orbit does: the current pivot is
        // projected onto the view axis so the pan scale matches the framing
        // under the cursor. Pan motion is perpendicular to the view axis,
        // so that anchor distance stays constant for the whole gesture.
        var forward = forwardVector();
        var alongAxis = (orbitPivot.x - position.x) * forward.x
            + (orbitPivot.y - position.y) * forward.y
            + (orbitPivot.z - position.z) * forward.z;
        if (alongAxis < 1.0) alongAxis = 1.0;
        orbitDistance = alongAxis;
        orbitPivot.set(
            position.x + forward.x * alongAxis,
            position.y + forward.y * alongAxis,
            position.z + forward.z * alongAxis);
    }

    public function addPanDelta(dx:Float, dy:Float):Void {
        cancelFocusTransition();
        var forward = forwardVector();
        var right = rightVector();
        var screenUp = screenUpVector();
        var scale = panScale();
        // Content follows the cursor: dragging right moves the camera left,
        // dragging down moves it up.
        position.x += (-right.x * dx + screenUp.x * dy) * scale;
        position.y += (-right.y * dx + screenUp.y * dy) * scale;
        position.z += (-right.z * dx + screenUp.z * dy) * scale;
        clampPosition();
    }

    public function endPan():Void {}

    /**
     * Start orbiting around `pivot`. The pivot is projected onto the current
     * view axis so the orbit radius is exact and the camera never jumps;
     * its depth is kept for the whole gesture.
     */
    public function beginOrbit(pivot:h3d.Vector):Void {
        cancelFocusTransition();
        var forward = forwardVector();
        var alongAxis = (pivot.x - position.x) * forward.x
            + (pivot.y - position.y) * forward.y
            + (pivot.z - position.z) * forward.z;
        if (alongAxis < 1.0) alongAxis = 1.0;
        orbitPivot.set(
            position.x + forward.x * alongAxis,
            position.y + forward.y * alongAxis,
            position.z + forward.z * alongAxis);
        orbitDistance = alongAxis;
        orbiting = true;
        applyOrbitPlacement();
    }

    public function addOrbitDelta(dx:Float, dy:Float):Void {
        if (!orbiting) return;
        // Match the pointer direction used by Unreal's Alt+LMB tumble instead
        // of applying the previous doubly-inverted orbit response.
        yawRad += dx * lookSensitivity * DEG_TO_RAD;
        pitchRad = clampPitch(pitchRad - dy * lookSensitivity * DEG_TO_RAD);
        applyOrbitPlacement();
    }

    public function endOrbit():Void {
        orbiting = false;
    }

    /** Window focus loss must never leave a stale velocity or stuck orbit. */
    public function onWindowFocusLost():Void {
        lookActive = false;
        cancelFocusTransition();
        stopMovement();
    }

    // ------------------------------------------------------------------
    // Frame update
    // ------------------------------------------------------------------

    public function update(dt:Float):Void {
        if (dt <= 0) return;
        if (focusActive) {
            // A gizmo drag disables camera input through keyboardEnabled. It
            // must also stop an in-flight focus so the projection cannot move
            // underneath the active transform handle.
            if (!keyboardEnabled) {
                cancelFocusTransition();
            } else {
                updateFocusTransition(dt);
                applyCamera();
                return;
            }
        }
        buildTargetVelocity();
        if (!navigationActive()) {
            // Releasing RMB must stop flight immediately. Letting the smoothed
            // velocity decay here would continue moving a camera that no
            // longer owns a navigation gesture.
            stopMovement();
        } else {
            var alpha = 1 - Math.exp(-moveSmoothing * dt);
            velocity.x += (desiredVelocity.x - velocity.x) * alpha;
            velocity.y += (desiredVelocity.y - velocity.y) * alpha;
            velocity.z += (desiredVelocity.z - velocity.z) * alpha;
        }
        if (!orbiting) {
            position.x += velocity.x * dt;
            position.y += velocity.y * dt;
            position.z += velocity.z * dt;
            clampPosition();
        }
        applyCamera();
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /** Exposed for input routing and the headless activation regression. */
    public function isFlyNavigationActive():Bool {
        return navigationActive();
    }

    /** Movement keys require viewport ownership and an active RMB look. */
    function navigationActive():Bool {
        return keyboardEnabled && viewportFocused && lookActive;
    }

    function stopMovement():Void {
        desiredVelocity.set(0, 0, 0);
        velocity.set(0, 0, 0);
    }

    function buildTargetVelocity():Void {
        desiredVelocity.set(0, 0, 0);
        if (orbiting || !navigationActive()) return;
        var forward = forwardVector();
        var right = rightVector();
        var any = false;
        if (hxd.Key.isDown(hxd.Key.W)) {
            desiredVelocity.x += forward.x;
            desiredVelocity.y += forward.y;
            desiredVelocity.z += forward.z;
            any = true;
        }
        if (hxd.Key.isDown(hxd.Key.S)) {
            desiredVelocity.x -= forward.x;
            desiredVelocity.y -= forward.y;
            desiredVelocity.z -= forward.z;
            any = true;
        }
        if (hxd.Key.isDown(hxd.Key.D)) {
            desiredVelocity.x += right.x;
            desiredVelocity.z += right.z;
            any = true;
        }
        if (hxd.Key.isDown(hxd.Key.A)) {
            desiredVelocity.x -= right.x;
            desiredVelocity.z -= right.z;
            any = true;
        }
        if (hxd.Key.isDown(hxd.Key.E)) {
            desiredVelocity.y += 1;
            any = true;
        }
        if (hxd.Key.isDown(hxd.Key.Q)) {
            desiredVelocity.y -= 1;
            any = true;
        }
        if (!any) return;
        // Normalize so diagonals do not move faster than a single axis.
        var length = Math.sqrt(desiredVelocity.x * desiredVelocity.x
            + desiredVelocity.y * desiredVelocity.y
            + desiredVelocity.z * desiredVelocity.z);
        if (length > 0.000001) {
            desiredVelocity.x /= length;
            desiredVelocity.y /= length;
            desiredVelocity.z /= length;
        }
        var speed = effectiveSpeed();
        desiredVelocity.x *= speed;
        desiredVelocity.y *= speed;
        desiredVelocity.z *= speed;
    }

    /** View forward from yaw/pitch; yaw 0 looks toward -Z with world Y up. */
    function forwardVector():h3d.Vector {
        var cosPitch = Math.cos(pitchRad);
        scratchForward.set(
            -Math.sin(yawRad) * cosPitch,
            Math.sin(pitchRad),
            -Math.cos(yawRad) * cosPitch);
        return scratchForward;
    }

    /** Screen-right direction: world up crossed with forward, normalized. */
    function rightVector():h3d.Vector {
        var forward = scratchForward;
        var rx = forward.z;
        var rz = -forward.x;
        var length = Math.sqrt(rx * rx + rz * rz);
        if (length < 0.000001) {
            // Degenerate straight-up/straight-down pitch (clamped well before
            // this, but keep the basis valid regardless).
            scratchRight.set(1, 0, 0);
        } else {
            scratchRight.set(rx / length, 0, rz / length);
        }
        return scratchRight;
    }

    /** Screen-up direction: forward crossed with right, normalized. */
    function screenUpVector():h3d.Vector {
        var forward = scratchForward;
        var right = scratchRight;
        scratchUp.set(
            forward.y * right.z,
            forward.z * right.x - forward.x * right.z,
            -forward.y * right.x);
        var length = Math.sqrt(scratchUp.x * scratchUp.x
            + scratchUp.y * scratchUp.y + scratchUp.z * scratchUp.z);
        if (length > 0.000001) {
            scratchUp.x /= length;
            scratchUp.y /= length;
            scratchUp.z /= length;
        }
        return scratchUp;
    }

    /** World distance covered by one pixel of pan at the pivot's depth. */
    function panScale():Float {
        var dx = position.x - orbitPivot.x;
        var dy = position.y - orbitPivot.y;
        var dz = position.z - orbitPivot.z;
        var distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (distance < 0.01) distance = 0.01;
        var halfFov = EditorViewport.VIEW_FOV_DEG * 0.5 * DEG_TO_RAD;
        return 2 * distance * Math.tan(halfFov) / Math.max(1, viewportWidth);
    }

    /** Place the camera on the orbit sphere while keeping the view on the pivot. */
    function applyOrbitPlacement():Void {
        var forward = forwardVector();
        position.set(
            orbitPivot.x - forward.x * orbitDistance,
            orbitPivot.y - forward.y * orbitDistance,
            orbitPivot.z - forward.z * orbitDistance);
        clampPosition();
    }

    /**
     * Cubic smoothstep has zero velocity at both ends. Placement is evaluated
     * directly from immutable endpoints, avoiding accumulated error and making
     * completion independent of frame rate and travel distance.
     */
    function updateFocusTransition(dt:Float):Void {
        focusElapsed += dt;
        var progress = activeFocusDuration <= 0.0
            ? 1.0
            : Math.min(1.0, focusElapsed / activeFocusDuration);
        var eased = progress * progress * (3.0 - 2.0 * progress);
        position.set(
            focusStart.x + (focusDestination.x - focusStart.x) * eased,
            focusStart.y + (focusDestination.y - focusStart.y) * eased,
            focusStart.z + (focusDestination.z - focusStart.z) * eased);
        clampPosition();
        if (progress >= 1.0) {
            // Snap to the exact endpoint so no asymptotic tail or large-world
            // floating-point residue remains after the transition.
            position.set(focusDestination.x, focusDestination.y,
                focusDestination.z);
            cancelFocusTransition();
        }
    }

    function applyCamera():Void {
        var forward = forwardVector();
        camera.pos.set(position.x, position.y, position.z);
        camera.target.set(
            position.x + forward.x,
            position.y + forward.y,
            position.z + forward.z);
    }

    function clampPitch(value:Float):Float {
        var limit = pitchLimit * DEG_TO_RAD;
        if (value < -limit) return -limit;
        if (value > limit) return limit;
        return value;
    }

    /** Keep the editor camera inside the transform boundary. */
    function clampPosition():Void {
        position.x = WorldBounds.clampCoordinate(position.x);
        position.y = WorldBounds.clampCoordinate(position.y);
        position.z = WorldBounds.clampCoordinate(position.z);
    }
}
