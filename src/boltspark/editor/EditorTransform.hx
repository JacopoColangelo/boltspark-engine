package boltspark.editor;

/**
 * Renderer-independent editor transform.
 *
 * Position and scale use editor world units. Rotation retains both the exact
 * quaternion and the continuous Euler hint used by the Inspector, so undo and
 * redo never introduce a quaternion/Euler round trip.
 */
class EditorTransform {
    public var positionX:Float;
    public var positionY:Float;
    public var positionZ:Float;
    public var rotationX:Float;
    public var rotationY:Float;
    public var rotationZ:Float;
    public var rotationW:Float;
    public var rotationHintX:Float;
    public var rotationHintY:Float;
    public var rotationHintZ:Float;
    public var rotationHintValid:Bool;
    public var scaleX:Float;
    public var scaleY:Float;
    public var scaleZ:Float;

    public function new(positionX:Float = 0, positionY:Float = 0,
            positionZ:Float = 0, rotationX:Float = 0, rotationY:Float = 0,
            rotationZ:Float = 0, rotationW:Float = 1,
            rotationHintX:Float = 0, rotationHintY:Float = 0,
            rotationHintZ:Float = 0, rotationHintValid:Bool = false,
            scaleX:Float = 1, scaleY:Float = 1, scaleZ:Float = 1) {
        this.positionX = positionX;
        this.positionY = positionY;
        this.positionZ = positionZ;
        this.rotationX = rotationX;
        this.rotationY = rotationY;
        this.rotationZ = rotationZ;
        this.rotationW = rotationW;
        this.rotationHintX = rotationHintX;
        this.rotationHintY = rotationHintY;
        this.rotationHintZ = rotationHintZ;
        this.rotationHintValid = rotationHintValid;
        this.scaleX = scaleX;
        this.scaleY = scaleY;
        this.scaleZ = scaleZ;
    }

    public function clone():EditorTransform {
        return new EditorTransform(positionX, positionY, positionZ,
            rotationX, rotationY, rotationZ, rotationW,
            rotationHintX, rotationHintY, rotationHintZ, rotationHintValid,
            scaleX, scaleY, scaleZ);
    }

    public function sameAs(other:EditorTransform, epsilon:Float = 0.0000001):Bool {
        return other != null
            && close(positionX, other.positionX, epsilon)
            && close(positionY, other.positionY, epsilon)
            && close(positionZ, other.positionZ, epsilon)
            && close(rotationX, other.rotationX, epsilon)
            && close(rotationY, other.rotationY, epsilon)
            && close(rotationZ, other.rotationZ, epsilon)
            && close(rotationW, other.rotationW, epsilon)
            && rotationHintValid == other.rotationHintValid
            && (!rotationHintValid || (
                close(rotationHintX, other.rotationHintX, epsilon)
                && close(rotationHintY, other.rotationHintY, epsilon)
                && close(rotationHintZ, other.rotationHintZ, epsilon)))
            && close(scaleX, other.scaleX, epsilon)
            && close(scaleY, other.scaleY, epsilon)
            && close(scaleZ, other.scaleZ, epsilon);
    }

    static inline function close(a:Float, b:Float, epsilon:Float):Bool {
        return Math.isFinite(a) && Math.isFinite(b) && Math.abs(a - b) <= epsilon;
    }
}
