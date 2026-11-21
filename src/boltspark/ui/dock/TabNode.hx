package boltspark.ui.dock;

import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.ui.layout.LayoutRect;

/**
 * A tab group: an ordered list of panel slots, a tab bar, and one active panel.
 * Empty groups are transient (they are pruned by DockTree) but legal so a drag
 * can temporarily detach every panel.
 */
class TabNode extends DockNode {
    public static inline var TAB_MIN_WIDTH:Float = 28;
    public static inline var TAB_MAX_WIDTH:Float = 180;
    public static inline var CLOSE_SIZE:Float = 16;

    public var slots:Array<PanelSlot> = [];
    public var activeIndex:Int = 0;
    /** Configured height when this group has more than one tab. */
    public var tabBarHeight:Float = 24;
    /** Effective bar height for the current tab count (0 for a single tab). */
    public var barHeight:Float = 0;
    public var tabRects:Array<LayoutRect> = [];
    public var closeRects:Array<LayoutRect> = [];

    public function new() super();

    override public function nodeType():String return "tab";

    override public function collectTabs(out:Array<TabNode>):Void out.push(this);

    override public function countPanels():Int return slots.length;

    override public function findTab(id:String, ?key:String):Null<TabNode> {
        return indexOf(id, key) >= 0 ? this : null;
    }

    override public function findSlot(id:String, ?key:String):Null<PanelSlot> {
        var index = indexOf(id, key);
        return index < 0 ? null : slots[index];
    }

    override public function minSize():{w:Float, h:Float} {
        return {w: TAB_MIN_WIDTH, h: tabBarHeight + 40};
    }

    public function indexOf(id:String, ?key:String):Int {
        for (index in 0...slots.length) {
            if (slots[index].view.panelId != id) continue;
            if (key == null || key == "" || slots[index].instanceKey == key) return index;
        }
        return -1;
    }

    public function add(slot:PanelSlot, ?index:Int):Int {
        var at = index == null || index < 0 || index > slots.length ? slots.length : index;
        slots.insert(at, slot);
        if (activeIndex < 0 || activeIndex >= slots.length) activeIndex = at;
        return at;
    }

    public function removeAt(index:Int):Null<PanelSlot> {
        if (index < 0 || index >= slots.length) return null;
        var removed = slots.splice(index, 1)[0];
        if (activeIndex >= slots.length) activeIndex = slots.length - 1;
        if (activeIndex < 0) activeIndex = 0;
        return removed;
    }

    public function remove(id:String, ?key:String):Null<PanelSlot> {
        return removeAt(indexOf(id, key));
    }

    public function activate(id:String, ?key:String):Bool {
        var index = indexOf(id, key);
        if (index < 0) return false;
        activeIndex = index;
        return true;
    }

    public function activeSlot():Null<PanelSlot> {
        if (activeIndex < 0 || activeIndex >= slots.length) return null;
        return slots[activeIndex];
    }

    public function activeView():Null<DockPanelView> {
        var slot = activeSlot();
        return slot == null ? null : slot.view;
    }

    public function move(from:Int, to:Int):Bool {
        if (from < 0 || from >= slots.length || to < 0 || to >= slots.length
                || from == to) return false;
        var slot = slots.splice(from, 1)[0];
        var target = to > from ? to - 1 : to;
        slots.insert(target, slot);
        activeIndex = target;
        return true;
    }

    public function bodyRect():LayoutRect {
        return new LayoutRect(rect.x, rect.y + barHeight,
            rect.width, Math.max(0, rect.height - barHeight));
    }

    public function tabRect(index:Int):Null<LayoutRect> {
        return index >= 0 && index < tabRects.length ? tabRects[index] : null;
    }

    public function closeRect(index:Int):Null<LayoutRect> {
        return index >= 0 && index < closeRects.length ? closeRects[index] : null;
    }

    /** Index whose tab bar cell contains x, or -1. Used for reorder drops. */
    public function tabIndexAt(x:Float):Int {
        for (index in 0...tabRects.length) {
            if (tabRects[index].contains(x, rect.y + barHeight * 0.5)) return index;
        }
        return -1;
    }

    override public function layout(rect:LayoutRect):Void {
        super.layout(rect);
        tabRects.resize(0);
        closeRects.resize(0);
        if (activeIndex < 0) activeIndex = 0;
        if (activeIndex >= slots.length) activeIndex = Std.int(Math.max(0, slots.length - 1));
        barHeight = slots.length > 0 ? tabBarHeight : 0;
        if (slots.length == 0) return;
        var width = Math.max(0, rect.width);
        var perTab = width / slots.length;
        // Whole-pixel tab cells keep FreeType atlas glyphs crisp.
        var tabWidth = Math.round(DockNode.clamp(perTab,
            TAB_MIN_WIDTH, TAB_MAX_WIDTH));
        var originX = Math.round(rect.x);
        for (index in 0...slots.length) {
            var x = originX + index * tabWidth;
            var barY = Math.round(rect.y);
            tabRects.push(new LayoutRect(x, barY, tabWidth, barHeight));
            closeRects.push(new LayoutRect(x + tabWidth - CLOSE_SIZE - 2,
                barY + 3, CLOSE_SIZE, Math.max(6, barHeight - 6)));
        }
    }
}
