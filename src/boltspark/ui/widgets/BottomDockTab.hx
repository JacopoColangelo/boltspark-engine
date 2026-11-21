package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiText;

/**
 * Frameless bottom-dock tab: Tabler icon plus a full, never-elided label.
 * The active state is carried by the accent rule in the dock tab strip, so the
 * tab itself only tints its icon and text instead of drawing a button frame.
 */
class BottomDockTab extends h2d.Object {
    public var onClick:Null<Void->Void>;
    public var width(get, never):Float;
    public var naturalWidth(get, never):Float;

    final hit:h2d.Interactive;
    final icon:h2d.Graphics;
    final iconKind:UiIconKind;
    final label:UiText;
    var active:Bool = false;
    var hovered:Bool = false;

    public function new(ctx:UiContext, text:String, iconKind:UiIconKind,
            width:Float, height:Float, ?parent:h2d.Object) {
        super(parent);
        this.iconKind = iconKind;

        hit = new h2d.Interactive(width, height, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onOver = function(_) {
            hovered = true;
            restyle();
        };
        hit.onOut = function(_) {
            hovered = false;
            restyle();
        };
        hit.onRelease = function(_) if (onClick != null) onClick();

        icon = new h2d.Graphics(this);
        icon.x = 6;
        icon.y = Math.round((height - 14) * 0.5);
        label = new UiText(ctx.semiboldFont, this);
        label.text = text;
        label.lineBreak = false;
        label.x = 26;
        label.y = Math.round((height - label.textHeight) * 0.5);
        restyle();
    }

    public function setActive(value:Bool):Void {
        if (active == value) return;
        active = value;
        restyle();
    }

    public function setWidth(width:Float):Void {
        hit.width = width;
        // Very narrow docks keep the icon; the full label comes back as soon
        // as it fits rather than being cut down with an ellipsis.
        label.visible = width >= naturalWidth;
    }

    inline function get_width():Float return hit.width;
    inline function get_naturalWidth():Float return label.textWidth + 36;

    function restyle():Void {
        var textColor = active ? Theme.TEXT
            : (hovered ? Theme.TEXT_SECONDARY : Theme.MUTED);
        var iconColor = active ? Theme.ACCENT
            : (hovered ? Theme.TEXT_SECONDARY : Theme.MUTED);
        label.textColor = textColor;
        icon.clear();
        UiIcons.draw(icon, iconKind, 0, 0, 14, iconColor);
    }
}
