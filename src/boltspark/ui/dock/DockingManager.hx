package boltspark.ui.dock;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.InputAdapter;
import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.dock.DockLayoutRenderer.DockPreview;
import boltspark.ui.dock.DockLayoutSerializer.DockLayoutSnapshot;
import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.platform.NativeWindow;
import boltspark.platform.FloatWindowManager;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayout.DockLayoutGeometry;
import boltspark.ui.layout.LayoutRect;

/**
 * Central docking coordinator. Owns the main recursive tree, floating windows,
 * the panel registry, rendering, drag/drop and persistence, while the panels
 * themselves stay completely unaware of docking.
 */
class DockingManager {
    public final registry:PanelRegistry;
    public final renderer:DockLayoutRenderer;
    public final drag:DockDragController;

    /** Fired when the active bottom tab changes (keeps legacy layout state in sync). */
    public var onBottomTabChanged:Null<Int->Void>;
    /** Fired after any structural layout change so the Window menu can refresh. */
    public var onLayoutChanged:Null<Void->Void>;
    /** Fired whenever rectangles change so the host can redraw shared chrome. */
    public var onGeometryChanged:Null<Void->Void>;
    /** Build a JSON snapshot for a floating panel hosted in a native window. */
    public var onSnapshotRequest:Null<String->Dynamic>;
    /** Apply an edit reported by a native panel host. */
    public var onDockPanelEdit:Null<String->String->Dynamic->Void>;
    /** Fired before writing, so hosts can mirror live sizes into legacy state. */
    public var onBeforeSave:Null<Void->Void>;
    /** Fired whenever the dock layout was written, to mirror legacy layout.json. */
    public var onLayoutSaved:Null<Void->Void>;
    /** Fired after reset-to-default so hosts can reset legacy preferences. */
    public var onLayoutReset:Null<Void->Void>;

    final ctx:UiContext;
    final serializer:DockLayoutSerializer;
    final panelLayer:h2d.Object;
    /** Floating panel content: above main dock chrome, below float frames. */
    final floatPanelLayer:h2d.Object;

    var root:Null<DockNode> = null;
    var floating:Array<FloatingDockWindow> = [];
    var body:LayoutRect = new LayoutRect(0, 0, 0, 0);
    var nextFloatId:Int = 1;
    var focusedPanelId:String = "";
    var startupWarnings:Array<String> = [];

    final dockWindows:FloatWindowManager;

    public function new(ctx:UiContext, input:InputAdapter, registry:PanelRegistry,
            panelLayer:h2d.Object, floatPanelLayer:h2d.Object,
            chromeLayer:h2d.Object, floatLayer:h2d.Object,
            overlayLayer:h2d.Object, dockWindows:FloatWindowManager) {
        this.ctx = ctx;
        this.dockWindows = dockWindows;
        this.registry = registry;
        this.panelLayer = panelLayer;
        this.floatPanelLayer = floatPanelLayer;
        serializer = new DockLayoutSerializer();
        renderer = new DockLayoutRenderer(ctx, registry, chromeLayer, floatLayer, overlayLayer);
        renderer.onTabPush = function(tab, index, x, y) {
            tab.activeIndex = index;
            var active = tab.activeSlot();
            if (active != null) focusedPanelId = active.view.panelId;
            onTabActivated();
            renderer.draw();
            drag.begin(tab, index, x, y);
        };
        renderer.onTabClose = function(tab, index) {
            var slot = tab.slots[index];
            if (slot != null) close(slot.view.panelId, slot.instanceKey);
        };
        renderer.onSplitDrag = function(split, pointer) {
            split.setRatioFromPointer(pointer);
            applyLayout();
        };
        renderer.onSplitDragEnd = function() {
            applyLayout();
            save();
        };
        renderer.onFloatChanged = function() {
            applyLayout();
            save();
        };
        renderer.onFloatDockRequest = function(window) dockWindowIntoEditor(window);
        renderer.onFloatClose = function(window) closeFloat(window);
        drag = new DockDragController(this, ctx, overlayLayer);
        // Floats re-read the live snapshot through the same callback the docked
        // panels use, so native windows never depend on a stale pushed copy.
        dockWindows.onSnapshotRequest = function(panelId:String):Dynamic {
            return onSnapshotRequest != null ? onSnapshotRequest(panelId) : null;
        };
        dockWindows.onHeaderDrag = handleFloatHeaderDrag;
    }

