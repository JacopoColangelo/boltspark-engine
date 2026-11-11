package boltspark.ui.widgets;

/**
 * Color swatch picker: a row of small clickable color rectangles.
 *
 * Reports the selected color through onColorChanged and highlights the
 * active swatch with a bright outline.
 */
class SwatchPicker extends h2d.Object {
    public var onColorChanged:Null<Int->Void>;

    public final colors:Array<Int>;
    final swatches:Array<h2d.Graphics> = [];
    final edges:Array<h2d.Graphics> = [];
    final size:Float;
    var selectedIndex:Int = 0;

    public function new(ctx:boltspark.ui.UiContext, colors:Array<Int>, size:Float, gap:Float, ?parent:h2d.Object) {
        super(parent);
        this.colors = colors;
        this.size = size;

        for (i in 0...colors.length) {
            var color = colors[i];
            var swatch = new h2d.Graphics(this);
            swatch.beginFill(color);
            swatch.drawRect(0, 0, size, size);
            swatch.endFill();
            swatch.x = i * (size + gap);

            var hit = new h2d.Interactive(size, size, swatch);
            hit.cursor = hxd.Cursor.Button;
            hit.onClick = function(_) select(i);

            var edge = new h2d.Graphics(swatch);
            edge.lineStyle(2, boltspark.ui.Theme.SWATCH_SELECTED, 1);
            edge.drawRect(1, 1, size - 2, size - 2);
            edges.push(edge);

            swatches.push(swatch);
        }
        select(0);
    }

    /** The color currently selected. */
    public function selectedColor():Int {
        return colors[selectedIndex];
    }

    function select(index:Int):Void {
        selectedIndex = index;
        for (i in 0...edges.length) {
            edges[i].visible = i == index;
        }
        if (onColorChanged != null) onColorChanged(colors[index]);
    }
}
