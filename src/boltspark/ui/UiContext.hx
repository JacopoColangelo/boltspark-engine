package boltspark.ui;

/**
 * Shared BoltUI context handed to widgets and panels.
 *
 * Bundles the native window reference, embedded UI font family, rounded
 * surface tile, native resize cursors, and current OS window size so widget
 * code never touches global state directly.
 * It is native H2D plumbing only: no DOM, no CSS, no browser stack.
 */
class UiContext {
    public final window:hxd.Window;
    public final font:h2d.Font;
    public final semiboldFont:h2d.Font;
    public final captionFont:h2d.Font;
    public final titleFont:h2d.Font;
    public final monoFont:h2d.Font;
    public final roundedTile:h2d.Tile;
    public final resizeHorizontal:hxd.Cursor;
    public final resizeVertical:hxd.Cursor;

    #if hldx
    final arrowCursor:dx.Cursor;
    final sizeWECursor:dx.Cursor;
    final sizeNSCursor:dx.Cursor;
    #end

    public var width(get, never):Int;
    public var height(get, never):Int;

    public function new(window:hxd.Window) {
        this.window = window;
        font = prepareFont(hxd.Res.fonts.ui_regular_13.toFont());
        semiboldFont = prepareFont(hxd.Res.fonts.ui_semibold_13.toFont());
        captionFont = prepareFont(hxd.Res.fonts.ui_semibold_11.toFont());
        titleFont = prepareFont(hxd.Res.fonts.ui_bold_15.toFont());
        monoFont = prepareFont(hxd.Res.fonts.mono_12.toFont());
        roundedTile = hxd.Res.surfaces.rounded.toTile();
        roundedTile.getTexture().filter = h3d.mat.Data.Filter.Linear;

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

    function prepareFont(result:h2d.Font):h2d.Font {
        if (result.tile != null) result.tile.getTexture().filter = h3d.mat.Data.Filter.Linear;
        return result;
    }

    public function restoreArrowCursor():Void {
        #if hldx
        arrowCursor.set();
        #else
        hxd.System.setCursor(hxd.Cursor.Default);
        #end
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
