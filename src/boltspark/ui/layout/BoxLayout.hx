package boltspark.ui.layout;

/** Deterministic row/column/stack geometry independent of H2D rendering. */
class BoxLayout {
    public static function row(bounds:LayoutRect, widths:Array<Float>,
            spacing:Float = 0):Array<LayoutRect> {
        return linear(bounds, widths, spacing, true);
    }

    public static function column(bounds:LayoutRect, heights:Array<Float>,
            spacing:Float = 0):Array<LayoutRect> {
        return linear(bounds, heights, spacing, false);
    }

    public static function stack(bounds:LayoutRect, count:Int,
            inset:Float = 0):Array<LayoutRect> {
        var result:Array<LayoutRect> = [];
        var inner = bounds.inset(inset);
        for (_ in 0...Std.int(Math.max(0, count))) result.push(inner);
        return result;
    }

    /**
     * Positive values are fixed logical pixels. Zero/negative entries share
     * the remaining extent equally, making resize behavior deterministic.
     */
    static function linear(bounds:LayoutRect, sizes:Array<Float>, spacing:Float,
            horizontal:Bool):Array<LayoutRect> {
        var result:Array<LayoutRect> = [];
        if (sizes.length == 0) return result;
        spacing = Math.max(0, spacing);
        var available = Math.max(0,
            (horizontal ? bounds.width : bounds.height) - spacing * (sizes.length - 1));
        var fixed = 0.0;
        var flexible = 0;
        for (size in sizes) {
            if (size > 0) fixed += size; else flexible++;
        }
        var flexibleSize = flexible == 0 ? 0 : Math.max(0, available - fixed) / flexible;
        var cursor = horizontal ? bounds.x : bounds.y;
        for (size in sizes) {
            var extent = Math.max(0, size > 0 ? size : flexibleSize);
            result.push(horizontal
                ? new LayoutRect(cursor, bounds.y, extent, bounds.height)
                : new LayoutRect(bounds.x, cursor, bounds.width, extent));
            cursor += extent + spacing;
        }
        return result;
    }
}
