package boltspark.editor;

/**
 * Renderer-independent affine editor transform.
 *
 * Position, quaternion rotation, signed scale, and three upper-triangular
 * shear terms compose into one exact local matrix. Explicit shear is required
 * to preserve an object's world matrix when it is reparented between rotated,
 * non-uniformly scaled ancestors.
 */
class EditorTransform {
    public var positionX(get, set):Float;
    public var positionY(get, set):Float;
    public var positionZ(get, set):Float;
    public var rotationX(get, set):Float;
    public var rotationY(get, set):Float;
    public var rotationZ(get, set):Float;
    public var rotationW(get, set):Float;
    public var rotationHintX(get, set):Float;
    public var rotationHintY(get, set):Float;
    public var rotationHintZ(get, set):Float;
    public var rotationHintValid(get, set):Bool;
    public var scaleX(get, set):Float;
    public var scaleY(get, set):Float;
    public var scaleZ(get, set):Float;
    public var shearXY(get, set):Float;
    public var shearXZ(get, set):Float;
    public var shearYZ(get, set):Float;

    /** Increments whenever a channel changes; used by lazy world caches. */
    public var revision(default, null):Int = 1;
    @:noCompletion public var onChanged:Null<Void->Void>;

    var px:Float;
    var py:Float;
    var pz:Float;
    var qx:Float;
    var qy:Float;
    var qz:Float;
    var qw:Float;
    var hintX:Float;
    var hintY:Float;
    var hintZ:Float;
    var hintValid:Bool;
    var sx:Float;
    var sy:Float;
    var sz:Float;
    var shXY:Float;
    var shXZ:Float;
    var shYZ:Float;
    var cachedMatrix:TransformMatrix;
    var cachedMatrixRevision:Int = -1;

    public function new(positionX:Float = 0, positionY:Float = 0,
            positionZ:Float = 0, rotationX:Float = 0, rotationY:Float = 0,
            rotationZ:Float = 0, rotationW:Float = 1,
            rotationHintX:Float = 0, rotationHintY:Float = 0,
            rotationHintZ:Float = 0, rotationHintValid:Bool = false,
            scaleX:Float = 1, scaleY:Float = 1, scaleZ:Float = 1,
            shearXY:Float = 0, shearXZ:Float = 0, shearYZ:Float = 0) {
        px = positionX;
        py = positionY;
        pz = positionZ;
        qx = rotationX;
        qy = rotationY;
        qz = rotationZ;
        qw = rotationW;
        hintX = rotationHintX;
        hintY = rotationHintY;
        hintZ = rotationHintZ;
        hintValid = rotationHintValid;
        sx = scaleX;
        sy = scaleY;
        sz = scaleZ;
        shXY = shearXY;
        shXZ = shearXZ;
        shYZ = shearYZ;
    }

    public function clone():EditorTransform {
        return new EditorTransform(px, py, pz, qx, qy, qz, qw,
            hintX, hintY, hintZ, hintValid, sx, sy, sz,
            shXY, shXZ, shYZ);
    }

    /** Build the exact affine matrix represented by these channels. */
    public function toMatrix():TransformMatrix {
        if (cachedMatrixRevision == revision && cachedMatrix != null) {
            return cachedMatrix.clone();
        }

        // Scale first so finite but very large quaternion channels cannot
        // overflow their squared length during normalization.
        var maxQuaternion = Math.max(Math.max(Math.abs(qx), Math.abs(qy)),
            Math.max(Math.abs(qz), Math.abs(qw)));
        if (!Math.isFinite(maxQuaternion) || maxQuaternion <= 0.000000000001) {
            throw "Cannot compose a non-finite or zero-length quaternion";
        }
        var normalizedX = qx / maxQuaternion;
        var normalizedY = qy / maxQuaternion;
        var normalizedZ = qz / maxQuaternion;
        var normalizedW = qw / maxQuaternion;
        var length = Math.sqrt(normalizedX * normalizedX
            + normalizedY * normalizedY + normalizedZ * normalizedZ
            + normalizedW * normalizedW);
        var x = normalizedX / length;
        var y = normalizedY / length;
        var z = normalizedZ / length;
        var w = normalizedW / length;
        var xx = x * x;
        var yy = y * y;
        var zz = z * z;
        var xy = x * y;
        var xz = x * z;
        var yz = y * z;
        var wx = w * x;
        var wy = w * y;
        var wz = w * z;

        // Rotation matrix columns.
        var r00 = 1 - 2 * (yy + zz);
        var r10 = 2 * (xy + wz);
        var r20 = 2 * (xz - wy);
        var r01 = 2 * (xy - wz);
        var r11 = 1 - 2 * (xx + zz);
        var r21 = 2 * (yz + wx);
        var r02 = 2 * (xz + wy);
        var r12 = 2 * (yz - wx);
        var r22 = 1 - 2 * (xx + yy);

        // Linear transform = R * H * S, where H is upper triangular.
        cachedMatrix = new TransformMatrix(
            r00 * sx,
            (r00 * shXY + r01) * sy,
            (r00 * shXZ + r01 * shYZ + r02) * sz,
            px,
            r10 * sx,
            (r10 * shXY + r11) * sy,
            (r10 * shXZ + r11 * shYZ + r12) * sz,
            py,
            r20 * sx,
            (r20 * shXY + r21) * sy,
            (r20 * shXZ + r21 * shYZ + r22) * sz,
            pz);
        cachedMatrixRevision = revision;
        return cachedMatrix.clone();
    }

