package boltspark.editor;

import boltspark.ui.Theme;

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
 * Rendering is line graphics through the same DX12 driver as the scene
 * (always-on-top lines that never write depth) in the Unreal reference style:
 * arrow shafts with wireframe cone heads, two-axis plane quads, rotation
 * rings around each axis, a screen-facing omni ring for free rotation, and
 * wireframe boxes for scale handles.
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
	// handles, and 6 the tool-specific center handle (rotate omni ball /
	// uniform scale box).
	public static inline var HANDLE_AXIS_X:Int = 0;
	public static inline var HANDLE_AXIS_Y:Int = 1;
	public static inline var HANDLE_AXIS_Z:Int = 2;
	public static inline var HANDLE_PLANE_XY:Int = 3;
	public static inline var HANDLE_PLANE_YZ:Int = 4;
	public static inline var HANDLE_PLANE_ZX:Int = 5;
	public static inline var HANDLE_CENTER:Int = 6;

	static inline var AXIS_LENGTH:Float = 1.05;
	static inline var HEAD_LENGTH:Float = 0.2;
	static inline var HEAD_RADIUS:Float = 0.085;
	static inline var PLANE_OFFSET:Float = 0.6;
	static inline var PLANE_HALF:Float = 0.13;
	static inline var RING_RADIUS:Float = 1.05;
	static inline var OMNI_RADIUS:Float = 1.38;
	static inline var BOX_HALF:Float = 0.075;
	static inline var CENTER_HALF:Float = 0.1;
	static inline var SHAFT_END:Float = 0.92;
	static inline var SHAFT_PICK_START:Float = 0.2;
	static inline var PICK_PIXELS:Float = 14;
	static inline var LINE_WIDTH:Float = 2.2;
	static inline var LINE_WIDTH_ACTIVE:Float = 3.2;
	static inline var RING_WIDTH:Float = 1.8;
	static inline var RING_WIDTH_ACTIVE:Float = 3.0;
	static inline var RING_SEGMENTS:Int = 48;
	static inline var CONE_SEGMENTS:Int = 10;
	static inline var OMNI_MIN_RADIUS:Float = 4;

	final graphics:h3d.scene.Graphics;
	/** Reusable solver result (the gizmo solves one axis at a time). */
	final closest:AxisRayClosest = new AxisRayClosest();
	var attached:h3d.scene.Object;
	var currentTool:Int = TOOL_MOVE;
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

	// Move axis drag.
	var dragAnchorT:Float = 0;

	// Move/scale plane drag (two-axis handles). Captured at beginDrag and
	// never touched by drawing (drawing uses the draw* scratch basis below).
	final planeU:h3d.Vector = new h3d.Vector();
	final planeV:h3d.Vector = new h3d.Vector();
	final planeNormal:h3d.Vector = new h3d.Vector();
	final planeAnchor:h3d.Vector = new h3d.Vector();

	// Scratch plane basis for drawing/picking so redraws during a drag can
	// never corrupt the drag's captured plane frame.
	final drawPlaneU:h3d.Vector = new h3d.Vector();
	final drawPlaneV:h3d.Vector = new h3d.Vector();
	final drawPlaneN:h3d.Vector = new h3d.Vector();

	// Rotation ring drag.
	final ringAxis:h3d.Vector = new h3d.Vector();
	final ringU:h3d.Vector = new h3d.Vector();
	final ringV:h3d.Vector = new h3d.Vector();
	var ringLastAngle:Float = 0;
	var ringDelta:Float = 0;

	// Omni trackball drag.
	final omniCenterPx:h3d.Vector = new h3d.Vector();
	var omniPrevS:h3d.Vector;
	final omniQuat:h3d.Quat = new h3d.Quat();

	// Scale drag anchors.
	var scaleAxisT0:Float = 1;
	var scaleDist0:Float = 1;
	final scaleCenterPx:h3d.Vector = new h3d.Vector();

	/** Scratch vectors for drag math (one call at a time). */
	final tmpA:h3d.Vector = new h3d.Vector();
	final tmpB:h3d.Vector = new h3d.Vector();
	final tmpC:h3d.Vector = new h3d.Vector();

	public function new(parent:h3d.scene.Object) {
		graphics = new h3d.scene.Graphics(parent);
		graphics.name = "TransformGizmo";
		graphics.material.mainPass.depthWrite = false;
		graphics.material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
		graphics.visible = false;
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

	/** Human-readable handle name for console logging. */
	public function describe(handle:Int):String {
		var axisNames = "xyz";
		return switch (currentTool) {
			case TOOL_MOVE:
				switch (handle) {
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
			collectSamples(handle, ray, samples);
			var distance = nearestSamplePixels(samples, px, py);
			if (distance >= 0 && distance < bestDistance) {
				bestDistance = distance;
				best = handle;
			}
		}
		return best;
	}

	/** Keep the gizmo glued to the attached object; call per frame. */
	public function follow():Void {
		if (attached == null || !graphics.visible) return;
		graphics.setPosition(attached.x, attached.y, attached.z);
		var quat = attached.getRotationQuat();
		if (attached.x != lastPos.x || attached.y != lastPos.y
				|| attached.z != lastPos.z || quatChanged(quat)) {
			lastPos.set(attached.x, attached.y, attached.z);
			lastQuat.load(quat);
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
		hoverHandle = -1;

		if (currentTool == TOOL_MOVE) {
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KMoveAxis;
				solveAxisRay(dragStartPos, axisVector(handle), ray, closest);
				dragAnchorT = closest.valid ? closest.axisT : 0;
			} else {
				dragKind = KMovePlane;
				planeBasis(handle, planeU, planeV, planeNormal);
				planeAnchor.set(dragStartPos.x, dragStartPos.y, dragStartPos.z);
				if (rayPlaneHit(ray, dragStartPos, planeNormal, tmpA)) {
					planeAnchor.set(tmpA.x, tmpA.y, tmpA.z);
				}
			}
		} else if (currentTool == TOOL_ROTATE) {
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KRotRing;
				// The ring lies in the object's local plane; its world normal
				// is the local axis rotated by the object's orientation.
				var localAxis = axisVector(handle);
				quatRotate(startQuat, localAxis, ringAxis);
				ringAxis.normalize();
				// Build a stable orthonormal in-plane basis for angle reads.
				var reference = new h3d.Vector(1, 0, 0);
				if (Math.abs(ringAxis.x) > 0.9) reference.set(0, 1, 0);
				ringU.load(ringAxis.cross(reference));
				ringU.normalize();
				ringV.load(ringAxis.cross(ringU));
				ringV.normalize();
				var hit = rayPlaneHit(ray, dragStartPos, ringAxis, tmpA);
				var angle = 0.0;
				if (hit) angle = planeAngle(tmpA);
				ringLastAngle = angle;
				ringDelta = 0;
			} else {
				dragKind = KRotOmni;
				projectToScreen(dragStartPos, omniCenterPx);
				omniPrevS = null;
				omniQuat.load(startQuat);
			}
		} else {
			scaleAxisT0 = 1;
			scaleDist0 = 1;
			if (handle <= HANDLE_AXIS_Z) {
				dragKind = KScaleAxis;
				solveAxisRay(dragStartPos, axisVector(handle), ray, closest);
				if (closest.valid && Math.abs(closest.axisT) > 0.05) {
					scaleAxisT0 = closest.axisT;
				}
			} else if (handle <= HANDLE_PLANE_ZX) {
				dragKind = KScalePlane;
				planeBasis(handle, planeU, planeV, planeNormal);
				if (rayPlaneHit(ray, dragStartPos, planeNormal, tmpA)) {
					scaleDist0 = Math.max(1e-6, tmpA.sub(dragStartPos).length());
				} else {
					scaleDist0 = 1;
				}
			} else {
				dragKind = KScaleUniform;
				projectToScreen(dragStartPos, scaleCenterPx);
				var dx = px - scaleCenterPx.x;
				var dy = py - scaleCenterPx.y;
				scaleDist0 = Math.max(OMNI_MIN_RADIUS, Math.sqrt(dx * dx + dy * dy));
			}
		}
		redraw();
	}

	/**
	 * Move the drag for the current pointer ray. Returns the new transform,
	 * or null when this step is degenerate (parallel ray, tiny trackball
	 * radius) and the last valid state should be kept.
	 */
	public function dragTo(ray:h3d.col.Ray, px:Float, py:Float):Null<GizmoResult> {
		if (dragHandle < 0 || dragKind == null) return null;
		return switch (dragKind) {
			case KMoveAxis: dragMoveAxis(ray);
			case KMovePlane: dragMovePlane(ray);
			case KRotRing: dragRotateRing(ray);
			case KRotOmni: dragRotateOmni(px, py);
			case KScaleAxis: dragScaleAxis(ray);
			case KScalePlane: dragScalePlane(ray);
			case KScaleUniform: dragScaleUniform(px, py);
		};
	}

	function dragMoveAxis(ray:h3d.col.Ray):Null<GizmoResult> {
		solveAxisRay(dragStartPos, axisVector(dragHandle), ray, closest);
		if (!closest.valid) return null;
		var delta = closest.axisT - dragAnchorT;
		var axis = axisVector(dragHandle);
		return MovePosition(
			dragStartPos.x + axis.x * delta,
			dragStartPos.y + axis.y * delta,
			dragStartPos.z + axis.z * delta);
	}

	function dragMovePlane(ray:h3d.col.Ray):Null<GizmoResult> {
		if (!rayPlaneHit(ray, dragStartPos, planeNormal, tmpA)) return null;
		return MovePosition(
			dragStartPos.x + (tmpA.x - planeAnchor.x),
			dragStartPos.y + (tmpA.y - planeAnchor.y),
			dragStartPos.z + (tmpA.z - planeAnchor.z));
	}

	function dragRotateRing(ray:h3d.col.Ray):Null<GizmoResult> {
		if (!rayPlaneHit(ray, dragStartPos, ringAxis, tmpA)) return null;
		var angle = planeAngle(tmpA);
		var step = angle - ringLastAngle;
		// Normalize the step to (-pi, pi] so sweeps can accumulate turns.
		while (step > Math.PI) step -= Math.PI * 2;
		while (step <= -Math.PI) step += Math.PI * 2;
		ringLastAngle = angle;
		if (Math.abs(step) < 1e-9) return null;
		ringDelta += step;
		var quat = new h3d.Quat();
		quat.initRotateAxis(ringAxis.x, ringAxis.y, ringAxis.z, ringDelta);
		var result = new h3d.Quat();
		// Rotating around the object's local ring axis equals premultiplying
		// the same rotation expressed on the ring's world axis.
		result.multiply(quat, startQuat);
		return RotateQuat(result);
	}

	function dragRotateOmni(px:Float, py:Float):Null<GizmoResult> {
		var s = omniScreenVector(px, py, tmpA);
		if (s == null) return null;
		if (omniPrevS == null) {
			omniPrevS = new h3d.Vector();
			omniPrevS.load(s);
			return null;
		}
		var cx = omniPrevS.y * s.z - omniPrevS.z * s.y;
		var cy = omniPrevS.z * s.x - omniPrevS.x * s.z;
		var cz = omniPrevS.x * s.y - omniPrevS.y * s.x;
		var dot = omniPrevS.dot(s);
		var crossLength = Math.sqrt(cx * cx + cy * cy + cz * cz);
		if (crossLength < 1e-6) return null;
		var angle = Math.atan2(crossLength, dot);
		if (angle < 1e-6) return null;
		// Map the view-space trackball axis into the world through the
		// camera basis (right, up, toward-scene).
		var basis = cameraBasis();
		var worldAxis = tmpB;
		worldAxis.set(
			basis.ax.x * cx + basis.ay.x * cy + basis.az.x * cz,
			basis.ax.y * cx + basis.ay.y * cy + basis.az.y * cz,
			basis.ax.z * cx + basis.ay.z * cy + basis.az.z * cz);
		worldAxis.normalize();
		var quat = new h3d.Quat();
		quat.initRotateAxis(worldAxis.x, worldAxis.y, worldAxis.z, angle);
		omniQuat.multiply(quat, omniQuat);
		omniPrevS.load(s);
		var result = new h3d.Quat();
		result.load(omniQuat);
		return RotateQuat(result);
	}

	/** Screen delta mapped to a view-space unit vector (y up), or null. */
	function omniScreenVector(px:Float, py:Float, out:h3d.Vector):Null<h3d.Vector> {
		var dx = px - omniCenterPx.x;
		var dy = py - omniCenterPx.y;
		var length = Math.sqrt(dx * dx + dy * dy);
		if (length < OMNI_MIN_RADIUS) return null;
		out.set(dx / length, -dy / length, 0);
		return out;
	}

	function dragScaleAxis(ray:h3d.col.Ray):Null<GizmoResult> {
		solveAxisRay(dragStartPos, axisVector(dragHandle), ray, closest);
		if (!closest.valid) return null;
		var ratio = closest.axisT / scaleAxisT0;
		if (ratio <= 0) return null;
		return scaleResult(dragHandle, ratio);
	}

	function dragScalePlane(ray:h3d.col.Ray):Null<GizmoResult> {
		if (!rayPlaneHit(ray, dragStartPos, planeNormal, tmpA)) return null;
		var ratio = tmpA.sub(dragStartPos).length() / scaleDist0;
		if (ratio <= 0) return null;
		return scaleResult(dragHandle, ratio);
	}

	function dragScaleUniform(px:Float, py:Float):Null<GizmoResult> {
		var dx = px - scaleCenterPx.x;
		var dy = py - scaleCenterPx.y;
		var ratio = Math.sqrt(dx * dx + dy * dy) / scaleDist0;
		if (ratio <= 0) return null;
		return scaleResult(HANDLE_CENTER, ratio);
	}

	/** Build a scale result applying `ratio` to the handle's axes. */
	function scaleResult(handle:Int, ratio:Float):GizmoResult {
		inline function scaled(start:Float):Float {
			return Math.max(0.01, Math.min(1000, start * ratio));
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
		// origin resolves to the omni ball / uniform box instead of an axis
		// shaft sample that happens to project nearby.
		return switch (currentTool) {
			case TOOL_MOVE: [0, 1, 2, 3, 4, 5];
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
			if (handle <= HANDLE_AXIS_Z) {
				ringSamples(handle, RING_RADIUS, out);
			} else {
				omniRingSamples(out);
			}
			return;
		}
		if (handle <= HANDLE_AXIS_Z) {
			var axis = axisVector(handle);
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
		var camera = graphics.getScene().camera;
		var projected = camera.project(world.x, world.y, world.z,
			engine.width, engine.height, false);
		out.set(projected.x, projected.y, 0);
	}

	/** Camera basis: right (ax), up (ay), toward scene (az). */
	function cameraBasis():{ax:h3d.Vector, ay:h3d.Vector, az:h3d.Vector} {
		var camera = graphics.getScene().camera;
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

	/** Fill `u`/`v`/`n` with the two-axis plane handle's basis. */
	function planeBasis(handle:Int, u:h3d.Vector, v:h3d.Vector,
			n:h3d.Vector):Void {
		switch (handle) {
			case HANDLE_PLANE_XY:
				u.set(1, 0, 0); v.set(0, 1, 0); n.set(0, 0, 1);
			case HANDLE_PLANE_YZ:
				u.set(0, 1, 0); v.set(0, 0, 1); n.set(1, 0, 0);
			default:
				u.set(0, 0, 1); v.set(1, 0, 0); n.set(0, 1, 0);
		}
	}

	/** In-plane angle of a hit point around ringU/ringV from ringLastAngle. */
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
			case 0: active ? Theme.AXIS_X_HOVER : Theme.AXIS_X;
			case 1: active ? Theme.AXIS_Y_HOVER : Theme.AXIS_Y;
			default: active ? Theme.AXIS_Z_HOVER : Theme.AXIS_Z;
		};
	}

	static function planeColor(handle:Int, active:Bool):Int {
		return switch (handle) {
			case HANDLE_PLANE_XY: active ? Theme.AXIS_XY_HOVER : Theme.AXIS_XY;
			case HANDLE_PLANE_YZ: active ? Theme.AXIS_YZ_HOVER : Theme.AXIS_YZ;
			default: active ? Theme.AXIS_ZX_HOVER : Theme.AXIS_ZX;
		};
	}

	// ------------------------------------------------------------------
	// Drawing (all coordinates are relative to the object position).
	// ------------------------------------------------------------------

	function refresh():Void {
		graphics.visible = attached != null;
		if (graphics.visible) redraw();
	}

	function redraw():Void {
		graphics.clear();
		switch (currentTool) {
			case TOOL_MOVE: drawMoveGizmo();
			case TOOL_ROTATE: drawRotateGizmo();
			default: drawScaleGizmo();
		}
	}

	function drawMoveGizmo():Void {
		for (axis in 0...3) {
			var active = axis == hoverHandle || axis == dragHandle;
			graphics.lineStyle(active ? LINE_WIDTH_ACTIVE : LINE_WIDTH,
				axisColor(axis, active), 1);
			drawArrow(axis);
		}
		for (plane in [HANDLE_PLANE_XY, HANDLE_PLANE_YZ, HANDLE_PLANE_ZX]) {
			var active = plane == hoverHandle || plane == dragHandle;
			graphics.lineStyle(active ? 2.6 : 1.6, planeColor(plane, active), 1);
			drawPlaneQuad(plane);
		}
	}

	function drawRotateGizmo():Void {
		for (axis in 0...3) {
			var active = axis == hoverHandle || axis == dragHandle;
			graphics.lineStyle(active ? RING_WIDTH_ACTIVE : RING_WIDTH,
				axisColor(axis, active), 1);
			drawLocalRing(axis, RING_RADIUS);
		}
		var active = HANDLE_CENTER == hoverHandle || HANDLE_CENTER == dragHandle;
		graphics.lineStyle(active ? RING_WIDTH_ACTIVE : RING_WIDTH,
			active ? Theme.GIZMO_NEUTRAL_HOVER : Theme.GIZMO_NEUTRAL, 1);
		drawOmniRing();
	}

	function drawScaleGizmo():Void {
		for (axis in 0...3) {
			var active = axis == hoverHandle || axis == dragHandle;
			graphics.lineStyle(active ? LINE_WIDTH_ACTIVE : LINE_WIDTH,
				axisColor(axis, active), 1);
			drawScaleShaft(axis);
			drawAxisBox(axis);
		}
		for (plane in [HANDLE_PLANE_XY, HANDLE_PLANE_YZ, HANDLE_PLANE_ZX]) {
			var active = plane == hoverHandle || plane == dragHandle;
			graphics.lineStyle(active ? 2.6 : 1.6, planeColor(plane, active), 1);
			drawPlaneQuad(plane);
		}
		var active = HANDLE_CENTER == hoverHandle || HANDLE_CENTER == dragHandle;
		graphics.lineStyle(active ? 2.6 : 1.6,
			active ? Theme.GIZMO_NEUTRAL_HOVER : Theme.GIZMO_NEUTRAL, 1);
		drawCenterBox();
	}

	/** Shaft line plus a wireframe cone arrowhead for one axis. */
	function drawArrow(axis:Int):Void {
		var direction = axisVector(axis);
		var headStart = AXIS_LENGTH - HEAD_LENGTH;
		graphics.moveTo(0, 0, 0);
		graphics.lineTo(direction.x * headStart, direction.y * headStart,
			direction.z * headStart);
		drawCone(axis, headStart, AXIS_LENGTH, HEAD_RADIUS);
	}

	/** Scale tool shaft: short line ending before the handle box. */
	function drawScaleShaft(axis:Int):Void {
		var direction = axisVector(axis);
		graphics.moveTo(0, 0, 0);
		graphics.lineTo(direction.x * SHAFT_END, direction.y * SHAFT_END,
			direction.z * SHAFT_END);
	}

	/** Wireframe cone from base t0 to tip t1 along one axis. */
	function drawCone(axis:Int, t0:Float, t1:Float, radius:Float):Void {
		var direction = axisVector(axis);
		var u = perpendicularU(axis);
		var v = perpendicularV(axis);
		for (segment in 0...CONE_SEGMENTS) {
			var angle0 = segment / CONE_SEGMENTS * Math.PI * 2;
			var angle1 = (segment + 1) / CONE_SEGMENTS * Math.PI * 2;
			graphics.moveTo(
				direction.x * t0 + u.x * radius * Math.cos(angle0) + v.x * radius * Math.sin(angle0),
				direction.y * t0 + u.y * radius * Math.cos(angle0) + v.y * radius * Math.sin(angle0),
				direction.z * t0 + u.z * radius * Math.cos(angle0) + v.z * radius * Math.sin(angle0));
			graphics.lineTo(
				direction.x * t0 + u.x * radius * Math.cos(angle1) + v.x * radius * Math.sin(angle1),
				direction.y * t0 + u.y * radius * Math.cos(angle1) + v.y * radius * Math.sin(angle1),
				direction.z * t0 + u.z * radius * Math.cos(angle1) + v.z * radius * Math.sin(angle1));
			graphics.moveTo(
				direction.x * t0 + u.x * radius * Math.cos(angle0) + v.x * radius * Math.sin(angle0),
				direction.y * t0 + u.y * radius * Math.cos(angle0) + v.y * radius * Math.sin(angle0),
				direction.z * t0 + u.z * radius * Math.cos(angle0) + v.z * radius * Math.sin(angle0));
			graphics.lineTo(direction.x * t1, direction.y * t1, direction.z * t1);
		}
	}

	/** Wireframe axis-aligned box centered at `t` along one axis. */
	function drawAxisBox(axis:Int):Void {
		var direction = axisVector(axis);
		var u = perpendicularU(axis);
		var v = perpendicularV(axis);
		drawBox(direction.x * AXIS_LENGTH, direction.y * AXIS_LENGTH,
			direction.z * AXIS_LENGTH, direction, u, v,
			BOX_HALF * 1.4, BOX_HALF, BOX_HALF);
	}

	/** Wireframe uniform-scale box at the gizmo center. */
	function drawCenterBox():Void {
		drawBox(0, 0, 0, new h3d.Vector(1, 0, 0), new h3d.Vector(0, 1, 0),
			new h3d.Vector(0, 0, 1), CENTER_HALF, CENTER_HALF, CENTER_HALF);
	}

	/** Wireframe box centered at (cx,cy,cz) with half extents along u/v/w. */
	function drawBox(cx:Float, cy:Float, cz:Float, w:h3d.Vector, u:h3d.Vector,
			v:h3d.Vector, hw:Float, hu:Float, hv:Float):Void {
		inline function corner(su:Float, sv:Float, sw:Float):Array<Float> {
			return [cx + w.x * hw * sw + u.x * hu * su + v.x * hv * sv,
				cy + w.y * hw * sw + u.y * hu * su + v.y * hv * sv,
				cz + w.z * hw * sw + u.z * hu * su + v.z * hv * sv];
		}
		// Four side rectangles parallel to the axis direction.
		for (su in [-1, 1]) {
			for (sv in [-1, 1]) {
				var a = corner(su, sv, -1);
				var b = corner(su, sv, 1);
				graphics.moveTo(a[0], a[1], a[2]);
				graphics.lineTo(b[0], b[1], b[2]);
			}
		}
		// Two end caps.
		for (sw in [-1, 1]) {
			var p00 = corner(-1, -1, sw);
			var p10 = corner(1, -1, sw);
			var p11 = corner(1, 1, sw);
			var p01 = corner(-1, 1, sw);
			graphics.moveTo(p00[0], p00[1], p00[2]);
			graphics.lineTo(p10[0], p10[1], p10[2]);
			graphics.lineTo(p11[0], p11[1], p11[2]);
			graphics.lineTo(p01[0], p01[1], p01[2]);
			graphics.lineTo(p00[0], p00[1], p00[2]);
		}
	}

	/** Wireframe two-axis plane quad (move/scale plane handle). */
	function drawPlaneQuad(handle:Int):Void {
		planeBasis(handle, drawPlaneU, drawPlaneV, drawPlaneN);
		var cx = PLANE_OFFSET * (drawPlaneU.x + drawPlaneV.x);
		var cy = PLANE_OFFSET * (drawPlaneU.y + drawPlaneV.y);
		var cz = PLANE_OFFSET * (drawPlaneU.z + drawPlaneV.z);
		graphics.moveTo(cx - drawPlaneU.x * PLANE_HALF - drawPlaneV.x * PLANE_HALF,
			cy - drawPlaneU.y * PLANE_HALF - drawPlaneV.y * PLANE_HALF,
			cz - drawPlaneU.z * PLANE_HALF - drawPlaneV.z * PLANE_HALF);
		graphics.lineTo(cx + drawPlaneU.x * PLANE_HALF - drawPlaneV.x * PLANE_HALF,
			cy + drawPlaneU.y * PLANE_HALF - drawPlaneV.y * PLANE_HALF,
			cz + drawPlaneU.z * PLANE_HALF - drawPlaneV.z * PLANE_HALF);
		graphics.lineTo(cx + drawPlaneU.x * PLANE_HALF + drawPlaneV.x * PLANE_HALF,
			cy + drawPlaneU.y * PLANE_HALF + drawPlaneV.y * PLANE_HALF,
			cz + drawPlaneU.z * PLANE_HALF + drawPlaneV.z * PLANE_HALF);
		graphics.lineTo(cx - drawPlaneU.x * PLANE_HALF + drawPlaneV.x * PLANE_HALF,
			cy - drawPlaneU.y * PLANE_HALF + drawPlaneV.y * PLANE_HALF,
			cz - drawPlaneU.z * PLANE_HALF + drawPlaneV.z * PLANE_HALF);
		graphics.lineTo(cx - drawPlaneU.x * PLANE_HALF - drawPlaneV.x * PLANE_HALF,
			cy - drawPlaneU.y * PLANE_HALF - drawPlaneV.y * PLANE_HALF,
			cz - drawPlaneU.z * PLANE_HALF - drawPlaneV.z * PLANE_HALF);
	}

	/** Wireframe ring around one local axis, oriented by the object. */
	function drawLocalRing(axis:Int, radius:Float):Void {
		var quat = attached == null ? null : attached.getRotationQuat();
		var localU = perpendicularU(axis);
		var localV = perpendicularV(axis);
		var worldU = new h3d.Vector();
		var worldV = new h3d.Vector();
		if (quat != null) {
			quatRotate(quat, localU, worldU);
			quatRotate(quat, localV, worldV);
		} else {
			worldU.load(localU);
			worldV.load(localV);
		}
		drawCircle(worldU, worldV, radius);
	}

	/** Wireframe screen-facing ring (omni rotation handle). */
	function drawOmniRing():Void {
		var basis = cameraBasis();
		drawCircle(basis.ax, basis.ay, OMNI_RADIUS);
	}

	/** Closed polyline circle in the plane spanned by u/v. */
	function drawCircle(u:h3d.Vector, v:h3d.Vector, radius:Float):Void {
		for (segment in 0...RING_SEGMENTS) {
			var angle0 = segment / RING_SEGMENTS * Math.PI * 2;
			var angle1 = (segment + 1) / RING_SEGMENTS * Math.PI * 2;
			graphics.moveTo(
				u.x * radius * Math.cos(angle0) + v.x * radius * Math.sin(angle0),
				u.y * radius * Math.cos(angle0) + v.y * radius * Math.sin(angle0),
				u.z * radius * Math.cos(angle0) + v.z * radius * Math.sin(angle0));
			graphics.lineTo(
				u.x * radius * Math.cos(angle1) + v.x * radius * Math.sin(angle1),
				u.y * radius * Math.cos(angle1) + v.y * radius * Math.sin(angle1),
				u.z * radius * Math.cos(angle1) + v.z * radius * Math.sin(angle1));
		}
	}

	function ringSamples(axis:Int, radius:Float, out:Array<h3d.Vector>):Void {
		var quat = attached == null ? null : attached.getRotationQuat();
		var localU = perpendicularU(axis);
		var localV = perpendicularV(axis);
		var worldU = new h3d.Vector();
		var worldV = new h3d.Vector();
		if (quat != null) {
			quatRotate(quat, localU, worldU);
			quatRotate(quat, localV, worldV);
		} else {
			worldU.load(localU);
			worldV.load(localV);
		}
		for (segment in 0...RING_SEGMENTS) {
			var angle = segment / RING_SEGMENTS * Math.PI * 2;
			var cos = Math.cos(angle) * radius;
			var sin = Math.sin(angle) * radius;
			out.push(pointAt(
				worldU.x * cos + worldV.x * sin,
				worldU.y * cos + worldV.y * sin,
				worldU.z * cos + worldV.z * sin));
		}
	}

	function omniRingSamples(out:Array<h3d.Vector>):Void {
		var basis = cameraBasis();
		for (segment in 0...RING_SEGMENTS) {
			var angle = segment / RING_SEGMENTS * Math.PI * 2;
			var cos = Math.cos(angle) * OMNI_RADIUS;
			var sin = Math.sin(angle) * OMNI_RADIUS;
			out.push(pointAt(
				basis.ax.x * cos + basis.ay.x * sin,
				basis.ax.y * cos + basis.ay.y * sin,
				basis.ax.z * cos + basis.ay.z * sin));
		}
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
	KRotRing;
	KRotOmni;
	KScaleAxis;
	KScalePlane;
	KScaleUniform;
}
