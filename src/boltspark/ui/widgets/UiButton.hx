package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/** Compact square-edged native editor button with an optional icon. */
class UiButton extends h2d.Object {
    public var onClick:Null<Void->Void>;

    final surface:UiSurface;
    final hit:h2d.Interactive;
    final icon:h2d.Graphics;
    final label:h2d.Text;
    var fullText:String;
    var widthValue:Float;
    final heightValue:Float;
    var iconKind:UiIconKind = None;
    var hovered:Bool = false;
    var pressed:Bool = false;
    var primary:Bool = false;
    var danger:Bool = false;
    var quiet:Bool = false;
    var selected:Bool = false;
    /** Optional fixed icon size. Toolbars with short controls use this to keep
     *  icons legible instead of shrinking them to `height - 10`. */
    var iconSizeOverride:Int = 0;

    public function new(ctx:UiContext, text:String, w:Float, h:Float, ?parent:h2d.Object) {
        super(parent);
        widthValue = w;
        heightValue = h;
        fullText = text;

        surface = new UiSurface(ctx, this);
        surface.setSize(w, h);
        hit = new h2d.Interactive(w, h, this);
        hit.backgroundColor = 0;
        // Desktop editor buttons retain the arrow cursor; the pointing hand is
        // a web convention and becomes visually noisy across dense toolbars.
        hit.cursor = hxd.Cursor.Default;
        hit.onOver = function(_) {
            hovered = true;
            redraw();
        };
        hit.onOut = function(_) {
            hovered = false;
            pressed = false;
            redraw();
        };
        hit.onPush = function(_) {
            pressed = true;
            redraw();
        };
        hit.onRelease = function(_) {
            pressed = false;
            redraw();
            if (onClick != null) onClick();
        };
        hit.onReleaseOutside = function(_) {
            pressed = false;
            redraw();
        };

        icon = new h2d.Graphics(this);
        label = new UiText(ctx.semiboldFont, this);
        label.textColor = Theme.TEXT;
        label.lineBreak = false;
        setText(text);
        redraw();
    }

    public function setIcon(kind:UiIconKind):UiButton {
        iconKind = kind;
        redrawIcon();
        center();
        return this;
    }

    /** Render the icon at a fixed pixel size (the atlas supports 6-16 px). */
    public function setIconSize(size:Int):UiButton {
        iconSizeOverride = size;
        redrawIcon();
        center();
        return this;
    }

    inline function iconSize():Float {
        return iconSizeOverride > 0
            ? iconSizeOverride
            : Math.min(16, heightValue - 10);
    }

    public function setPrimary(value:Bool = true):UiButton {
        primary = value;
        redraw();
        return this;
    }

    public function setDanger(value:Bool = true):UiButton {
        danger = value;
        redraw();
        return this;
    }

    public function setQuiet(value:Bool = true):UiButton {
        quiet = value;
        redraw();
        return this;
    }

    public function setSelected(value:Bool):UiButton {
        selected = value;
        redraw();
        return this;
    }

    /** Set text and re-center; long values are elided. */
    public function setText(text:String):Void {
        fullText = text;
        fitLabel();
        center();
    }

    public function setWidth(w:Float):Void {
        widthValue = Math.max(0, w);
        hit.width = widthValue;
        surface.setSize(widthValue, heightValue);
        fitLabel();
        center();
    }

    public function center():Void {
        var iconSize = iconKind == None ? 0.0 : iconSize();
        var gap = iconSize > 0 && label.text.length > 0 ? 7.0 : 0.0;
        var contentWidth = iconSize + gap + label.textWidth;
        var contentX = Math.round(Math.max(0, (widthValue - contentWidth) * 0.5));
        icon.x = contentX;
        icon.y = Math.max(0, Math.round((heightValue - iconSize) * 0.5));
        label.x = contentX + iconSize + gap;
        label.y = Math.max(0, Math.round((heightValue - label.textHeight) * 0.5 - 0.5));
    }

    function fitLabel():Void {
        var iconReserve = iconKind == None ? 12.0 : 39.0;
        var maxWidth = Math.max(0, widthValue - iconReserve);
        label.text = fullText;
        if (label.calcTextWidth(fullText) <= maxWidth) return;
        label.text = "";
        for (i in 0...fullText.length) {
            var candidate = fullText.substr(0, i + 1) + "...";
            if (label.calcTextWidth(candidate) > maxWidth) break;
            label.text = candidate;
        }
    }

    function redraw():Void {
        surface.visible = true;
        var fill = Theme.BUTTON;
        var border = Theme.BORDER;
        var textColor = Theme.TEXT;
        if (quiet) {
            surface.visible = hovered || selected || pressed;
            fill = selected ? Theme.ACCENT_MUTED : Theme.SURFACE_2;
            border = selected ? Theme.ACCENT : Theme.BORDER_STRONG;
        }
        if (primary) {
            fill = pressed ? 0x236B59 : (hovered ? 0x326F60 : Theme.ACCENT_MUTED);
            border = hovered || pressed ? Theme.ACCENT_HOVER : Theme.ACCENT;
            textColor = 0xFFFFFF;
        } else if (danger) {
            fill = pressed ? 0x673437 : (hovered ? 0x513137 : Theme.SURFACE_2);
            border = hovered ? Theme.DANGER : Theme.BORDER;
            textColor = hovered ? 0xFFB7B7 : Theme.TEXT;
        } else if (pressed || selected) {
            fill = Theme.ACCENT_MUTED;
            border = Theme.ACCENT;
        } else if (hovered) {
            fill = Theme.BUTTON_HOVER;
            border = Theme.BORDER_STRONG;
        }
        surface.setStyle(fill, border, 0);
        label.textColor = textColor;
        redrawIcon(textColor);
    }

    function redrawIcon(?color:Int):Void {
        icon.clear();
        if (iconKind == None) return;
        UiIcons.draw(icon, iconKind, 0, 0, iconSize(),
            color == null ? label.textColor : color);
        fitLabel();
        center();
    }
}
