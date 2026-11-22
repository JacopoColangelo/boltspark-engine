package boltspark.ui.dock;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiText;
import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.dock.DockPanelView.PanelSlot;
import boltspark.ui.layout.LayoutRect;

typedef DockPreview = {
    var rect:LayoutRect;
    var side:DockSide;
    var label:String;
}

private class TabVisuals {
    public var labels:Array<h2d.Text> = [];
    public var hits:Array<h2d.Interactive> = [];
    public var closes:Array<h2d.Interactive> = [];
    /** Per-tab "..." drag grip, drawn inside the tab next to its close X. */
    public var grips:Array<h2d.Interactive> = [];
    public var hoveredCloses:Array<Bool> = [];
    public var hoveredGrips:Array<Bool> = [];
    /** One Graphics per tab: UiIcons.draw clears its target's children. */
    public var icons:Array<h2d.Graphics> = [];
    public function new() {}
}

private class FloatVisual {
    public var window:FloatingDockWindow;
    public var container:h2d.Object;
    public var content:h2d.Object;
    public var graphics:h2d.Graphics;
    public var title:h2d.Text;
    public var titleHit:h2d.Interactive;
    public var closeHit:h2d.Interactive;
    public var minimizeHit:h2d.Interactive;
    public var maximizeHit:h2d.Interactive;
    public var resizeHit:h2d.Interactive;
    public var icon:h2d.Graphics;
    public var hoverButton:Int = -1;
    public var grabbing:Bool = false;
    public var resizing:Bool = false;
    public var lastX:Float = 0;
    public var lastY:Float = 0;
    public function new() {}
}

/**
 * Draws themed dock chrome and owns its hit targets. Rebuilds interactives only
 * when the tree changes; `draw()` is called on layout/selection/hover changes,
 * never unconditionally every frame.
 */
class DockLayoutRenderer {
    public var onTabPush:Null<TabNode->Int->Float->Float->Void>;
    public var onTabClose:Null<TabNode->Int->Void>;
    public var onSplitDrag:Null<SplitNode->Float->Void>;
    public var onSplitDragEnd:Null<Void->Void>;
    public var onFloatChanged:Null<Void->Void>;
    public var onFloatDockRequest:Null<FloatingDockWindow->Void>;
    public var onFloatClose:Null<FloatingDockWindow->Void>;
    /** Editor body rect used to maximize a floating window. */
    public var body:LayoutRect = new LayoutRect(0, 0, 0, 0);

    final ctx:UiContext;
    final registry:PanelRegistry;
    final chromeLayer:h2d.Object;
    final floatLayer:h2d.Object;
    final overlayLayer:h2d.Object;
    final graphics:h2d.Graphics;
    final hitRoot:h2d.Object;
    final overlay:h2d.Graphics;
    final ghostSurface:h2d.Object;
    final ghostGraphics:h2d.Graphics;
    final ghostLabel:h2d.Text;
    final floatVisuals:Map<Int, FloatVisual> = [];
    final tabVisuals:Map<TabNode, TabVisuals> = [];
    final splitHits:Map<SplitNode, h2d.Interactive> = [];
    /** Single-tab groups inside a float: their frame title already names them. */
    final singleFloatTabs:Map<TabNode, Bool> = [];

    var root:Null<DockNode> = null;
    var floating:Array<FloatingDockWindow> = [];
    var preview:Null<DockPreview> = null;
    var hoveredSplit:Null<SplitNode> = null;
    var activeSplit:Null<SplitNode> = null;
    var activeSplitHit:Null<h2d.Interactive> = null;
    var focusedFloat:Int = -1;
    var nativeCapture:Bool = false;
    var activeFloatHit:Null<h2d.Interactive> = null;