    /**
     * Decompose an affine matrix without discarding shear. The returned
     * channels always recompose to the input (within floating-point error).
     */
    public static function fromMatrix(matrix:TransformMatrix,
            ?rotationHint:EditorTransform):EditorTransform {
        if (matrix == null || !matrix.isFinite()) {
            throw "Cannot decompose a null or non-finite transform matrix";
        }
        var epsilon = 0.000000000001;

        // Gram-Schmidt factorization of the linear transform's columns.
        var c0x = matrix.m00;
        var c0y = matrix.m10;
        var c0z = matrix.m20;
        var scaleX = length3(c0x, c0y, c0z);
        if (scaleX <= epsilon) throw "Cannot decompose singular X scale";
        var u0x = c0x / scaleX;
        var u0y = c0y / scaleX;
        var u0z = c0z / scaleX;

        var c1x = matrix.m01;
        var c1y = matrix.m11;
        var c1z = matrix.m21;
        var dot01 = dot3(u0x, u0y, u0z, c1x, c1y, c1z);
        c1x -= u0x * dot01;
        c1y -= u0y * dot01;
        c1z -= u0z * dot01;
        var scaleY = length3(c1x, c1y, c1z);
        if (scaleY <= epsilon) throw "Cannot decompose singular Y scale";
        var u1x = c1x / scaleY;
        var u1y = c1y / scaleY;
        var u1z = c1z / scaleY;
        var shearXY = dot01 / scaleY;

        var c2x = matrix.m02;
        var c2y = matrix.m12;
        var c2z = matrix.m22;
        var dot02 = dot3(u0x, u0y, u0z, c2x, c2y, c2z);
        c2x -= u0x * dot02;
        c2y -= u0y * dot02;
        c2z -= u0z * dot02;
        var dot12 = dot3(u1x, u1y, u1z, c2x, c2y, c2z);
        c2x -= u1x * dot12;
        c2y -= u1y * dot12;
        c2z -= u1z * dot12;
        var scaleZ = length3(c2x, c2y, c2z);
        if (scaleZ <= epsilon) throw "Cannot decompose singular Z scale";
        var u2x = c2x / scaleZ;
        var u2y = c2y / scaleZ;
        var u2z = c2z / scaleZ;
        var shearXZ = dot02 / scaleZ;
        var shearYZ = dot12 / scaleZ;

        var orientationDeterminant = u0x * (u1y * u2z - u1z * u2y)
            - u1x * (u0y * u2z - u0z * u2y)
            + u2x * (u0y * u1z - u0z * u1y);
        if (orientationDeterminant < 0) {
            // Keep the rotation proper and place reflection on X. Shears that
            // use the X basis must flip with it to preserve the exact matrix.
            scaleX = -scaleX;
            u0x = -u0x;
            u0y = -u0y;
            u0z = -u0z;
            shearXY = -shearXY;
            shearXZ = -shearXZ;
        }

        var quaternion = quaternionFromColumns(
            u0x, u0y, u0z, u1x, u1y, u1z, u2x, u2y, u2z);
        return new EditorTransform(matrix.m03, matrix.m13, matrix.m23,
            quaternion.x, quaternion.y, quaternion.z, quaternion.w,
            rotationHint == null ? 0 : rotationHint.rotationHintX,
            rotationHint == null ? 0 : rotationHint.rotationHintY,
            rotationHint == null ? 0 : rotationHint.rotationHintZ,
            rotationHint != null && rotationHint.rotationHintValid,
            scaleX, scaleY, scaleZ, shearXY, shearXZ, shearYZ);
    }

