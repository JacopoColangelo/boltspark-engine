package boltspark.ui.widgets;

import boltspark.ui.UiContext;

/** Editable transform axis with text, spinner arrows, and horizontal scrub. */
class AxisValue extends h2d.Object {
    public var onCommit:Null<Float->Void>;
    public var onEditRejected:Null<String->Void>;

    final field:NumericDragField;

    public function new(ctx:UiContext, axisName:String, axisColor:Int, width:Float,
            height:Float, ?parent:h2d.Object) {
        super(parent);
        field = new NumericDragField(ctx, width, height,
            Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY, 0.1, 0,
            format, axisName, axisColor, this);
        field.onValueChanged = function(next) {
            if (onCommit != null) onCommit(next);
        };
        field.onEditRejected = function(message) {
            if (onEditRejected != null) onEditRejected(message);
        };
    }

    public inline function setWidth(width:Float):Void field.setWidth(width);

    public inline function setValue(next:Float):Void field.setValue(next);

    public inline function isEditing():Bool return field.isEditing();

    static function format(value:Float):String {
        return Std.string(Math.round(value * 100) / 100);
    }
}
