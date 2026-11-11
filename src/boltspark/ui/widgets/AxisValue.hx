package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;

/** Read-only compact transform value used by the first inspector slice. */
class AxisValue extends h2d.Object {
    final surface:UiSurface;
    final axis:h2d.Text;
    final valueText:h2d.Text;
    final heightValue:Float;

    public function new(ctx:UiContext, axisName:String, axisColor:Int, width:Float,
            height:Float, ?parent:h2d.Object) {
        super(parent);
        heightValue = height;
        surface = new UiSurface(ctx, this);
        surface.setStyle(Theme.FIELD_BG, Theme.BORDER, 0);
        axis = new h2d.Text(ctx.semiboldFont, this);
        axis.text = axisName;
        axis.textColor = axisColor;
        axis.lineBreak = false;
        valueText = new h2d.Text(ctx.monoFont, this);
        valueText.textColor = Theme.TEXT;
        valueText.lineBreak = false;
        setValue(0);
        setWidth(width);
    }

    public function setWidth(width:Float):Void {
        var safe = Math.max(0, width);
        surface.setSize(safe, heightValue);
        axis.x = 8;
        axis.y = Math.max(0, (heightValue - axis.textHeight) * 0.5 - 1);
        valueText.x = 25;
        valueText.y = Math.max(0, (heightValue - valueText.textHeight) * 0.5 - 1);
    }

    public function setValue(value:Float):Void {
        var rounded = Math.round(value * 100) / 100;
        valueText.text = Std.string(rounded);
    }
}
