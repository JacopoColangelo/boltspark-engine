package boltspark.engine;

import boltspark.editor.EditorTransform;
import boltspark.editor.TransformMatrix;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;

/** Mandatory GameObject transform component backed by existing affine math. */
class Transform extends Component {
    public static inline var TYPE_ID:String = "transform";

    public var value(default, null):EditorTransform;
    public var revision(get, never):Int;

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

    public function new(?initialValue:EditorTransform) {
        super();
        replaceValue(initialValue == null ? new EditorTransform() : initialValue);
    }

    override function get_typeId():String return TYPE_ID;
    override function get_displayName():String return "Transform";

    /** Replace authored channels without replacing the mandatory component. */
    public function setValue(next:EditorTransform):Void {
        if (next == null) throw "Transform value cannot be null";
        replaceValue(next);
        changed();
    }

    public function clone():EditorTransform return value.clone();
    public function toMatrix():TransformMatrix return value.toMatrix();
    public function sameAs(other:Dynamic, epsilon:Float = 0.0000001):Bool {
        var compared:EditorTransform = Std.isOfType(other, Transform)
            ? (cast other : Transform).value
            : cast other;
        return value.sameAs(compared, epsilon);
    }
    public function isFiniteAndInvertible(epsilon:Float = 0.000000000001):Bool {
        return value.isFiniteAndInvertible(epsilon);
    }

    override public function cloneComponent():Component {
        return new Transform(value);
    }

    override public function inspectorData(componentIndex:Int):ComponentInspectorData {
        // The live editor projection replaces this row with its normalized
        // quaternion-derived display values. Retain authored hints here so the
        // component core stays renderer-independent and headless-testable.
        var displayRotationX = value.rotationHintValid ? value.rotationHintX : 0;
        var displayRotationY = value.rotationHintValid ? value.rotationHintY : 0;
        var displayRotationZ = value.rotationHintValid ? value.rotationHintZ : 0;
        return new ComponentInspectorData(componentIndex, TYPE_ID, "Transform", [
            ComponentPropertyData.vector3("position", "Position",
                value.positionX, value.positionY, value.positionZ, true),
            ComponentPropertyData.vector3("rotation", "Rotation",
                displayRotationX, displayRotationY, displayRotationZ, true),
            ComponentPropertyData.vector3("scale", "Scale",
                value.scaleX, value.scaleY, value.scaleZ, true, true)
        ], false);
    }

    function replaceValue(source:EditorTransform):Void {
        if (value != null) value.onChanged = null;
        value = source.clone();
        value.onChanged = changed;
    }

    inline function get_revision():Int return value.revision;
    inline function get_positionX():Float return value.positionX;
    inline function set_positionX(v:Float):Float return value.positionX = v;
    inline function get_positionY():Float return value.positionY;
    inline function set_positionY(v:Float):Float return value.positionY = v;
    inline function get_positionZ():Float return value.positionZ;
    inline function set_positionZ(v:Float):Float return value.positionZ = v;
    inline function get_rotationX():Float return value.rotationX;
    inline function set_rotationX(v:Float):Float return value.rotationX = v;
    inline function get_rotationY():Float return value.rotationY;
    inline function set_rotationY(v:Float):Float return value.rotationY = v;
    inline function get_rotationZ():Float return value.rotationZ;
    inline function set_rotationZ(v:Float):Float return value.rotationZ = v;
    inline function get_rotationW():Float return value.rotationW;
    inline function set_rotationW(v:Float):Float return value.rotationW = v;
    inline function get_rotationHintX():Float return value.rotationHintX;
    inline function set_rotationHintX(v:Float):Float return value.rotationHintX = v;
    inline function get_rotationHintY():Float return value.rotationHintY;
    inline function set_rotationHintY(v:Float):Float return value.rotationHintY = v;
    inline function get_rotationHintZ():Float return value.rotationHintZ;
    inline function set_rotationHintZ(v:Float):Float return value.rotationHintZ = v;
    inline function get_rotationHintValid():Bool return value.rotationHintValid;
    inline function set_rotationHintValid(v:Bool):Bool return value.rotationHintValid = v;
    inline function get_scaleX():Float return value.scaleX;
    inline function set_scaleX(v:Float):Float return value.scaleX = v;
    inline function get_scaleY():Float return value.scaleY;
    inline function set_scaleY(v:Float):Float return value.scaleY = v;
    inline function get_scaleZ():Float return value.scaleZ;
    inline function set_scaleZ(v:Float):Float return value.scaleZ = v;
    inline function get_shearXY():Float return value.shearXY;
    inline function set_shearXY(v:Float):Float return value.shearXY = v;
    inline function get_shearXZ():Float return value.shearXZ;
    inline function set_shearXZ(v:Float):Float return value.shearXZ = v;
    inline function get_shearYZ():Float return value.shearYZ;
    inline function set_shearYZ(v:Float):Float return value.shearYZ = v;
}
