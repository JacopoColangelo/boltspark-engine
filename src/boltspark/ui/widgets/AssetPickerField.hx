package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiText;

/**
 * Compact object-picker field for asset-valued Inspector properties.
 *
 * The widget stays deliberately asset-agnostic: it renders the current label
 * and asks its owner to open a picker via `onPick`. The owner supplies the
 * type-aware option list (and owns the shared dropdown popup), so the same
 * field works for meshes, materials, or any future asset family.
 */
class AssetPickerField extends h2d.Object {
    static inline var ARROW_WIDTH:Float = 16;

    public var onPick:Null<Void->Void>;

    final ctx:UiContext;
    final surface:FieldSurface;
    final valueText:h2d.Text;
    final chevron:h2d.Graphics;
    final hit:h2d.Interactive;
    var labelValue:String = "None";
    var widthValue:Float = 0;
    var heightValue:Float;
    var hovered:Bool = false;

    public function new(ctx:UiContext, width:Float, height:Float,
            value:String, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        heightValue = height;
        labelValue = value;

        surface = new FieldSurface(this);
        valueText = new UiText(ctx.font, this);
        valueText.lineBreak = false;
        valueText.textColor = Theme.TEXT;
        chevron = new h2d.Graphics(this);
        UiIcons.draw(chevron, ChevronDown, 0, 0, 10, Theme.MUTED);

        hit = new h2d.Interactive(1, 1, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onOver = function(_) {
            hovered = true;
            updateStyle();
        };
        hit.onOut = function(_) {
            hovered = false;
            updateStyle();
        };
        hit.onClick = function(event) {
            event.propagate = false;
            if (onPick != null) onPick();
        };

        setValue(value);
        setWidth(width);
    }

    public function setValue(value:String):Void {
        labelValue = value == null ? "" : value;
        fitLabel();
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        surface.setSize(widthValue, heightValue);
        valueText.x = 6;
        valueText.y = Math.max(0,
            Math.round((heightValue - valueText.textHeight) * 0.5 - 1));
        chevron.x = Math.max(0, widthValue - ARROW_WIDTH);
        chevron.y = Math.max(0, Math.round((heightValue - 10) * 0.5));
        hit.width = widthValue;
        hit.height = heightValue;
        fitLabel();
    }

    function fitLabel():Void {
        var maxWidth = Math.max(0, widthValue - ARROW_WIDTH - 10);
        if (valueText.calcTextWidth(labelValue) <= maxWidth) {
            valueText.text = labelValue;
            return;
        }
        var text = "";
        for (index in 0...labelValue.length) {
            var candidate = labelValue.substr(0, index + 1) + "…";
            if (valueText.calcTextWidth(candidate) > maxWidth) break;
            text = candidate;
        }
        valueText.text = text;
    }

    function updateStyle():Void {
        surface.setStyle(
            hovered ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            hovered ? Theme.ACCENT : Theme.BORDER);
    }
}
