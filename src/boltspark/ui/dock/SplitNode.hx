package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.ui.layout.LayoutRect;

/**
 * A recursive split with two children, a proportional ratio, a draggable handle
 * and independent minimum sizes for both sides.
 */
class SplitNode extends DockNode {
    public static inline var HANDLE_SIZE:Float = 4;

    public var orientation:DockOrientation;
    public var ratio:Float;
    public var first:DockNode;
    public var second:DockNode;
    public var minFirst:Float;
    public var minSecond:Float;
    /** Handle rectangle in absolute coordinates, refreshed by layout(). */
    public var handleRect:LayoutRect = new LayoutRect(0, 0, 0, 0);
    /** Current size available to the two children (excluding the handle). */
    public var available(default, null):Float = 0;

    public function new(orientation:DockOrientation, first:DockNode, second:DockNode,
            ratio:Float = 0.5, minFirst:Float = 120, minSecond:Float = 120) {
        super();
        this.orientation = orientation;
        this.first = first;
        this.second = second;
        this.ratio = DockNode.clamp(ratio, 0.02, 0.98);
        this.minFirst = minFirst;
        this.minSecond = minSecond;
        first.parent = this;
        second.parent = this;
    }

    override public function nodeType():String return "split";

    public function replaceChild(oldChild:DockNode, newChild:DockNode):Bool {
        if (first == oldChild) {
            first = newChild;
            newChild.parent = this;
            return true;
        }
        if (second == oldChild) {
            second = newChild;
            newChild.parent = this;
            return true;
        }
        return false;
    }

    override public function collectTabs(out:Array<TabNode>):Void {
        first.collectTabs(out);
        second.collectTabs(out);
    }

    override public function collectNodes(out:Array<DockNode>):Void {
        super.collectNodes(out);
        first.collectNodes(out);
        second.collectNodes(out);
    }

    override public function countPanels():Int return first.countPanels() + second.countPanels();

    override public function findTab(id:String, ?key:String):Null<TabNode> {
        var hit = first.findTab(id, key);
        return hit != null ? hit : second.findTab(id, key);
    }

    override public function findSlot(id:String, ?key:String):Null<PanelSlot> {
        var hit = first.findSlot(id, key);
        return hit != null ? hit : second.findSlot(id, key);
    }

    override public function minSize():{w:Float, h:Float} {
        var a = first.minSize();
        var b = second.minSize();
        return orientation == Horizontal
            ? {w: a.w + b.w + HANDLE_SIZE, h: Math.max(a.h, b.h)}
            : {w: Math.max(a.w, b.w), h: a.h + b.h + HANDLE_SIZE};
    }

    override public function layout(rect:LayoutRect):Void {
        super.layout(rect);
        if (orientation == Horizontal) {
            available = Math.max(0, rect.width - HANDLE_SIZE);
            var firstSize = computeFirst(available, minFirst, minSecond);
            first.layout(new LayoutRect(rect.x, rect.y, firstSize, rect.height));
            handleRect = new LayoutRect(rect.x + firstSize, rect.y, HANDLE_SIZE, rect.height);
            second.layout(new LayoutRect(rect.x + firstSize + HANDLE_SIZE, rect.y,
                Math.max(0, available - firstSize), rect.height));
        } else {
            available = Math.max(0, rect.height - HANDLE_SIZE);
            var firstSize = computeFirst(available, minFirst, minSecond);
            first.layout(new LayoutRect(rect.x, rect.y, rect.width, firstSize));
            handleRect = new LayoutRect(rect.x, rect.y + firstSize, rect.width, HANDLE_SIZE);
            second.layout(new LayoutRect(rect.x, rect.y + firstSize + HANDLE_SIZE,
                rect.width, Math.max(0, available - firstSize)));
        }
    }

    function computeFirst(total:Float, minA:Float, minB:Float):Float {
        var lo = Math.min(minA, total);
        var hi = Math.max(0, total - minB);
        if (lo > hi) lo = hi;
        // Clamping is display-only: a small/minimized window must never
        // permanently rewrite the user's preferred ratio.
        return DockNode.clamp(ratio * total, lo, hi);
    }

    /** Move the handle to an absolute pointer coordinate, respecting minimums. */
    public function setRatioFromPointer(pointer:Float):Void {
        if (available <= 0) return;
        var axisStart = orientation == Horizontal ? rect.x : rect.y;
        var lo = Math.min(minFirst, available);
        var hi = Math.max(0, available - minSecond);
        if (lo > hi) lo = hi;
        var size = DockNode.clamp(pointer - axisStart, lo, hi);
        ratio = size / available;
    }

    /** Nudge the handle by a relative delta (used by keyboard/synthetic input). */
    public function dragRatio(delta:Float):Void {
        if (available <= 0) return;
        var lo = Math.min(minFirst, available);
        var hi = Math.max(0, available - minSecond);
        if (lo > hi) lo = hi;
        var size = DockNode.clamp(ratio * available + delta, lo, hi);
        ratio = size / available;
    }
}
