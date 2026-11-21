package boltspark.ui.dock;

import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.ui.layout.LayoutRect;

/**
 * Base of the recursive docking tree. Pure data: no H2D objects, no input, no
 * rendering. A node owns a computed rectangle and delegates geometry to its
 * concrete subtype.
 */
class DockNode {
    public var parent:Null<DockNode> = null;
    /** Last computed absolute rectangle (window coordinates for the root). */
    public var rect:LayoutRect = new LayoutRect(0, 0, 0, 0);

    public function new() {}

    public function nodeType():String return "node";

    public function layout(rect:LayoutRect):Void {
        this.rect = rect;
    }

    /** Depth-first collection of every tab group below this node. */
    public function collectTabs(out:Array<TabNode>):Void {}

    public function collectNodes(out:Array<DockNode>):Void {
        out.push(this);
    }

    public function countPanels():Int return 0;

    public function findTab(id:String, ?key:String):Null<TabNode> return null;

    public function findSlot(id:String, ?key:String):Null<PanelSlot> return null;

    public function firstTab():Null<TabNode> {
        var tabs:Array<TabNode> = [];
        collectTabs(tabs);
        return tabs.length == 0 ? null : tabs[0];
    }

    /** Minimum space this subtree needs along each axis. */
    public function minSize():{w:Float, h:Float} return {w: 0, h: 0};

    public function contains(px:Float, py:Float):Bool return rect.contains(px, py);

    public static function clamp(value:Float, min:Float, max:Float):Float {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}
