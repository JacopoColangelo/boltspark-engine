package;

import boltspark.editor.ArcballRotation;

/** Headless regression for the production camera-relative arcball math. */
class ArcballRotationRepro {
	static inline var EPSILON:Float = 1e-6;

	static function main():Void {
		var right = new h3d.Vector(1, 0, 0);
		var up = new h3d.Vector(0, 1, 0);
		var towardScene = new h3d.Vector(0, 0, 1);

		// Center drags catch horizontal/vertical direction. Off-center pairs
		// carry a view-Z component and verify smooth multi-axis tumble.
		verifyStep(0, 0, 0.35, 0,
			right, up, towardScene, "center to right");
		verifyStep(0.72, 0, 0.68, 0.28,
			right, up, towardScene, "right side upward");
		verifyStep(0, 0.72, 0.28, 0.68,
			right, up, towardScene, "top side rightward");
		verifyStep(-0.48, 0.31, -0.29, 0.57,
			right, up, towardScene, "mixed diagonal");

		// The same relationship must hold for an arbitrarily oriented camera.
		var angledForward = unit(-0.61, -0.44, -0.66);
		var angledRight = new h3d.Vector(0, 1, 0).cross(angledForward);
		angledRight.normalize();
		var angledUp = angledForward.cross(angledRight);
		angledUp.normalize();
		verifyStep(0.62, -0.18, 0.48, 0.32,
			angledRight, angledUp, angledForward, "angled camera");

		verifyTangentialRoll();
		verifyBellJoin();
		verifyUnboundedSegments();
		verifyPathReversal();

		Sys.println("[arcball] surface direction, roll, reversal, and unbounded drag passed");
	}

	/** Verify the exact production step axis and its camera-basis projection. */
	static function verifyStep(previousX:Float, previousY:Float,
			currentX:Float, currentY:Float, right:h3d.Vector, up:h3d.Vector,
			towardScene:h3d.Vector, label:String):Void {
		var previous = surface(previousX, previousY);
		var current = surface(currentX, currentY);
		var cameraAxis = new h3d.Vector();
		var angle = ArcballRotation.cameraStep(previous, current,
			previousX, previousY, currentX, currentY, cameraAxis);
		var dx = currentX - previousX;
		var dy = currentY - previousY;
		assertNear(angle, Math.sqrt(dx * dx + dy * dy), EPSILON,
			'${label}: step angle was not linear pointer travel');

		var expectedAxis = previous.cross(current);
		expectedAxis.normalize();
		if (cameraAxis.dot(expectedAxis) < 1 - EPSILON) {
			throw '${label}: camera axis disagrees with previous x current; '
				+ 'actual=${cameraAxis}, expected=${expectedAxis}';
		}

		var worldAxis = new h3d.Vector();
		assertTrue(ArcballRotation.worldAxis(cameraAxis.x, cameraAxis.y,
			cameraAxis.z, right, up, towardScene, worldAxis),
			'${label}: degenerate world axis');
		var from = surfaceWorld(previous, right, up, towardScene);
		var expected = surfaceWorld(current, right, up, towardScene);
		var rotation = new h3d.Quat();
		rotation.initRotateAxis(worldAxis.x, worldAxis.y, worldAxis.z, angle);
		var actual = rotate(rotation, from);
		if (actual.dot(expected) <= from.dot(expected)) {
			throw '${label}: production step moved away from the pointer target';
		}
	}

	/** Tangential motion must retain roll both inside and outside the rim. */
	static function verifyTangentialRoll():Void {
		var rightAxis = stepAxis(0.72, 0, 0.72, 0.1);
		assertTrue(rightAxis.z > 0,
			"right-side upward drag rolled backward");
		var topAxis = stepAxis(0, 0.72, 0.1, 0.72);
		assertTrue(topAxis.z < 0,
			"top-side rightward drag rolled backward");

		var outsideRight = stepAxis(3, 0, 3, 0.1);
		assertTrue(outsideRight.z > 0.9,
			"outside-right upward drag lost view-axis roll");
		var outsideTop = stepAxis(0, 3, 0.1, 3);
		assertTrue(outsideTop.z < -0.9,
			"outside-top rightward drag lost view-axis roll");
	}

	/** Bell's cap/sheet join must be unit-length, camera-facing, and C1. */
	static function verifyBellJoin():Void {
		var join = Math.sqrt(0.5);
		var delta = 0.00001;
		var before = surface(join - delta, 0);
		var at = surface(join, 0);
		var after = surface(join + delta, 0);
		for (point in [before, at, after]) {
			assertNear(point.length(), 1, EPSILON,
				"Bell surface point was not normalized");
			assertTrue(point.z <= 0, "Bell surface escaped camera-facing hemisphere");
		}
		var leftSlope = new h3d.Vector(
			(at.x - before.x) / delta,
			(at.y - before.y) / delta,
			(at.z - before.z) / delta);
		var rightSlope = new h3d.Vector(
			(after.x - at.x) / delta,
			(after.y - at.y) / delta,
			(after.z - at.z) / delta);
		assertTrue(leftSlope.distance(rightSlope) < 0.0001,
			'Bell surface slope broke at join: left=${leftSlope}, right=${rightSlope}');
	}

