package boltspark.ui.widgets;

/**
 * Numeric stepper widget: [-] value [+].
 *
 * Edits a bounded float in fixed steps and reports changes through
 * onValueChanged. Used by the inspector for editable object properties.
 */
class Stepper extends h2d.Object {
    public var onValueChanged:Null<Float->Void>;

    public var value(default, null):Float;
    public final min:Float;
    public final max:Float;
    public final step:Float;

    final minus:UiButton;
    final plus:UiButton;
    final valueText:h2d.Text;
    final format:Float->String;
    final width:Float;
    final height:Float;

    public function new(ctx:boltspark.ui.UiContext, w:Float, h:Float,
            min:Float, max:Float, step:Float, initial:Float,
            format:Float->String, ?parent:h2d.Object) {
        super(parent);
        this.width = w;
        this.height = h;
        this.min = min;
        this.max = max;
        this.step = step;
        this.value = initial;
        this.format = format;

        var buttonSize = h;
        minus = new UiButton(ctx, "-", buttonSize, h, this);
        minus.onClick = function() {
            value = clamp(value - step);
            refresh();
        };

        plus = new UiButton(ctx, "+", buttonSize, h, this);
        plus.onClick = function() {
            value = clamp(value + step);
            refresh();
        };

        valueText = new h2d.Text(ctx.font, this);
        valueText.textColor = boltspark.ui.Theme.TEXT;

        refresh();
    }

    public function setValue(v:Float):Void {
        value = clamp(v);
        refresh();
    }

    function clamp(v:Float):Float {
        if (v < min) v = min;
        if (v > max) v = max;
        return v;
    }

    function refresh():Void {
        valueText.text = format(value);
        var buttonSize = height;
        minus.setPosition(0, 0);
        plus.setPosition(width - buttonSize, 0);
        valueText.x = buttonSize + Math.max(0, (width - buttonSize * 2 - valueText.textWidth) / 2);
        valueText.y = Math.max(0, (height - valueText.textHeight) / 2);
        if (onValueChanged != null) onValueChanged(value);
    }
}
