import boltspark.editor.RotationEuler;

/** Headless regression for continuous Inspector Euler hints. */
class RotationEulerRepro {
    static inline var DEG_TO_RAD:Float = 0.017453292519943295;

    static function main():Void {
        verifyFullTurnContinuity();
        verifyGimbalContinuity(1);
        verifyGimbalContinuity(-1);
        verifyDisplayNormalization();
        Sys.println("[rotation-euler] continuous branch selection passed");
    }

    static function verifyFullTurnContinuity():Void {
        var reference = new h3d.Vector(165, 0, 0);
        for (angle in [170.0, 175.0, 179.0, 180.0, 181.0, 185.0, 190.0,
                350.0, 355.0, 360.0, 365.0, 370.0]) {
            var expected = new h3d.Vector(angle, 0, 0);
            var quat = fromEditor(expected);
            var actual = RotationEuler.degrees(quat, reference);
            assertEquivalent(quat, actual);
            assertNear(actual.x, angle, 1e-5,
                'X wrapped at ${angle} degrees: ${actual.x}');
            reference = actual;
        }
    }

    static function verifyGimbalContinuity(sign:Int):Void {
        var x = sign > 0 ? 30.0 : -40.0;
        var z = sign > 0 ? 20.0 : 15.0;
        var values = sign > 0
            ? [80.0, 85.0, 89.0, 89.99999, 90.0, 90.00001, 91.0, 95.0, 100.0]
            : [-80.0, -85.0, -89.0, -89.99999, -90.0, -90.00001, -91.0, -95.0, -100.0];
        var reference = new h3d.Vector(x, values[0] - sign * 5, z);
        for (y in values) {
            var expected = new h3d.Vector(x, y, z);
            var quat = fromEditor(expected);
            var actual = RotationEuler.degrees(quat, reference);
            assertEquivalent(quat, actual);
            assertNear(actual.x, x, 1e-3,
                'X changed branch near Y=${y}: ${actual.x}');
            assertNear(actual.y, y, 1e-3,
                'Y changed branch near Y=${y}: ${actual.y}');
            assertNear(actual.z, z, 1e-3,
                'Z changed branch near Y=${y}: ${actual.z}');
            reference = actual;
        }
    }

    static function verifyDisplayNormalization():Void {
        var inputs = [-725.0, -540.0, -360.0, -181.0, -180.0, -179.0,
            0.0, 179.0, 180.0, 181.0, 360.0, 540.0, 725.0];
        var expected = [-5.0, 180.0, 0.0, 179.0, 180.0, -179.0,
            0.0, 179.0, 180.0, -179.0, 0.0, 180.0, 5.0];
        for (index in 0...inputs.length) {
            var actual = RotationEuler.normalizedDegrees(inputs[index]);
            assertNear(actual, expected[index], 1e-9,
                'Unexpected normalized angle for ${inputs[index]}: ${actual}');
            if (actual <= -180 || actual > 180) {
                throw 'Displayed angle outside (-180, 180]: ${actual}';
            }
        }
    }

    static function fromEditor(degrees:h3d.Vector):h3d.Quat {
        var quat = new h3d.Quat();
        quat.initRotation(
            degrees.z * DEG_TO_RAD,
            degrees.y * DEG_TO_RAD,
            degrees.x * DEG_TO_RAD);
        quat.normalize();
        return quat;
    }

    static function assertEquivalent(expected:h3d.Quat, degrees:h3d.Vector):Void {
        var rebuilt = fromEditor(degrees);
        var similarity = Math.abs(expected.dot(rebuilt));
        if (similarity < 0.999999) {
            throw 'Euler hint changed orientation: similarity=${similarity} '
                + 'degrees=(${degrees.x}, ${degrees.y}, ${degrees.z})';
        }
    }

    static function assertNear(actual:Float, expected:Float, epsilon:Float,
            message:String):Void {
        if (Math.abs(actual - expected) > epsilon) throw message;
    }
}