    public function new(ctx:UiContext, registry:PanelRegistry, chromeLayer:h2d.Object,
            floatLayer:h2d.Object, overlayLayer:h2d.Object) {
        this.ctx = ctx;
        this.registry = registry;
        this.chromeLayer = chromeLayer;
        this.floatLayer = floatLayer;
        this.overlayLayer = overlayLayer;
        graphics = new h2d.Graphics(chromeLayer);
        hitRoot = new h2d.Object(chromeLayer);
        overlay = new h2d.Graphics(overlayLayer);

        ghostSurface = new h2d.Object(overlayLayer);
        ghostGraphics = new h2d.Graphics(ghostSurface);
        ghostGraphics.beginFill(Theme.ACCENT_MUTED, 0.95);
        ghostGraphics.drawRect(0, 0, 132, 24);
        ghostGraphics.endFill();
        ghostGraphics.lineStyle(1, Theme.ACCENT, 1);
        ghostGraphics.moveTo(0.5, 0);
        ghostGraphics.lineTo(0.5, 24);
        ghostGraphics.moveTo(132, 0);
        ghostGraphics.lineTo(132, 24);
        ghostLabel = new h2d.Text(ctx.captionFont, ghostSurface);
        ghostLabel.textColor = Theme.TEXT;
        ghostLabel.x = 8;
        ghostLabel.y = 5;
        ghostSurface.visible = false;
    }

    /** Reparent panel views into this container for a floating window. */
    public function floatContent(windowId:Int):Null<h2d.Object> {
        var visual = floatVisuals.get(windowId);
        return visual == null ? null : visual.content;
    }

    public function setFocusedFloat(id:Int):Void {
        if (focusedFloat == id) return;
        focusedFloat = id;
        draw();
    }

    /** Replace all hit targets after a structural change. */
    public function rebuild(root:Null<DockNode>, floating:Array<FloatingDockWindow>):Void {
        this.root = root;
        this.floating = floating;
        hitRoot.removeChildren();
        for (visual in floatVisuals) {
            visual.container.remove();
        }
        floatVisuals.clear();
        tabVisuals.clear();
        splitHits.clear();
        singleFloatTabs.clear();
        hoveredSplit = null;

        if (root != null) buildNode(root, true);
        for (window in floating) {
            var tabs:Array<TabNode> = [];
            window.root.collectTabs(tabs);
            for (tab in tabs) {
                if (tab.slots.length == 1) singleFloatTabs.set(tab, true);
            }
            if (!window.native) buildFloat(window);
        }
        draw();
    }

    function buildNode(node:DockNode, main:Bool):Void {
        if (Std.isOfType(node, TabNode)) {
            var tab = cast(node, TabNode);
            if (isFixed(tab)) return;
            for (index in 0...tab.slots.length) buildTabHit(tab, index);
            return;
        }
        if (Std.isOfType(node, SplitNode)) {
            var split = cast(node, SplitNode);
            buildSplitHit(split);
            buildNode(split.first, main);
            buildNode(split.second, main);
        }
    }

    static function isFixed(tab:TabNode):Bool {
        for (slot in tab.slots) if (slot.locked) return true;
        return false;
    }

