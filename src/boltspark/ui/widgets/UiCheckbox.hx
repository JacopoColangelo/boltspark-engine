package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/** Flat editor checkbox: an inset dark field with a subtle border when off,
 *  the same field with an accent border and Tabler check mark when on. */
class UiCheckbox extends h2d.Object {
    public var onChanged:Null<Bool->Void>;
    public var value(get, set):Bool;

    static inline var BOX_SIZE:Float = 16;
    static inline var HEIGHT:Float = 22;
    static inline var MARK_SIZE:Float = 12;

    final box:UiSurface;
    final mark:h2d.Graphics;
    final label:UiText;
    final hit:h2d.Interactive;
    var currentValue:Bool;

    public function new(ctx:UiContext, text:String, ?parent:h2d.Object) {
        super(parent);
        currentValue = false;

        box = new UiSurface(ctx, this);
        box.setSize(BOX_SIZE, BOX_SIZE);
        box.y = Math.round((HEIGHT - BOX_SIZE) * 0.5);
        mark = new h2d.Graphics(this);
        var markInset = Math.round((BOX_SIZE - MARK_SIZE) * 0.5);
        mark.x = markInset;
        mark.y = box.y + markInset;
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

    /** Restrict clicks to the box itself when the checkbox has no label and
     *  another control (such as a name field) sits directly to its right. */
    public function setBoxOnlyHit():Void {
        hit.width = BOX_SIZE + 8;
    }

    function get_value():Bool return currentValue;

    function set_value(value:Bool):Bool {
        currentValue = value;
        redraw();
        return value;
    }

    function redraw():Void {
        if (currentValue) {
            // Keep the editor's inset-field look: dark fill, accent border,
            // and the pinned Tabler check glyph tinted to match the border.
            box.setStyle(Theme.FIELD_FOCUS, Theme.ACCENT, 0);
            UiIcons.draw(mark, Check, 0, 0, MARK_SIZE, Theme.ACCENT_HOVER);
        } else {
            box.setStyle(Theme.FIELD_BG, Theme.BORDER, 0);
            // UiIcons.draw() attaches a Bitmap child; Graphics.clear() would
            // only drop draw commands, so remove the child explicitly.
            mark.removeChildren();
        }
    }
}
