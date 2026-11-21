package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.dock.DockPanelView.PanelSlot;

/**
 * Pure structural operations on the docking tree. Every operation returns the
 * (possibly new) root, so callers always keep a single authoritative root.
 */
class DockTree {
    static inline var MIN_SPLIT_FIRST:Float = 140;
    static inline var MIN_SPLIT_SECOND:Float = 140;

    /** Replace a node in its parent. Returns the new root when node was root. */
    public static function replace(root:DockNode, node:DockNode,
            replacement:DockNode):DockNode {
        if (node == root) {
            replacement.parent = null;
            return replacement;
        }
        var parent = node.parent;
        if (parent != null) {
            if (Std.isOfType(parent, SplitNode)) {
                replacement.parent = parent;
            }
        }
        return root;
    }

    /** Drop empty tab groups and reduce splits that lost a child. */
    public static function prune(node:Null<DockNode>):Null<DockNode> {
        if (node == null) return null;
        if (Std.isOfType(node, TabNode)) {
            return cast(node, TabNode).slots.length > 0 ? node : null;
        }
        if (!Std.isOfType(node, SplitNode)) return node;
        var split = cast(node, SplitNode);
        var a = prune(split.first);
        var b = prune(split.second);
        if (a == null && b == null) return null;
        if (a == null) {
            b.parent = null;
            return b;
        }
        if (b == null) {
            a.parent = null;
            return a;
        }
        split.first = a;
        split.second = b;
        a.parent = split;
        b.parent = split;
        return split;
    }

    /** Insert a slot into a tab group, or split around it. */
    public static function add(root:Null<DockNode>, slot:PanelSlot,
            target:Null<TabNode>, side:DockSide, ?index:Int):DockNode {
        if (slot.locked) return root;
        if (root == null) {
            var only = new TabNode();
            only.add(slot);
            return only;
        }
        var destination = target;
        if (destination == null) destination = root.firstTab();
        if (destination == null) {
            var only = new TabNode();
            only.add(slot);
            return only;
        }
        var existing = destination.indexOf(slot.view.panelId, slot.instanceKey);
        if (existing >= 0) {
            // Never duplicate a view inside one group: focus the existing tab.
            destination.activeIndex = existing;
            return root;
        }
        // `index` is only an insertion position for a Center drop. Passing an
        // index from a drag must not turn a directional drop into a tab join.
        if (side == DockSide.Center) {
            // Fixed panels never accept extra tabs into their group.
            for (existing in destination.slots) {
                if (existing.locked) return root;
            }
            destination.add(slot, index);
            return root;
        }

        // Capture the old parent before creating the split: the SplitNode
        // constructor reparents `destination`, so reading parent afterwards
        // would find the new split and create a cycle.
        var oldParent = destination.parent;
        var newTab = new TabNode();
        newTab.add(slot);
        var horizontal = side == DockSide.Left || side == DockSide.Right;
        var newFirst = side == DockSide.Left || side == DockSide.Top;
        var first = newFirst ? newTab : destination;
        var second = newFirst ? destination : newTab;
        var firstMinimum = horizontal
            ? Math.max(MIN_SPLIT_FIRST, first.minSize().w)
            : Math.max(100, first.minSize().h);
        var secondMinimum = horizontal
            ? Math.max(MIN_SPLIT_SECOND, second.minSize().w)
            : Math.max(100, second.minSize().h);
        var split = new SplitNode(horizontal ? DockOrientation.Horizontal : DockOrientation.Vertical,
            first, second, 0.5, firstMinimum, secondMinimum);
        if (oldParent == null) {
            split.parent = null;
            return split;
        }
        if (Std.isOfType(oldParent, SplitNode)) {
            cast(oldParent, SplitNode).replaceChild(destination, split);
            split.parent = oldParent;
        }
        return root;
    }

    /** Detach a panel. The view instance is returned so callers can cache it. */
    public static function remove(root:Null<DockNode>, id:String,
            ?key:String):{root:Null<DockNode>, slot:Null<PanelSlot>} {
        if (root == null) return {root: null, slot: null};
        var tab = root.findTab(id, key);
        if (tab == null) return {root: root, slot: null};
        var slot = tab.remove(id, key);
        if (slot == null || slot.locked) {
            if (slot != null) tab.add(slot);
            return {root: root, slot: null};
        }
        var pruned = prune(root);
        if (pruned == null) pruned = new TabNode();
        return {root: pruned, slot: slot};
    }

    public static function move(root:Null<DockNode>, slot:PanelSlot,
            target:Null<TabNode>, side:DockSide, ?index:Int):DockNode {
        var removed = remove(root, slot.view.panelId, slot.instanceKey);
        if (removed.slot == null) return root;
        // Re-target: the previous target may have been pruned away.
        var destination = target;
        if (destination != null && removed.root != null) {
            var tabs:Array<TabNode> = [];
            removed.root.collectTabs(tabs);
            if (tabs.indexOf(destination) < 0) destination = null;
        }
        return add(removed.root, removed.slot, destination, side, index);
    }

    public static function reorder(tab:TabNode, from:Int, to:Int):Bool {
        for (slot in tab.slots) if (slot.locked) return false;
        return tab.move(from, to);
    }

    public static function collectSlots(root:Null<DockNode>):Array<PanelSlot> {
        var result:Array<PanelSlot> = [];
        if (root == null) return result;
        var tabs:Array<TabNode> = [];
        root.collectTabs(tabs);
        for (tab in tabs) {
            for (slot in tab.slots) result.push(slot);
        }
        return result;
    }

    /** True when the same view id/instance key is already in the tree. */
    public static function contains(root:Null<DockNode>, id:String, ?key:String):Bool {
        return root != null && root.findSlot(id, key) != null;
    }
}
