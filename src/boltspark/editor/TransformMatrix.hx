package boltspark.editor;

/**
 * Renderer-independent affine 3D matrix using column vectors.
 *
 * The upper-left 3x3 stores the linear transform and the last column stores
 * translation. Composition follows the scene-graph convention
 * `world = parentWorld * local`.
 */
class TransformMatrix {
    public var m00:Float;
    public var m01:Float;
    public var m02:Float;
    public var m03:Float;
    public var m10:Float;
    public var m11:Float;
    public var m12:Float;
    public var m13:Float;
    public var m20:Float;
    public var m21:Float;
    public var m22:Float;
    public var m23:Float;

    public function new(m00:Float = 1, m01:Float = 0, m02:Float = 0,
            m03:Float = 0, m10:Float = 0, m11:Float = 1,
            m12:Float = 0, m13:Float = 0, m20:Float = 0,
            m21:Float = 0, m22:Float = 1, m23:Float = 0) {
        this.m00 = m00;
        this.m01 = m01;
        this.m02 = m02;
        this.m03 = m03;
        this.m10 = m10;
        this.m11 = m11;
        this.m12 = m12;
        this.m13 = m13;
        this.m20 = m20;
        this.m21 = m21;
        this.m22 = m22;
        this.m23 = m23;
    }

    public static function identity():TransformMatrix {
        return new TransformMatrix();
    }

    public function clone():TransformMatrix {
        return new TransformMatrix(m00, m01, m02, m03,
            m10, m11, m12, m13, m20, m21, m22, m23);
    }

    /** Return `this * other`. */
    public function multiplied(other:TransformMatrix):TransformMatrix {
        if (other == null) throw "Cannot multiply by a null transform matrix";
        return new TransformMatrix(
            m00 * other.m00 + m01 * other.m10 + m02 * other.m20,
            m00 * other.m01 + m01 * other.m11 + m02 * other.m21,
            m00 * other.m02 + m01 * other.m12 + m02 * other.m22,
            m00 * other.m03 + m01 * other.m13 + m02 * other.m23 + m03,
            m10 * other.m00 + m11 * other.m10 + m12 * other.m20,
            m10 * other.m01 + m11 * other.m11 + m12 * other.m21,
            m10 * other.m02 + m11 * other.m12 + m12 * other.m22,
            m10 * other.m03 + m11 * other.m13 + m12 * other.m23 + m13,
            m20 * other.m00 + m21 * other.m10 + m22 * other.m20,
            m20 * other.m01 + m21 * other.m11 + m22 * other.m21,
            m20 * other.m02 + m21 * other.m12 + m22 * other.m22,
            m20 * other.m03 + m21 * other.m13 + m22 * other.m23 + m23);
    }

    public function determinant():Float {
        return m00 * (m11 * m22 - m12 * m21)
            - m01 * (m10 * m22 - m12 * m20)
            + m02 * (m10 * m21 - m11 * m20);
    }

    /** Invert this affine matrix, rejecting singular and non-finite results. */
    public function inverse(epsilon:Float = 0.000000000001):TransformMatrix {
        var determinant = determinant();
        if (!Math.isFinite(determinant) || Math.abs(determinant) <= epsilon) {
            throw "Cannot invert a singular transform matrix";
        }
        var inv = 1.0 / determinant;
        var r00 = (m11 * m22 - m12 * m21) * inv;
        var r01 = (m02 * m21 - m01 * m22) * inv;
        var r02 = (m01 * m12 - m02 * m11) * inv;
        var r10 = (m12 * m20 - m10 * m22) * inv;
        var r11 = (m00 * m22 - m02 * m20) * inv;
        var r12 = (m02 * m10 - m00 * m12) * inv;
        var r20 = (m10 * m21 - m11 * m20) * inv;
        var r21 = (m01 * m20 - m00 * m21) * inv;
        var r22 = (m00 * m11 - m01 * m10) * inv;
        return new TransformMatrix(r00, r01, r02,
            -(r00 * m03 + r01 * m13 + r02 * m23),
            r10, r11, r12,
            -(r10 * m03 + r11 * m13 + r12 * m23),
            r20, r21, r22,
            -(r20 * m03 + r21 * m13 + r22 * m23));
    }

    public function transformPoint(x:Float, y:Float, z:Float):TransformPoint {
        return new TransformPoint(
            m00 * x + m01 * y + m02 * z + m03,
            m10 * x + m11 * y + m12 * z + m13,
            m20 * x + m21 * y + m22 * z + m23);
    }

    public function sameAs(other:TransformMatrix,
            epsilon:Float = 0.000001):Bool {
        return other != null
            && close(m00, other.m00, epsilon)
            && close(m01, other.m01, epsilon)
            && close(m02, other.m02, epsilon)
            && close(m03, other.m03, epsilon)
            && close(m10, other.m10, epsilon)
            && close(m11, other.m11, epsilon)
            && close(m12, other.m12, epsilon)
            && close(m13, other.m13, epsilon)
            && close(m20, other.m20, epsilon)
            && close(m21, other.m21, epsilon)
            && close(m22, other.m22, epsilon)
            && close(m23, other.m23, epsilon);
    }

    public function isFinite():Bool {
        for (value in [m00, m01, m02, m03, m10, m11,
                m12, m13, m20, m21, m22, m23]) {
            if (!Math.isFinite(value)) return false;
        }
        return true;
    }

    static inline function close(a:Float, b:Float, epsilon:Float):Bool {
        return Math.isFinite(a) && Math.isFinite(b)
            && Math.abs(a - b) <= epsilon;
    }
}

/** Small renderer-independent point value returned by matrix operations. */
class TransformPoint {
    public var x:Float;
    public var y:Float;
    public var z:Float;

    public function new(x:Float = 0, y:Float = 0, z:Float = 0) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
}
