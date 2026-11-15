package boltspark.ui.render;

/** Mutable pooled command; callers consume only the active prefix of a list. */
class UiDrawCommand {
    public var kind:UiDrawCommandKind = FillRect;
    public var x1:Float = 0;
    public var y1:Float = 0;
    public var x2:Float = 0;
    public var y2:Float = 0;
    public var color:Int = 0;
    public var alpha:Float = 1;
    public var thickness:Float = 1;

    public function new() {}
}