    /** Screen-space header drag: show a dock preview, then dock on release. */
    function handleFloatHeaderDrag(key:String, phase:Int,
            screenX:Int, screenY:Int):Void {
        var window:Null<FloatingDockWindow> = null;
        for (candidate in floating) {
            if (candidate.nativeKey == key) {
                window = candidate;
                break;
            }
        }
        if (window == null) return;
        if (phase == 0) return;
        var origin = NativeWindow.clientOrigin(ctx.window);
        var x = screenX - origin.x;
        var y = screenY - origin.y;
        var inside = x >= 0 && y >= 0 && x <= ctx.width && y <= ctx.height;
        var plan = null;
        if (inside) {
            var first = window.root.firstTab();
            var slot = first == null ? null : first.activeSlot();
            if (slot != null) plan = resolveDrop(slot, x, y, null);
        }
        if (phase == 1) {
            renderer.setPreview(plan == null ? null : plan.preview);
            return;
        }
        renderer.setPreview(null);
        if (plan != null && plan.target != null) {
            dockWindowIntoEditor(window, plan.target, plan.side);
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    public function initialize(legacy:DockLayout):Void {
        body = editorBody();
        var loaded = serializer.load(registry);
        if (loaded.ok && loaded.root != null) {
            root = loaded.root;
            floating = loaded.floating;
            startupWarnings = loaded.warnings;
        } else {
            root = DockDefaultLayout.create(registry, body, legacy);
            floating = [];
            startupWarnings = loaded.warnings;
        }
        for (window in floating) {
            if (window.id >= nextFloatId) nextFloatId = window.id + 1;
        }
        // A persisted float must become a real HWND before the first draw,
        // otherwise it would linger as an in-app ghost rectangle.
        if (useNativeFloats()) {
            for (window in floating) hostNativeFloat(window);
        }
        rebuild();
        // Create the file on first launch / after recovery so later changes
        // always have a valid baseline to overwrite.
        save();
    }

    public function startupMessage():String {
        if (startupWarnings.length == 0) return "";
        return startupWarnings.join(" ");
    }

    public function layout(rect:LayoutRect):Void {
        body = rect;
        applyLayout();
    }

    function editorBody():LayoutRect {
        return new LayoutRect(0, Theme.TOP_BAR_HEIGHT, ctx.width,
            Math.max(0, ctx.height - Theme.TOP_BAR_HEIGHT - Theme.STATUS_BAR_HEIGHT));
    }

    // ------------------------------------------------------------------
    // Public API: open / close / focus / move / float / dock / reorder
    // ------------------------------------------------------------------

    public function open(id:String, ?side:DockSide, ?target:TabNode):Bool {
        if (!registry.has(id)) return false;
        if (isOpen(id)) {
            focus(id);
            return true;
        }
        var slot = registry.slot(id);
        var descriptor = registry.descriptor(id);
        var direction = side != null ? side
            : (descriptor.defaultSide == null ? DockSide.Center : descriptor.defaultSide);
        var destination = target != null ? target : root.firstTab();
        root = DockTree.add(root, slot, destination, direction);
        rebuild();
        focus(id);
        return true;
    }

    public function close(id:String, ?key:String):Bool {
        if (registry.flag(id, "fixed", false)) return false;
        var found = removeSlotFromAll(id, key);
        if (!found) return false;
        rebuild();
        save();
        return true;
    }

    public function isOpen(id:String, ?key:String):Bool {
        return root != null && root.findTab(id, key) != null
            || anyFloatContains(id, key);
    }

    public function focus(id:String, ?key:String):Bool {
        var tab = findTab(id, key);
        if (tab == null) return false;
        if (!tab.activate(id, key)) return false;
        focusedPanelId = id;
        onTabActivated();
        bringToFront(tab);
        renderer.draw();
        syncViews();
        return true;
    }

    public function reorder(tab:TabNode, from:Int, to:Int):Bool {
        if (!DockTree.reorder(tab, from, to)) return false;
        renderer.rebuild(root, floating);
        syncViews();
        save();
        return true;
    }

    /** Move one panel slot into another tab group or split around it. */
    public function moveSlot(slot:PanelSlot, target:TabNode, side:DockSide,
            ?index:Int):Void {
        if (slot == null || target == null) return;
        if (slot.locked || !registry.flag(slot.view.panelId, "dock", true)) return;
        var owner = rootForTab(target);
        if (owner == null) return;
        removeSlotFromAll(slot.view.panelId, slot.instanceKey);
        var replacement = resolveTargetAfterRemoval(owner, target);
        if (owner == root) {
            root = DockTree.add(root, slot, replacement, side, index);
        } else {
            var window = windowForRoot(owner);
            if (window == null) return;
            window.root = DockTree.add(window.root, slot, replacement, side, index);
        }
        rebuild();
        save();
    }

    /** Undock one panel into a new floating container. */
    public function floatSlot(slot:PanelSlot, rect:LayoutRect):Void {
        if (slot == null || slot.locked) return;
        if (!registry.flag(slot.view.panelId, "float", true)) return;
        // Remember where this panel came from so closing/docking the float can
        // put it back in the same tab group and slot order.
        var sourceTab = findTab(slot.view.panelId, slot.instanceKey);
        var originIndex = sourceTab == null ? -1 : sourceTab.slots.indexOf(slot);
        var tabs:Array<TabNode> = [];
        if (root != null) root.collectTabs(tabs);
        var neighbor:Null<TabNode> = null;
        var side:DockSide = DockSide.Right;
        if (sourceTab != null) {
            var index = tabs.indexOf(sourceTab);
            if (index > 0) neighbor = tabs[index - 1]
            else if (index >= 0 && index + 1 < tabs.length) neighbor = tabs[index + 1];
            if (neighbor != null) {
                side = neighbor.rect.x < sourceTab.rect.x ? DockSide.Right
                    : (neighbor.rect.y < sourceTab.rect.y ? DockSide.Bottom
                    : (neighbor.rect.x > sourceTab.rect.x ? DockSide.Left : DockSide.Top));
            }
        }
        removeSlotFromAll(slot.view.panelId, slot.instanceKey);
        var tab = new TabNode();
        tab.add(slot);
        var descriptor = registry.descriptor(slot.view.panelId);
        var title = descriptor == null ? slot.view.panelId : descriptor.displayName;
        var geometry = DockZones.clampFloating(body, rect.x, rect.y, rect.width, rect.height);
        var window = new FloatingDockWindow(nextFloatId++, tab, geometry.x, geometry.y,
            geometry.width, geometry.height, title);
        window.originTab = sourceTab;
        window.originIndex = originIndex;
        window.originNeighbor = neighbor;
        window.originSide = side;
        floating.push(window);
        // Raw-Win32 floats are the default. If the native module cannot create
        // the HWND, cancel the float and put the slot back instead of leaving
        // an in-app ghost behind. BOLTSPARK_INAPP_DOCK_FLOATS=1 restores the
        // original in-app floating window explicitly.
        if (useNativeFloats() && !hostNativeFloat(window)) {
            floating.remove(window);
            var destination = root.firstTab();
            root = DockTree.add(root, slot, destination, DockSide.Center);
            if (root.findTab(slot.view.panelId, slot.instanceKey) == null) {
                root = DockTree.add(root, slot, destination, DockSide.Right);
            }
            rebuild();
            save();
            return;
        }
        rebuild();
        bringToFront(tab);
        save();
        log('floated ${slot.view.panelId} at ${Math.round(geometry.x)},'
            + '${Math.round(geometry.y)}');
    }

    static inline function useNativeFloats():Bool {
        return Sys.getEnv("BOLTSPARK_INAPP_DOCK_FLOATS") != "1";
    }

    /** Host a floating container in its own raw-Win32 HWND. */
    function hostNativeFloat(window:FloatingDockWindow):Bool {
        if (window.nativeKey != "") return true;
        var first = window.root.firstTab();
        var slot = first == null ? null : first.activeSlot();
        if (slot == null) return false;
        var key = "dock:" + slot.view.panelId + ":" + window.id;
        var screen = nativeGeometry(window);
        var error = dockWindows.openDockPanel(key, slot.view.panelId,
            window.title, screen.x, screen.y, screen.w, screen.h);
        if (error != null) {
            log(error);
            return false;
        }
        window.nativeKey = key;
        rememberNativeGeometry(key, screen);
        // Host the real H2D view in the float so it keeps the same widgets,
        // theme and live state as the docked panel.
        dockWindows.bindView(key, slot.view, hostFor(slot.view),
            slot.view.panelId, window.title);
        pushSnapshot(window);
        return true;
    }

    /** Dock an entire floating window back into the editor. */
    public function dockWindowIntoEditor(window:FloatingDockWindow,
            ?target:TabNode, ?side:DockSide):Void {
        var slots = DockTree.collectSlots(window.root);
        if (slots.length == 0) {
            closeFloat(window);
            return;
        }
        var direction = side == null ? DockSide.Center : side;
        var destination = target != null && root != null
            && containsTab(root, target) ? target : root.firstTab();
        var restoreTab = target == null && root != null && window.originTab != null
            && containsTab(root, window.originTab) ? window.originTab : null;
        floating.remove(window);
        if (window.nativeKey != "") {
            dockWindows.closeDockPanel(window.nativeKey);
            nativeGeometrySent.remove(window.nativeKey);
            window.nativeKey = "";
        }
        for (slot in slots) {
            if (restoreTab != null) {
                root = DockTree.add(root, slot, restoreTab, DockSide.Center,
                    window.originIndex);
                if (root.findTab(slot.view.panelId, slot.instanceKey) == null
                        && window.originNeighbor != null
                        && containsTab(root, window.originNeighbor)) {
                    root = DockTree.add(root, slot, window.originNeighbor,
                        window.originSide, window.originIndex);
                }
            } else {
                root = DockTree.add(root, slot, destination, direction);
                if (root.findTab(slot.view.panelId, slot.instanceKey) == null
                        && direction == DockSide.Center) {
                    // A Center add is refused when the destination group holds a
                    // fixed panel (e.g. the viewport). Split around it instead of
                    // silently dropping the re-docked panel.
                    root = DockTree.add(root, slot, destination, DockSide.Right);
                }
            }
            destination = root.findTab(slot.view.panelId, slot.instanceKey);
            direction = DockSide.Center;
            // Re-host the view in the editor's panel layer and make it visible
            // again; syncViews() below handles the normal case as well.
            var host = hostFor(slot.view);
            if (host != null && host.parent != panelLayer) panelLayer.addChild(host);
            slot.view.setVisible(true);
        }
        rebuild();
        save();
        log('docked floating window into editor');
    }

    /** Float the panel last focused (used by the Window menu). */
    public function floatFocused():Bool {
        if (focusedPanelId == "" || !isOpen(focusedPanelId)) {
            log('float focused: no active panel (${focusedPanelId})');
            return false;
        }
        var slot = findSlotAnywhere(focusedPanelId);
        if (slot == null || slot.locked) return false;
        var rect = new LayoutRect(
            body.x + Math.max(0, (body.width - 520) * 0.5),
            body.y + Math.max(0, (body.height - 360) * 0.5), 520, 360);
        floatSlot(slot, rect);
        return true;
    }

    /** Dock every floating container back into the main editor. */
    public function dockAllFloating():Void {
        for (window in floating.copy()) dockWindowIntoEditor(window);
    }

    function findSlotAnywhere(id:String):Null<PanelSlot> {
        if (root != null) {
            var hit = root.findSlot(id);
            if (hit != null) return hit;
        }
        for (window in floating) {
            var hit = window.root.findSlot(id);
            if (hit != null) return hit;
        }
        return null;
    }

    public function closeFloat(window:FloatingDockWindow):Void {
        var index = floating.indexOf(window);
        if (index < 0) return;
        if (window.nativeKey != "") {
            dockWindows.closeDockPanel(window.nativeKey);
            nativeGeometrySent.remove(window.nativeKey);
        }
        floating.splice(index, 1);
        rebuild();
        save();
    }

    public function reset():Void {
        var error = serializer.delete();
        if (error != null) log("layout: " + error);
        root = DockDefaultLayout.create(registry, body, new DockLayout());
        floating = [];
        nextFloatId = 1;
        if (onLayoutReset != null) onLayoutReset();
        rebuild();
        save();
    }

    public function save():Void {
        if (onBeforeSave != null) onBeforeSave();
        var snapshot:DockLayoutSnapshot = {
            root: root,
            floating: floating,
            closed: closedPanelIds(),
            bottomTab: bottomTabIndex()
        };
        var error = serializer.save(snapshot);
        if (error != null) log("layout: " + error);
        syncLegacy();
        if (onLayoutSaved != null) onLayoutSaved();
        if (onLayoutChanged != null) onLayoutChanged();
    }

    /** Reload the saved layout from disk, falling back to the default. */
    public function reload():Void {
        initialize(body.width > 0 ? legacyFromCurrent() : new DockLayout());
    }

    function legacyFromCurrent():DockLayout {
        var result = new DockLayout();
        var sizes = legacySizes();
        result.setPreferred(sizes.left, sizes.right, sizes.console);
        result.bottomTab = sizes.bottomTab;
        return result;
    }

    /** Live panel rectangles expressed in the legacy geometry shape. */
    public function geometry():DockLayoutGeometry {
        var empty = new LayoutRect(0, body.y, 0, 0);
        var hierarchy = root == null ? null : root.findTab("boltspark.hierarchy");
        var inspector = root == null ? null : root.findTab("boltspark.inspector");
        var bottom = root == null ? null : root.findTab("boltspark.assets");
        var viewport = root == null ? null : root.findTab("boltspark.viewport");
        var handles:Array<SplitNode> = [];
        if (root != null) {
            var nodes:Array<DockNode> = [];
            root.collectNodes(nodes);
            for (node in nodes) {
                if (Std.isOfType(node, SplitNode)) handles.push(cast(node, SplitNode));
            }
        }
        function findHandle(orientation:DockOrientation, nearX:Float, nearY:Float):LayoutRect {
            for (split in handles) {
                if (split.orientation != orientation) continue;
                if (Math.abs(split.handleRect.x - nearX) <= 8
                        && Math.abs(split.handleRect.y - nearY) <= 8) {
                    return split.handleRect;
                }
            }
            return empty;
        }
        function snap(rect:LayoutRect):LayoutRect {
            return new LayoutRect(Math.round(rect.x), Math.round(rect.y),
                Math.round(rect.width), Math.round(rect.height));
        }
        var leftRect = snap(hierarchy == null ? empty : hierarchy.rect);
        var rightRect = snap(inspector == null ? empty : inspector.rect);
        var bottomRect = snap(bottom == null ? empty : bottom.rect);
        return {
            leftPanel: leftRect,
            leftSplitter: findHandle(DockOrientation.Horizontal,
                leftRect.x + leftRect.width, leftRect.y),
            viewport: snap(viewport == null ? empty : viewport.rect),
            consoleSplitter: findHandle(DockOrientation.Vertical,
                bottomRect.x, bottomRect.y - 4),
            console: bottomRect,
            rightSplitter: findHandle(DockOrientation.Horizontal,
                rightRect.x - 4, rightRect.y),
            rightPanel: rightRect
        };
    }

    /**
     * Whole-pixel backgrounds for every dock group except the viewport, whose
     * 3D pass provides its own. Keeps shared chrome aligned with the live tree.
     */
    public function panelBackgroundRects():Array<LayoutRect> {
        var result:Array<LayoutRect> = [];
        // A native float owns its pixels. Painting a background rect for its
        // docking tab in the editor chrome would leave a ghost rectangle in
        // the main window behind the real HWND.
        var nativeTabs:Map<TabNode, Bool> = new Map();
        for (window in floating) {
            if (!window.native) continue;
            var tabs:Array<TabNode> = [];
            window.root.collectTabs(tabs);
            for (tab in tabs) nativeTabs.set(tab, true);
        }
        for (tab in allTabs()) {
            if (nativeTabs.exists(tab)) continue;
            var slot = tab.activeSlot();
            if (slot != null && slot.view.panelId == "boltspark.viewport") continue;
            var r = tab.rect;
            result.push(new LayoutRect(Math.round(r.x), Math.round(r.y),
                Math.round(r.width), Math.round(r.height)));
        }
        return result;
    }

    /** Absolute body rectangle of the 3D viewport tab. */
    public function viewportBody():LayoutRect {
        var viewport = root == null ? null : root.findTab("boltspark.viewport");
        return viewport == null
            ? new LayoutRect(0, body.y, body.width, body.height)
            : viewport.rect;
    }

    public function isDragActive():Bool return drag.isActive;

    public function cancelDrag():Void drag.cancel();

    // ------------------------------------------------------------------
    // Drag target resolution
    // ------------------------------------------------------------------

    public function resolveDrop(slot:PanelSlot, x:Float, y:Float,
            sourceTab:Null<TabNode>):Null<DockDropPlan> {
        var candidates = allTabs();
        for (tab in candidates) {
            var r = tab.rect;
            if (!r.contains(x, y)) continue;
            if (r.width <= 0 || r.height <= 0) continue;
            var side = DockZones.sideFor(tab, x, y);
            // A fixed viewport can never accept a tab; force a directional
            // split so a drop in its middle still docks around it.
            for (existing in tab.slots) {
                if (existing.locked && side == DockSide.Center) {
                    side = DockZones.directionalFallback(tab, x, y);
                }
            }
            var index = side == DockSide.Center && y <= r.y + tab.barHeight
                ? tab.tabIndexAt(x) : tab.slots.length;
            if (index < 0) index = tab.slots.length;
            var preview = previewRect(tab, side);
            return {target: tab, side: side, index: index,
                floating: false, preview: preview};
        }
        if (DockZones.isFloatingPoint(body, x, y)) {
            var geometry = DockZones.clampFloating(body, x - 240, y - 160, 480, 320);
            return {
                target: null,
                side: DockSide.Center,
                index: 0,
                floating: true,
                preview: {rect: geometry, side: DockSide.Center, label: "Float"}
            };
        }
        return null;
    }

    function previewRect(tab:TabNode, side:DockSide):DockPreview {
        var r = tab.rect;
        var rect = switch (side) {
            case Left: new LayoutRect(r.x, r.y, r.width * 0.4, r.height);
            case Right: new LayoutRect(r.x + r.width * 0.6, r.y, r.width * 0.4, r.height);
            case Top: new LayoutRect(r.x, r.y, r.width, r.height * 0.4);
            case Bottom: new LayoutRect(r.x, r.y + r.height * 0.6,
                r.width, r.height * 0.4);
            case Center: tab.bodyRect();
        };
        var descriptor = registry.descriptor(tab.slots[0] == null
            ? "" : tab.slots[0].view.panelId);
        return {rect: rect, side: side,
            label: descriptor == null ? "" : descriptor.displayName};
    }

    // ------------------------------------------------------------------
    // Tree/view synchronization
    // ------------------------------------------------------------------

    function rebuild():Void {
        for (graphic in floatBackgrounds) graphic.remove();
        floatBackgrounds.clear();
        for (window in floating) {
            // Native floats own their pixels; an in-app frame would be a ghost.
            if (window.native) continue;
            floatBackgrounds.set(window.id, new h2d.Graphics(floatPanelLayer));
        }
        // Refresh rectangles first: the renderer builds one hit target per
        // tab and draws using tabRects, which both must match the new tree.
        if (root != null) root.layout(body);
        for (window in floating) window.layout();
        renderer.rebuild(root, floating);
        applyLayout();
    }

    function applyLayout():Void {
        renderer.body = body;
        if (root != null) root.layout(body);
        for (window in floating) {
            DockZones.clampFloating(body, window.x, window.y, window.width, window.height);
            window.layout();
            if (window.nativeKey != "") {
                var screen = nativeGeometry(window);
                var signature = '${screen.x},${screen.y},${screen.w},${screen.h}';
                if (nativeGeometrySent.get(window.nativeKey) != signature) {
                    rememberNativeGeometry(window.nativeKey, screen);
                    dockWindows.sendGeometry(window.nativeKey,
                        screen.x, screen.y, screen.w, screen.h);
                }
            }
        }
        drawFloatBackgrounds();
        syncViews();
        renderer.draw();
        syncLegacy();
        if (onGeometryChanged != null) onGeometryChanged();
    }

    function drawFloatBackgrounds():Void {
        for (window in floating) {
            if (window.native) continue;
            var graphic = floatBackgrounds.get(window.id);
            if (graphic == null) continue;
            graphic.clear();
            if (window.minimized) continue;
            graphic.beginFill(Theme.PANEL, 1);
            graphic.drawRect(Math.round(window.x), Math.round(window.y) + 24,
                Math.round(window.width), Math.max(0, Math.round(window.height) - 24));
            graphic.endFill();
        }
    }

    function syncViews():Void {
        var active = new Map<DockPanelView, Bool>();
        for (tab in allTabs()) {
            var slot = tab.activeSlot();
            if (slot == null) continue;
            var inNative = isTabInNativeFloat(tab);
            // A native float renders this view offscreen into its own HWND, so
            // keep it visible; only skip the main-editor layout/reparent path.
            active.set(slot.view, true);
            slot.view.setVisible(true);
            if (inNative) continue;
            // A floating panel's native content must sit above the main dock
            // chrome (tab bars / backgrounds), otherwise overlapping docked
            // panels draw over it. Reparent only when the layer changes.
            var host = hostFor(slot.view);
            if (host != null) {
                var layer = isTabFloating(tab) ? floatPanelLayer : panelLayer;
                if (host.parent != layer) layer.addChild(host);
            }
            // Hierarchy/Inspector/Viewport already reserve their own header
            // space inside the content. The tab bar overlays that (now
            // label-free) strip, so the full rect keeps fields at stable
            // coordinates while other panels use the bar-free body rect.
            var rect = switch (slot.view.panelId) {
                case "boltspark.hierarchy", "boltspark.inspector",
                    "boltspark.viewport": tab.rect;
                default: tab.bodyRect();
            };
            slot.view.layout(rect);
        }
        for (id in registry.ids()) {
            var view = registry.peek(id);
            if (view != null && !active.exists(view)) view.setVisible(false);
        }
    }

    function bringToFront(tab:TabNode):Void {
        var slot = tab.activeSlot();
        if (slot == null || isTabInNativeFloat(tab)) return;
        var host = hostFor(slot.view);
        if (host == null) return;
        var layer = isTabFloating(tab) ? floatPanelLayer : panelLayer;
        layer.addChild(host);
    }

    function isTabInNativeFloat(tab:TabNode):Bool {
        for (window in floating) {
            if (window.native && containsTab(window.root, tab)) return true;
        }
        return false;
    }

    function isTabFloating(tab:TabNode):Bool {
        for (window in floating) {
            if (containsTab(window.root, tab)) return true;
        }
        return false;
    }

    // Host objects are registered by EditorShell so the manager can raise a
    // focused/floating panel without reparenting it outside the panel layer.
    final hosts:Map<DockPanelView, h2d.Object> = [];
    /** Hosts registered by panel id before the serializer creates the views. */
    final hostById:Map<String, h2d.Object> = [];
    final floatBackgrounds:Map<Int, h2d.Graphics> = [];
    final nativeGeometrySent:Map<String, String> = [];

    public function bindHost(view:DockPanelView, host:h2d.Object):Void {
        hosts.set(view, host);
    }

    public function bindHostId(id:String, host:h2d.Object):Void {
        hostById.set(id, host);
        var view = registry.peek(id);
        if (view != null) bindHost(view, host);
    }

    function hostFor(view:DockPanelView):Null<h2d.Object> {
        var host = hosts.get(view);
        return host != null ? host : hostById.get(view.panelId);
    }

    // ------------------------------------------------------------------
    // Tree lookup helpers
    // ------------------------------------------------------------------

    function allTabs():Array<TabNode> {
        var tabs:Array<TabNode> = [];
        if (root != null) root.collectTabs(tabs);
        for (window in floating) window.root.collectTabs(tabs);
        return tabs;
    }

    function findTab(id:String, ?key:String):Null<TabNode> {
        if (root != null) {
            var hit = root.findTab(id, key);
            if (hit != null) return hit;
        }
        for (window in floating) {
            var hit = window.root.findTab(id, key);
            if (hit != null) return hit;
        }
        return null;
    }

    function anyFloatContains(id:String, ?key:String):Bool {
        for (window in floating) {
            if (window.root.findTab(id, key) != null) return true;
        }
        return false;
    }

    function rootForTab(tab:TabNode):Null<DockNode> {
        if (root != null && containsTab(root, tab)) return root;
        for (window in floating) {
            if (containsTab(window.root, tab)) return window.root;
        }
        return null;
    }

    function windowForRoot(candidate:DockNode):Null<FloatingDockWindow> {
        for (window in floating) {
            if (window.root == candidate) return window;
        }
        return null;
    }

    static function containsTab(node:DockNode, tab:TabNode):Bool {
        var tabs:Array<TabNode> = [];
        node.collectTabs(tabs);
        return tabs.indexOf(tab) >= 0;
    }

    function resolveTargetAfterRemoval(owner:DockNode, previous:TabNode):Null<TabNode> {
        if (containsTab(owner, previous)) return previous;
        return owner.firstTab();
    }

    function removeSlotFromAll(id:String, ?key:String):Bool {
        if (root != null) {
            var removed = DockTree.remove(root, id, key);
            if (removed.slot != null) {
                root = removed.root;
                return true;
            }
        }
        for (window in floating) {
            var tab = window.root.findTab(id, key);
            if (tab == null) continue;
            var slot = tab.remove(id, key);
            if (slot == null) continue;
            var pruned = DockTree.prune(window.root);
            window.root = pruned == null ? new TabNode() : pruned;
            if (DockTree.collectSlots(window.root).length == 0) {
                if (window.nativeKey != "") {
                    dockWindows.closeDockPanel(window.nativeKey);
                    nativeGeometrySent.remove(window.nativeKey);
                }
                floating.remove(window);
            }
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Legacy compatibility and menu data
    // ------------------------------------------------------------------

    function bottomTabIndex():Int {
        var bottom = root == null ? null : root.findTab("boltspark.assets");
        return bottom != null && bottom.activeSlot() != null
            && bottom.activeSlot().view.panelId == "boltspark.console" ? 1 : 0;
    }

    function syncLegacy():Void {
        if (onBottomTabChanged != null) onBottomTabChanged(bottomTabIndex());
    }

    public function onTabActivated():Void {
        syncLegacy();
        renderer.draw();
        syncViews();
    }

    public function legacySizes():{left:Float, right:Float, console:Float, bottomTab:Int} {
        var hierarchy = root == null ? null : root.findTab("boltspark.hierarchy");
        var inspector = root == null ? null : root.findTab("boltspark.inspector");
        var bottom = root == null ? null : root.findTab("boltspark.assets");
        // Legacy layout.json stores console *content* height; exclude the
        // docking tab bar so external geometry math stays unchanged.
        var consoleHeight = bottom == null
            ? Theme.CONSOLE_HEIGHT
            : bottom.rect.height - bottom.barHeight;
        return {
            left: hierarchy == null ? Theme.LEFT_PANEL_WIDTH : hierarchy.rect.width,
            right: inspector == null ? Theme.RIGHT_PANEL_WIDTH : inspector.rect.width,
            console: consoleHeight,
            bottomTab: bottomTabIndex()
        };
    }

    public function closedPanelIds():Array<String> {
        var result:Array<String> = [];
        for (id in registry.ids()) {
            if (!isOpen(id)) result.push(id);
        }
        return result;
    }

    public function openPanelIds():Array<String> {
        var result:Array<String> = [];
        for (slot in DockTree.collectSlots(root)) {
            if (result.indexOf(slot.view.panelId) < 0) result.push(slot.view.panelId);
        }
        return result;
    }

    // ------------------------------------------------------------------
    // In-process native HWND float hosts
    // ------------------------------------------------------------------

    public function update(dt:Float):Void {
        dockWindows.update(dt);
        for (message in dockWindows.takeMessages()) {
            handleDockMessage(message.key, message.text);
        }
    }

    function handleDockMessage(key:String, text:String):Void {
        var data:Dynamic = null;
        try {
            data = haxe.Json.parse(StringTools.trim(text));
        } catch (_:Dynamic) {
            return;
        }
        if (!Reflect.isObject(data)) return;
        var command = Std.string(Reflect.field(data, "cmd"));
        switch (command) {
            case "ready":
                log('native panel ready ' + Std.string(Reflect.field(data, "panelId")));
                for (window in floating) {
                    if (window.nativeKey == key) pushSnapshot(window);
                }
            case "edit":
                if (onDockPanelEdit != null) {
                    onDockPanelEdit(Std.string(Reflect.field(data, "panelId")),
                        Std.string(Reflect.field(data, "id")),
                        Reflect.field(data, "value"));
                }
            case "dock":
                for (window in floating.copy()) {
                    if (window.nativeKey == key) dockWindowIntoEditor(window);
                }
            case "remove":
                for (window in floating.copy()) {
                    if (window.nativeKey == key) closeFloat(window);
                }
            case "shown":
                log('native panel shown ' + Std.string(Reflect.field(data, "panelId")));
            case "closed":
                // The user pressed the float's X (or the OS close button).
                // Return the panel to its slot rather than deleting it.
                for (window in floating.copy()) {
                    if (window.nativeKey == key) dockWindowIntoEditor(window);
                }
            case _:
        }
    }

    function rememberNativeGeometry(key:String,
            geometry:{x:Float, y:Float, w:Float, h:Float}):Void {
        nativeGeometrySent.set(key,
            '${geometry.x},${geometry.y},${geometry.w},${geometry.h}');
    }

    function nativeGeometry(window:FloatingDockWindow):{x:Float, y:Float, w:Float, h:Float} {
        // Docking rects are client-space, so place the HWND at the editor's
        // client origin (not its frame origin, which is off by the title bar).
        var origin = NativeWindow.clientOrigin(ctx.window);
        return {x: origin.x + window.x, y: origin.y + window.y,
            w: window.width, h: window.height};
    }

    function pushSnapshot(window:FloatingDockWindow):Void {
        if (!window.native || onSnapshotRequest == null) return;
        var slot = window.root.firstTab() == null
            ? null : window.root.firstTab().activeSlot();
        if (slot == null) return;
        var snapshot = onSnapshotRequest(slot.view.panelId);
        if (snapshot == null) snapshot = {title: window.title, rows: []};
        dockWindows.sendSnapshot(window.nativeKey, slot.view.panelId, snapshot);
    }

    /** Push fresh snapshots to every native float (called on editor changes). */
    public function refreshNativePanels():Void {
        for (window in floating) pushSnapshot(window);
    }

    public function shutdown():Void {
        dockWindows.shutdown();
    }

    function log(line:String):Void Sys.println("[dock] " + line);
}
