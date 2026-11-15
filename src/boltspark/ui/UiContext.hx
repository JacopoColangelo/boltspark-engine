package boltspark.ui;

import freetype.heaps.types.FontTypes.FreeTypeFontOptions;
import boltspark.ui.core.UiFrame;

/**
 * Shared BoltUI context handed to widgets and panels.
 *
 * Bundles the native window reference, embedded UI font family, native resize
 * cursors, and current OS window size so widget
 * code never touches global state directly.
 * It is native H2D plumbing only: no DOM, no CSS, no browser stack.
 */
class UiContext {
    static final UI_PRELOAD_CHARS:String = hxd.Charset.ASCII + "°±·×–—•…";

    public final window:hxd.Window;
    public final font:h2d.Font;
    public final semiboldFont:h2d.Font;
    public final captionFont:h2d.Font;
    public final labelFont:h2d.Font;
    public final titleFont:h2d.Font;
    public final monoFont:h2d.Font;
    public final resizeHorizontal:hxd.Cursor;
    public final resizeVertical:hxd.Cursor;
    /** Backend-independent frame/input/state core shared by all BoltUI views. */
    public final frame:UiFrame = new UiFrame();

    #if hldx
    final arrowCursor:dx.Cursor;
    final sizeWECursor:dx.Cursor;
    final sizeNSCursor:dx.Cursor;
    #end

    public var width(get, never):Int;
    public var height(get, never):Int;

    public function new(window:hxd.Window) {
        this.window = window;
        font = prepareFont(hxd.Res.fonts.inter_regular.toDynamicFont(13, fontOptions()));
        semiboldFont = prepareFont(hxd.Res.fonts.inter_semibold.toDynamicFont(13, fontOptions()));
        captionFont = prepareFont(hxd.Res.fonts.inter_semibold.toDynamicFont(11, fontOptions()));
        labelFont = prepareFont(hxd.Res.fonts.inter_semibold.toDynamicFont(12, fontOptions()));
        titleFont = prepareFont(hxd.Res.fonts.inter_bold.toDynamicFont(15, fontOptions()));
        // Preserve the existing JetBrains Mono Regular face, 12px size, and
        // fixed-width advances while moving its glyphs to FreeType's native
        // exact-size hinting and on-demand cache.
        monoFont = prepareFont(hxd.Res.fonts.jetbrains_mono.toDynamicFont(
            12, fontOptions(false)));
        #if hldx
        arrowCursor = dx.Cursor.createSystem(dx.Cursor.CursorKind.Arrow);
        sizeWECursor = dx.Cursor.createSystem(dx.Cursor.CursorKind.SizeWE);
        sizeNSCursor = dx.Cursor.createSystem(dx.Cursor.CursorKind.SizeNS);
        resizeHorizontal = hxd.Cursor.Callback(function() sizeWECursor.set());
        resizeVertical = hxd.Cursor.Callback(function() sizeNSCursor.set());
        #else
        resizeHorizontal = hxd.Cursor.Move;
        resizeVertical = hxd.Cursor.Move;
        #end
    }

    public inline function beginFrame():Void frame.begin(width, height);

    public inline function endFrame():Array<String> return frame.end();

    function fontOptions(kerning:Bool = true):FreeTypeFontOptions {
        return {
            antiAliasing: true,
            atlasWidth: 256,
            chars: UI_PRELOAD_CHARS,
            kerning: kerning,
            padding: 2,
            uploadTexture: true
        };
    }

    function prepareFont(result:h2d.Font):h2d.Font {
        if (result.tile != null) result.tile.getTexture().filter = h3d.mat.Data.Filter.Linear;
        return result;
    }

    public function restoreArrowCursor():Void {
        #if hldx
        // Keep Heaps' cursor cache and the native DirectX cursor synchronized.
        // Resize callbacks set a dx.Cursor directly, so either operation alone
        // can leave the other layer believing a stale cursor is active.
        hxd.System.setCursor(hxd.Cursor.Default);
        arrowCursor.set();
        #else
        hxd.System.setCursor(hxd.Cursor.Default);
        #end
    }

    /** Route mouse events to this window until the active drag finishes. */
    public function setMouseCapture(enabled:Bool):Void {
        #if hldx
        // h2d capture only redirects events that reach Heaps. Win32 capture is
        // also required for a windowed drag to keep receiving pointer motion
        // and the button release after the cursor leaves the client area.
        @:privateAccess window.window.captureMouseEvents(enabled);
        #end
    }

    /** Force an I-beam after a callback cursor (for example numeric scrubbing). */
    public function showTextInputCursor():Void {
        // Transition through Default so Heaps cannot skip the native update
        // because its cached cursor was already TextInput.
        hxd.System.setCursor(hxd.Cursor.Default);
        hxd.System.setCursor(hxd.Cursor.TextInput);
    }

    inline function get_width():Int return window.width;

    inline function get_height():Int return window.height;

    /** Center a text widget horizontally inside [x, x + width]. */
    public function centerX(label:h2d.Text, x:Float, w:Float):Void {
        label.x = Math.round(x + Math.max(0, (w - label.textWidth) / 2));
    }

    /** Vertically center a text widget inside [y, y + height]. */
    public function centerY(label:h2d.Text, y:Float, h:Float):Void {
        label.y = Math.round(y + Math.max(0, (h - label.textHeight) / 2));
    }
}
