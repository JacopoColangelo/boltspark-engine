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

    public function new(positionX:Float = 0, positionY:Float = 0,
            positionZ:Float = 0, rotationX:Float = 0, rotationY:Float = 0,
            rotationZ:Float = 0, scaleX:Float = 1, scaleY:Float = 1,
            scaleZ:Float = 1) {
        this.positionX = positionX;
        this.positionY = positionY;
        this.positionZ = positionZ;
        this.rotationX = rotationX;
        this.rotationY = rotationY;
        this.rotationZ = rotationZ;
        this.scaleX = scaleX;
        this.scaleY = scaleY;
        this.scaleZ = scaleZ;
    }
}