    function buildTabHit(tab:TabNode, index:Int):Void {
        var slot = tab.slots[index];
        var descriptor = registry.descriptor(slot.view.panelId);
        var labelText = descriptor == null ? slot.view.panelId : descriptor.displayName;
        var label = new UiText(ctx.captionFont, hitRoot);
        label.text = labelText;
        label.textColor = Theme.TEXT_SECONDARY;
        label.lineBreak = false;
        label.name = "tab-label:" + index;

        var hit = new h2d.Interactive(1, 1, hitRoot);
        hit.name = "tab-hit:" + index;
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onPush = function(event) {
            if (event.button != 0) return;
            event.propagate = false;
            if (onTabPush != null) onTabPush(tab, index, ctx.mouseX, ctx.mouseY);
        };
        hit.onOver = function(_) draw();
        hit.onOut = function(_) draw();
        var visuals = tabVisuals.get(tab);
        if (visuals == null) {
            visuals = new TabVisuals();
            tabVisuals.set(tab, visuals);
        }
        visuals.labels[index] = label;
        visuals.hits[index] = hit;
        visuals.icons[index] = new h2d.Graphics(hitRoot);
        visuals.hoveredCloses[index] = false;
        visuals.hoveredGrips[index] = false;

        if (registry.flag(slot.view.panelId, "dock", true)) {
            var grip = new h2d.Interactive(1, 1, hitRoot);
            grip.backgroundColor = 0;
            grip.cursor = hxd.Cursor.Default;
            grip.onPush = function(event) {
                if (event.button != 0) return;
                event.propagate = false;
                if (onTabPush != null) {
                    onTabPush(tab, index, ctx.mouseX, ctx.mouseY);
                }
            };
            grip.name = "tab-grip:" + index;
            grip.onOver = function(_) {
                visuals.hoveredGrips[index] = true;
                draw();
            };
            grip.onOut = function(_) {
                visuals.hoveredGrips[index] = false;
                draw();
            };
            visuals.grips[index] = grip;
        }

        if (registry.flag(slot.view.panelId, "close", true)) {
            var close = new h2d.Interactive(1, 1, hitRoot);
            close.backgroundColor = 0;
            close.cursor = hxd.Cursor.Default;
            close.onPush = function(event) event.propagate = false;
            close.onClick = function(event) {
                event.propagate = false;
                if (onTabClose != null) onTabClose(tab, index);
            };
            close.name = "tab-close:" + index;
            close.onOver = function(_) {
                visuals.hoveredCloses[index] = true;
                draw();
            };
            close.onOut = function(_) {
                visuals.hoveredCloses[index] = false;
                draw();
            };
            visuals.closes[index] = close;
        }
    }

    function buildSplitHit(split:SplitNode):Void {
        var hit = new h2d.Interactive(1, 1, hitRoot);
        hit.backgroundColor = 0;
        hit.cursor = split.orientation == DockOrientation.Horizontal
            ? ctx.resizeHorizontal : ctx.resizeVertical;
        hit.name = "split-handle";
        hit.onOver = function(_) {
            hoveredSplit = split;
            draw();
        };
        hit.onOut = function(_) {
            if (!draggingSplit(split)) {
                hoveredSplit = null;
                ctx.restoreArrowCursor();
                draw();
            }
        };
        hit.onPush = function(_) beginSplitDrag(split, hit);
        splitHits.set(split, hit);
    }

    function draggingSplit(split:SplitNode):Bool return activeSplit == split;

