package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/**
 * Delayed hover tooltip drawn above the editor chrome.
 *
 * Callers use window coordinates; the tooltip clamps itself to the native
 * window so a hover near the right or bottom edge stays fully visible.
 */
class UiTooltip {
    static inline var DELAY:Float = 0.55;
    static inline var PADDING:Int = 7;
    static inline var OFFSET_X:Float = 14;
    static inline var OFFSET_Y:Float = 16;

    final ctx:UiContext;
    final surface:UiSurface;
    final label:UiText;
    var pendingText:String = "";
    var remaining:Float = 0;
    var anchorX:Float = 0;
    var anchorY:Float = 0;

    public function new(ctx:UiContext, parent:h2d.Object) {
        this.ctx = ctx;
        surface = new UiSurface(ctx, parent);
        surface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0.06);
        surface.visible = false;
        label = new UiText(ctx.captionFont, surface);
        label.textColor = Theme.TEXT;
        label.lineBreak = false;
        label.x = PADDING;
        label.y = PADDING;
    }

    /** Start (or replace) a hover tooltip at the current pointer position. */
    public function schedule(text:String, mouseX:Float, mouseY:Float):Void {
        if (text == null || text.length == 0) {
            cancel();
            return;
        }
        if (surface.visible && label.text == text) return;
        cancel();
        pendingText = text;
        remaining = DELAY;
        anchorX = mouseX;
        anchorY = mouseY;
    }

    public function cancel():Void {
        pendingText = "";
        remaining = 0;
        surface.visible = false;
    }

    public function update(dt:Float):Void {
        if (pendingText == "") return;
        remaining -= dt;
        if (remaining > 0) return;

        label.text = pendingText;
        var width = label.textWidth + PADDING * 2;
        var height = label.textHeight + PADDING * 2;
        surface.setSize(width, height);
        surface.x = Math.max(2, Math.min(anchorX + OFFSET_X, ctx.width - width - 2));
        surface.y = Math.max(2, Math.min(anchorY + OFFSET_Y, ctx.height - height - 2));
        surface.visible = true;
        Sys.println('[probe] tooltip ${pendingText}');
        pendingText = "";
    }
}
