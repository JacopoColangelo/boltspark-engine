package boltspark.editor;

import boltspark.editor.shaders.GizmoFrontHemisphereShader;
import boltspark.ui.Theme;
import h2d.BlendMode;

/**
 * Result of one gizmo drag step. Main applies it to the scene object through
 * the editor command flow; the gizmo never mutates scene objects itself.
 */
enum GizmoResult {
	MovePosition(x:Float, y:Float, z:Float);
	RotateQuat(q:h3d.Quat);
	ScaleValues(sx:Float, sy:Float, sz:Float);
}

/**
 * Viewport transform gizmo (Move / Rotate / Scale) drawn in s3d at the
 * primary selection's position.
 *
 * Rendering is solid primitives only through the same DX12 driver as the
 * scene (always-on-top meshes that never write depth), in the Unreal
 * reference style: solid cylinder shafts with solid cone arrowheads,
 * two-axis plane quads, solid torus rotation rings, and solid boxes for
 * scale handles. Free rotation is an invisible arc-ball: any drag inside
 * the projected rotation rings that misses an axis ring tumbles the
 * object. No line graphics are used anywhere.
 *
 * All constrained-drag math lives here. Picking projects candidate handle
 * samples to engine pixels and compares them against the pointer, so hit
 * testing stays consistent at any camera distance. Drags solve ray/axis
 * (closest point), ray/plane (intersection), accumulated ring angles, and a
 * trackball mapping for omni rotation. Main converts viewport pointer
 * coordinates to rays plus engine-space pixel positions and applies returned
 * results through the editor command flow.
 */
class TransformGizmo {
	// Tool indices, mirroring the editor toolbar order.
	public static inline var TOOL_MOVE:Int = 0;
	public static inline var TOOL_ROTATE:Int = 1;
	public static inline var TOOL_SCALE:Int = 2;

	// Handle ids. 0-2 are the X/Y/Z axes, 3-5 the XY/YZ/ZX two-axis plane
	// handles, and 6 the tool-specific center handle (free view-plane move /
	// rotate omni ball / uniform scale box).
	public static inline var HANDLE_AXIS_X:Int = 0;
	public static inline var HANDLE_AXIS_Y:Int = 1;
	public static inline var HANDLE_AXIS_Z:Int = 2;
	public static inline var HANDLE_PLANE_XY:Int = 3;
	public static inline var HANDLE_PLANE_YZ:Int = 4;
	public static inline var HANDLE_PLANE_ZX:Int = 5;
	public static inline var HANDLE_CENTER:Int = 6;

	// Gizmo axis space (viewport HUD toggle): World keeps every handle
	// aligned to the world axes; Local aligns them to the attached object's
	// current rotation.
	public static inline var SPACE_WORLD:Int = 0;
	public static inline var SPACE_LOCAL:Int = 1;

	static inline var AXIS_LENGTH:Float = 1.05;
	static inline var HEAD_LENGTH:Float = 0.18;
	static inline var HEAD_RADIUS:Float = 0.1;
	static inline var PLANE_OFFSET:Float = 0.6;
	static inline var PLANE_HALF:Float = 0.13;
	static inline var RING_RADIUS:Float = 0.8;
	static inline var RING_TUBE:Float = 0.024;
	static inline var BOX_HALF:Float = 0.075;
	static inline var CENTER_HALF:Float = 0.1;
	static inline var SHAFT_RADIUS:Float = 0.026;
	static inline var SHAFT_END:Float = 0.92;
	static inline var SHAFT_PICK_START:Float = 0.2;
	static inline var PICK_PIXELS:Float = 14;
	static inline var RING_SEGMENTS:Int = 48;
	/** Tiny overlap at the silhouette avoids precision-sized gaps in the arcs. */
	static inline var RING_VISIBILITY_PADDING:Float = 0.001;
	static inline var OMNI_MIN_RADIUS:Float = 4;
	/** Local projection sample used to build stable pixels-per-world mappings. */
	static inline var SCREEN_PROJECTION_STEP:Float = 0.1;
	static inline var SCREEN_EPSILON_SQ:Float = 1e-8;
	static inline var PLANE_SCREEN_SIN_EPSILON:Float = 1e-4;

	final solidRoot:h3d.scene.Object;
	/** Scene reference for camera queries (the root the gizmo lives in). */
	final scene:h3d.scene.Scene;
	final moveShafts:Array<h3d.scene.Mesh> = [];
	final moveHeads:Array<h3d.scene.Mesh> = [];
	final movePlanes:Array<h3d.scene.Mesh> = [];
	var moveCenter:h3d.scene.Mesh;
	final rotateRings:Array<h3d.scene.Mesh> = [];
	final rotateRingMasks:Array<GizmoFrontHemisphereShader> = [];
	final scaleShafts:Array<h3d.scene.Mesh> = [];
	final scaleHeads:Array<h3d.scene.Mesh> = [];
	final scalePlanes:Array<h3d.scene.Mesh> = [];
	var scaleCenter:h3d.scene.Mesh;	/** Reusable solver result (the gizmo solves one axis at a time). */
	final closest:AxisRayClosest = new AxisRayClosest();
	var attached:h3d.scene.Object;
	var currentTool:Int = TOOL_MOVE;
	/** World/Local handle alignment (viewport HUD toggle). */
	var gizmoSpace:Int = SPACE_WORLD;
	var hoverHandle:Int = -1;
	var dragHandle:Int = -1;
	var dragKind:DragKind;

	/** Last drawn transform, so follow() only redraws on real changes. */
	final lastPos:h3d.Vector = new h3d.Vector(Math.NaN, 0, 0);
	final lastQuat:h3d.Quat = new h3d.Quat();

	// Shared drag anchors.
	final dragStartPos:h3d.Vector = new h3d.Vector();
	final startQuat:h3d.Quat = new h3d.Quat();
	final scaleStart:h3d.Vector = new h3d.Vector(1, 1, 1);
	/** Unbounded engine-pixel pointer captured when the drag begins. */
	final dragStartPointer:h3d.Vector = new h3d.Vector();
	/** Projected pixels per world unit for axis move/scale drags. */
	final dragScreenAxis:h3d.Vector = new h3d.Vector();
	var dragScreenAxisLengthSq:Float = 0;

	// Move axis drag.
	final dragAxis:h3d.Vector = new h3d.Vector();

	// Move/scale plane drag (two-axis handles). Captured at beginDrag and
	// never touched by drawing (drawing uses the draw* scratch basis below).
	final planeU:h3d.Vector = new h3d.Vector();
	final planeV:h3d.Vector = new h3d.Vector();
	final planeNormal:h3d.Vector = new h3d.Vector();
	/** Projected pixels per world unit for the captured plane basis. */
	final planeScreenU:h3d.Vector = new h3d.Vector();
	final planeScreenV:h3d.Vector = new h3d.Vector();
	var planeScreenDet:Float = 0;

	// Scratch plane basis for drawing/picking so redraws during a drag can
	// never corrupt the drag's captured plane frame.
	final drawPlaneU:h3d.Vector = new h3d.Vector();
	final drawPlaneV:h3d.Vector = new h3d.Vector();
	final drawPlaneN:h3d.Vector = new h3d.Vector();

