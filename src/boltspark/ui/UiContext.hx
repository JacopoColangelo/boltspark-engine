package boltspark.ui;

/**
 * Shared BoltUI context handed to widgets and panels.
 *
 * Bundles the native window reference, the default font, and the current
 * OS window size so widget code never touches global state directly.
 * It is native H2D plumbing only: no DOM, no CSS, no browser stack.
 */
class UiContext {
    public final window:hxd.Window;
    public final font:h2d.Font;

    public var width(get, never):Int;
    public var height(get, never):Int;

    public function new(window:hxd.Window, font:h2d.Font) {
        this.window = window;
        this.font = font;
    }

    inline function get_width():Int return window.width;

    inline function get_height():Int return window.height;

    /** Center a text widget horizontally inside [x, x + width]. */
    public function centerX(label:h2d.Text, x:Float, w:Float):Void {
        label.x = x + Math.max(0, (w - label.textWidth) / 2);
    }

    /** Vertically center a text widget inside [y, y + height]. */
    public function centerY(label:h2d.Text, y:Float, h:Float):Void {
        label.y = y + Math.max(0, (h - label.textHeight) / 2);
    }
}
