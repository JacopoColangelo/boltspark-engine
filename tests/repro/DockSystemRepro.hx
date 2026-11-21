import boltspark.ui.dock.DockDefaultLayout;
import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.dock.DockLayoutSerializer;
import boltspark.ui.dock.DockLayoutSerializer.DockLayoutSnapshot;
import boltspark.ui.dock.DockNode;
import boltspark.ui.dock.DockPanelView;
import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.ui.dock.DockTree;
import boltspark.ui.dock.DockZones;
import boltspark.ui.dock.FloatingDockWindow;
import boltspark.ui.dock.PanelRegistry;
import boltspark.ui.dock.SplitNode;
import boltspark.ui.dock.TabNode;
import boltspark.ui.layout.LayoutRect;

/** Headless contract tests for the recursive docking model and serializer. */
class DockSystemRepro {
    static inline var HIERARCHY:String = "boltspark.hierarchy";
    static inline var VIEWPORT:String = "boltspark.viewport";
    static inline var INSPECTOR:String = "boltspark.inspector";
    static inline var CONSOLE:String = "boltspark.console";
    static inline var ASSETS:String = "boltspark.assets";

    static function main():Void {
        var registry = makeRegistry();
        var body = new LayoutRect(0, 66, 1440, 814);

        // Registry caches instances; closing never destroys the factory.
        var first = registry.create(HIERARCHY);
        assertTrue(first == registry.create(HIERARCHY), "registry duplicated a view");
        assertTrue(registry.count() == 5, "unexpected registered panel count");

        var root = DockDefaultLayout.create(registry, body, null);
        var tabs:Array<TabNode> = [];
        root.collectTabs(tabs);
        assertTrue(tabs.length == 4, "default layout must have four tab groups");
        assertNear(root.rect.width, 1440, "root width");
        var hierarchyTab = root.findTab(HIERARCHY);
        var inspectorTab = root.findTab(INSPECTOR);
        var bottomTab = root.findTab(ASSETS);
        assertTrue(hierarchyTab != null && inspectorTab != null && bottomTab != null,
            "default layout is missing a panel");
        assertNear(hierarchyTab.rect.width, 250, "default left width");
        assertTrue(hierarchyTab.barHeight > 0, "every tab group must show a bar");
        assertTrue(bottomTab.barHeight > 0, "multi-tab group must show a bar");
        var fixedSlot = root.findSlot(VIEWPORT);
        assertTrue(fixedSlot != null && fixedSlot.locked,
            "viewport must be a fixed, always-visible panel");
        assertTrue(hierarchyTab.slots[0].locked != true,
            "ordinary panels must not be locked");
        var cannotRemove = DockTree.remove(root, VIEWPORT);
        assertTrue(cannotRemove.slot == null, "fixed viewport was removed");
        var cannotJoin = DockTree.add(root, registrySlot(registry, CONSOLE),
            root.findTab(VIEWPORT), DockSide.Center);
        assertTrue(cannotJoin.findTab(VIEWPORT).slots.length == 1,
            "a tab joined the fixed viewport group");
        assertNear(inspectorTab.rect.width, 318, "default right width");

        // Split geometry respects minimum sizes and the handle.
        var split = cast(root, SplitNode);
        split.ratio = 0.001;
        root.layout(body);
        assertTrue(split.first.rect.width >= 200, "left minimum was violated");
        split.ratio = 0.999;
        root.layout(body);
        assertTrue(split.second.rect.width > 0, "right side collapsed");
        split.setRatioFromPointer(200);
        root.layout(body);
        assertNear(split.first.rect.width, 200, "splitter pointer positioning");

        // Open -> close -> reopen never duplicates an instance.
        var reopened = registry.create(INSPECTOR);
        var removed = DockTree.remove(root, INSPECTOR);
        assertTrue(removed.slot != null, "remove did not return the slot");
        assertTrue(removed.root.findTab(INSPECTOR) == null, "panel survived removal");
        root = DockTree.add(removed.root, removed.slot, hierarchyTab, DockSide.Right);
        assertTrue(root.findTab(INSPECTOR) != null, "reopen failed");
        assertTrue(root.findTab(INSPECTOR).findSlot(INSPECTOR).view == reopened,
            "reopen created a duplicate view");
        assertTrue(registry.count() == 5, "close/reopen changed the registry");

        // Center drop joins a tab group; reorder swaps positions.
        root = DockTree.add(root, registrySlot(registry, CONSOLE),
            root.findTab(ASSETS), DockSide.Center);
        var bottom = root.findTab(ASSETS);
        assertTrue(bottom.slots.length == 2, "center drop did not create a tab group");
        assertTrue(bottom.activate(CONSOLE), "tab activation failed");
        assertTrue(DockTree.reorder(bottom, 1, 0), "tab reorder failed");
        assertTrue(bottom.slots[0].view.panelId == CONSOLE, "reorder did not move the tab");

        // A directional drop must create a split even when the drag controller
        // supplies an insertion index (regression: index forced a tab join).
        var splitRoot = DockDefaultLayout.create(makeRegistry(), body, null);
        var detached = DockTree.remove(splitRoot, CONSOLE);
        var inspectorTarget = detached.root.findTab(INSPECTOR);
        var splitResult = DockTree.add(detached.root, detached.slot,
            inspectorTarget, DockSide.Bottom, 2);
        assertTrue(splitResult.findTab(CONSOLE) != splitResult.findTab(INSPECTOR),
            "directional drop joined the tab group instead of splitting");
        assertTrue(splitResult.findTab(INSPECTOR).slots.length == 1,
            "directional drop polluted the target tab group");

        // Directional drop splits around the target.
        root = DockTree.add(root, registrySlot(registry, VIEWPORT),
            root.findTab(HIERARCHY), DockSide.Left);
        assertTrue(root.findTab(VIEWPORT) != null, "left split lost the viewport");
        assertTrue(DockTree.contains(root, VIEWPORT), "viewport missing after split");

        // Drop zones: tab bar means center, edges mean directional split.
        // Use a two-tab group so an actual bar exists (single tabs have none).
        var zoneTab = new TabNode();
        zoneTab.add(registrySlot(registry, HIERARCHY));
        zoneTab.add(registrySlot(registry, CONSOLE));
        zoneTab.layout(new LayoutRect(100, 100, 300, 400));
        checkSide(zoneTab, 250, 105, DockSide.Center, "tab bar drop must join");
        checkSide(zoneTab, 105, 300, DockSide.Left, "left edge drop");
        checkSide(zoneTab, 395, 300, DockSide.Right, "right edge drop");
        checkSide(zoneTab, 250, 300, DockSide.Center, "center drop");
        assertTrue(DockZones.isFloatingPoint(new LayoutRect(0, 0, 800, 600), -40, 300),
            "outside-editor float detection failed");
        assertTrue(!DockZones.isFloatingPoint(new LayoutRect(0, 0, 800, 600), 400, 300),
            "inside-editor point was treated as float");
        var wide = new TabNode();
        wide.add(registrySlot(registry, VIEWPORT));
        wide.layout(new LayoutRect(0, 0, 1440, 600));
        assertTrue(DockZones.sideFor(wide, 300, 300) == DockSide.Center,
            "a wide panel claimed a drop 300px from its edge");
        assertTrue(DockZones.sideFor(wide, 50, 300) == DockSide.Left,
            "a true left-edge drop was not detected");
        assertTrue(DockZones.directionalFallback(wide, 700, 500) == DockSide.Bottom,
            "fixed-panel fallback should split downward");
        assertTrue(DockZones.directionalFallback(wide, 200, 300) == DockSide.Left,
            "fixed-panel fallback should split left");

        // Serialization round trip, including active tabs and panel state.
        cast(first, FakeView).stateValue = "saved-value";
        var snapshot:DockLayoutSnapshot = {
            root: root,
            floating: [new FloatingDockWindow(7, singleTab(registry, CONSOLE),
                220, 180, 520, 360, "Floating Log")],
            closed: [],
            bottomTab: 1
        };
        var serializer = new DockLayoutSerializer();
        var json = serializer.toJson(snapshot);
        var loaded = serializer.parse(json, makeRegistry());
        assertTrue(loaded.ok, "serialized layout did not round-trip: "
            + loaded.warnings.join("; "));
        assertTrue(loaded.version == DockLayoutSerializer.VERSION, "layout version mismatch");
        assertTrue(loaded.root.findTab(VIEWPORT) != null, "viewport lost in round trip");
        assertTrue(loaded.floating.length == 1, "floating window lost in round trip");
        assertNear(loaded.floating[0].width, 520, "floating width lost");
        var restored = cast(loaded.root.findSlot(HIERARCHY).view, FakeView);
        assertTrue(restored.restoreStateCalled && restored.stateValue == "saved-value",
            "panel state was not restored");

        // Corrupted data and unknown panel ids recover gracefully.
        var corrupt = serializer.parse("{ not json", registry);
        assertTrue(!corrupt.ok && corrupt.warnings.length > 0, "corrupt layout was accepted");
        var unknown = serializer.parse('{"version":3,"root":{"kind":"tab","panels":'
            + '[{"id":"removed.panel","key":"removed.panel","state":null}],"active":0},'
            + '"floating":[]}', registry);
        assertTrue(!unknown.ok && unknown.warnings.length > 0,
            "layout with only missing panels was not rejected");
        var mixed = serializer.parse('{"version":3,"root":{"kind":"tab","panels":'
            + '[{"id":"removed.panel","key":"removed.panel","state":null},'
            + '{"id":"boltspark.hierarchy","key":"boltspark.hierarchy","state":null}],'
            + '"active":1},"floating":[]}', registry);
        assertTrue(mixed.ok && cast(mixed.root, TabNode).slots.length == 1,
            "unknown panel was not skipped cleanly");
        var legacyVersion = serializer.parse('{"version":1,"root":{"kind":"tab","panels":'
            + '[{"id":"boltspark.inspector","key":"boltspark.inspector","state":null}],'
            + '"active":0},"floating":[]}', registry);
        assertTrue(legacyVersion.ok, "version-1 layout did not migrate");

        // A minimized window must never destroy the preferred split ratio.
        var zero = new SplitNode(DockOrientation.Horizontal, new TabNode(),
            new TabNode(), 0.25, 120, 120);
        zero.layout(new LayoutRect(0, 0, 0, 0));
        assertNear(zero.ratio, 0.25, "zero-size layout changed the ratio");
        zero.layout(new LayoutRect(0, 0, 1000, 500));
        assertNear(zero.first.rect.width, 249, "ratio did not survive restore");

        // Move a panel across containers without duplicating its view.
        var moving = DockDefaultLayout.create(registry, body, null);
        var inspectorSlot = moving.findSlot(INSPECTOR);
        var assetsGroup = moving.findTab(ASSETS);
        var movedRoot = DockTree.move(moving, inspectorSlot, assetsGroup, DockSide.Center);
        assertTrue(movedRoot.findTab(INSPECTOR) == movedRoot.findTab(ASSETS),
            "cross-container move did not join the target group");
        assertTrue(movedRoot.findTab(VIEWPORT) != null,
            "moving a panel removed the fixed viewport");
        assertTrue(DockTree.contains(movedRoot, VIEWPORT),
            "fixed viewport was lost during a move");

        // Rapid open/close cycles must not leak instances or corrupt the tree.
        var churn = DockDefaultLayout.create(makeRegistry(), body, null);
        for (index in 0...30) {
            var removed = DockTree.remove(churn, CONSOLE);
            churn = DockTree.add(removed.root, removed.slot,
                churn.findTab(ASSETS), DockSide.Center);
        }
        assertTrue(DockTree.contains(churn, CONSOLE), "rapid churn lost a panel");
        assertTrue(DockTree.collectSlots(churn).length == 5,
            "rapid churn changed the panel count");

        Sys.println("[dock-system] model, drag zones, persistence and recovery passed");
    }