	// Rotation ring drag.
	/** Engine-space axis for the editor's mapped X/Y/Z rotation handle. */
	final ringAxis:h3d.Vector = new h3d.Vector();
	final ringU:h3d.Vector = new h3d.Vector();
	final ringV:h3d.Vector = new h3d.Vector();
	var ringDelta:Float = 0;
	/** Fixed press-time ring tangent in pixels per radian. */
	final ringScreenTangent:h3d.Vector = new h3d.Vector();
	var ringScreenTangentLengthSq:Float = 0;

	// Omni trackball drag.
	final omniCenterPx:h3d.Vector = new h3d.Vector();
	var omniRadiusPx:Float = 100;
	var omniPrevS:h3d.Vector;
	/** Raw previous pointer paired with `omniPrevS`. */
	var omniPrevPx:Float = 0;
	var omniPrevPy:Float = 0;
	final omniQuat:h3d.Quat = new h3d.Quat();

	// Scale drag anchors.
	var scaleAxisT0:Float = 1;
	var scaleDist0:Float = 1;
	final scaleCenterPx:h3d.Vector = new h3d.Vector();
	final scaleScreenDirection:h3d.Vector = new h3d.Vector();
	var scaleDirectionPending:Bool = false;

	/** Scratch vectors for drag math (one call at a time). */
	final tmpA:h3d.Vector = new h3d.Vector();
	final tmpB:h3d.Vector = new h3d.Vector();
	final tmpC:h3d.Vector = new h3d.Vector();

	public function new(parent:h3d.scene.Object) {
		scene = parent.getScene();
		solidRoot = new h3d.scene.Object(parent);
		solidRoot.name = "TransformGizmoSolids";
		buildSolidHandles();
		solidRoot.visible = false;
	}

	/** Attach the gizmo to an object (or detach with null). */
	public function attach(target:Null<h3d.scene.Object>):Void {
		attached = target;
		hoverHandle = -1;
		dragHandle = -1;
		dragKind = null;
		lastPos.set(Math.NaN, 0, 0);
		refresh();
	}

	/** Switch the active viewport tool; each tool draws its own handles. */
	public function setTool(tool:Int):Void {
		currentTool = tool;
		hoverHandle = -1;
		dragHandle = -1;
		dragKind = null;
		refresh();
	}

	/** Switch world/local handle alignment; ignored while dragging. */
	public function setSpace(space:Int):Void {
		if (dragHandle >= 0 || space == gizmoSpace) return;
		gizmoSpace = space;
		hoverHandle = -1;
		redraw();
	}

	/** Current world direction for an axis handle (diagnostics/evidence). */
	public function getAxisDirection(axis:Int):h3d.Vector {
		return gizmoAxis(axis);
	}

	/** Human-readable handle name for console logging. */
	public function describe(handle:Int):String {
		var axisNames = "xyz";
		return switch (currentTool) {
			case TOOL_MOVE:
				switch (handle) {
					case HANDLE_CENTER: "position.view";
					case HANDLE_PLANE_XY: "plane.xy";
					case HANDLE_PLANE_YZ: "plane.yz";
					case HANDLE_PLANE_ZX: "plane.zx";
					default: 'position.${axisNames.charAt(handle)}';
				}
			case TOOL_ROTATE:
				switch (handle) {
					case HANDLE_CENTER: "rotation.omni";
					default: 'rotation.${axisNames.charAt(handle)}';
				}
			default:
				switch (handle) {
					case HANDLE_PLANE_XY: "scale.xy";
					case HANDLE_PLANE_YZ: "scale.yz";
					case HANDLE_PLANE_ZX: "scale.zx";
					case HANDLE_CENTER: "scale.uniform";
					default: 'scale.${axisNames.charAt(handle)}';
				}
		}
	}

	/** Highlight the handle under the pointer; returns true on a change. */
	public function setHover(handle:Int):Bool {
		if (dragHandle >= 0 || handle == hoverHandle) return false;
		hoverHandle = handle;
		redraw();
		return true;
	}

	/**
	 * Pick the handle nearest the pointer, or -1. Candidates are scored by
	 * their closest sample in engine pixels, so the test is consistent at any
	 * camera distance. `px`/`py` are engine-space pointer coordinates in the
	 * same space Main builds rays from.
	 */
	public function pick(ray:h3d.col.Ray, px:Float, py:Float):Int {
		if (attached == null) return -1;
		samples.resize(0);
		var best = -1;
		var bestDistance = PICK_PIXELS;
		for (handle in activeHandles()) {
			// Score each handle from only its own samples. Keeping prior handle
			// samples here biases later rings and can mismatch visible colors.
			samples.resize(0);
			collectSamples(handle, ray, samples);
			var distance = nearestSamplePixels(samples, px, py);
			if (distance >= 0 && distance < bestDistance) {
				bestDistance = distance;
				best = handle;
			}
		}
		// Free-rotate fallback: a pointer inside the projected gizmo that is
		// not near an axis ring starts a free arc-ball rotation, so the whole
		// ring interior is usable and no center ball handle is drawn.
		if (best < 0 && currentTool == TOOL_ROTATE && insideGizmoDisc(px, py)) {
			return HANDLE_CENTER;
		}
		return best;
	}

	/**
	 * Projected screen-space radius (engine pixels) of the rotation gizmo,
	 * measured along the camera's right axis.
	 */
	function projectedGizmoRadius():Float {
		var center = new h3d.Vector();
		projectToScreen(pointAt(0, 0, 0), center);
		var basis = cameraBasis();
		var edge = new h3d.Vector();
		projectToScreen(pointAt(basis.ax.x * RING_RADIUS,
			basis.ax.y * RING_RADIUS, basis.ax.z * RING_RADIUS), edge);
		var dx = edge.x - center.x;
		var dy = edge.y - center.y;
		return Math.max(OMNI_MIN_RADIUS, Math.sqrt(dx * dx + dy * dy));
	}

	/** True when the engine-space pointer lies within the gizmo's disc. */
	function insideGizmoDisc(px:Float, py:Float):Bool {
		var center = new h3d.Vector();
		projectToScreen(pointAt(0, 0, 0), center);
		var dx = px - center.x;
		var dy = py - center.y;
		return Math.sqrt(dx * dx + dy * dy) < projectedGizmoRadius() * 0.85;
	}

	/** Keep the gizmo glued to the attached object; call per frame. */
	public function follow():Void {
		if (attached == null || !solidRoot.visible) return;
		solidRoot.setPosition(attached.x, attached.y, attached.z);
		var quat = attached.getRotationQuat();
		var moved = attached.x != lastPos.x || attached.y != lastPos.y
			|| attached.z != lastPos.z;
		var rotated = quatChanged(quat);
		if (moved) {
			lastPos.set(attached.x, attached.y, attached.z);
		}
		// Keep the cached quaternion current in both modes, but only local
		// handles need rebuilt when the object rotates. World handles remain
		// fixed even while the selected object is explicitly rotated.
		if (rotated) {
			lastQuat.load(quat);
		}
		if (moved || (gizmoSpace == SPACE_LOCAL && rotated)) {
			redraw();
		}
	}

