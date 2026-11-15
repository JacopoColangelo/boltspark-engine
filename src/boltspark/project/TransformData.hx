package boltspark.project;

/** Serializable editor transform using the current Position/Rotator/Scale convention. */
class TransformData {
    public var positionX:Float;
    public var positionY:Float;
    public var positionZ:Float;
    public var rotationX:Float;
    public var rotationY:Float;
    public var rotationZ:Float;
    public var scaleX:Float;
    public var scaleY:Float;
    public var scaleZ:Float;
    /** Exact quaternion; older schema-1 files may omit it. */
    public var quaternionX:Float;
    public var quaternionY:Float;
    public var quaternionZ:Float;
    public var quaternionW:Float;
    public var quaternionValid:Bool;
    /** Upper-triangular affine shear retained during world-preserving parenting. */
    public var shearXY:Float;
    public var shearXZ:Float;
    public var shearYZ:Float;
    /** Whether Rotation is a deliberate continuous editor-Euler hint. */
    public var rotationHintValid:Bool;

    public function new(positionX:Float = 0, positionY:Float = 0,
            positionZ:Float = 0, rotationX:Float = 0, rotationY:Float = 0,
            rotationZ:Float = 0, scaleX:Float = 1, scaleY:Float = 1,
            scaleZ:Float = 1, quaternionX:Float = 0,
            quaternionY:Float = 0, quaternionZ:Float = 0,
            quaternionW:Float = 1, quaternionValid:Bool = false,
            shearXY:Float = 0, shearXZ:Float = 0, shearYZ:Float = 0,
            rotationHintValid:Bool = true) {
        this.positionX = positionX;
        this.positionY = positionY;
        this.positionZ = positionZ;
        this.rotationX = rotationX;
        this.rotationY = rotationY;
        this.rotationZ = rotationZ;
        this.scaleX = scaleX;
        this.scaleY = scaleY;
        this.scaleZ = scaleZ;
        this.quaternionX = quaternionX;
        this.quaternionY = quaternionY;
        this.quaternionZ = quaternionZ;
        this.quaternionW = quaternionW;
        this.quaternionValid = quaternionValid;
        this.shearXY = shearXY;
        this.shearXZ = shearXZ;
        this.shearYZ = shearYZ;
        this.rotationHintValid = rotationHintValid;
    }
}
