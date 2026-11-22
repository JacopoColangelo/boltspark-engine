package boltspark.platform;

import boltspark.platform.NativeDragLabel;
import boltspark.platform.NativeFloatWindow.WinFloatLabelHandle;
import boltspark.ui.Theme;
import boltspark.ui.render.FloatGlyphAtlas;
import haxe.io.Bytes;

/**
 * One small, always-on-top, click-through HWND that draws the shared drag
 * label above every editor window. It replaces the old pair of labels (main
 * editor viewport hint + per-float ghost), which duplicated each other and
 * disappeared under a floating panel's header.
 *
 * Text is composited into a 32-bit BGRA buffer by FloatGlyphAtlas and handed
 * to winfloat.c, which paints it into a layered window. The whole surface is
 * opaque; the color key is only needed by the native layer.
 */
class DragLabelOverlay {
    static inline var HEIGHT:Int = 22;
    static inline var PAD_X:Int = 10;
    static inline var TEXT_BASELINE:Int = 15;

    final handle:WinFloatLabelHandle;
    final atlas:FloatGlyphAtlas;
    var buffer:Bytes = Bytes.alloc(0);
    var width:Int = 0;
    var visible:Bool = false;

    public static function create():Null<DragLabelOverlay> {
        var handle = NativeDragLabel.create();
        if (handle == null) return null;
        return new DragLabelOverlay(handle);
    }

    function new(handle:WinFloatLabelHandle) {
        this.handle = handle;
        // Same face/size as the old viewport hint (UiContext.font).
        atlas = new FloatGlyphAtlas(
            hxd.Res.fonts.inter_regular.entry.getBytes(), 13);
    }

    /** Move and redraw the label at a screen-space cursor position. */
    public function update(text:String, screenX:Int, screenY:Int):Void {
        if (text == null || text == "") {
            hide();
            return;
        }
        var wanted = atlas.textWidth(text) + PAD_X * 2;
        if (wanted < 76) wanted = 76;
        if (wanted != width) {
            width = wanted;
            buffer = Bytes.alloc(width * HEIGHT * 4);
        }
        fillRect(0, 0, width, HEIGHT, Theme.FIELD_BG);
        fillRect(0, 0, width, 2, Theme.ACCENT);
        fillRect(0, HEIGHT - 2, width, 2, Theme.ACCENT);
        fillRect(0, 0, 2, HEIGHT, Theme.ACCENT);
        fillRect(width - 2, 0, 2, HEIGHT, Theme.ACCENT);
        atlas.drawLine(buffer, width, HEIGHT, text, PAD_X,
            TEXT_BASELINE, 0xE8F0F5);
        NativeDragLabel.paint(handle, buffer, width, HEIGHT, screenX, screenY);
        visible = true;
    }

    public function hide():Void {
        if (!visible) return;
        NativeDragLabel.hide(handle);
        visible = false;
    }

    public function destroy():Void {
        hide();
        NativeDragLabel.destroy(handle);
    }

    /** Write a solid top-down BGRA rectangle. */
    function fillRect(x0:Int, y0:Int, w:Int, h:Int, color:Int):Void {
        var b = color & 0xFF;
        var g = (color >> 8) & 0xFF;
        var r = (color >> 16) & 0xFF;
        var xEnd = Std.int(Math.min(width, x0 + w));
        var yEnd = Std.int(Math.min(HEIGHT, y0 + h));
        for (y in Std.int(Math.max(0, y0))...yEnd) {
            var row = y * width * 4;
            for (x in Std.int(Math.max(0, x0))...xEnd) {
                var at = row + x * 4;
                buffer.set(at, b);
                buffer.set(at + 1, g);
                buffer.set(at + 2, r);
                buffer.set(at + 3, 0xFF);
            }
        }
    }
}
