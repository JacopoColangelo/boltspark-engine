package boltspark.ui;

import boltspark.ui.shaders.UiIconShader;

enum abstract UiIconKind(Int) from Int to Int {
    var None = 0;
    var Add = 1;
    var Trash = 2;
    var Cube = 3;
    var Search = 4;
    var Play = 5;
    var Pause = 6;
    var Stop = 7;
    var Move = 8;
    var Rotate = 9;
    var Scale = 10;
    var ChevronDown = 11;
    var ChevronRight = 12;
    var Console = 13;
    var Sliders = 14;
    var Hierarchy = 15;
    var Close = 16;
    var Grid = 17;
    var More = 18;
    var ChevronUp = 19;
    var BrandOuter = 20;
    var BrandBolt = 21;
    var StatusDot = 22;
    var Link = 23;
    var Unlink = 24;
    var Reset = 25;
}

/** Exact-size analytic editor icons with pixel-grid-fitted strokes. */
class UiIcons {
    public static function draw(target:h2d.Graphics, kind:UiIconKind, x:Float, y:Float,
            size:Float, color:Int, alpha:Float = 1):Void {
        target.removeChildren();
        if (kind == None || size <= 0) return;

        // Like a hinted font glyph, each icon is rasterized at the exact size
        // it occupies. Integer quad bounds keep the analytic coverage stable;
        // the shader then fits one- and two-pixel stems to the pixel grid.
        var pixelSize = Math.max(1, Math.round(size));

        // The one-pixel white texture only supplies a quad. Icon coverage is
        // calculated analytically in UiIconShader; no icon bitmap is sampled.
        var bitmap = new h2d.Bitmap(h2d.Tile.fromColor(0xFFFFFF), target);
        bitmap.x = Math.round(x);
        bitmap.y = Math.round(y);
        bitmap.width = pixelSize;
        bitmap.height = pixelSize;
        bitmap.smooth = false;
        bitmap.color.setColor(color);
        bitmap.color.a = Math.max(0, Math.min(1, alpha));

        var shader = new UiIconShader();
        shader.iconKind = kind;
        shader.iconSize = pixelSize;
        // Small controls retain a single-pixel stem. Header icons use a
        // grayscale-hinted 1.5 px optical weight, while 16 px toolbar glyphs
        // use two full pixels to match Inter SemiBold. Unlike the old
        // size*0.075 rule, each supported size now has a deliberate weight.
        var strokePixels = pixelSize >= 16 ? 2.0 : (pixelSize >= 14 ? 1.5 : 1.0);
        shader.stroke = strokePixels / pixelSize;
        bitmap.addShader(shader);
    }
}
