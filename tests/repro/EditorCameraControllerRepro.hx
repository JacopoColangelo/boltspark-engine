package;

import boltspark.editor.EditorCameraController;

/** Headless regression for Unreal-style editor-camera navigation. */
class EditorCameraControllerRepro {
    static function main():Void {
        var camera = new h3d.Camera();
        camera.pos.set(5.8, 4.2, 6.4);
        camera.target.set(0, 0, 0);
        camera.up.set(0, 1, 0);

        var controller = new EditorCameraController(camera);
        controller.viewportFocused = true;

        assertFalse(controller.isFlyNavigationActive(),
            "hover alone enabled fly navigation");
        var hoverPosition = camera.pos.clone();
        setKeyDown(hxd.Key.W, true);
        controller.update(0.1);
        assertPosition(camera.pos, hoverPosition,
            "hover-only W moved the camera");

        var initialSpeed = controller.baseSpeedValue();
        controller.adjustSpeedForWheel(-1);
        assertNear(controller.baseSpeedValue(), initialSpeed,
            "hover-only wheel changed camera speed");

        var dollyStart = camera.pos.clone();
        var dollyForward = direction(camera.pos, camera.target);
        controller.dollyForWheel(-1);
        var dollyTravel = displacement(dollyStart, camera.pos);
        assertTrue(dot(dollyTravel, dollyForward) > 0,
            "hover-wheel up did not dolly into the scene");
        controller.dollyForWheel(1);
        assertPosition(camera.pos, dollyStart,
            "opposite hover-wheel steps did not cancel");

        controller.beginLook();
        assertTrue(controller.isFlyNavigationActive(),
            "RMB look did not enable fly navigation");
        controller.adjustSpeedForWheel(-1);
        assertTrue(controller.baseSpeedValue() > initialSpeed,
            "RMB-look wheel did not change camera speed");
        controller.update(0.1);
        assertMoved(camera.pos, hoverPosition,
            "RMB + W did not move the camera");

        controller.endLook();
        assertFalse(controller.isFlyNavigationActive(),
            "RMB release left fly navigation active");
        var releasedPosition = camera.pos.clone();
        controller.update(0.1);
        assertPosition(camera.pos, releasedPosition,
            "camera retained smoothed velocity after RMB release");
        setKeyDown(hxd.Key.W, false);

        setKeyDown(hxd.Key.E, true);
        controller.update(0.1);
        assertPosition(camera.pos, releasedPosition,
            "hover-only E changed camera elevation");
        controller.beginLook();
        var elevationBefore = camera.pos.y;
        controller.update(0.1);
        assertTrue(camera.pos.y > elevationBefore,
            "RMB + E did not raise camera elevation");
        controller.endLook();
        setKeyDown(hxd.Key.E, false);

        var releasedSpeed = controller.baseSpeedValue();
        controller.adjustSpeedForWheel(-1);
        assertNear(controller.baseSpeedValue(), releasedSpeed,
            "post-release wheel changed camera speed");

        controller.viewportFocused = false;
        controller.beginLook();
        assertFalse(controller.isFlyNavigationActive(),
            "look without viewport ownership enabled navigation");
        controller.endLook();

        controller.viewportFocused = true;
        controller.keyboardEnabled = false;
        controller.beginLook();
        assertFalse(controller.isFlyNavigationActive(),
            "keyboard lockout did not disable navigation");
        controller.endLook();

        verifyOrbitDirection();
        verifyFocusFraming();

        Sys.println("[editor-camera] RMB gating, wheel dolly, orbit direction,"
            + " and focus framing passed");
    }

    static function verifyOrbitDirection():Void {
        var horizontalCamera = cameraAt(0, 0, 10, 0, 0, 0);
        var horizontal = new EditorCameraController(horizontalCamera);
        horizontal.beginOrbit(new h3d.Vector(0, 0, 0));
        horizontal.addOrbitDelta(20, 0);
        horizontal.update(0.016);
        assertTrue(horizontalCamera.pos.x > 0,
            "rightward Alt+LMB orbit remained horizontally inverted");
        horizontal.endOrbit();

        var verticalCamera = cameraAt(0, 0, 10, 0, 0, 0);
        var vertical = new EditorCameraController(verticalCamera);
        vertical.beginOrbit(new h3d.Vector(0, 0, 0));
        vertical.addOrbitDelta(0, 20);
        vertical.update(0.016);
        assertTrue(verticalCamera.pos.y > 0,
            "downward Alt+LMB orbit remained vertically inverted");
        vertical.endOrbit();
    }

    static function verifyFocusFraming():Void {
        var camera = cameraAt(0, 0, 10, 0, 0, 0);
        var controller = new EditorCameraController(camera);
        controller.setViewportSize(1000, 500);
        var center = new h3d.Vector(3, 2, -4);
        assertTrue(controller.focusOn(center, 2),
            "valid focus sphere was rejected");
        var towardCenter = displacement(camera.pos, center);
        var view = direction(camera.pos, camera.target);
        var distance = length(towardCenter);
        assertTrue(distance > 2, "focus camera was placed inside its object");
        assertNear(dot(towardCenter, view) / distance, 1,
            "focus center was not placed on the view axis");
        assertNear(camera.pos.x, center.x, "focus changed view direction (x)");
        assertNear(camera.pos.y, center.y, "focus changed view direction (y)");
    }

    static function cameraAt(px:Float, py:Float, pz:Float,
            tx:Float, ty:Float, tz:Float):h3d.Camera {
        var camera = new h3d.Camera();
        camera.pos.set(px, py, pz);
        camera.target.set(tx, ty, tz);
        camera.up.set(0, 1, 0);
        return camera;
    }

    static function setKeyDown(keyCode:Int, down:Bool):Void {
        @:privateAccess hxd.Key.keyPressed[keyCode] = down ? 1 : 0;
    }

    static function assertPosition(actual:h3d.Vector, expected:h3d.Vector,
            message:String):Void {
        assertNear(actual.x, expected.x, message + " (x)");
        assertNear(actual.y, expected.y, message + " (y)");
        assertNear(actual.z, expected.z, message + " (z)");
    }

    static function assertMoved(actual:h3d.Vector, previous:h3d.Vector,
            message:String):Void {
        if (length(displacement(previous, actual)) <= 0.000001) {
            throw message;
        }
    }

    static function direction(from:h3d.Vector, to:h3d.Vector):h3d.Vector {
        var result = displacement(from, to);
        var magnitude = length(result);
        result.x /= magnitude;
        result.y /= magnitude;
        result.z /= magnitude;
        return result;
    }

    static function displacement(from:h3d.Vector, to:h3d.Vector):h3d.Vector {
        return new h3d.Vector(to.x - from.x, to.y - from.y, to.z - from.z);
    }

    static function dot(a:h3d.Vector, b:h3d.Vector):Float {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    static function length(value:h3d.Vector):Float {
        return Math.sqrt(dot(value, value));
    }

    static function assertNear(actual:Float, expected:Float, message:String):Void {
        if (Math.abs(actual - expected) > 0.000001) {
            throw '${message}: expected ${expected}, got ${actual}';
        }
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }

    static function assertFalse(value:Bool, message:String):Void {
        assertTrue(!value, message);
    }
}
