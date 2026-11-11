package boltspark.ui.widgets;

import boltspark.ui.UiContext;

/** Bounded numeric property backed by the shared drag-and-arrow field. */
class Stepper extends h2d.Object {
    public var onValueChanged:Null<Float->Void>;
    public var onEditRejected:Null<String->Void>;

    public var value(get, never):Float;
    public final min:Float;
    public final max:Float;
    public final step:Float;

    final field:NumericDragField;

    public function new(ctx:UiContext, width:Float, height:Float,
            min:Float, max:Float, step:Float, initial:Float,
            format:Float->String, ?parent:h2d.Object) {
        super(parent);
        this.min = min;
        this.max = max;
        this.step = step;
        field = new NumericDragField(ctx, width, height,
            min, max, step, initial, format, "", 0, this);
        field.onValueChanged = function(next) {
            if (onValueChanged != null) onValueChanged(next);
        };
        field.onEditRejected = function(message) {
            if (onEditRejected != null) onEditRejected(message);
        };
    }

    public inline function setValue(next:Float):Void field.setValue(next);

    public inline function setWidth(width:Float):Void field.setWidth(width);

    public inline function isEditing():Bool return field.isEditing();

    inline function get_value():Float return field.value;
}
