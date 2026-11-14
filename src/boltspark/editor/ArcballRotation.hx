package boltspark.editor;

/**
 * Camera-space arcball math shared by the viewport and its regression.
 *
 * Screen-space and trackball coordinates map directly to the camera basis:
 * right (ax), up (ay), and toward-scene (az). Camera-facing trackball points
 * have z <= 0. Successive points choose the rotation axis through
 * `previous x current`, preserving view-axis roll during off-centre and
 * outside-rim drags. Pointer travel supplies the angle independently of the
 * flattened outside surface, so rotation remains unbounded.
 */
class ArcballRotation {
	/** Largest normalized pointer step solved at once by the virtual sphere. */
	public static inline var MAX_SCREEN_STEP:Float = 0.125;
	/** Safety cap for one coalesced raw-input event. */
	public static inline var MAX_SUBSTEPS:Int = 64;
	static inline var AXIS_EPSILON_SQ:Float = 1e-12;
	static inline var MOTION_EPSILON_SQ:Float = 1e-12;

	/** Production subdivision count for one normalized pointer segment. */
	public static function segmentSubsteps(deltaX:Float, deltaY:Float):Int {
		var motion = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
		var count = Std.int(Math.ceil(motion / MAX_SCREEN_STEP));
		if (count < 1) count = 1;
		if (count > MAX_SUBSTEPS) count = MAX_SUBSTEPS;
		return count;
	}

	/**
	 * Map normalized pointer coordinates to Bell's continuous trackball
	 * surface. The spherical cap and hyperbolic sheet meet with equal value
	 * and slope at r^2 = 0.5; normalizing keeps the returned point on the
	 * camera-facing unit hemisphere without a rim clamp.
	 */
	public static function surface(x:Float, y:Float,
			out:h3d.Vector):h3d.Vector {
		var radiusSq = x * x + y * y;
		var z = radiusSq <= 0.5
			? -Math.sqrt(Math.max(0, 1 - radiusSq))
			: -0.5 / Math.sqrt(radiusSq);
		out.set(x, y, z);
		out.normalize();
		return out;
	}

	/**
	 * Build one incremental camera-space rotation from two Bell-surface
	 * points. The normalized surface cross product supplies the axis, including
	 * its view-axis component. The returned angle is normalized pointer travel
	 * in radians, rather than the shrinking outside-surface arc, which makes a
	 * long relative-mode drag unbounded and independent of event subdivision.
	 *
	 * `previousX/Y` and `currentX/Y` are pointer coordinates in trackball-radius
	 * units. Returns zero for a stationary step.
	 */
	public static function cameraStep(previousSurface:h3d.Vector,
			currentSurface:h3d.Vector, previousX:Float, previousY:Float,
			currentX:Float, currentY:Float, outAxis:h3d.Vector):Float {
		var dx = currentX - previousX;
		var dy = currentY - previousY;
		var motionSq = dx * dx + dy * dy;
		if (motionSq < MOTION_EPSILON_SQ) {
			outAxis.set(0, 0, 0);
			return 0;
		}

		outAxis.set(
			previousSurface.y * currentSurface.z
				- previousSurface.z * currentSurface.y,
			previousSurface.z * currentSurface.x
				- previousSurface.x * currentSurface.z,
			previousSurface.x * currentSurface.y
				- previousSurface.y * currentSurface.x);
		var axisLengthSq = outAxis.lengthSq();
		if (axisLengthSq < AXIS_EPSILON_SQ) {
			// At extreme virtual-pointer distances the Bell surface approaches
			// the horizon closely enough for its cross product to lose precision.
			// The lifted-plane differential has the same handedness and retains
			// radial tumble plus tangential view-axis roll without stalling.
			outAxis.set(dy, -dx,
				previousX * currentY - previousY * currentX);
			axisLengthSq = outAxis.lengthSq();
		}
		if (axisLengthSq < AXIS_EPSILON_SQ) {
			outAxis.set(0, 0, 0);
			return 0;
		}
		outAxis.scale(1 / Math.sqrt(axisLengthSq));
		return Math.sqrt(motionSq);
	}

	/**
	 * Convert an arcball axis from camera-space (right, up, toward-scene)
	 * coordinates to a normalized world-space axis.
	 */
	public static function worldAxis(viewX:Float, viewY:Float, viewZ:Float,
			right:h3d.Vector, up:h3d.Vector, towardScene:h3d.Vector,
			out:h3d.Vector):Bool {
		out.set(
			right.x * viewX + up.x * viewY + towardScene.x * viewZ,
			right.y * viewX + up.y * viewY + towardScene.y * viewZ,
			right.z * viewX + up.z * viewY + towardScene.z * viewZ);
		var lengthSq = out.lengthSq();
		if (lengthSq < AXIS_EPSILON_SQ) {
			out.set(0, 0, 0);
			return false;
		}
		out.scale(1 / Math.sqrt(lengthSq));
		return true;
	}
}
