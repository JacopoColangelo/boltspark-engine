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

    public function new(id:String, label:String, kind:ComponentPropertyKind,
            ?numberValues:Array<Float>, textValue:String = "",
            editable:Bool = true, resettable:Bool = false,
            linkable:Bool = false, linked:Bool = false) {
        this.id = id;
        this.label = label;
        this.kind = kind;
        this.numberValues = numberValues == null ? [] : numberValues.copy();
        this.textValue = textValue == null ? "" : textValue;
        this.editable = editable;
        this.resettable = resettable;
        this.linkable = linkable;
        this.linked = linked;
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
}