    function beginSplitDrag(split:SplitNode, hit:h2d.Interactive):Void {
        if (activeSplit != null) return;
        activeSplit = split;
        activeSplitHit = hit;
        hit.preventClick();
        hit.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    var pointer = split.orientation == DockOrientation.Horizontal
                        ? ctx.mouseX : ctx.mouseY;
                    if (onSplitDrag != null) onSplitDrag(split, pointer);
                    event.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    event.propagate = false;
                    endSplitDrag();
                case _:
                    event.propagate = true;
            }
        }, endSplitDrag);
        if (!nativeCapture) {
            ctx.setMouseCapture(true);
            nativeCapture = true;
        }
        draw();
    }

    function endSplitDrag():Void {
        if (activeSplit == null) return;
        activeSplit = null;
        if (activeSplitHit != null) {
            var hit = activeSplitHit;
            activeSplitHit = null;
            if (hit.getScene() != null) hit.stopCapture();
        }
        if (nativeCapture) {
            ctx.setMouseCapture(false);
            nativeCapture = false;
        }
        ctx.restoreArrowCursor();
        draw();
        if (onSplitDragEnd != null) onSplitDragEnd();
    }

    // ------------------------------------------------------------------
    // Floating windows
    // ------------------------------------------------------------------

    function buildFloat(window:FloatingDockWindow):Void {
        var visual = new FloatVisual();
        visual.window = window;
        visual.container = new h2d.Object(floatLayer);
        visual.content = new h2d.Object(visual.container);
        visual.graphics = new h2d.Graphics(visual.container);

        visual.title = new UiText(ctx.captionFont, visual.container);
        visual.title.text = window.title;
        visual.title.textColor = Theme.TEXT;
        visual.title.lineBreak = false;

        visual.titleHit = new h2d.Interactive(1, 1, visual.container);
        visual.titleHit.backgroundColor = 0;
        visual.titleHit.cursor = hxd.Cursor.Default;
        visual.titleHit.onPush = function(event) {
            if (event.button != 0) return;
            event.propagate = false;
            visual.grabbing = true;
            activeFloatHit = visual.titleHit;
            visual.lastX = ctx.mouseX;
            visual.lastY = ctx.mouseY;
            visual.titleHit.preventClick();
            setFocusedFloat(window.id);
            visual.titleHit.startCapture(function(captured) {
                switch (captured.kind) {
                    case EMove:
                        window.x += ctx.mouseX - visual.lastX;
                        window.y += ctx.mouseY - visual.lastY;
                        visual.lastX = ctx.mouseX;
                        visual.lastY = ctx.mouseY;
                        clampFloat(window);
                        applyFloat(visual);
                        if (onFloatChanged != null) onFloatChanged();
                        captured.propagate = false;
                    case ERelease, EReleaseOutside, EFocusLost:
                        captured.propagate = false;
                        // Releasing a title-bar drag only moves the window.
                        // Docking is an explicit action (title click / menu).
                        finishFloatGesture(visual);
                    case _:
                        captured.propagate = true;
                }
            }, function() finishFloatGesture(visual));
            if (!nativeCapture) {
                ctx.setMouseCapture(true);
                nativeCapture = true;
            }
        };
        visual.titleHit.onClick = function(event) {
            event.propagate = false;
            toggleMaximize(visual);
        };
        visual.icon = new h2d.Graphics(visual.container);

        visual.closeHit = new h2d.Interactive(18, 18, visual.container);
        visual.closeHit.backgroundColor = 0;
        visual.closeHit.cursor = hxd.Cursor.Default;
        visual.closeHit.onPush = function(event) event.propagate = false;
        visual.closeHit.onOver = function(_) {
            visual.hoverButton = 2;
            drawFloatFrame(visual);
        };
        visual.closeHit.onOut = function(_) {
            visual.hoverButton = -1;
            drawFloatFrame(visual);
        };
        visual.closeHit.onClick = function(event) {
            event.propagate = false;
            if (onFloatClose != null) onFloatClose(window);
        };
        visual.closeHit.name = "float-close:" + window.id;

        visual.minimizeHit = new h2d.Interactive(18, 18, visual.container);
        visual.minimizeHit.backgroundColor = 0;
        visual.minimizeHit.cursor = hxd.Cursor.Default;
        visual.minimizeHit.onPush = function(event) event.propagate = false;
        visual.minimizeHit.onOver = function(_) {
            visual.hoverButton = 0;
            drawFloatFrame(visual);
        };
        visual.minimizeHit.onOut = function(_) {
            visual.hoverButton = -1;
            drawFloatFrame(visual);
        };
        visual.minimizeHit.onClick = function(event) {
            event.propagate = false;
            window.minimized = !window.minimized;
            visual.content.visible = !window.minimized;
            if (onFloatChanged != null) onFloatChanged();
        };
        visual.minimizeHit.name = "float-minimize:" + window.id;

        visual.maximizeHit = new h2d.Interactive(18, 18, visual.container);
        visual.maximizeHit.backgroundColor = 0;
        visual.maximizeHit.cursor = hxd.Cursor.Default;
        visual.maximizeHit.onPush = function(event) event.propagate = false;
        visual.maximizeHit.onOver = function(_) {
            visual.hoverButton = 1;
            drawFloatFrame(visual);
        };
        visual.maximizeHit.onOut = function(_) {
            visual.hoverButton = -1;
            drawFloatFrame(visual);
        };
        visual.maximizeHit.onClick = function(event) {
            event.propagate = false;
            toggleMaximize(visual);
        };
        visual.maximizeHit.name = "float-maximize:" + window.id;

        visual.resizeHit = new h2d.Interactive(16, 16, visual.container);
        visual.resizeHit.backgroundColor = 0;
        visual.resizeHit.cursor = ctx.resizeHorizontal;
        visual.resizeHit.onPush = function(event) {
            event.propagate = false;
            visual.resizing = true;
            activeFloatHit = visual.resizeHit;
            visual.lastX = ctx.mouseX;
            visual.lastY = ctx.mouseY;
            visual.resizeHit.preventClick();
            visual.resizeHit.startCapture(function(captured) {
                switch (captured.kind) {
                    case EMove:
                        window.width = Math.max(240, window.width
                            + ctx.mouseX - visual.lastX);
                        window.height = Math.max(160, window.height
                            + ctx.mouseY - visual.lastY);
                        visual.lastX = ctx.mouseX;
                        visual.lastY = ctx.mouseY;
                        clampFloat(window);
                        applyFloat(visual);
                        if (onFloatChanged != null) onFloatChanged();
                        captured.propagate = false;
                    case ERelease, EReleaseOutside, EFocusLost:
                        captured.propagate = false;
                        finishFloatGesture(visual);
                    case _:
                        captured.propagate = true;
                }
            }, function() finishFloatGesture(visual));
            if (!nativeCapture) {
                ctx.setMouseCapture(true);
                nativeCapture = true;
            }
        };

        floatVisuals.set(window.id, visual);
        applyFloat(visual);
    }

    function toggleMaximize(visual:FloatVisual):Void {
        var window = visual.window;
        if (window.maximized) {
            window.maximized = false;
            if (window.restoreRect != null) {
                window.x = window.restoreRect.x;
                window.y = window.restoreRect.y;
                window.width = window.restoreRect.width;
                window.height = window.restoreRect.height;
            }
        } else {
            window.restoreRect = new LayoutRect(window.x, window.y,
                window.width, window.height);
            window.x = body.x + 8;
            window.y = body.y + 8;
            window.width = Math.max(240, body.width - 16);
            window.height = Math.max(160, body.height - 16);
        }
        window.minimized = false;
        applyFloat(visual);
        drawFloatFrame(visual);
        if (onFloatChanged != null) onFloatChanged();
    }

    function finishFloatGesture(visual:FloatVisual):Void {
        visual.grabbing = false;
        visual.resizing = false;
        if (activeFloatHit != null) {
            var hit = activeFloatHit;
            activeFloatHit = null;
            if (hit.getScene() != null) hit.stopCapture();
        }
        if (nativeCapture) {
            ctx.setMouseCapture(false);
            nativeCapture = false;
        }
        draw();
        if (onFloatChanged != null) onFloatChanged();
    }

    function clampFloat(window:FloatingDockWindow):Void {
        window.x = DockNode.clamp(window.x, 0, Math.max(0, ctx.width - 80));
        window.y = DockNode.clamp(window.y, Theme.TOP_BAR_HEIGHT,
            Math.max(Theme.TOP_BAR_HEIGHT, ctx.height - Theme.STATUS_BAR_HEIGHT - 40));
        window.width = Math.min(window.width, Math.max(240, ctx.width - window.x));
        window.height = Math.min(window.height,
            Math.max(160, ctx.height - Theme.STATUS_BAR_HEIGHT - window.y));
    }

    function applyFloat(visual:FloatVisual):Void {
        var window = visual.window;
        visual.container.x = Math.round(window.x);
        visual.container.y = Math.round(window.y);
        visual.content.x = 0;
        visual.content.y = 24;
        visual.content.visible = !window.minimized;
        var width = Math.round(window.width);
        var height = Math.round(window.minimized ? 24 : window.height);
        visual.title.x = 26;
        visual.title.y = 4;
        visual.icon.x = 8;
        visual.icon.y = 6;
        visual.titleHit.x = 0;
        visual.titleHit.y = 0;
        visual.titleHit.width = Math.max(0, width - 96);
        visual.titleHit.height = 22;
        visual.minimizeHit.x = Math.max(0, width - 92);
        visual.minimizeHit.y = 3;
        visual.maximizeHit.x = Math.max(0, width - 68);
        visual.maximizeHit.y = 3;
        visual.closeHit.x = Math.max(0, width - 44);
        visual.closeHit.y = 3;
        visual.resizeHit.x = Math.max(0, width - 16);
        visual.resizeHit.y = Math.max(0, height - 16);
        visual.resizeHit.visible = !window.minimized && !window.maximized;
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    public function draw():Void {
        graphics.clear();
        if (root != null) drawNode(root);
        for (visual in floatVisuals) drawFloatFrame(visual);
        drawOverlay();
    }

    function drawNode(node:DockNode):Void {
        if (Std.isOfType(node, TabNode)) {
            var tab = cast(node, TabNode);
            if (isFixed(tab)) return;
            var bar = tab.rect;
            if (bar.width <= 0 || bar.height <= 0) return;
            var barX = Math.round(bar.x);
            var barY = Math.round(bar.y);
            var barW = Math.round(bar.width);
            if (tab.barHeight > 0) {
                graphics.beginFill(Theme.TITLE_BAR, 1);
                graphics.drawRect(barX, barY, barW, tab.barHeight);
                graphics.endFill();
                graphics.beginFill(Theme.BORDER, 1);
                graphics.drawRect(barX, barY + tab.barHeight - 1,
                    barW, 1);
                graphics.endFill();
            }
            var visuals = tabVisuals.get(tab);
            var cellCount = Std.int(Math.min(tab.tabRects.length, tab.slots.length));
            for (index in 0...cellCount) {
                var cell = tab.tabRects[index];
                var active = index == tab.activeIndex;
                if (active) {
                    graphics.beginFill(Theme.PANEL_HEADER, 1);
                    graphics.drawRect(cell.x, cell.y, cell.width, cell.height);
                    graphics.endFill();
                    graphics.beginFill(Theme.ACCENT, 1);
                    graphics.drawRect(cell.x, cell.y, cell.width, 2);
                    graphics.endFill();
                }
                var descriptor = registry.descriptor(tab.slots[index].view.panelId);
                var iconValue = descriptor == null || descriptor.icon == null
                    || descriptor.icon <= 0 ? 43 : descriptor.icon;
                var iconGraphics = visuals == null ? null : visuals.icons[index];
                if (iconGraphics != null) {
                    iconGraphics.x = Math.round(cell.x) + 7;
                    iconGraphics.y = Math.round(cell.y) + 5;
                    UiIcons.draw(iconGraphics, iconValue, 0, 0, 12,
                        active ? Theme.ACCENT : Theme.TEXT_SECONDARY);
                }
                var label = visuals == null ? null : visuals.labels[index];
                if (label != null) {
                    label.x = Math.round(cell.x) + 25;
                    label.y = Math.round(cell.y) + 4;
                    label.textColor = active ? Theme.TEXT : Theme.MUTED;
                    label.visible = cell.width > 76
                        && !(singleFloatTabs.exists(tab) && tab.slots.length == 1);
                }
                var hit = visuals == null ? null : visuals.hits[index];
                if (hit != null) {
                    hit.x = cell.x;
                    hit.y = cell.y;
                    hit.width = Math.max(1, cell.width - 36);
                    hit.height = cell.height;
                }
                var grip = visuals == null ? null : visuals.grips[index];
                if (grip != null) {
                    grip.x = cell.x + cell.width - 34;
                    grip.y = cell.y + 3;
                    grip.width = 14;
                    grip.height = Math.max(6, cell.height - 6);
                    var gripHover = visuals.hoveredGrips[index];
                    if (gripHover) {
                        graphics.beginFill(Theme.SURFACE_3, 1);
                        graphics.drawRect(grip.x - 2, grip.y,
                            grip.width + 4, grip.height);
                        graphics.endFill();
                        graphics.lineStyle(1, Theme.BORDER_STRONG, 1);
                        graphics.drawRect(grip.x - 2.5, grip.y - 0.5,
                            grip.width + 5, grip.height + 1);
                        graphics.lineStyle();
                    }
                    var dotColor = gripHover ? Theme.TEXT
                        : (active ? Theme.TEXT_SECONDARY : Theme.MUTED);
                    graphics.beginFill(dotColor, 1);
                    var dotY = grip.y + Math.round((grip.height - 2) * 0.5);
                    for (dot in 0...3) {
                        graphics.drawRect(grip.x + dot * 5, dotY, 2, 2);
                    }
                    graphics.endFill();
                }
                var close = visuals == null ? null : visuals.closes[index];
                if (close != null) {
                    var closeRect = tab.closeRects[index];
                    close.x = closeRect.x;
                    close.y = closeRect.y;
                    close.width = closeRect.width;
                    close.height = closeRect.height;
                    var cx = closeRect.x + closeRect.width * 0.5;
                    var cy = closeRect.y + closeRect.height * 0.5;
                    var closeHover = visuals.hoveredCloses[index];
                    if (closeHover) {
                        graphics.beginFill(Theme.SURFACE_3, 1);
                        graphics.drawRect(closeRect.x - 1, closeRect.y - 1,
                            closeRect.width + 2, closeRect.height + 2);
                        graphics.endFill();
                        graphics.lineStyle(1, Theme.DANGER, 1);
                        graphics.drawRect(closeRect.x - 1.5, closeRect.y - 1.5,
                            closeRect.width + 3, closeRect.height + 3);
                        graphics.lineStyle();
                    }
                    graphics.lineStyle(1, closeHover ? Theme.DANGER
                        : (active ? Theme.TEXT_SECONDARY : Theme.MUTED), 1);
                    graphics.moveTo(cx - 3, cy - 3);
                    graphics.lineTo(cx + 3, cy + 3);
                    graphics.moveTo(cx + 3, cy - 3);
                    graphics.lineTo(cx - 3, cy + 3);
                    graphics.lineStyle();
                }
            }
            return;
        }
        if (Std.isOfType(node, SplitNode)) {
            var split = cast(node, SplitNode);
            var handle = split.handleRect;
            var color = activeSplit == split ? Theme.ACCENT
                : (hoveredSplit == split ? Theme.SPLITTER_HOVER : Theme.PANEL_EDGE);
            graphics.beginFill(color, 1);
            graphics.drawRect(handle.x, handle.y, handle.width, handle.height);
            graphics.endFill();
            var hit = splitHits.get(split);
            if (hit != null) {
                hit.x = handle.x - 2;
                hit.y = handle.y;
                hit.width = Math.max(4, handle.width + 4);
                hit.height = handle.height;
            }
            drawNode(split.first);
            drawNode(split.second);
        }
    }

    function drawFloatFrame(visual:FloatVisual):Void {
        var window = visual.window;
        var height = window.minimized ? 24 : window.height;
        var g = visual.graphics;
        g.clear();
        // Soft offset shadow. The body stays transparent: panel content lives
        // in the host's float layer below this frame and must show through.
        g.beginFill(0x000000, 0.30);
        g.drawRect(4, 5, window.width, height);
        g.endFill();
        g.beginFill(Theme.TITLE_BAR, 1);
        g.drawRect(0, 0, window.width, 24);
        g.endFill();
        g.lineStyle(1, focusedFloat == window.id ? Theme.ACCENT : Theme.BORDER_STRONG, 1);
        g.moveTo(0.5, 0);
        g.lineTo(window.width - 0.5, 0);
        g.lineTo(window.width - 0.5, height - 0.5);
        g.lineTo(0.5, height - 0.5);
        g.lineTo(0.5, 0);
        g.lineStyle();
        g.lineStyle(1, Theme.BORDER, 1);
        g.moveTo(0, 23.5);
        g.lineTo(window.width, 23.5);
        g.lineStyle();
        drawFloatButton(g, visual.minimizeHit.x, "minus", visual.hoverButton == 0);
        drawFloatButton(g, visual.maximizeHit.x,
            window.maximized ? "restore" : "maximize", visual.hoverButton == 1);
        drawFloatButton(g, visual.closeHit.x, "close", visual.hoverButton == 2);
        if (!window.minimized && !window.maximized) {
            g.beginFill(Theme.BORDER_STRONG, 1);
            g.drawRect(window.width - 12, height - 12, 9, 9);
            g.endFill();
        }
        // Panel icon in the title bar.
        var iconId = 43;
        var tab = window.root.firstTab();
        if (tab != null && tab.activeSlot() != null) {
            var descriptor = registry.descriptor(tab.activeSlot().view.panelId);
            if (descriptor != null && descriptor.icon != null && descriptor.icon > 0) {
                iconId = descriptor.icon;
            }
        }
        UiIcons.draw(visual.icon, iconId, 0, 0, 12, Theme.TEXT_SECONDARY);
        applyFloat(visual);
    }

    function drawFloatButton(g:h2d.Graphics, x:Float, kind:String,
            hovered:Bool):Void {
        var y = 8;
        g.beginFill(hovered ? Theme.SURFACE_3 : Theme.SURFACE_2, 1);
        g.drawRect(x, y - 3, 16, 16);
        g.endFill();
        g.lineStyle(1, hovered ? Theme.ACCENT : Theme.TEXT_SECONDARY, 1);
        if (kind == "close") {
            g.moveTo(x + 5, y + 2);
            g.lineTo(x + 11, y + 8);
            g.moveTo(x + 11, y + 2);
            g.lineTo(x + 5, y + 8);
        } else if (kind == "maximize" || kind == "restore") {
            if (kind == "restore") {
                g.drawRect(x + 3, y + 3, 8, 8);
                g.drawRect(x + 6, y, 7, 7);
            } else {
                g.drawRect(x + 4, y + 2, 8, 8);
            }
        } else {
            g.moveTo(x + 4, y + 6);
            g.lineTo(x + 12, y + 6);
        }
        g.lineStyle();
    }

    function drawOverlay():Void {
        // UiIcons.draw adds Bitmap children; clear() only drops draw commands.
        overlay.removeChildren();
        overlay.clear();
        if (preview == null) return;
        var r = preview.rect;
        var color = Theme.ACCENT;
        overlay.beginFill(color, 0.16);
        overlay.drawRect(r.x, r.y, r.width, r.height);
        overlay.endFill();
        overlay.lineStyle(2, color, 0.95);
        overlay.moveTo(r.x, r.y);
        overlay.lineTo(r.x + r.width, r.y);
        overlay.lineTo(r.x + r.width, r.y + r.height);
        overlay.lineTo(r.x, r.y + r.height);
        overlay.lineTo(r.x, r.y);
        overlay.lineStyle();

        var cx = r.x + r.width * 0.5;
        var cy = r.y + r.height * 0.5;
        var icon = switch (preview.side) {
            case Left: 34;   // ArrowLeft
            case Right: 35;  // ArrowRight
            case Top: 36;    // ArrowUp
            case Bottom: 46; // ArrowDown
            case Center: 43; // DockPanel
        };
        UiIcons.draw(overlay, icon, cx - 8, cy - 8, 16, color);
    }

    public function setPreview(value:Null<DockPreview>):Void {
        preview = value;
        drawOverlay();
    }

    public function setDragGhost(label:Null<String>, x:Float, y:Float):Void {
        if (label == null) {
            ghostSurface.visible = false;
            return;
        }
        if (ghostLabel.text != label) ghostLabel.text = label;
        ghostSurface.x = x + 12;
        ghostSurface.y = y + 12;
        ghostSurface.visible = true;
    }

}