    static function checkSide(tab:TabNode, x:Float, y:Float,
            expected:DockSide, label:String):Void {
        var actual = DockZones.sideFor(tab, x, y);
        if (actual != expected) throw '${label}: expected ${expected}, got ${actual}';
    }

    static function registrySlot(registry:PanelRegistry, id:String):PanelSlot {
        return {view: registry.create(id), instanceKey: id};
    }

    static function singleTab(registry:PanelRegistry, id:String):TabNode {
        var tab = new TabNode();
        tab.add(registrySlot(registry, id));
        return tab;
    }

    static function makeRegistry():PanelRegistry {
        var registry = new PanelRegistry();
        register(registry, HIERARCHY, "Scene Hierarchy", 15, DockSide.Left);
        register(registry, VIEWPORT, "Scene View", 39, DockSide.Center, true);
        register(registry, INSPECTOR, "Inspector", 14, DockSide.Right);
        register(registry, CONSOLE, "Output Log", 13, DockSide.Bottom);
        register(registry, ASSETS, "Asset Browser", 24, DockSide.Bottom);
        return registry;
    }

    static function register(registry:PanelRegistry, id:String, name:String,
            icon:Int, side:DockSide, ?fixed:Bool):Void {
        registry.register({
            id: id,
            displayName: name,
            icon: icon,
            factory: function() return new FakeView(id),
            defaultSide: side,
            minWidth: 120,
            minHeight: 80,
            canClose: fixed != true,
            canFloat: fixed != true,
            canDock: fixed != true,
            fixed: fixed
        });
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }

    static function assertNear(actual:Float, expected:Float, label:String):Void {
        if (Math.abs(actual - expected) > 0.01) {
            throw '${label}: expected ${expected}, got ${actual}';
        }
    }
}

private class FakeView implements DockPanelView {
    public var panelId(default, null):String;
    public var stateValue:String = "";
    public var restoreStateCalled:Bool = false;
    public var lastRect:Null<LayoutRect> = null;

    public function new(id:String) panelId = id;

    public function layout(rect:LayoutRect):Void lastRect = rect;

    public function setVisible(visible:Bool):Void {}

    public function serializeState():Dynamic return {value: stateValue};

    public function restoreState(state:Dynamic):Void {
        restoreStateCalled = true;
        if (state != null && Reflect.isObject(state)) {
            var value = Reflect.field(state, "value");
            if (Std.isOfType(value, String)) stateValue = value;
        }
    }
}
