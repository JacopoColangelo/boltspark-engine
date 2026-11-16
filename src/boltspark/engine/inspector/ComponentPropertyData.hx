package boltspark.engine.inspector;

/** UI-neutral description of one editable or read-only component property. */
class ComponentPropertyData {
    public final id:String;
    public final label:String;
    public final kind:ComponentPropertyKind;
    public final numberValues:Array<Float>;
    public final textValue:String;
    public final editable:Bool;
    public final resettable:Bool;
    public final linkable:Bool;
    public final linked:Bool;
    /**
     * Per-axis "no single value" flags for a multi-object selection. The
     * backing value in `numberValues`/`textValue` stays valid (it is the
     * primary object's value, used as an edit/scrub base), while the UI shows
     * "Multiple Values" for flagged axes until the user commits a new value.
     */
    public final mixed:Array<Bool>;
    /** For `Asset` properties: the family of asset the picker accepts. */
    public final assetType:Null<AssetType>;
    /** For `Asset` properties: id of the currently assigned asset ("" = none). */
    public final assetId:String;
    /** For `Asset` properties: choices offered by the type-aware picker. */
    public final options:Array<AssetOption>;
    /** For `Boolean` properties: current on/off state. */
    public final boolValue:Bool;
    /** For `Number`/`Integer` properties: editing range and step. */
    public final numberMin:Float;
    public final numberMax:Float;
    public final numberStep:Float;
    public final integerValue:Bool;

    public function new(id:String, label:String, kind:ComponentPropertyKind,
            ?numberValues:Array<Float>, textValue:String = "",
            editable:Bool = true, resettable:Bool = false,
            linkable:Bool = false, linked:Bool = false,
            ?mixed:Array<Bool>, ?assetType:AssetType, assetId:String = "",
            ?options:Array<AssetOption>, boolValue:Bool = false,
            numberMin:Float = 0, numberMax:Float = 1,
            numberStep:Float = 0.1, integer:Bool = false) {
        this.id = id;
        this.label = label;
        this.kind = kind;
        this.numberValues = numberValues == null ? [] : numberValues.copy();
        this.textValue = textValue == null ? "" : textValue;
        this.editable = editable;
        this.resettable = resettable;
        this.linkable = linkable;
        this.linked = linked;
        this.mixed = mixed == null ? [false, false, false] : mixed.copy();
        this.assetType = assetType;
        this.assetId = assetId;
        this.options = options == null ? [] : options.copy();
        this.boolValue = boolValue;
        this.numberMin = numberMin;
        this.numberMax = numberMax;
        this.numberStep = numberStep;
        this.integerValue = integer;
    }

    /** True when one axis (axis 0 for Text properties) differs across the selection. */
    public inline function isMixed(axis:Int = 0):Bool {
        return axis >= 0 && axis < mixed.length && mixed[axis];
    }

    public static function vector3(id:String, label:String,
            x:Float, y:Float, z:Float, resettable:Bool = false,
            linkable:Bool = false, linked:Bool = false):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Vector3, [x, y, z], "",
            true, resettable, linkable, linked);
    }

    public static function text(id:String, label:String, value:String,
            editable:Bool = false):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Text, [], value,
            editable);
    }

    /**
     * Object-picker property. `textValue` doubles as the displayed label so
     * existing consumers that read it (and mixed-selection code) keep working.
     */
    public static function asset(id:String, label:String, assetType:AssetType,
            assetId:String, valueLabel:String, options:Array<AssetOption>,
            editable:Bool = true):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Asset, [], valueLabel,
            editable, false, false, false, null, assetType, assetId, options);
    }

    public static function number(id:String, label:String, value:Float,
            min:Float, max:Float, step:Float = 0.1,
            resettable:Bool = false):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Number, [value], "",
            true, resettable, false, false, null, null, "", null,
            false, min, max, step);
    }

    public static function integer(id:String, label:String, value:Int,
            min:Int, max:Int, resettable:Bool = false):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Integer, [value], "",
            true, resettable, false, false, null, null, "", null,
            false, min, max, 1, true);
    }

    public static function boolean(id:String, label:String,
            value:Bool, resettable:Bool = false):ComponentPropertyData {
        return new ComponentPropertyData(id, label, Boolean, [], "",
            true, resettable, false, false, null, null, "", null,
            value);
    }
}