    /** Quaternion matching the editor's existing mapped Euler convention. */
    public static function fromEditorEulerDegrees(xDegrees:Float,
            yDegrees:Float, zDegrees:Float):EditorTransform {
        var x = zDegrees * Math.PI / 180;
        var y = yDegrees * Math.PI / 180;
        var z = xDegrees * Math.PI / 180;
        var cx = Math.cos(x * 0.5);
        var sx = Math.sin(x * 0.5);
        var cy = Math.cos(y * 0.5);
        var sy = Math.sin(y * 0.5);
        var cz = Math.cos(z * 0.5);
        var sz = Math.sin(z * 0.5);
        // Exact h3d.Quat.initRotation convention used by the existing editor.
        return new EditorTransform(0, 0, 0,
            sx * cy * cz - cx * sy * sz,
            cx * sy * cz + sx * cy * sz,
            cx * cy * sz - sx * sy * cz,
            cx * cy * cz + sx * sy * sz,
            xDegrees, yDegrees, zDegrees, true);
    }

    public function sameAs(other:EditorTransform,
            epsilon:Float = 0.0000001):Bool {
        return other != null
            && close(px, other.positionX, epsilon)
            && close(py, other.positionY, epsilon)
            && close(pz, other.positionZ, epsilon)
            && close(qx, other.rotationX, epsilon)
            && close(qy, other.rotationY, epsilon)
            && close(qz, other.rotationZ, epsilon)
            && close(qw, other.rotationW, epsilon)
            && hintValid == other.rotationHintValid
            && (!hintValid || (close(hintX, other.rotationHintX, epsilon)
                && close(hintY, other.rotationHintY, epsilon)
                && close(hintZ, other.rotationHintZ, epsilon)))
            && close(sx, other.scaleX, epsilon)
            && close(sy, other.scaleY, epsilon)
            && close(sz, other.scaleZ, epsilon)
            && close(shXY, other.shearXY, epsilon)
            && close(shXZ, other.shearXZ, epsilon)
            && close(shYZ, other.shearYZ, epsilon);
    }

    public function isFiniteAndInvertible(epsilon:Float = 0.000000000001):Bool {
        for (value in [px, py, pz, qx, qy, qz, qw,
                sx, sy, sz, shXY, shXZ, shYZ]) {
            if (!Math.isFinite(value)) return false;
        }
        if (hintValid && (!Math.isFinite(hintX)
                || !Math.isFinite(hintY) || !Math.isFinite(hintZ))) {
            return false;
        }
        var maxQuaternion = Math.max(Math.max(Math.abs(qx), Math.abs(qy)),
            Math.max(Math.abs(qz), Math.abs(qw)));
        if (maxQuaternion <= epsilon) return false;
        var matrix = toMatrix();
        var determinant = matrix.determinant();
        return matrix.isFinite() && Math.isFinite(determinant)
            && Math.abs(determinant) > epsilon;
    }

    function touch():Void {
        revision++;
        cachedMatrixRevision = -1;
        if (onChanged != null) onChanged();
    }

    inline function assignFloat(current:Float, value:Float,
            assign:Float->Void):Float {
        if (current != value) {
            assign(value);
            touch();
        }
        return value;
    }

