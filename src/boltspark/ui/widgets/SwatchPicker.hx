package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;

/** Compact anti-aliased material color swatches. */
class SwatchPicker extends h2d.Object {
    public var onColorChanged:Null<Int->Void>;

    public final colors:Array<Int>;
    final swatches:Array<UiSurface> = [];
    final hovered:Array<Bool> = [];
    final size:Float;
    final gap:Float;
    var selectedIndex:Int = 0;

    public function new(ctx:UiContext, colors:Array<Int>, size:Float, gap:Float,
            ?parent:h2d.Object) {
        super(parent);
        this.colors = colors;
        this.size = size;
        this.gap = gap;

        for (i in 0...colors.length) {
            var swatch = new UiSurface(ctx, this);
            swatch.setSize(size, size);
            swatch.x = i * (size + gap);
            swatches.push(swatch);
            hovered.push(false);

            var hit = new h2d.Interactive(size, size, swatch);
            hit.cursor = hxd.Cursor.Button;
            hit.backgroundColor = 0;
            hit.onOver = function(_) {
                hovered[i] = true;
                redraw(i);
            };
            hit.onOut = function(_) {
                hovered[i] = false;
                redraw(i);
            };
            hit.onClick = function(_) select(i);
        }
        select(0, false);
    }

    public inline function selectedColor():Int return colors[selectedIndex];

    /** Full row width including gaps; used by right-aligned owners. */
    public function totalWidth():Float {
        return colors.length * size + Math.max(0, colors.length - 1) * gap;
    }

    public function setColor(color:Int):Void {
        var index = colors.indexOf(color);
        if (index >= 0) select(index, false);
    }

    function select(index:Int, notify:Bool = true):Void {
        selectedIndex = index;
        for (i in 0...swatches.length) redraw(i);
        if (notify && onColorChanged != null) onColorChanged(colors[index]);
    }

    function redraw(index:Int):Void {
        var active = index == selectedIndex;
        swatches[index].setStyle(colors[index],
            active ? Theme.SWATCH_SELECTED : (hovered[index] ? Theme.TEXT_SECONDARY : Theme.SWATCH_EDGE),
            active ? 0.20 : 0,
            active ? 2 : 1);
    }
}
