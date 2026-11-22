package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.layout.LayoutRect;

/**
 * Pure-data floating container. It owns an independent docking tree and its
 * own geometry; the renderer/host turns this into a native H2D overlay window.
 */
class FloatingDockWindow {
    public var id:Int;
    public var title:String;
    public var root:DockNode;
    public var x:Float;
    public var y:Float;
    public var width:Float;
    public var height:Float;
    public var minimized:Bool = false;
    /** Set when this proxy is hosted in a real native child-process window. */
    public var nativeKey:String = "";
    public var maximized:Bool = false;
    public var restoreRect:Null<LayoutRect> = null;
    /** Where the panel lived before floating, so closing can restore it. */
    public var originTab:Null<TabNode> = null;
    public var originIndex:Int = -1;
    public var originNeighbor:Null<TabNode> = null;
    public var originSide:DockSide = DockSide.Center;
    public var native(get, never):Bool;
    inline function get_native():Bool return nativeKey != "";

    public function new(id:Int, root:DockNode, x:Float, y:Float,
            width:Float, height:Float, ?title:String) {
        this.id = id;
        this.root = root;
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        this.title = title == null ? "Floating Panel" : title;
        root.parent = null;
    }

    public function layout():Void {
        if (minimized) return;
        // The frame owns a 24px title bar; the docking tree fills the body.
        root.layout(new boltspark.ui.layout.LayoutRect(x, y + 24, width,
            Math.max(0, height - 24)));
    }

    public function contains(px:Float, py:Float):Bool {
        return px >= x && py >= y && px <= x + width && py <= y + height;
    }
}