    inline function get_positionX():Float return px;
    function set_positionX(value:Float):Float return assignFloat(px, value, function(v) px = v);
    inline function get_positionY():Float return py;
    function set_positionY(value:Float):Float return assignFloat(py, value, function(v) py = v);
    inline function get_positionZ():Float return pz;
    function set_positionZ(value:Float):Float return assignFloat(pz, value, function(v) pz = v);
    inline function get_rotationX():Float return qx;
    function set_rotationX(value:Float):Float return assignFloat(qx, value, function(v) qx = v);
    inline function get_rotationY():Float return qy;
    function set_rotationY(value:Float):Float return assignFloat(qy, value, function(v) qy = v);
    inline function get_rotationZ():Float return qz;
    function set_rotationZ(value:Float):Float return assignFloat(qz, value, function(v) qz = v);
    inline function get_rotationW():Float return qw;
    function set_rotationW(value:Float):Float return assignFloat(qw, value, function(v) qw = v);
    inline function get_rotationHintX():Float return hintX;
    function set_rotationHintX(value:Float):Float return assignFloat(hintX, value, function(v) hintX = v);
    inline function get_rotationHintY():Float return hintY;
    function set_rotationHintY(value:Float):Float return assignFloat(hintY, value, function(v) hintY = v);
    inline function get_rotationHintZ():Float return hintZ;
    function set_rotationHintZ(value:Float):Float return assignFloat(hintZ, value, function(v) hintZ = v);
    inline function get_rotationHintValid():Bool return hintValid;
    function set_rotationHintValid(value:Bool):Bool {
        if (hintValid != value) {
            hintValid = value;
            touch();
        }
        return value;
    }
    inline function get_scaleX():Float return sx;
    function set_scaleX(value:Float):Float return assignFloat(sx, value, function(v) sx = v);
    inline function get_scaleY():Float return sy;
    function set_scaleY(value:Float):Float return assignFloat(sy, value, function(v) sy = v);
    inline function get_scaleZ():Float return sz;
    function set_scaleZ(value:Float):Float return assignFloat(sz, value, function(v) sz = v);
    inline function get_shearXY():Float return shXY;
    function set_shearXY(value:Float):Float return assignFloat(shXY, value, function(v) shXY = v);
    inline function get_shearXZ():Float return shXZ;
    function set_shearXZ(value:Float):Float return assignFloat(shXZ, value, function(v) shXZ = v);
    inline function get_shearYZ():Float return shYZ;
    function set_shearYZ(value:Float):Float return assignFloat(shYZ, value, function(v) shYZ = v);

    static inline function dot3(ax:Float, ay:Float, az:Float,
            bx:Float, by:Float, bz:Float):Float {
        return ax * bx + ay * by + az * bz;
    }

    static inline function length3(x:Float, y:Float, z:Float):Float {
        return Math.sqrt(x * x + y * y + z * z);
    }

    static function quaternionFromColumns(r00:Float, r10:Float, r20:Float,
            r01:Float, r11:Float, r21:Float,
            r02:Float, r12:Float, r22:Float):QuaternionChannels {
        var x:Float;
        var y:Float;
        var z:Float;
        var w:Float;
        var trace = r00 + r11 + r22;
        if (trace > 0) {
            var s = Math.sqrt(trace + 1.0) * 2;
            w = 0.25 * s;
            x = (r21 - r12) / s;
            y = (r02 - r20) / s;
            z = (r10 - r01) / s;
        } else if (r00 > r11 && r00 > r22) {
            var s = Math.sqrt(1.0 + r00 - r11 - r22) * 2;
            w = (r21 - r12) / s;
            x = 0.25 * s;
            y = (r01 + r10) / s;
            z = (r02 + r20) / s;
        } else if (r11 > r22) {
            var s = Math.sqrt(1.0 + r11 - r00 - r22) * 2;
            w = (r02 - r20) / s;
            x = (r01 + r10) / s;
            y = 0.25 * s;
            z = (r12 + r21) / s;
        } else {
            var s = Math.sqrt(1.0 + r22 - r00 - r11) * 2;
            w = (r10 - r01) / s;
            x = (r02 + r20) / s;
            y = (r12 + r21) / s;
            z = 0.25 * s;
        }
        var length = Math.sqrt(x * x + y * y + z * z + w * w);
        if (length <= 0.000000000001) return new QuaternionChannels(0, 0, 0, 1);
        return new QuaternionChannels(x / length, y / length, z / length, w / length);
    }

    static inline function close(a:Float, b:Float, epsilon:Float):Bool {
        return Math.isFinite(a) && Math.isFinite(b)
            && Math.abs(a - b) <= epsilon;
    }
}

private class QuaternionChannels {
    public final x:Float;
    public final y:Float;
    public final z:Float;
    public final w:Float;

    public function new(x:Float, y:Float, z:Float, w:Float) {
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }
}