	/** Long coalesced and finely segmented drags must stay unbounded and agree. */
	static function verifyUnboundedSegments():Void {
		for (distance in [1.0, 5.0, 20.0]) {
			var coarse = new h3d.Quat();
			var coarseTravel = applySegment(coarse, 0, 0, distance, 0);
			assertNear(coarseTravel, distance, 1e-9,
				'unbounded segment saturated at ${distance} radii');

			var fine = new h3d.Quat();
			var fineTravel = 0.0;
			var pieces = 200;
			for (piece in 0...pieces) {
				fineTravel += applySegment(fine,
					distance * piece / pieces, 0,
					distance * (piece + 1) / pieces, 0);
			}
			assertNear(fineTravel, distance, 1e-9,
				'fine segment saturated at ${distance} radii');
			assertQuatEquivalent(coarse, fine,
				'coalesced/fine radial drag mismatch at ${distance} radii');
		}
	}

	/** Traversing an arbitrary segment and the same samples backward is inverse. */
	static function verifyPathReversal():Void {
		var rotation = new h3d.Quat();
		applySegment(rotation, -0.35, 0.22, 3.4, 1.15);
		applySegment(rotation, 3.4, 1.15, -0.35, 0.22);
		assertQuatEquivalent(rotation, new h3d.Quat(),
			"out-and-back arcball path did not return to identity");
	}

	/** Apply the same bounded straight-line subdivision used by TransformGizmo. */
	static function applySegment(rotation:h3d.Quat, startX:Float, startY:Float,
			endX:Float, endY:Float):Float {
		var dx = endX - startX;
		var dy = endY - startY;
		var substeps = ArcballRotation.segmentSubsteps(dx, dy);
		var previousX = startX;
		var previousY = startY;
		var previous = surface(previousX, previousY);
		var travel = 0.0;
		for (step in 1...substeps + 1) {
			var t = step / substeps;
			var currentX = startX + dx * t;
			var currentY = startY + dy * t;
			var current = surface(currentX, currentY);
			var axis = new h3d.Vector();
			var angle = ArcballRotation.cameraStep(previous, current,
				previousX, previousY, currentX, currentY, axis);
			if (angle > 0) {
				var increment = new h3d.Quat();
				increment.initRotateAxis(axis.x, axis.y, axis.z, angle);
				var accumulated = new h3d.Quat();
				accumulated.multiply(increment, rotation);
				rotation.load(accumulated);
				rotation.normalize();
				travel += angle;
			}
			previousX = currentX;
			previousY = currentY;
			previous = current;
		}
		return travel;
	}

	static function stepAxis(previousX:Float, previousY:Float,
			currentX:Float, currentY:Float):h3d.Vector {
		var axis = new h3d.Vector();
		var angle = ArcballRotation.cameraStep(
			surface(previousX, previousY), surface(currentX, currentY),
			previousX, previousY, currentX, currentY, axis);
		assertTrue(angle > 0, "arcball step unexpectedly stalled");
		return axis;
	}

	static function surface(x:Float, y:Float):h3d.Vector {
		return ArcballRotation.surface(x, y, new h3d.Vector());
	}

	/** Surface point in world space from camera-basis coordinates. */
	static function surfaceWorld(point:h3d.Vector, right:h3d.Vector,
			up:h3d.Vector, towardScene:h3d.Vector):h3d.Vector {
		return new h3d.Vector(
			right.x * point.x + up.x * point.y + towardScene.x * point.z,
			right.y * point.x + up.y * point.y + towardScene.y * point.z,
			right.z * point.x + up.z * point.y + towardScene.z * point.z);
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

	static function assertQuatEquivalent(actual:h3d.Quat, expected:h3d.Quat,
			message:String):Void {
		if (Math.abs(actual.dot(expected)) < 1 - EPSILON) {
			throw '${message}: actual=${actual}, expected=${expected}';
		}
	}

	static function assertNear(actual:Float, expected:Float, epsilon:Float,
			message:String):Void {
		if (Math.abs(actual - expected) > epsilon) {
			throw '${message}: expected ${expected}, got ${actual}';
		}
	}

	static function assertTrue(value:Bool, message:String):Void {
		if (!value) throw message;
	}
}