	function quatChanged(quat:h3d.Quat):Bool {
		return Math.abs(quat.x - lastQuat.x) > 1e-9
			|| Math.abs(quat.y - lastQuat.y) > 1e-9
			|| Math.abs(quat.z - lastQuat.z) > 1e-9
			|| Math.abs(quat.w - lastQuat.w) > 1e-9;
	}

	/**
	 * Start a drag of `handle` on `target` using the pointer ray and the
	 * engine-space pointer pixel. Anchors are captured so nothing jumps on
	 * the first move.
	 */
	public function beginDrag(handle:Int, target:h3d.scene.Object,
			ray:h3d.col.Ray, px:Float, py:Float):Void {
		dragHandle = handle;
		dragStartPos.set(target.x, target.y, target.z);
		startQuat.load(target.getRotationQuat());
		scaleStart.set(target.scaleX, target.scaleY, target.scaleZ);
		dragStartPointer.set(px, py, 0);
		hoverHandle = -1;

		if (currentTool == TOOL_MOVE) {
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KMoveAxis;
				dragAxis.load(gizmoAxis(handle));
				captureScreenDirection(dragAxis, dragScreenAxis);
				dragScreenAxisLengthSq = screenLengthSq(dragScreenAxis);
			} else if (handle == HANDLE_CENTER) {
				// Free move: translate within the camera view plane.
				dragKind = KMoveView;
				var basis = cameraBasis();
				planeU.load(basis.ax);
				planeV.load(basis.ay);
				planeNormal.load(basis.az);
				capturePlaneScreenBasis();
			} else {
				dragKind = KMovePlane;
				planeBasis(handle, planeU, planeV, planeNormal);
				capturePlaneScreenBasis();
			}
		} else if (currentTool == TOOL_ROTATE) {
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KRotRing;
				// Editor rotation X/Z map to the engine's Z/X axes respectively;
				// rendering, picking, and transform application all use this same
				// mapped axis. Y remains unchanged.
				var localAxis = axisVector(rotationEngineAxis(handle));
				if (gizmoSpace == SPACE_LOCAL) {
					quatRotate(startQuat, localAxis, ringAxis);
				} else {
					ringAxis.load(localAxis);
				}
				ringAxis.normalize();
				// Build a stable basis in the plane that is actually rendered.
				var reference = new h3d.Vector(1, 0, 0);
				if (Math.abs(ringAxis.x) > 0.9) reference.set(0, 1, 0);
				ringU.load(ringAxis.cross(reference));
				ringU.normalize();
				ringV.load(ringAxis.cross(ringU));
				ringV.normalize();
				var hit = rayPlaneHit(ray, dragStartPos, ringAxis, tmpA);
				var angle = 0.0;
				if (hit) angle = planeAngle(tmpA);
				ringDelta = 0;
				captureRingScreenTangent(angle);
			} else {
				dragKind = KRotOmni;
				projectToScreen(dragStartPos, omniCenterPx);
				// The trackball radius in engine pixels matches the projected
				// gizmo size, so a drag anywhere inside the rings maps onto
				// the virtual sphere with a continuous outside-rim continuation.
				omniRadiusPx = projectedGizmoRadius();
				omniPrevS = new h3d.Vector();
				storeOmniPrev(px, py);
				omniQuat.load(startQuat);
			}
		} else {
			scaleAxisT0 = 1;
			scaleDist0 = 1;
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KScaleAxis;
				dragAxis.load(gizmoAxis(handle));
				solveAxisRay(dragStartPos, dragAxis, ray, closest);
				if (closest.valid && closest.axisT > 0.05) {
					scaleAxisT0 = closest.axisT;
				}
				captureScreenDirection(dragAxis, dragScreenAxis);
				dragScreenAxisLengthSq = screenLengthSq(dragScreenAxis);
			} else if (handle <= HANDLE_PLANE_ZX) {
				dragKind = KScalePlane;
				planeBasis(handle, planeU, planeV, planeNormal);
				captureScaleScreenDirection(px, py);
			} else {
				dragKind = KScaleUniform;
				captureScaleScreenDirection(px, py);
			}
		}
		redraw();
	}

	/**
	 * Move the drag to an unbounded engine-pixel pointer. Drag mappings are
	 * captured at press time and consume screen displacement directly; no ray
	 * is built from an off-screen coordinate, so sensitivity cannot flatten as
	 * the virtual pointer travels farther beyond a monitor edge.
	 */
	public function dragTo(px:Float, py:Float):Null<GizmoResult> {
		if (dragHandle < 0 || dragKind == null) return null;
		return switch (dragKind) {
			case KMoveAxis: dragMoveAxis(px, py);
			case KMovePlane, KMoveView: dragMovePlane(px, py);
			case KRotRing: dragRotateRing(px, py);
			case KRotOmni: dragRotateOmni(px, py);
			case KScaleAxis: dragScaleAxis(px, py);
			case KScalePlane: dragScalePlane(px, py);
			case KScaleUniform: dragScaleUniform(px, py);
		};
	}

	function dragMoveAxis(px:Float, py:Float):Null<GizmoResult> {
		if (dragScreenAxisLengthSq < SCREEN_EPSILON_SQ) return null;
		var dx = px - dragStartPointer.x;
		var dy = py - dragStartPointer.y;
		var delta = (dx * dragScreenAxis.x + dy * dragScreenAxis.y)
			/ dragScreenAxisLengthSq;
		return MovePosition(
			dragStartPos.x + dragAxis.x * delta,
			dragStartPos.y + dragAxis.y * delta,
			dragStartPos.z + dragAxis.z * delta);
	}

	function dragMovePlane(px:Float, py:Float):Null<GizmoResult> {
		var basisMagnitude = Math.sqrt(screenLengthSq(planeScreenU)
			* screenLengthSq(planeScreenV));
		if (basisMagnitude < SCREEN_EPSILON_SQ
				|| Math.abs(planeScreenDet) < basisMagnitude * PLANE_SCREEN_SIN_EPSILON) {
			return null;
		}
		var dx = px - dragStartPointer.x;
		var dy = py - dragStartPointer.y;
		// Invert the projected 2x2 plane basis. This is a press-time local
		// screen mapping, so sensitivity remains constant even when the raw
		// pointer has travelled many screens away.
		var du = (dx * planeScreenV.y - dy * planeScreenV.x) / planeScreenDet;
		var dv = (planeScreenU.x * dy - planeScreenU.y * dx) / planeScreenDet;
		return MovePosition(
			dragStartPos.x + planeU.x * du + planeV.x * dv,
			dragStartPos.y + planeU.y * du + planeV.y * dv,
			dragStartPos.z + planeU.z * du + planeV.z * dv);
	}

	function dragRotateRing(px:Float, py:Float):Null<GizmoResult> {
		if (ringScreenTangentLengthSq < SCREEN_EPSILON_SQ) return null;
		var dx = px - dragStartPointer.x;
		var dy = py - dragStartPointer.y;
		// The press-time projected tangent is measured in pixels/radian.
		// Projecting total raw motion onto it gives an unbounded angle with
		// no atan2 radius falloff after the pointer passes a screen edge.
		ringDelta = (dx * ringScreenTangent.x + dy * ringScreenTangent.y)
			/ ringScreenTangentLengthSq;
		if (Math.abs(ringDelta) < 1e-9) return null;
		var quat = new h3d.Quat();
		quat.initRotateAxis(ringAxis.x, ringAxis.y, ringAxis.z, ringDelta);
		var result = new h3d.Quat();
		// Rotating around the object's local ring axis equals premultiplying
		// the same rotation expressed on the ring's world axis.
		result.multiply(quat, startQuat);
		return RotateQuat(result);
	}

	function dragRotateOmni(px:Float, py:Float):Null<GizmoResult> {
		if (omniPrevS == null) return null;
		// Raw-input events can coalesce a fast movement into one large delta.
		// Solving only its endpoints can make near-antipodal sphere points have
		// an almost-zero cross product and incorrectly look stationary. Follow
		// the actual screen segment in bounded steps instead.
		var startPx = omniPrevPx;
		var startPy = omniPrevPy;
		var normalizedDx = (px - startPx) / omniRadiusPx;
		var normalizedDy = (py - startPy) / omniRadiusPx;
		var substeps = ArcballRotation.segmentSubsteps(
			normalizedDx, normalizedDy);
		var basis = cameraBasis();
		var changed = false;
		for (step in 1...substeps + 1) {
			var t = step / substeps;
			if (applyOmniStep(
					startPx + (px - startPx) * t,
					startPy + (py - startPy) * t,
					basis)) {
				changed = true;
			}
		}
		if (!changed) return null;
		var result = new h3d.Quat();
		result.load(omniQuat);
		return RotateQuat(result);
	}

	/**
	 * Apply one bounded virtual-sphere pointer step.
	 *
	 * Absolute pointer positions map to successive points on the same Bell
	 * surface, preserving the view-axis component of off-centre/tangential
	 * motion. ArcballRotation uses normalized pointer travel for the angle so
	 * the flattened outside sheet cannot damp or bound a long raw-input drag.
	 */
	function applyOmniStep(px:Float, py:Float,
			basis:{ax:h3d.Vector, ay:h3d.Vector, az:h3d.Vector}):Bool {
		var previousX = (omniPrevPx - omniCenterPx.x) / omniRadiusPx;
		var previousY = -(omniPrevPy - omniCenterPx.y) / omniRadiusPx;
		var currentX = (px - omniCenterPx.x) / omniRadiusPx;
		var currentY = -(py - omniCenterPx.y) / omniRadiusPx;
		var currentSurface = omniScreenVector(px, py, tmpA);
		var cameraAxis = tmpC;
		var angle = ArcballRotation.cameraStep(
			omniPrevS, currentSurface,
			previousX, previousY, currentX, currentY, cameraAxis);
		if (angle <= 0) {
			storeOmniPrev(px, py);
			return false;
		}
		return applyOmniRotation(cameraAxis.x, cameraAxis.y, cameraAxis.z,
			angle, px, py, basis);
	}

	/** Map one camera-space arcball axis into world space and accumulate it. */
	function applyOmniRotation(cx:Float, cy:Float, cz:Float, angle:Float,
			px:Float, py:Float,
			basis:{ax:h3d.Vector, ay:h3d.Vector, az:h3d.Vector}):Bool {
		var worldAxis = tmpB;
		if (!ArcballRotation.worldAxis(
				cx, cy, cz, basis.ax, basis.ay, basis.az, worldAxis)) {
			storeOmniPrev(px, py);
			return false;
		}
		var quat = new h3d.Quat();
		quat.initRotateAxis(worldAxis.x, worldAxis.y, worldAxis.z, angle);
		omniQuat.multiply(quat, omniQuat);
		// Keep long freeform drags on the unit sphere; accumulated floating-point
		// drift must never leak into transform or Euler extraction.
		omniQuat.normalize();
		storeOmniPrev(px, py);
		return true;
	}

	/** Cache the paired Bell-surface point and raw pointer for the next step. */
	function storeOmniPrev(px:Float, py:Float):Void {
		omniPrevS.load(omniScreenVector(px, py, tmpA));
		omniPrevPx = px;
		omniPrevPy = py;
	}

	/**
	 * Map an engine-space pointer to the virtual trackball vector in camera
	 * space (right, up, toward-scene). Uses a continuous Bell trackball
	 * surface (hemisphere inside r^2 <= 0.5, hyperbolic sheet outside) so the
	 * response is C1-smooth across the entire viewport and never clamps,
	 * stalls, or inverts. Camera-facing hemisphere points have z <= 0.
	 */
	function omniScreenVector(px:Float, py:Float, out:h3d.Vector):h3d.Vector {
		var x = (px - omniCenterPx.x) / omniRadiusPx;
		var y = -(py - omniCenterPx.y) / omniRadiusPx;
		return ArcballRotation.surface(x, y, out);
	}

	function dragScaleAxis(px:Float, py:Float):Null<GizmoResult> {
		if (dragScreenAxisLengthSq < SCREEN_EPSILON_SQ) return null;
		var dx = px - dragStartPointer.x;
		var dy = py - dragStartPointer.y;
		var axisDelta = (dx * dragScreenAxis.x + dy * dragScreenAxis.y)
			/ dragScreenAxisLengthSq;
		var ratio = (scaleAxisT0 + axisDelta) / scaleAxisT0;
		return scaleResult(dragHandle, ratio);
	}

	function dragScalePlane(px:Float, py:Float):Null<GizmoResult> {
		var ratio = screenScaleRatio(px, py);
		if (ratio == null) return null;
		return scaleResult(dragHandle, ratio);
	}

	function dragScaleUniform(px:Float, py:Float):Null<GizmoResult> {
		var ratio = screenScaleRatio(px, py);
		if (ratio == null) return null;
		return scaleResult(HANDLE_CENTER, ratio);
	}

	/** Build a scale result applying `ratio` to the handle's axes. */
	function scaleResult(handle:Int, ratio:Float):GizmoResult {
		inline function scaled(start:Float):Float {
			return ScalePolicy.clamp(start * ratio, start);
		}
		return switch (handle) {
			case HANDLE_AXIS_X:
				ScaleValues(scaled(scaleStart.x), scaleStart.y, scaleStart.z);
			case HANDLE_AXIS_Y:
				ScaleValues(scaleStart.x, scaled(scaleStart.y), scaleStart.z);
			case HANDLE_AXIS_Z:
				ScaleValues(scaleStart.x, scaleStart.y, scaled(scaleStart.z));
			case HANDLE_PLANE_XY:
				ScaleValues(scaled(scaleStart.x), scaled(scaleStart.y), scaleStart.z);
			case HANDLE_PLANE_YZ:
				ScaleValues(scaleStart.x, scaled(scaleStart.y), scaled(scaleStart.z));
			case HANDLE_PLANE_ZX:
				ScaleValues(scaled(scaleStart.x), scaleStart.y, scaled(scaleStart.z));
			default:
				ScaleValues(scaled(scaleStart.x), scaled(scaleStart.y), scaled(scaleStart.z));
		};
	}

	/** End the active drag and return to hover highlighting. */
	public function endDrag():Void {
		dragHandle = -1;
		dragKind = null;
		omniPrevS = null;
		redraw();
	}

	function activeHandles():Array<Int> {
		// The center handle is checked first so a pointer near the gizmo
		// origin resolves to the free-move ball / free-rotate interior /
		// uniform box instead of an axis shaft sample that projects nearby.
		return switch (currentTool) {
			case TOOL_MOVE: [HANDLE_CENTER, 0, 1, 2, 3, 4, 5];
			case TOOL_ROTATE: [HANDLE_CENTER, 0, 1, 2];
			default: [HANDLE_CENTER, 0, 1, 2, 3, 4, 5];
		};
	}

	/** The scratch sample list used by pick(). */
	final samples:Array<h3d.Vector> = [];

	/**
	 * Collect world-space samples for one handle: shaft/head points for
	 * arrows, quad corners for planes, circle points for rings, and the
	 * handle centers for boxes.
	 */
	function collectSamples(handle:Int, ray:h3d.col.Ray, out:Array<h3d.Vector>):Void {
		if (currentTool == TOOL_ROTATE) {
			// HANDLE_CENTER has no samples of its own: pick() falls back to
			// the whole ring interior for free arc-ball rotation.
			if (handle <= HANDLE_AXIS_Z) {
				ringSamples(handle, RING_RADIUS, out);
			}
			return;
		}
		if (handle <= HANDLE_AXIS_Z) {
			var axis = gizmoAxis(handle);
			// Samples start off-center: the shaft region near the origin is
			// reserved for the center handle's pick radius.
			for (step in 0...8) {
				out.push(scaledAxisPoint(axis,
					SHAFT_PICK_START + step / 7 * (SHAFT_END - SHAFT_PICK_START)));
			}
			out.push(scaledAxisPoint(axis, AXIS_LENGTH));
			out.push(scaledAxisPoint(axis, AXIS_LENGTH - HEAD_LENGTH * 0.5));
		} else if (handle <= HANDLE_PLANE_ZX) {
			planeBasis(handle, drawPlaneU, drawPlaneV, drawPlaneN);
			var cx = PLANE_OFFSET * (drawPlaneU.x + drawPlaneV.x);
			var cy = PLANE_OFFSET * (drawPlaneU.y + drawPlaneV.y);
			var cz = PLANE_OFFSET * (drawPlaneU.z + drawPlaneV.z);
			for (du in [-1, 0, 1]) {
				for (dv in [-1, 0, 1]) {
					out.push(pointAt(
						cx + drawPlaneU.x * PLANE_HALF * du + drawPlaneV.x * PLANE_HALF * dv,
						cy + drawPlaneU.y * PLANE_HALF * du + drawPlaneV.y * PLANE_HALF * dv,
						cz + drawPlaneU.z * PLANE_HALF * du + drawPlaneV.z * PLANE_HALF * dv));
				}
			}
		} else {
			out.push(pointAt(0, 0, 0));
			if (currentTool == TOOL_MOVE) {
				var basis = cameraBasis();
				var half = CENTER_HALF * 1.15;
				for (sx in [-1, 1]) {
					for (sy in [-1, 1]) {
						out.push(pointAt(
							basis.ax.x * half * sx + basis.ay.x * half * sy,
							basis.ax.y * half * sx + basis.ay.y * half * sy,
							basis.ax.z * half * sx + basis.ay.z * half * sy));
					}
				}
			}
		}
	}

	/** Distance in engine pixels from the pointer to the nearest sample. */
	function nearestSamplePixels(samples:Array<h3d.Vector>, px:Float, py:Float):Float {
		var best = -1.0;
		for (sample in samples) {
			projectToScreen(sample, tmpC);
			var dx = tmpC.x - px;
			var dy = tmpC.y - py;
			var distance = Math.sqrt(dx * dx + dy * dy);
			if (best < 0 || distance < best) best = distance;
		}
		return best;
	}

	/** Project a world point to engine pixels (into out.x/out.y). */
	function projectToScreen(world:h3d.Vector, out:h3d.Vector):Void {
		var engine = h3d.Engine.getCurrent();
		var camera = scene.camera;
		var projected = camera.project(world.x, world.y, world.z,
			engine.width, engine.height, false);
		out.set(projected.x, projected.y, 0);
	}

	static inline function screenLengthSq(vector:h3d.Vector):Float {
		return vector.x * vector.x + vector.y * vector.y;
	}

	/**
	 * Project a unit world direction at the drag origin into engine pixels.
	 * A short local sample avoids perspective distortion from treating a whole
	 * world unit as a derivative, while division by the sample length leaves
	 * the result in pixels per world unit.
	 */
	function captureScreenDirection(direction:h3d.Vector, out:h3d.Vector):Void {
		var originPx = new h3d.Vector();
		var endPx = new h3d.Vector();
		projectToScreen(dragStartPos, originPx);
		var end = new h3d.Vector(
			dragStartPos.x + direction.x * SCREEN_PROJECTION_STEP,
			dragStartPos.y + direction.y * SCREEN_PROJECTION_STEP,
			dragStartPos.z + direction.z * SCREEN_PROJECTION_STEP);
		projectToScreen(end, endPx);
		out.set((endPx.x - originPx.x) / SCREEN_PROJECTION_STEP,
			(endPx.y - originPx.y) / SCREEN_PROJECTION_STEP, 0);
	}

	/** Capture the local screen Jacobian of the active movement plane. */
	function capturePlaneScreenBasis():Void {
		captureScreenDirection(planeU, planeScreenU);
		captureScreenDirection(planeV, planeScreenV);
		planeScreenDet = planeScreenU.x * planeScreenV.y
			- planeScreenU.y * planeScreenV.x;
	}

	/** World point on the captured rotation ring at `angle`. */
	function ringWorldPoint(angle:Float, out:h3d.Vector):Void {
		var cos = Math.cos(angle) * RING_RADIUS;
		var sin = Math.sin(angle) * RING_RADIUS;
		out.set(
			dragStartPos.x + ringU.x * cos + ringV.x * sin,
			dragStartPos.y + ringU.y * cos + ringV.y * sin,
			dragStartPos.z + ringU.z * cos + ringV.z * sin);
	}

	/**
	 * Capture the projected ring tangent at the grab point in pixels/radian.
	 * Ring drags subsequently use raw displacement against this fixed tangent
	 * instead of repeatedly taking atan2 of an ever more distant pointer.
	 */
	function captureRingScreenTangent(angle:Float):Void {
		var angleStep = 0.01;
		var world = new h3d.Vector();
		var nextWorld = new h3d.Vector();
		var projected = new h3d.Vector();
		var nextProjected = new h3d.Vector();
		ringWorldPoint(angle, world);
		ringWorldPoint(angle + angleStep, nextWorld);
		projectToScreen(world, projected);
		projectToScreen(nextWorld, nextProjected);
		ringScreenTangent.set(
			(nextProjected.x - projected.x) / angleStep,
			(nextProjected.y - projected.y) / angleStep, 0);
		ringScreenTangentLengthSq = screenLengthSq(ringScreenTangent);
	}

	/** Capture the outward screen direction used by plane/uniform scaling. */
	function captureScaleScreenDirection(px:Float, py:Float):Void {
		projectToScreen(dragStartPos, scaleCenterPx);
		var dx = px - scaleCenterPx.x;
		var dy = py - scaleCenterPx.y;
		var distanceSq = dx * dx + dy * dy;
		if (distanceSq < SCREEN_EPSILON_SQ) {
			// The exact center has no radial direction. The first non-zero raw
			// movement chooses one, after which reversing the mouse shrinks.
			scaleScreenDirection.set(0, 0, 0);
			scaleDist0 = OMNI_MIN_RADIUS;
			scaleDirectionPending = true;
			return;
		}
		var distance = Math.sqrt(distanceSq);
		scaleScreenDirection.set(dx / distance, dy / distance, 0);
		scaleDist0 = Math.max(OMNI_MIN_RADIUS, distance);
		scaleDirectionPending = false;
	}

	/** Linear, unbounded scale ratio from the accumulated raw pointer. */
	function screenScaleRatio(px:Float, py:Float):Null<Float> {
		var dx = px - dragStartPointer.x;
		var dy = py - dragStartPointer.y;
		if (scaleDirectionPending) {
			var distanceSq = dx * dx + dy * dy;
			if (distanceSq < SCREEN_EPSILON_SQ) return null;
			var distance = Math.sqrt(distanceSq);
			scaleScreenDirection.set(dx / distance, dy / distance, 0);
			scaleDirectionPending = false;
		}
		return 1 + (dx * scaleScreenDirection.x + dy * scaleScreenDirection.y)
			/ scaleDist0;
	}

	/** Camera basis: right (ax), up (ay), toward scene (az). */
	function cameraBasis():{ax:h3d.Vector, ay:h3d.Vector, az:h3d.Vector} {
		var camera = scene.camera;
		var az = camera.target.sub(camera.pos);
		az.normalize();
		var ax = camera.up.clone().cross(az);
		ax.normalize();
		var ay = az.cross(ax);
		return {ax: ax, ay: ay, az: az};
	}

	/** World point relative to the attached object's origin. */
	function pointAt(x:Float, y:Float, z:Float):h3d.Vector {
		return new h3d.Vector(
			(attached == null ? 0 : attached.x) + x,
			(attached == null ? 0 : attached.y) + y,
			(attached == null ? 0 : attached.z) + z);
	}

	function scaledAxisPoint(axis:h3d.Vector, t:Float):h3d.Vector {
		return pointAt(axis.x * t, axis.y * t, axis.z * t);
	}

	/** Fill `u`/`v`/`n` with the plane basis in the active world/local space. */
	function planeBasis(handle:Int, u:h3d.Vector, v:h3d.Vector,
			n:h3d.Vector):Void {
		switch (handle) {
			case HANDLE_PLANE_XY:
				u.load(gizmoAxis(HANDLE_AXIS_X));
				v.load(gizmoAxis(HANDLE_AXIS_Y));
				n.load(gizmoAxis(HANDLE_AXIS_Z));
			case HANDLE_PLANE_YZ:
				u.load(gizmoAxis(HANDLE_AXIS_Y));
				v.load(gizmoAxis(HANDLE_AXIS_Z));
				n.load(gizmoAxis(HANDLE_AXIS_X));
			default:
				u.load(gizmoAxis(HANDLE_AXIS_Z));
				v.load(gizmoAxis(HANDLE_AXIS_X));
				n.load(gizmoAxis(HANDLE_AXIS_Y));
		}
	}

	/** In-plane angle of a hit point around the captured ring basis. */
	function planeAngle(hit:h3d.Vector):Float {
		var dx = hit.x - dragStartPos.x;
		var dy = hit.y - dragStartPos.y;
		var dz = hit.z - dragStartPos.z;
		return Math.atan2(dx * ringV.x + dy * ringV.y + dz * ringV.z,
			dx * ringU.x + dy * ringU.y + dz * ringU.z);
	}

	static function axisVector(axis:Int):h3d.Vector {
		return switch (axis) {
			case 0: new h3d.Vector(1, 0, 0);
			case 1: new h3d.Vector(0, 1, 0);
			default: new h3d.Vector(0, 0, 1);
		};
	}

	/** One handle axis expressed in world coordinates for the active space. */
	function gizmoAxis(axis:Int):h3d.Vector {
		return gizmoDirection(axisVector(axis));
	}

	/** Convert a local direction to the active gizmo space. */
	function gizmoDirection(local:h3d.Vector):h3d.Vector {
		if (gizmoSpace != SPACE_LOCAL || attached == null) return local;
		var world = new h3d.Vector();
		quatRotate(attached.getRotationQuat(), local, world);
		world.normalize();
		return world;
	}

	/** Rotate `v` by `q` into `out` (v' = q v q^-1). */
	static function quatRotate(q:h3d.Quat, v:h3d.Vector, out:h3d.Vector):Void {
		var tx = 2 * (q.y * v.z - q.z * v.y);
		var ty = 2 * (q.z * v.x - q.x * v.z);
		var tz = 2 * (q.x * v.y - q.y * v.x);
		out.set(
			v.x + q.w * tx + (q.y * tz - q.z * ty),
			v.y + q.w * ty + (q.z * tx - q.x * tz),
			v.z + q.w * tz + (q.x * ty - q.y * tx));
	}

	/** Intersect `ray` with the plane through `point` along `normal`. */
	static function rayPlaneHit(ray:h3d.col.Ray, point:h3d.Vector,
			normal:h3d.Vector, out:h3d.Vector):Bool {
		var denom = ray.lx * normal.x + ray.ly * normal.y + ray.lz * normal.z;
		if (Math.abs(denom) < 1e-9) return false;
		var t = ((point.x - ray.px) * normal.x
			+ (point.y - ray.py) * normal.y
			+ (point.z - ray.pz) * normal.z) / denom;
		if (t < 0) return false;
		out.set(ray.px + ray.lx * t, ray.py + ray.ly * t, ray.pz + ray.lz * t);
		return true;
	}

	/**
	 * Solve the closest points between the pointer ray and the axis line
	 * (origin + t * axis, `axis` unit) with the standard two-line solution.
	 */
	static function solveAxisRay(origin:h3d.Vector, axis:h3d.Vector,
			ray:h3d.col.Ray, out:AxisRayClosest):Void {
		var wx = ray.px - origin.x;
		var wy = ray.py - origin.y;
		var wz = ray.pz - origin.z;
		var a = ray.lx * ray.lx + ray.ly * ray.ly + ray.lz * ray.lz;
		var b = ray.lx * axis.x + ray.ly * axis.y + ray.lz * axis.z;
		var c = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z;
		var d = ray.lx * wx + ray.ly * wy + ray.lz * wz;
		var e = axis.x * wx + axis.y * wy + axis.z * wz;
		var denom = a * c - b * b;
		if (Math.abs(denom) < 1e-9) {
			out.valid = false;
			return;
		}
		out.valid = true;
		var rayS = (b * e - c * d) / denom;
		out.axisT = (a * e - b * d) / denom;
		var dx = ray.px + ray.lx * rayS - (origin.x + axis.x * out.axisT);
		var dy = ray.py + ray.ly * rayS - (origin.y + axis.y * out.axisT);
		var dz = ray.pz + ray.lz * rayS - (origin.z + axis.z * out.axisT);
		out.distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
	}

	static function axisColor(axis:Int, active:Bool):Int {
		return switch (axis) {
			case 0: active ? Theme.GIZMO_AXIS_X_HOVER : Theme.GIZMO_AXIS_X;
			case 1: active ? Theme.GIZMO_AXIS_Y_HOVER : Theme.GIZMO_AXIS_Y;
			default: active ? Theme.GIZMO_AXIS_Z_HOVER : Theme.GIZMO_AXIS_Z;
		};
	}

	static function planeColor(handle:Int, active:Bool):Int {
		return switch (handle) {
			case HANDLE_PLANE_XY: active ? Theme.GIZMO_PLANE_XY_HOVER : Theme.GIZMO_PLANE_XY;
			case HANDLE_PLANE_YZ: active ? Theme.GIZMO_PLANE_YZ_HOVER : Theme.GIZMO_PLANE_YZ;
			default: active ? Theme.GIZMO_PLANE_ZX_HOVER : Theme.GIZMO_PLANE_ZX;
		};
	}

	/** Lerp `color` toward white by `amount` (0..1) for subtle hover hints. */
	static function brighten(color:Int, amount:Float):Int {
		var r = (color >> 16) & 0xFF;
		var g = (color >> 8) & 0xFF;
		var b = color & 0xFF;
		inline function lift(channel:Int):Int {
			return Math.round(channel + (0xFF - channel) * amount);
		}
		return (lift(r) << 16) | (lift(g) << 8) | lift(b);
	}

	// ------------------------------------------------------------------
	// Solid handle construction and placement (relative to the object).
	// ------------------------------------------------------------------

	static function configureOverlayMaterial(material:h3d.mat.Material):Void {
		material.shadows = false;
		material.mainPass.enableLights = false;
		material.mainPass.depthWrite = false;
		material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
		material.mainPass.culling = h3d.mat.Data.Face.None;
	}

	/**
	 * Build one handle mesh from a shared primitive. All handles are opaque
	 * solids with an always-on-top overlay material.
	 */
	function createSolid(primitive:h3d.prim.Primitive, name:String):h3d.scene.Mesh {
		var mesh = new h3d.scene.Mesh(primitive, null, solidRoot);
		mesh.name = name;
		configureOverlayMaterial(mesh.material);
		mesh.material.blendMode = Alpha;
		mesh.visible = false;
		return mesh;
	}

	function buildSolidHandles():Void {
		var shaft = GizmoPrimitives.cylinderX(16);
		var cone = GizmoPrimitives.coneX(20);
		var quad = GizmoPrimitives.quad();
		var cube = new h3d.prim.Cube(1, 1, 1, true);
		cube.addNormals();
		var centerBall = new h3d.prim.Sphere(CENTER_HALF * 1.2, 20, 14);
		centerBall.addNormals();
		for (axis in 0...3) {
			moveShafts.push(createSolid(shaft, 'MoveAxis${axis}Shaft'));
			moveHeads.push(createSolid(cone, 'MoveAxis${axis}Head'));
			movePlanes.push(createSolid(quad, 'MovePlane${axis}'));
			// Editor rotation X/Z map to engine Z/X. Build each colored ring on
			// that mapped axis so its rendering and transform semantics agree.
			var rotateRing = createSolid(
				GizmoPrimitives.axisTorus(rotationEngineAxis(axis), RING_RADIUS, RING_TUBE,
					RING_SEGMENTS, 10),
				'RotateRing${axis}');
			rotateRings.push(rotateRing);
			var mask = new GizmoFrontHemisphereShader();
			mask.visibilityPadding = RING_VISIBILITY_PADDING;
			rotateRing.material.mainPass.addShader(mask);
			rotateRingMasks.push(mask);
			scaleShafts.push(createSolid(shaft, 'ScaleAxis${axis}Shaft'));
			scaleHeads.push(createSolid(cube, 'ScaleAxis${axis}Head'));
			scalePlanes.push(createSolid(quad, 'ScalePlane${axis}'));
		}
		moveCenter = createSolid(centerBall, "MoveCenter");
		scaleCenter = createSolid(cube, "ScaleCenter");
	}

	/** Show a solid with its fill alpha. */
	function show(mesh:h3d.scene.Mesh, color:Int, alpha:Float):Void {
		mesh.visible = true;
		mesh.material.color.setColor(color);
		mesh.material.color.a = alpha;
	}

	function hideSolids(meshes:Array<h3d.scene.Mesh>):Void {
		for (mesh in meshes) mesh.visible = false;
	}

	function hideAllSolids():Void {
		hideSolids(moveShafts);
		hideSolids(moveHeads);
		hideSolids(movePlanes);
		hideSolids(rotateRings);
		hideSolids(scaleShafts);
		hideSolids(scaleHeads);
		hideSolids(scalePlanes);
		hideSolids([moveCenter, scaleCenter]);
	}

	/** Place a cylinder/cone mesh along `axis`. */
	function setAxisSolid(mesh:h3d.scene.Mesh, axis:h3d.Vector, start:Float,
			length:Float, radius:Float):Void {
		mesh.setPosition(axis.x * start, axis.y * start, axis.z * start);
		mesh.setDirection(axis);
		mesh.scaleX = length;
		mesh.scaleY = radius;
		mesh.scaleZ = radius;
	}

	/** Box handle at `t` along `axis` with independent side scales. */
	function setBoxSolid(mesh:h3d.scene.Mesh, axis:h3d.Vector, t:Float,
			sx:Float, sy:Float, sz:Float):Void {
		mesh.setPosition(axis.x * t, axis.y * t, axis.z * t);
		mesh.setDirection(axis);
		mesh.scaleX = sx;
		mesh.scaleY = sy;
		mesh.scaleZ = sz;
	}

	/** Flat quad mesh centered at (cx,cy,cz), X along `u`, facing `n`. */
	function setQuadSolid(mesh:h3d.scene.Mesh, cx:Float, cy:Float, cz:Float,
			u:h3d.Vector, n:h3d.Vector, size:Float):Void {
		mesh.setPosition(cx, cy, cz);
		mesh.setDirection(u, n);
		mesh.scaleX = size;
		mesh.scaleY = size;
		mesh.scaleZ = 1;
	}

	function setPlaneSolid(mesh:h3d.scene.Mesh, handle:Int):Void {
		planeBasis(handle, drawPlaneU, drawPlaneV, drawPlaneN);
		setQuadSolid(mesh,
			PLANE_OFFSET * (drawPlaneU.x + drawPlaneV.x),
			PLANE_OFFSET * (drawPlaneU.y + drawPlaneV.y),
			PLANE_OFFSET * (drawPlaneU.z + drawPlaneV.z),
			drawPlaneU, drawPlaneN, PLANE_HALF * 2);
	}

	function updateSolidHandles():Void {
		hideAllSolids();
		if (attached == null) return;
		switch (currentTool) {
			case TOOL_MOVE:
				for (axisIndex in 0...3) {
					var active = axisIndex == hoverHandle || axisIndex == dragHandle;
					var color = axisColor(axisIndex, active);
					var axis = gizmoAxis(axisIndex);
					setAxisSolid(moveShafts[axisIndex], axis, 0,
						AXIS_LENGTH - HEAD_LENGTH, SHAFT_RADIUS);
					show(moveShafts[axisIndex], color, 1);
					setAxisSolid(moveHeads[axisIndex], axis,
						AXIS_LENGTH - HEAD_LENGTH, HEAD_LENGTH, HEAD_RADIUS);
					show(moveHeads[axisIndex], color, 1);
				}
				var movePlaneHandles = [HANDLE_PLANE_XY, HANDLE_PLANE_YZ, HANDLE_PLANE_ZX];
				for (index in 0...movePlaneHandles.length) {
					var handle = movePlaneHandles[index];
					var active = handle == hoverHandle || handle == dragHandle;
					setPlaneSolid(movePlanes[index], handle);
					show(movePlanes[index], planeColor(handle, active),
						active ? 1 : 0.92);
				}
				var centerActive = HANDLE_CENTER == hoverHandle || HANDLE_CENTER == dragHandle;
				moveCenter.setPosition(0, 0, 0);
				moveCenter.setScale(1);
				show(moveCenter, centerActive ? Theme.GIZMO_NEUTRAL_HOVER
					: Theme.GIZMO_NEUTRAL, centerActive ? 1 : 0.9);

			case TOOL_ROTATE:
				var interiorActive = HANDLE_CENTER == hoverHandle
					|| HANDLE_CENTER == dragHandle;
				var localRotation = gizmoSpace == SPACE_LOCAL
					? attached.getRotationQuat().clone()
					: new h3d.Quat();
				for (axisIndex in 0...3) {
					var active = axisIndex == hoverHandle || axisIndex == dragHandle;
					var ringAxis = gizmoDirection(axisVector(rotationEngineAxis(axisIndex)));
					var mask = rotateRingMasks[axisIndex];
					mask.gizmoCenter.set(attached.x, attached.y, attached.z);
					mask.ringAxis.load(ringAxis);
					rotateRings[axisIndex].setPosition(0, 0, 0);
					rotateRings[axisIndex].setRotationQuat(localRotation.clone());
					rotateRings[axisIndex].setScale(1);
					// Arc-ball interior hover/drag slightly brightens every
					// ring as a hint that the whole disc rotates freely.
					var color = axisColor(axisIndex, active);
					if (interiorActive && !active) color = brighten(color, 0.25);
					show(rotateRings[axisIndex], color, 1);
				}
				// No center ball: HANDLE_CENTER is the invisible arc-ball
				// region covering the whole ring interior (see pick()).

			default:
				for (axisIndex in 0...3) {
					var active = axisIndex == hoverHandle || axisIndex == dragHandle;
					var color = axisColor(axisIndex, active);
					var axis = gizmoAxis(axisIndex);
					setAxisSolid(scaleShafts[axisIndex], axis, 0, SHAFT_END,
						SHAFT_RADIUS);
					show(scaleShafts[axisIndex], color, 1);
					setBoxSolid(scaleHeads[axisIndex], axis,
						AXIS_LENGTH - BOX_HALF * 1.4,
						BOX_HALF * 2.8, BOX_HALF * 2, BOX_HALF * 2);
					show(scaleHeads[axisIndex], color, 1);
				}
				var scalePlaneHandles = [HANDLE_PLANE_XY, HANDLE_PLANE_YZ, HANDLE_PLANE_ZX];
				for (index in 0...scalePlaneHandles.length) {
					var handle = scalePlaneHandles[index];
					var active = handle == hoverHandle || handle == dragHandle;
					setPlaneSolid(scalePlanes[index], handle);
					show(scalePlanes[index], planeColor(handle, active),
						active ? 1 : 0.92);
				}
				var centerActive = HANDLE_CENTER == hoverHandle || HANDLE_CENTER == dragHandle;
				scaleCenter.setPosition(0, 0, 0);
				scaleCenter.setRotation(0, 0, 0);
				scaleCenter.setScale(CENTER_HALF * 2);
				show(scaleCenter, centerActive ? Theme.GIZMO_NEUTRAL_HOVER
					: Theme.GIZMO_NEUTRAL, centerActive ? 1 : 0.95);
		}
	}

	function refresh():Void {
		var shown = attached != null;
		solidRoot.visible = shown;
		if (shown) {
			solidRoot.setPosition(attached.x, attached.y, attached.z);
			redraw();
		}
	}

	function redraw():Void {
		updateSolidHandles();
	}

	function ringSamples(axis:Int, radius:Float, out:Array<h3d.Vector>):Void {
		var engineAxis = rotationEngineAxis(axis);
		var worldU = gizmoDirection(perpendicularU(engineAxis));
		var worldV = gizmoDirection(perpendicularV(engineAxis));
		var center = pointAt(0, 0, 0);
		var viewDirection = scene.camera.pos.sub(center);
		viewDirection.normalize();
		for (segment in 0...RING_SEGMENTS) {
			var angle = segment / RING_SEGMENTS * Math.PI * 2;
			var cos = Math.cos(angle) * radius;
			var sin = Math.sin(angle) * radius;
			var x = worldU.x * cos + worldV.x * sin;
			var y = worldU.y * cos + worldV.y * sin;
			var z = worldU.z * cos + worldV.z * sin;
			// Keep hit testing aligned with the shader: hidden rear arcs must
			// not steal hover or drag input from visible handles/the arc-ball.
			if (x * viewDirection.x + y * viewDirection.y + z * viewDirection.z
					< -RING_VISIBILITY_PADDING) continue;
			out.push(pointAt(
				x, y, z));
		}
	}

	/**
	 * Convert an editor rotation component to the engine axis used to apply it.
	 * The editor convention swaps X/Z while preserving Y.
	 */
	static inline function rotationEngineAxis(axis:Int):Int {
		return switch (axis) {
			case HANDLE_AXIS_X: HANDLE_AXIS_Z;
			case HANDLE_AXIS_Z: HANDLE_AXIS_X;
			default: HANDLE_AXIS_Y;
		};
	}

	static function perpendicularU(axis:Int):h3d.Vector {
		return switch (axis) {
			case 0: new h3d.Vector(0, 1, 0);
			case 1: new h3d.Vector(1, 0, 0);
			default: new h3d.Vector(1, 0, 0);
		};
	}

	static function perpendicularV(axis:Int):h3d.Vector {
		return switch (axis) {
			case 0: new h3d.Vector(0, 0, 1);
			case 1: new h3d.Vector(0, 0, 1);
			default: new h3d.Vector(0, 1, 0);
		};
	}
}

/** Reusable result holder for the axis/pointer-ray closest-point solver. */
private class AxisRayClosest {
	public var valid:Bool = false;
	/** Parameter along the axis line. */
	public var axisT:Float = 0;
	/** World distance between the two closest points. */
	public var distance:Float = 0;

	public function new() {}
}

/** Drag modes selected by the tool and handle at beginDrag. */
private enum DragKind {
	KMoveAxis;
	KMovePlane;
	KMoveView;
	KRotRing;
	KRotOmni;
	KScaleAxis;
	KScalePlane;
	KScaleUniform;
}
