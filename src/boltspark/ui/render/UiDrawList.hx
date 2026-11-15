package boltspark.ui.render;

import boltspark.ui.layout.LayoutRect;

/** Allocation-stable draw-command buffer reused across chrome rebuilds. */
class UiDrawList {
    final pool:Array<UiDrawCommand> = [];
    public var count(default, null):Int = 0;

    public function new() {}

    public function reset():Void count = 0;

    public function get(index:Int):UiDrawCommand {
        if (index < 0 || index >= count) throw 'Draw command index out of range: ${index}';
        return pool[index];
    }

    public function fillRect(rect:LayoutRect, color:Int, alpha:Float = 1):Void {
        set(next(), FillRect, rect.x, rect.y, rect.width, rect.height,
            color, alpha, 0);
    }

    public function strokeRect(rect:LayoutRect, color:Int,
            thickness:Float = 1, alpha:Float = 1):Void {
        set(next(), StrokeRect, rect.x, rect.y, rect.width, rect.height,
            color, alpha, thickness);
    }

    public function line(x1:Float, y1:Float, x2:Float, y2:Float,
            color:Int, thickness:Float = 1, alpha:Float = 1):Void {
        set(next(), Line, x1, y1, x2, y2, color, alpha, thickness);
    }

    function next():UiDrawCommand {
        if (count == pool.length) pool.push(new UiDrawCommand());
        return pool[count++];
    }

    static function set(command:UiDrawCommand, kind:UiDrawCommandKind,
            x1:Float, y1:Float, x2:Float, y2:Float, color:Int,
            alpha:Float, thickness:Float):Void {
        command.kind = kind;
        command.x1 = x1;
        command.y1 = y1;
        command.x2 = x2;
        command.y2 = y2;
        command.color = color;
        command.alpha = alpha;
        command.thickness = thickness;
    }
}
