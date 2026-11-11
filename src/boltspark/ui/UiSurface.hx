package boltspark.ui;

/**
 * Lightweight anti-aliased rounded surface backed by one embedded 9-slice.
 * Three tinted layers provide a shadow, border, and fill without introducing
 * a shader or native dependency.
 */
class UiSurface extends h2d.Object {
    final shadow:h2d.ScaleGrid;
    final border:h2d.ScaleGrid;
    final fill:h2d.ScaleGrid;

    var widthValue:Float = 0;
    var heightValue:Float = 0;
    var inset:Float = 1;

    public function new(ctx:UiContext, ?parent:h2d.Object) {
        super(parent);
        shadow = makeGrid(ctx.roundedTile, this);
        border = makeGrid(ctx.roundedTile, this);
        fill = makeGrid(ctx.roundedTile, this);
        setStyle(Theme.SURFACE_2, Theme.BORDER, 0.24);
    }

    static function makeGrid(tile:h2d.Tile, parent:h2d.Object):h2d.ScaleGrid {
        var result = new h2d.ScaleGrid(tile, 9, 9, parent);
        result.tileBorders = false;
        result.tileCenter = false;
        return result;
    }

    public function setSize(width:Float, height:Float):Void {
        widthValue = Math.max(0, width);
        heightValue = Math.max(0, height);
        shadow.x = 0;
        shadow.y = 2;
        shadow.width = widthValue;
        shadow.height = heightValue;
        border.x = 0;
        border.y = 0;
        border.width = widthValue;
        border.height = heightValue;
        fill.x = inset;
        fill.y = inset;
        fill.width = Math.max(0, widthValue - inset * 2);
        fill.height = Math.max(0, heightValue - inset * 2);
    }

    public function setStyle(fillColor:Int, borderColor:Int, shadowAlpha:Float = 0.0,
            borderInset:Float = 1.0):Void {
        inset = Math.max(0, borderInset);
        tint(fill, fillColor, 1);
        tint(border, borderColor, 1);
        tint(shadow, 0x000000, Math.max(0, Math.min(1, shadowAlpha)));
        shadow.visible = shadowAlpha > 0;
        setSize(widthValue, heightValue);
    }

    public function setFill(color:Int):Void {
        tint(fill, color, 1);
    }

    public function setBorder(color:Int):Void {
        tint(border, color, 1);
    }

    static inline function tint(target:h2d.ScaleGrid, color:Int, alpha:Float):Void {
        target.color.setColor(0xFF000000 | color);
        target.color.a = alpha;
    }
}
