package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/** Flat editor checkbox: one-pixel border, inset field, accent check mark. */
class UiCheckbox extends h2d.Object {
    public var onChanged:Null<Bool->Void>;
    public var value(get, set):Bool;

    static inline var BOX_SIZE:Float = 14;
    static inline var HEIGHT:Float = 20;

    final box:UiSurface;
    final mark:h2d.Graphics;
    final label:UiText;
    final hit:h2d.Interactive;
    var currentValue:Bool;

    public function new(ctx:UiContext, text:String, ?parent:h2d.Object) {
        super(parent);
        currentValue = false;

        box = new UiSurface(ctx, this);
        box.setStyle(Theme.FIELD_BG, Theme.BORDER, 0);
        box.setSize(BOX_SIZE, BOX_SIZE);
        box.y = Math.round((HEIGHT - BOX_SIZE) * 0.5);
        mark = new h2d.Graphics(this);
        mark.y = box.y;
        label = new UiText(ctx.font, this);
        label.text = text;
        label.textColor = Theme.TEXT_SECONDARY;
        label.lineBreak = false;
        label.x = BOX_SIZE + 8;
        label.y = Math.round((HEIGHT - label.textHeight) * 0.5);
        hit = new h2d.Interactive(160, HEIGHT, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onPush = function(event) {
            set_value(!currentValue);
            if (onChanged != null) onChanged(currentValue);
            event.propagate = false;
        };
        redraw();
    }

    public function setWidth(width:Float):Void {
        hit.width = Math.max(BOX_SIZE + 8, width);
    }

    function get_value():Bool return currentValue;

    function set_value(value:Bool):Bool {
        currentValue = value;
        redraw();
        return value;
    }

    function redraw():Void {
        mark.clear();
        if (!currentValue) return;
        mark.lineStyle(2, Theme.ACCENT);
        mark.moveTo(3, 7);
        mark.lineTo(6, 10);
        mark.lineTo(11, 4);
    }
}
