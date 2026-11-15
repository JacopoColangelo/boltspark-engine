package boltspark.ui.layout;

class LayoutRect {
    public final x:Float;
    public final y:Float;
    public final width:Float;
    public final height:Float;

    public function new(x:Float, y:Float, width:Float, height:Float) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    public inline function contains(px:Float, py:Float):Bool {
        return px >= x && py >= y && px <= x + width && py <= y + height;
    }

    public function inset(amount:Float):LayoutRect {
        var value = Math.max(0, amount);
        return new LayoutRect(x + value, y + value,
            Math.max(0, width - value * 2), Math.max(0, height - value * 2));
    }

    public function isValid():Bool {
        return finite(x) && finite(y) && finite(width) && finite(height)
            && width >= 0 && height >= 0;
    }

    static inline function finite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY
            && value != Math.NEGATIVE_INFINITY;
    }
}
