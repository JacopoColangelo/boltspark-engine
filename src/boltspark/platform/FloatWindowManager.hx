package boltspark.platform;

import boltspark.platform.NativeFloatWindow.WinFloatHandle;
import boltspark.platform.NativeWindow;
import boltspark.ui.Theme;
import boltspark.ui.AssetDragSession;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiSurface;
import boltspark.ui.dock.DockPanelView;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.render.FloatGlyphAtlas;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.AssetBrowser;
import boltspark.ui.widgets.UiTooltip;
import h3d.mat.Data.TextureFlags;
import h3d.mat.Texture;
import haxe.io.Bytes;
import hxd.PixelFormat;

private typedef FloatPanel = {
    key:String,
    panelId:String,
    title:String,
    handle:WinFloatHandle,
    width:Int,
    height:Int,
    pixels:Bytes,
    atlas:FloatGlyphAtlas,
    scale:Float,
    snapshot:Null<Dynamic>,
    lines:Array<String>,
    rows:Array<Dynamic>,
    scroll:Int,
    dirty:Bool,
    hoverClose:Bool,
    /** WM_CLOSE fired: HWND is gone, waiting for Haxe to re-dock and free. */
    closed:Bool
}

/**
 * A live H2D panel view hosted in a float. The real widgets are rendered into
 * an offscreen DX12 target on the editor's existing device (the same technique
 * the thumbnail baker uses), then blitted to the HWND with GDI. Input events
 * from the HWND are dispatched into a private SceneEvents instance so h2d
 * interactives (buttons, rows, text fields) behave exactly as docked panels do.
 */
private typedef BoundView = {
    key:String,
    view:DockPanelView,
    host:h2d.Object,
    scene:h2d.Scene,
    events:Null<hxd.SceneEvents>,
    target:Null<Texture>,
    originalParent:Null<h2d.Object>,
    overlay:h2d.Object,
    header:h2d.Object,
    headerBg:h2d.Graphics,
    titleText:h2d.Text,
    minHit:h2d.Interactive,
    closeHit:h2d.Interactive,
    dockHit:h2d.Interactive,
    dragHit:h2d.Interactive,
    minSurface:UiSurface,
    closeSurface:UiSurface,
    dockSurface:UiSurface,
    minIcon:h2d.Graphics,
    closeIcon:h2d.Graphics,
    dockIcon:h2d.Graphics,
    hintText:h2d.Text,
    tooltip:UiTooltip,
    assetBrowser:Null<AssetBrowser>,
    tooltipOwner:Null<Dynamic>,
    previousTooltip:Null<Dynamic>,
    hadTooltip:Bool,
    layoutKey:String,
    bindTime:Float,
    forceLayout:Bool,
    hoverButton:Int
}

/**
 * Owns the process-local floating dock panels.
 *
 * Each panel is a real Win32 HWND (created by tools/native/winfloat.c) whose
 * client area is painted from a CPU BGRA buffer. No second Heaps instance, no
 * second swapchain and no child process is involved: the editor keeps its one
 * DX12 device while floats use GDI only. Snapshots and edits travel through
 * plain Haxe callbacks/messages on the existing DockingManager message bus.
 */
class FloatWindowManager {
    /** Supplies the same snapshot a docked panel would render. */
    public var onSnapshotRequest:Null<String->Dynamic>;
    /** phase 0 = start, 1 = move, 2 = drop; coordinates are screen-space. */
    public var onHeaderDrag:Null<String->Int->Int->Int->Void>;

    final ctx:UiContext;
    final panels:Map<String, FloatPanel> = new Map();
    final boundViews:Map<String, BoundView> = new Map();
    final pending:Array<{key:String, text:String}> = [];
    final atlasCache:Map<Int, FloatGlyphAtlas> = new Map();
    static var fontBytes:Null<Bytes> = null;
    var mainMenuOverlay:Null<h2d.Object> = null;
    var dragging:Null<{key:String, sx:Int, sy:Int, wx:Int, wy:Int}> = null;
    var dragCapturePanel:Null<String> = null;
    /** Focus/capture loss is reported from a Win32 WndProc. Never mutate the
     *  H2D scene from that callback; process each latched panel on update(). */
    final pendingFocusLoss:Map<String, Bool> = new Map();
    /** Single always-on-top label shared by the editor and every float. */
    var dragOverlay:Null<DragLabelOverlay> = null;

    public function new(ctx:UiContext) {
        this.ctx = ctx;
    }

    // ------------------------------------------------------------------
    // API used by DockingManager
    // ------------------------------------------------------------------

    /** Create (or reposition) the HWND hosting a floating dock panel. */
    public function openDockPanel(key:String, panelId:String, title:String,
            x:Float, y:Float, width:Float, height:Float):Null<String> {
        if (panels.exists(key)) {
            sendGeometry(key, x, y, width, height);
            return null;
        }
        try {
            var w = clampInt(width, 160, 4000);
            var h = clampInt(height, 100, 3000);
            var callback = function(kind:Int, a:Int, b:Int, c:Int) {
                onEvent(key, kind, a, b, c);
            };
            var handle = NativeFloatWindow.create(toNullTerminated(title),
                Math.round(x), Math.round(y), w, h, callback);
            if (handle == null) {
                return 'window: could not create native float for ${panelId}';
            }
            var scale = dpiScale(NativeFloatWindow.getDpi(handle));
            var panel:FloatPanel = {
                key: key,
                panelId: panelId,
                title: title,
                handle: handle,
                width: w,
                height: h,
                pixels: Bytes.alloc(w * h * 4),
                atlas: atlasFor(scale),
                scale: scale,
                snapshot: null,
                lines: [],
                rows: [],
                scroll: 0,
                dirty: true,
                hoverClose: false,
                closed: false
            };
            var clientW = NativeFloatWindow.clientWidth(handle);
            var clientH = NativeFloatWindow.clientHeight(handle);
            if (clientW > 0 && clientH > 0) setPanelSize(panel, clientW, clientH);
            panels.set(key, panel);
            // The layout may be restored before EditorShell installs its
            // snapshot callback; update() retries until a snapshot arrives.
            refreshSnapshot(panel);
            return null;
        } catch (error:Dynamic) {
            return 'window: could not create native float for ${panelId}: '
                + Std.string(error);
        }
    }

    /**
     * Host the actual docked view in this float. The host object is reparented
     * into a private H2D scene so it renders and receives input here instead of
     * in the main editor. Panels without a host (the fixed viewport) keep the
     * snapshot fallback.
     */
    public function bindView(key:String, view:DockPanelView,
            host:Null<h2d.Object>, panelId:String, title:String):Void {
        unbindView(key);
        if (host == null) return;
        var scene = new h2d.Scene();
        var events:Null<hxd.SceneEvents> = null;
        try {
            events = new hxd.SceneEvents();
            // Detach from the main window: only synthetic float events should
            // reach this scene, never the editor's own pointer/keyboard input.
            @:privateAccess {
                events.window.removeEventTarget(events.onEvent);
            }
            events.addScene(scene);
        } catch (error:Dynamic) {
            events = null;
            logError('scene events: ${Std.string(error)}');
        }
        var originalParent = host.parent;
        scene.addChild(host);
        view.setVisible(true);

        // Editor-themed header rendered with the same fonts/theme as docked
        // panels. Its buttons use UiSurface + UiIcons, matching editor chrome.
        var overlay = new h2d.Object(scene);
        var header = new h2d.Object(scene);
        var headerBg = new h2d.Graphics(header);
        var titleText = new h2d.Text(ctx.semiboldFont, header);
        titleText.textColor = Theme.TEXT;
        titleText.text = title;
        titleText.lineBreak = false;
        var hintText = new h2d.Text(ctx.captionFont, header);
        hintText.textColor = Theme.MUTED;
        hintText.text = "Drag to editor to dock";
        hintText.lineBreak = false;
        hintText.visible = false;

        function makeButton(icon:UiIconKind, kind:Int):{
                surface:UiSurface, icon:h2d.Graphics, hit:h2d.Interactive} {
            var surface = new UiSurface(ctx, header);
            surface.setStyle(Theme.SURFACE_2, Theme.BORDER, 0);
            var glyph = new h2d.Graphics(header);
            UiIcons.draw(glyph, icon, 0, 0, 12, Theme.TEXT_SECONDARY);
            var hit = new h2d.Interactive(20, 18, header);
            hit.backgroundColor = 0;
            hit.cursor = hxd.Cursor.Default;
            hit.onOver = function(_) setFloatHeaderButton(key, kind);
            hit.onOut = function(_) setFloatHeaderButton(key, 0);
            return {surface: surface, icon: glyph, hit: hit};
        }
        var dockButton = makeButton(DockPanel, 3);
        var minButton = makeButton(Minus, 1);
        var closeButton = makeButton(Close, 2);
        dockButton.hit.onPush = function(event) {
            event.propagate = false;
            push(key, '{"cmd":"dock"}');
        };
        minButton.hit.onPush = function(event) {
            event.propagate = false;
            var panel = panels.get(key);
            if (panel != null) NativeFloatWindow.minimize(panel.handle);
        };
        closeButton.hit.onPush = function(event) {
            event.propagate = false;
            // The dock button handles re-docking; X removes the panel.
            push(key, '{"cmd":"remove"}');
        };

        var dragHit = new h2d.Interactive(1, 1, header);
        dragHit.backgroundColor = 0;
        dragHit.cursor = hxd.Cursor.Default;
        dragHit.onPush = function(event) {
            event.propagate = false;
            beginHeaderDrag(key);
        };
        dragHit.onOver = function(_) {
            hintText.visible = true;
            setFloatHeaderButton(key, 0);
        };
        dragHit.onOut = function(_) hintText.visible = false;

        // Widgets with a `tooltip` field should schedule onto the float's own
        // tooltip, not the singleton living in the main editor scene.
        var floatTooltip = new UiTooltip(ctx, overlay);
        var floatAssetBrowser:Null<AssetBrowser> = Std.isOfType(host, AssetBrowser)
            ? cast host : null;
        if (floatAssetBrowser != null) floatAssetBrowser.setOverlayParent(overlay);
        // The real widget is `host` (AssetBrowser, ConsolePanel, etc.); `view`
        // is only its DockPanelView adapter. Checking the adapter left the
        // floating Asset Browser pointed at EditorShell's main tooltip, which
        // painted hover rectangles/text into the editor during a float drag.
        var tooltipOwner:Null<Dynamic> = Reflect.hasField(host, "tooltip")
            ? host : (Reflect.hasField(view, "tooltip") ? view : null);
        var hadTooltip = tooltipOwner != null;
        var previousTooltip:Null<Dynamic> = hadTooltip
            ? Reflect.field(tooltipOwner, "tooltip") : null;
        if (hadTooltip) Reflect.setField(tooltipOwner, "tooltip", floatTooltip);

        var bound:BoundView = {
            key: key,
            view: view,
            host: host,
            scene: scene,
            events: events,
            target: null,
            originalParent: originalParent,
            overlay: overlay,
            header: header,
            headerBg: headerBg,
            titleText: titleText,
            minHit: minButton.hit,
            closeHit: closeButton.hit,
            dockHit: dockButton.hit,
            dragHit: dragHit,
            minSurface: minButton.surface,
            closeSurface: closeButton.surface,
            dockSurface: dockButton.surface,
            minIcon: minButton.icon,
            closeIcon: closeButton.icon,
            dockIcon: dockButton.icon,
            hintText: hintText,
            tooltip: floatTooltip,
            assetBrowser: floatAssetBrowser,
            tooltipOwner: tooltipOwner,
            previousTooltip: previousTooltip,
            hadTooltip: hadTooltip,
            layoutKey: "",
            bindTime: haxe.Timer.stamp(),
            forceLayout: true,
            hoverButton: 0
        };
        // Menus must draw above the header, not under it.
        scene.removeChild(overlay);
        scene.addChild(overlay);
        boundViews.set(key, bound);
        var panel = panels.get(key);
        if (panel != null) {
            panel.panelId = panelId;
            layoutBound(panel, bound);
            panel.dirty = true;
        }
    }

    function unbindView(key:String):Void {
        var bound = boundViews.get(key);
        if (bound == null) return;
        if (bound.host.parent == bound.scene && bound.originalParent != null) {
            bound.originalParent.addChild(bound.host);
        }
        if (bound.events != null) bound.events.removeScene(bound.scene);
        if (MenuDropdown.overlayLayer == bound.overlay && mainMenuOverlay != null) {
            // A menu left open by the float must not keep the global overlay
            // pointing at a scene that is about to disappear.
            MenuDropdown.overlayLayer = mainMenuOverlay;
            MenuDropdown.hasOpenMenu = false;
        }
        if (bound.hadTooltip && bound.tooltipOwner != null) {
            Reflect.setField(bound.tooltipOwner, "tooltip", bound.previousTooltip);
        }
        if (bound.assetBrowser != null) bound.assetBrowser.restoreOverlayParent();
        bound.tooltip.dispose();
        if (bound.target != null) bound.target.dispose();
        boundViews.remove(key);
    }

    public function sendGeometry(key:String, x:Float, y:Float,
            width:Float, height:Float):Void {
        var panel = panels.get(key);
        if (panel == null) return;
        try {
            NativeFloatWindow.setGeometry(panel.handle, Math.round(x),
                Math.round(y), Math.round(width), Math.round(height));
        } catch (_:Dynamic) {
        }
    }

    public function sendSnapshot(key:String, panelId:String,
            data:Dynamic):Void {
        var panel = panels.get(key);
        if (panel == null) return;
        invalidateLayout(key);
        panel.panelId = panelId;
        applySnapshot(panel, data);
    }

    /** Mirror a new editor log line into every floating Output Log. */
    function invalidateLayout(key:String):Void {
        var bound = boundViews.get(key);
        if (bound != null) bound.layoutKey = "";
    }

    public function log(line:String):Void {
        for (bound in boundViews) bound.layoutKey = "";
        for (panel in panels) {
            if (panel.panelId != "boltspark.console") continue;
            refreshSnapshot(panel);
            panel.dirty = true;
        }
    }

    /** Destroy the HWND and free its native panel. */
    public function closeDockPanel(key:String):Void {
        var panel = panels.get(key);
        if (panel == null) return;
        // A float closed mid-drag owns the H2D capture; tear the gesture down
        // while its view is still bound, otherwise its widget never gets the
        // release and the shared drag state lingers forever.
        var bound = boundViews.get(key);
        if (dragCapturePanel == key
                || (bound != null && bound.assetBrowser != null
                    && bound.assetBrowser.hasActiveDrag())) {
            cancelFloatDrag(panel);
        }
        pendingFocusLoss.remove(key);
        panels.remove(key);
        if (dragCapturePanel == key) {
            dragCapturePanel = null;
            NativeFloatWindow.releaseCapture();
        }
        unbindView(key);
        try {
            NativeFloatWindow.destroy(panel.handle);
        } catch (error:Dynamic) {
            logError('destroy: ${Std.string(error)}');
        }
    }

    public function takeMessages():Array<{key:String, text:String}> {
        var result = pending.copy();
        pending.resize(0);
        return result;
    }

    /** Pump/draw all floats. Called from DockingManager.update() each frame. */
    public function update(dt:Float):Void {
        // Focus messages can be delivered outside winfloat_pump() by Win32.
        // Native code only latches them; consume any prior-frame notification
        // before touching the drag overlay or repainting a captured scene.
        flushFocusLoss();
        if (UiContext.dragLabel == null) {
            if (UiContext.dragPointerOverride != null) {
                UiContext.dragPointerOverride = null;
            }
            if (dragOverlay != null) dragOverlay.hide();
        } else {
            if (dragOverlay == null) {
                try {
                    dragOverlay = DragLabelOverlay.create();
                } catch (error:Dynamic) {
                    logError('drag label overlay: ${Std.string(error)}');
                }
            }
            if (dragOverlay != null) {
                try {
                    dragOverlay.update(UiContext.dragLabel,
                        NativeFloatWindow.cursorX() + 14,
                        NativeFloatWindow.cursorY() + 12);
                } catch (error:Dynamic) {
                    logError('drag label update: ${Std.string(error)}');
                }
            }
        }
        for (bound in boundViews) bound.tooltip.update(dt);
        for (key => panel in panels) {
            if (panel.closed) continue;
            try {
                NativeFloatWindow.pump(panel.handle);
            } catch (error:Dynamic) {
                logError('pump: ${Std.string(error)}');
                continue;
            }
            // Messages drained by pump() may have latched a cancellation. The
            // WndProc and its HashLink callback have returned at this point.
            flushFocusLoss();
            if (panel.closed) continue;

            syncNativeSize(panel);
            var scale = dpiScale(NativeFloatWindow.getDpi(panel.handle));
            if (Math.abs(scale - panel.scale) > 0.01) {
                panel.scale = scale;
                panel.atlas = atlasFor(scale);
                panel.scroll = clampScroll(panel);
                panel.dirty = true;
            }
            if (panel.snapshot == null) refreshSnapshot(panel);
            if (panel.dirty || boundViews.exists(panel.key)) repaint(panel);
        }
    }

    public function shutdown():Void {
        var keys:Array<String> = [];
        for (key in panels.keys()) keys.push(key);
        for (key in keys) closeDockPanel(key);
        pending.resize(0);
        pendingFocusLoss.clear();
        if (dragOverlay != null) {
            dragOverlay.destroy();
            dragOverlay = null;
        }
    }

    // ------------------------------------------------------------------
    // Events from the native WndProc
    // ------------------------------------------------------------------

    function onEvent(key:String, kind:Int, a:Int, b:Int, c:Int):Void {
        var panel = panels.get(key);
        if (panel == null) return;
        try {
            switch (kind) {
                case NativeFloatWindow.EVENT_CLOSE:
                    userClose(panel);
                case NativeFloatWindow.EVENT_DESTROY:
                    // Window is already gone; "closed" is the only message we
                    // send, so re-docking never happens twice.
                case NativeFloatWindow.EVENT_FOCUS_LOST:
                    // This callback still runs inside winfloat_pump(). Defer
                    // scene/capture teardown until the native call unwinds.
                    pendingFocusLoss.set(key, true);
                case NativeFloatWindow.EVENT_RESIZE:
                    // A modal Win32 sizing loop does not re-enter Heaps'
                    // update(), so repaint synchronously from the WndProc
                    // callback. Otherwise the newly exposed strip stays black
                    // until the mouse is released.
                    if (a > 0 && b > 0
                            && (a != panel.width || b != panel.height)) {
                        setPanelSize(panel, a, b);
                        repaint(panel);
                    }
                case NativeFloatWindow.EVENT_MOUSEMOVE:
                    if (dragging != null && dragging.key == key) {
                        updateHeaderDrag(key);
                    } else {
                        updateHover(panel, a, b);
                        dispatchMouse(panel, hxd.Event.EventKind.EMove, a, b, 0);
                        // The drag session starts after a movement threshold,
                        // not on the initial push. Take Win32 capture as soon as
                        // it exists so leaving the HWND keeps delivering events.
                        if (UiContext.dragLabel != null
                                && dragCapturePanel != key) {
                            dragCapturePanel = key;
                            NativeFloatWindow.setCapture(panel.handle);
                        }
                    }
                case NativeFloatWindow.EVENT_LBUTTONDOWN:
                    if (boundViews.exists(panel.key)) {
                        // Header buttons are H2D interactives in the float scene.
                        dispatchMouse(panel, hxd.Event.EventKind.EPush, a, b, 0);
                        // Inspector checkboxes commit on push and may rebuild
                        // every property widget synchronously. Force the new
                        // hierarchy through the float-width layout before its
                        // next paint. Do not do this for AssetBrowser: its
                        // layout rebuilds tiles and would destroy the pressed
                        // card before ERelease.
                        if (panel.panelId == "boltspark.inspector") {
                            invalidateLayout(key);
                        }
                        // A drag started inside the float must keep receiving
                        // motion/releases after the pointer leaves its bounds
                        // (e.g. dropping an asset onto the main editor viewport).
                        if (UiContext.dragLabel != null) {
                            dragCapturePanel = key;
                            NativeFloatWindow.setCapture(panel.handle);
                        }
                    } else if (isCloseBox(panel, a, b)) {
                        handleClick(panel, a, b);
                    } else {
                        dispatchMouse(panel, hxd.Event.EventKind.EPush, a, b, 0);
                        handleClick(panel, a, b);
                    }
                case NativeFloatWindow.EVENT_LBUTTONUP:
                    if (dragging != null && dragging.key == key) {
                        endHeaderDrag(key);
                    } else {
                        dispatchMouse(panel, hxd.Event.EventKind.ERelease, a, b, 0);
                        if (dragCapturePanel == key) {
                            dragCapturePanel = null;
                            NativeFloatWindow.releaseCapture();
                        }
                        invalidateLayout(key);
                    }
                case NativeFloatWindow.EVENT_RBUTTONDOWN:
                    // Heaps maps the physical right button to event.button == 1.
                    dispatchMouse(panel, hxd.Event.EventKind.EPush, a, b, 0, 1);
                case NativeFloatWindow.EVENT_RBUTTONUP:
                    dispatchMouse(panel, hxd.Event.EventKind.ERelease, a, b, 0, 1);
                    if (dragCapturePanel == key) {
                        dragCapturePanel = null;
                        NativeFloatWindow.releaseCapture();
                    }
                    invalidateLayout(key);
                case NativeFloatWindow.EVENT_WHEEL:
                    // a/b are client coordinates, c is the wheel delta
                    // (±120 per notch) from WM_MOUSEWHEEL.
                    if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
                        Sys.println('[probe] float wheel ${a},${b} delta=${c}');
                    }
                    if (!dispatchMouse(panel, hxd.Event.EventKind.EWheel, a, b, c)) {
                        scrollPanel(panel, -c);
                    }
                case NativeFloatWindow.EVENT_KEYDOWN:
                    dispatchKey(panel, hxd.Event.EventKind.EKeyDown, a, 0);
                    invalidateLayout(key);
                case NativeFloatWindow.EVENT_KEYUP:
                    dispatchKey(panel, hxd.Event.EventKind.EKeyUp, a, 0);
                case NativeFloatWindow.EVENT_CHAR:
                    dispatchKey(panel, hxd.Event.EventKind.ETextInput, 0, a);
                    invalidateLayout(key);
                case NativeFloatWindow.EVENT_PAINT:
                    // WM_PAINT is dispatched synchronously from paint(); never
                    // repaint here or it would recurse. The frame loop handles
                    // the dirty flag, and WM_SIZE still repaints synchronously
                    // during a modal resize.
                    panel.dirty = true;
                default:
            }
        } catch (error:Dynamic) {
            logError('event ${kind}: ${Std.string(error)}');
        }
    }

    /** Consume deduplicated focus-loss notifications at a safe frame boundary. */
    function flushFocusLoss():Void {
        if (!pendingFocusLoss.iterator().hasNext()) return;
        var keys:Array<String> = [];
        for (key in pendingFocusLoss.keys()) keys.push(key);
        for (key in keys) {
            pendingFocusLoss.remove(key);
            var panel = panels.get(key);
            if (panel != null) cancelFloatDrag(panel);
        }
    }

    /**
     * Match the docked browser: focus loss cancels the gesture. This runs only
     * after the native WndProc/pump callback has returned, so stopping capture
     * and rebuilding browser rows cannot invalidate an active native/H2D stack.
     */
    function cancelFloatDrag(panel:FloatPanel):Void {
        var bound = boundViews.get(panel.key);
        var hadDrag = UiContext.dragLabel != null
            || AssetDragSession.current() != null
            || (bound != null && bound.assetBrowser != null
                && bound.assetBrowser.hasActiveDrag());
        if (dragCapturePanel == panel.key) {
            // Clear ownership first: ReleaseCapture can synchronously produce
            // WM_CAPTURECHANGED/WM_CANCELMODE.
            dragCapturePanel = null;
            NativeFloatWindow.releaseCapture();
        }
        if (dragging != null && dragging.key == panel.key) {
            dragging = null;
            hadDrag = true;
            // Clear DockingManager's preview without resolving a drop.
            if (onHeaderDrag != null) {
                onHeaderDrag(panel.key, 2, -100000, -100000);
            }
        }
        UiContext.dragLabel = null;
        UiContext.dragPointerOverride = null;
        if (dragOverlay != null) dragOverlay.hide();
        if (bound != null && bound.assetBrowser != null) {
            hadDrag = bound.assetBrowser.abortDrag() || hadDrag;
        } else {
            AssetDragSession.cancel();
        }
        if (hadDrag && Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] float drag cancelled focus loss panel=${panel.panelId}');
        }
    }

    /** Returns true when a live H2D view consumed the event. */
    function dispatchMouse(panel:FloatPanel, kind:hxd.Event.EventKind,
            x:Int, y:Int, wheel:Int, button:Int = 0):Bool {
        var bound = boundViews.get(panel.key);
        if (bound == null) return false;
        // The H2D header is part of the float scene now, so client coordinates
        // map 1:1 onto scene coordinates.
        var event = new hxd.Event(kind, x, y);
        event.button = button;
        // hldx's Window.hl negates WM_MOUSEWHEEL, so the docked editor sees
        // wheel-down as +1. Match that convention for float widgets.
        event.wheelDelta = wheel > 0 ? -1 : (wheel < 0 ? 1 : 0);
        if (kind == hxd.Event.EventKind.EMove) {
            ctx.invalidateNativeCursorCache();
        }
        try {
            emit(bound, event);
        } catch (error:Dynamic) {
            // WM_SETCURSOR over a resize edge changes the OS cursor without
            // updating Heaps' logical cache. Preserve the actual widget cursor
            // selected by this event so returning to HTCLIENT restores it even
            // when SceneEvents has no hover transition to dispatch.
            NativeFloatWindow.rememberClientCursor(panel.handle);
            throw error;
        }
        NativeFloatWindow.rememberClientCursor(panel.handle);
        return true;
    }

    function dispatchKey(panel:FloatPanel, kind:hxd.Event.EventKind,
            keyCode:Int, charCode:Int):Void {
        var bound = boundViews.get(panel.key);
        if (bound == null) return;
        var event = new hxd.Event(kind);
        event.keyCode = keyCode;
        event.charCode = charCode;
        emit(bound, event);
    }

    function emit(bound:BoundView, event:hxd.Event):Void {
        var prevPointer = ctx.pointerOverride;
        var prevSize = ctx.sizeOverride;
        var prevFloatMode = ctx.floatMode;
        var prevTooltip = UiTooltip.current;
        var prevDragOffset = AssetDragSession.coordinateOffset;
        var prevDragPointer = UiContext.dragPointerOverride;
        var translatedPointer:Null<{x:Float, y:Float}> = null;
        if (mainMenuOverlay == null) mainMenuOverlay = MenuDropdown.overlayLayer;

        // Widgets may rebuild the inspector or throw while handling an event.
        // These overrides are global to the editor, so they must be restored
        // even on failure: leaving ctx.sizeOverride set makes EditorShell
        // resize the whole dock layout to the float's dimensions (and leaves
        // menus/tooltips/drag coordinates pointing into the float forever).
        function restore():Void {
            ctx.pointerOverride = prevPointer;
            ctx.sizeOverride = prevSize;
            ctx.floatMode = prevFloatMode;
            AssetDragSession.coordinateOffset = prevDragOffset;
            // Keep the translated pointer alive for the whole drag: the viewport
            // hint is positioned from Main.update(), outside float dispatch.
            if (UiContext.dragLabel == null) {
                UiContext.dragPointerOverride = prevDragPointer;
            }
            UiTooltip.current = prevTooltip;
            if (!MenuDropdown.hasOpenMenu && mainMenuOverlay != null) {
                MenuDropdown.overlayLayer = mainMenuOverlay;
            }
        }

        try {
            ctx.floatMode = true;
            var hostPanel = panels.get(bound.key);
            if (hostPanel != null) {
                // Floats are frameless, so their window rect origin is their
                // client origin. The editor has a title bar: use its *client*
                // origin or drops land one caption-height below the pointer.
                var origin = NativeWindow.clientOrigin(ctx.window);
                AssetDragSession.coordinateOffset = {
                    x: NativeFloatWindow.windowX(hostPanel.handle) - origin.x,
                    y: NativeFloatWindow.windowY(hostPanel.handle) - origin.y
                };
                translatedPointer = {
                    x: event.relX + AssetDragSession.coordinateOffset.x,
                    y: event.relY + AssetDragSession.coordinateOffset.y
                };
                if (UiContext.dragLabel != null) {
                    UiContext.dragPointerOverride = translatedPointer;
                }
            }
            ctx.pointerOverride = {x: event.relX, y: event.relY};
            var panel = panels.get(bound.key);
            if (panel != null) {
                ctx.sizeOverride = {width: panel.width, height: panel.height};
            }
            UiTooltip.current = bound.tooltip;
            MenuDropdown.overlayLayer = bound.overlay;
            if (bound.events != null) {
                // Go through checkEvents(), not emitEvent(): capture-based widgets
                // (numeric drag fields, splitters) and focus/hover bookkeeping are
                // handled by checkEvents() before it calls emitEvent(). Bypassing
                // it broke drag gestures inside floating panels.
                @:privateAccess bound.events.pendingEvents.push(event);
                @:privateAccess bound.events.checkEvents();
            } else {
                bound.scene.handleEvent(event, null);
            }
            // The movement that crosses the threshold creates dragLabel inside
            // checkEvents(). Publish that same event's translated pointer now,
            // rather than waiting for a second WM_MOUSEMOVE (which otherwise
            // flashes the label at the main HWND's stale cursor position).
            if (UiContext.dragLabel != null && translatedPointer != null) {
                UiContext.dragPointerOverride = translatedPointer;
            }
        } catch (error:Dynamic) {
            restore();
            throw error;
        }
        restore();
    }

    function beginHeaderDrag(key:String):Void {
        var panel = panels.get(key);
        if (panel == null) return;
        dragging = {
            key: key,
            sx: NativeFloatWindow.cursorX(),
            sy: NativeFloatWindow.cursorY(),
            wx: NativeFloatWindow.windowX(panel.handle),
            wy: NativeFloatWindow.windowY(panel.handle)
        };
        dragCapturePanel = key;
        NativeFloatWindow.setCapture(panel.handle);
        if (onHeaderDrag != null) {
            onHeaderDrag(key, 0, dragging.sx, dragging.sy);
        }
    }

    function updateHeaderDrag(key:String):Void {
        if (dragging == null || dragging.key != key) return;
        var panel = panels.get(key);
        if (panel == null) return;
        var sx = NativeFloatWindow.cursorX();
        var sy = NativeFloatWindow.cursorY();
        NativeFloatWindow.moveWindow(panel.handle,
            dragging.wx + (sx - dragging.sx),
            dragging.wy + (sy - dragging.sy));
        if (onHeaderDrag != null) onHeaderDrag(key, 1, sx, sy);
    }

    function endHeaderDrag(key:String):Void {
        if (dragging == null || dragging.key != key) return;
        if (dragCapturePanel == key) dragCapturePanel = null;
        NativeFloatWindow.releaseCapture();
        var sx = NativeFloatWindow.cursorX();
        var sy = NativeFloatWindow.cursorY();
        dragging = null;
        if (onHeaderDrag != null) onHeaderDrag(key, 2, sx, sy);
    }

    function userClose(panel:FloatPanel):Void {
        if (panel.closed) return;
        panel.closed = true;
        push(panel.key, '{"cmd":"closed"}');
    }

    function updateHover(panel:FloatPanel, x:Int, y:Int):Void {
        var hover = isCloseBox(panel, x, y);
        if (hover != panel.hoverClose) {
            panel.hoverClose = hover;
            panel.dirty = true;
        }
    }

    function handleClick(panel:FloatPanel, x:Int, y:Int):Void {
        if (isCloseBox(panel, x, y)) {
            userClose(panel);
            return;
        }
        var header = headerHeight(panel);
        if (y < header) return;
        var index = Std.int((y - header - Math.round(4 * panel.scale))
            / lineHeight(panel));
        var rows = panel.rows;
        if (index < 0 || index >= rows.length) return;
        var id = Reflect.field(rows[index], "id");
        if (id == null) return;
        push(panel.key, haxe.Json.stringify({
            cmd: "edit",
            panelId: panel.panelId,
            id: Std.string(id),
            value: true
        }));
    }

    function scrollPanel(panel:FloatPanel, delta:Int):Void {
        var step = delta > 0 ? 1 : (delta < 0 ? -1 : 0);
        if (step == 0) return;
        var next = clampInt(panel.scroll + step, 0, maxScroll(panel));
        if (next != panel.scroll) {
            panel.scroll = next;
            panel.dirty = true;
        }
    }

    function push(key:String, text:String):Void {
        pending.push({key: key, text: text});
    }

    // ------------------------------------------------------------------
    // Snapshot plumbing
    // ------------------------------------------------------------------

    function refreshSnapshot(panel:FloatPanel):Void {
        if (onSnapshotRequest == null) return;
        var data:Dynamic = null;
        try {
            data = onSnapshotRequest(panel.panelId);
        } catch (error:Dynamic) {
            logError('snapshot: ${Std.string(error)}');
            return;
        }
        if (data != null) applySnapshot(panel, data);
    }

    function applySnapshot(panel:FloatPanel, data:Dynamic):Void {
        if (!Reflect.isObject(data)) return;
        panel.snapshot = data;
        var title = Reflect.field(data, "title");
        if (title != null) panel.title = Std.string(title);
        var rawLines = Reflect.field(data, "lines");
        if (rawLines != null && Std.isOfType(rawLines, Array)) {
            var lines:Array<String> = [];
            for (line in cast(rawLines, Array<Dynamic>)) lines.push(Std.string(line));
            panel.lines = lines;
            panel.scroll = clampScroll(panel);
        }
        var rawRows = Reflect.field(data, "rows");
        if (rawRows != null && Std.isOfType(rawRows, Array)) {
            panel.rows = cast rawRows;
            panel.scroll = clampScroll(panel);
        }
        panel.dirty = true;
    }

    // ------------------------------------------------------------------
    // Framebuffer rendering
    // ------------------------------------------------------------------

    function render(panel:FloatPanel):Void {
        var w = panel.width;
        var h = panel.height;
        if (w <= 0 || h <= 0) return;
        var pixels = panel.pixels;
        var header = headerHeight(panel);
        var line = lineHeight(panel);
        var pad = Std.int(Math.max(4, Math.round(8 * panel.scale)));

        fillRect(pixels, w, h, 0, 0, w, h, Theme.PANEL);
        drawHeader(panel);

        var rowY = header + Math.round(4 * panel.scale);
        if (panel.panelId == "boltspark.console" || panel.rows.length == 0) {
            var lines = panel.lines;
            var visible = Math.max(1, Std.int((h - rowY) / line));
            var start = clampInt(lines.length - visible - panel.scroll,
                0, Std.int(Math.max(0, lines.length - 1)));
            for (i in start...lines.length) {
                panel.atlas.drawLine(pixels, w, h, lines[i], pad,
                    rowY + line - Math.round(3 * panel.scale),
                    Theme.TEXT_SECONDARY);
                rowY += line;
                if (rowY >= h) break;
            }
        } else {
            var rows = panel.rows;
            var start = clampInt(panel.scroll, 0,
                Std.int(Math.max(0, rows.length - 1)));
            for (i in start...rows.length) {
                var row = rows[i];
                var selected = Reflect.field(row, "selected") == true;
                if (selected) {
                    fillRect(pixels, w, h, 1, rowY - 1, w - 2, line,
                        Theme.ACCENT_MUTED);
                }
                var depth = Std.int(numberField(row, "depth"));
                var label = Std.string(Reflect.field(row, "label"));
                var kind = Std.string(Reflect.field(row, "kind"));
                var indent = Std.int(pad + depth * Math.round(12 * panel.scale));
                if (kind == "action") {
                    fillRect(pixels, w, h, indent - Math.round(6 * panel.scale),
                        rowY + Math.round(6 * panel.scale),
                        Std.int(Math.max(2, Math.round(4 * panel.scale))),
                        Std.int(Math.max(2, Math.round(4 * panel.scale))),
                        Theme.ACCENT);
                }
                panel.atlas.drawLine(pixels, w, h, label, indent,
                    rowY + line - Math.round(3 * panel.scale),
                    selected ? Theme.TEXT : Theme.TEXT_SECONDARY);
                rowY += line;
                if (rowY >= h) break;
            }
        }
    }

    /** Small consistent title strip drawn above the live H2D panel content. */
    function drawHeader(panel:FloatPanel):Void {
        var w = panel.width;
        var h = panel.height;
        var pixels = panel.pixels;
        var header = headerHeight(panel);
        var pad = Std.int(Math.max(4, Math.round(8 * panel.scale)));
        fillRect(pixels, w, h, 0, 0, w, header, Theme.PANEL_HEADER);
        fillRect(pixels, w, h, 0, header, w, 1, Theme.BORDER);
        fillRect(pixels, w, h, 0, h - 1, w, 1, Theme.PANEL_EDGE);
        panel.atlas.drawLine(pixels, w, h, panel.title, pad,
            Math.round(header * 0.72), Theme.TEXT);
        var boxW = Math.round(20 * panel.scale);
        var boxH = Std.int(Math.max(10, header - Math.round(10 * panel.scale)));
        var boxX = w - boxW - pad;
        var boxY = Math.round((header - boxH) * 0.5);
        fillRect(pixels, w, h, boxX, boxY, boxW, boxH,
            panel.hoverClose ? Theme.ACCENT : Theme.BORDER);
        var mark = "x";
        panel.atlas.drawLine(pixels, w, h, mark,
            boxX + Math.round((boxW - panel.atlas.textWidth(mark)) * 0.5),
            boxY + boxH - Math.round(3 * panel.scale), Theme.PANEL);
    }

    function setFloatHeaderButton(key:String, button:Int):Void {
        var bound = boundViews.get(key);
        if (bound == null || bound.hoverButton == button) return;
        bound.hoverButton = button;
        drawFloatHeader(key);
    }

    function drawFloatHeader(key:String):Void {
        var bound = boundViews.get(key);
        var panel = panels.get(key);
        if (bound == null || panel == null) return;
        var g = bound.headerBg;
        var w = panel.width;
        var header = headerHeight(panel);
        g.clear();
        g.beginFill(Theme.PANEL_HEADER, 1);
        g.drawRect(0, 0, w, header);
        g.endFill();
        g.beginFill(Theme.BORDER, 1);
        g.drawRect(0, header - 1, w, 1);
        g.endFill();

        // Hover states mirror the editor's small toolbar buttons: raised
        // surface + stronger border, with the close button turning danger-tinted.
        function styleButton(surface:UiSurface, glyph:h2d.Graphics,
                icon:UiIconKind, active:Bool, danger:Bool):Void {
            surface.setStyle(active ? Theme.SURFACE_3 : Theme.SURFACE_2,
                active ? (danger ? Theme.DANGER : Theme.BORDER_STRONG)
                    : Theme.BORDER, 0);
            UiIcons.draw(glyph, icon, 0, 0, 12,
                active ? Theme.TEXT : Theme.TEXT_SECONDARY);
        }
        styleButton(bound.dockSurface, bound.dockIcon, DockPanel,
            bound.hoverButton == 3, false);
        styleButton(bound.minSurface, bound.minIcon, Minus,
            bound.hoverButton == 1, false);
        styleButton(bound.closeSurface, bound.closeIcon, Close,
            bound.hoverButton == 2, true);
    }

    function layoutBound(panel:FloatPanel, bound:BoundView):Void {
        // Several panel layouts rebuild their whole widget tree (the Asset
        // Browser rebuilds every tile/folder row). Doing that each frame wiped
        // hover state and made floats extremely slow, so only relayout on a
        // real geometry change.
        var key = '${panel.width}x${panel.height}x${panel.scale}';
        if (bound.layoutKey == key) return;
        bound.layoutKey = key;
        var header = headerHeight(panel);
        var w = panel.width;
        // Panel views assume an editor-body origin of TOP_BAR_HEIGHT; adding
        // the header here maps their internal header below our title strip.
        bound.view.layout(new LayoutRect(0, header, w,
            Math.max(1, panel.height - header)));
        bound.tooltip.boundsOverride = {
            width: panel.width, height: panel.height
        };
        bound.titleText.x = 10;
        bound.titleText.y = Std.int(Math.max(0,
            (header - bound.titleText.textHeight) * 0.5));
        var btnY = Std.int(Math.max(0, (header - 18) * 0.5));
        bound.dockHit.x = w - 74;
        bound.minHit.x = w - 50;
        bound.closeHit.x = w - 26;
        for (hit in [bound.dockHit, bound.minHit, bound.closeHit]) {
            hit.y = btnY;
            hit.width = 20;
            hit.height = 18;
        }
        var surfaces = [bound.dockSurface, bound.minSurface, bound.closeSurface];
        var icons = [bound.dockIcon, bound.minIcon, bound.closeIcon];
        var hits = [bound.dockHit, bound.minHit, bound.closeHit];
        for (i in 0...surfaces.length) {
            surfaces[i].x = hits[i].x;
            surfaces[i].y = hits[i].y;
            surfaces[i].setSize(hits[i].width, hits[i].height);
            icons[i].x = hits[i].x + 4;
            icons[i].y = hits[i].y + 3;
        }
        bound.hintText.x = 10;
        bound.hintText.y = Std.int(Math.max(0,
            (header - bound.hintText.textHeight) * 0.5));
        bound.hintText.visible = false;
        bound.dragHit.x = 0;
        bound.dragHit.y = 0;
        bound.dragHit.width = Math.max(1, w - 78);
        bound.dragHit.height = header;
        NativeFloatWindow.setHeaderHeight(panel.handle, header, w - 78);
        drawFloatHeader(panel.key);
    }

    /** Render the real view hierarchy offscreen and copy it to the GDI buffer. */
    function renderBound(panel:FloatPanel, bound:BoundView):Void {
        var w = panel.width;
        var h = panel.height;
        if (w <= 0 || h <= 0) return;
        if (bound.target == null || bound.target.width != w
                || bound.target.height != h) {
            if (bound.target != null) bound.target.dispose();
            bound.target = new Texture(w, h, [TextureFlags.Target]);
        }
        // One delayed relayout after binding catches content created later
        // (selection data, component sections) without rebuilding every frame.
        if (bound.forceLayout && haxe.Timer.stamp() - bound.bindTime > 0.25) {
            bound.forceLayout = false;
            bound.layoutKey = "";
        }
        layoutBound(panel, bound);
        // drawTo() does not run Scene.sync(). Synchronize first so a hover that
        // moves/shows text, a tooltip or rebuilt rows can never render one frame
        // with stale absolute transforms or stale glyph geometry.
        @:privateAccess bound.scene.sync(bound.scene.ctx);
        bound.target.clear(Theme.PANEL);
        bound.scene.drawTo(bound.target);
        var captured = bound.target.capturePixels();
        if (captured == null) return;
        try {
            if (captured.format != RGBA) captured.convert(RGBA);
            var count = w * h * 4;
            if (captured.width == w && captured.height == h
                    && captured.bytes.length >= count) {
                var src:hxd.impl.UncheckedBytes = captured.bytes;
                var dst:hxd.impl.UncheckedBytes = panel.pixels;
                var offset = captured.offset;
                // D3D readback is bottom-up; StretchDIBits with a negative height wants
                // top-down BGRA. The H2D header is part of the captured scene already.
                for (y in 0...h) {
                    var srcRow = offset + y * w * 4;
                    var dstRow = y * w * 4;
                    for (x in 0...w) {
                        var at = x * 4;
                        dst[dstRow + at] = src[srcRow + at + 2];
                        dst[dstRow + at + 1] = src[srcRow + at + 1];
                        dst[dstRow + at + 2] = src[srcRow + at];
                        dst[dstRow + at + 3] = src[srcRow + at + 3];
                    }
                }
            }
        } catch (error:Dynamic) {
            // capturePixels allocates a full CPU readback every repaint. Floats
            // repaint continuously, so relying on GC here creates substantial
            // transient pressure exactly while hover geometry is rebuilding.
            captured.dispose();
            throw error;
        }
        captured.dispose();
    }

    /** Fill a clipped rectangle using a native row blit per scanline. */
    static function fillRect(dest:Bytes, width:Int, height:Int, x:Int, y:Int,
            rectW:Int, rectH:Int, color:Int):Void {
        var x0 = clampInt(x, 0, width);
        var y0 = clampInt(y, 0, height);
        var x1 = clampInt(x + rectW, 0, width);
        var y1 = clampInt(y + rectH, 0, height);
        if (x1 <= x0 || y1 <= y0) return;
        var rowWidth = x1 - x0;
        var row = Bytes.alloc(rowWidth * 4);
        var r = (color >> 16) & 0xFF;
        var g = (color >> 8) & 0xFF;
        var b = color & 0xFF;
        for (i in 0...rowWidth) {
            var at = i * 4;
            row.set(at, b);
            row.set(at + 1, g);
            row.set(at + 2, r);
            row.set(at + 3, 255);
        }
        for (yy in y0...y1) {
            dest.blit((yy * width + x0) * 4, row, 0, rowWidth * 4);
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /** Render and blit immediately. Safe to call from the native event callback. */
    function repaint(panel:FloatPanel):Void {
        if (panel.closed) return;
        try {
            var bound = boundViews.get(panel.key);
            if (bound != null) {
                renderBound(panel, bound);
            } else {
                render(panel);
            }
            NativeFloatWindow.paint(panel.handle, @:privateAccess panel.pixels.b,
                panel.width, panel.height);
            panel.dirty = false;
        } catch (error:Dynamic) {
            logError('paint: ${Std.string(error)}');
        }
    }

    function syncNativeSize(panel:FloatPanel):Void {
        var width = NativeFloatWindow.clientWidth(panel.handle);
        var height = NativeFloatWindow.clientHeight(panel.handle);
        if (width > 0 && height > 0
                && (width != panel.width || height != panel.height)) {
            setPanelSize(panel, width, height);
        }
    }

    function setPanelSize(panel:FloatPanel, width:Int, height:Int):Void {
        if (width <= 0 || height <= 0) return;
        panel.width = width;
        panel.height = height;
        panel.pixels = Bytes.alloc(width * height * 4);
        panel.scroll = clampScroll(panel);
        panel.dirty = true;
        NativeFloatWindow.setHeaderHeight(panel.handle, headerHeight(panel),
            boundViews.exists(panel.key) ? panel.width - 52 : 0);
    }

    inline function headerHeight(panel:FloatPanel):Int {
        return Std.int(Math.max(18, Math.round(24 * panel.scale)));
    }

    inline function lineHeight(panel:FloatPanel):Int {
        return Std.int(Math.max(12, Math.round(17 * panel.scale)));
    }

    inline function isCloseBox(panel:FloatPanel, x:Int, y:Int):Bool {
        var boxW = Math.round(20 * panel.scale);
        var pad = Std.int(Math.max(4, Math.round(8 * panel.scale)));
        return x >= panel.width - boxW - pad && x <= panel.width - pad
            && y >= 2 && y <= headerHeight(panel) - 2;
    }

    function maxScroll(panel:FloatPanel):Int {
        var header = headerHeight(panel);
        var visible = Math.max(1, Std.int((panel.height - header) / lineHeight(panel)));
        var linesMax = Std.int(Math.max(0, panel.lines.length - visible));
        var rowsMax = Std.int(Math.max(0, panel.rows.length - visible));
        return Std.int(Math.max(linesMax, rowsMax));
    }

    inline function clampScroll(panel:FloatPanel):Int {
        return clampInt(panel.scroll, 0, maxScroll(panel));
    }

    static inline function clampInt(value:Float, min:Int, max:Int):Int {
        var result = Math.round(value);
        if (result < min) return min;
        if (result > max) return max;
        return result;
    }

    static inline function dpiScale(dpi:Int):Float {
        if (dpi <= 0) return 1;
        var scale = dpi / 96;
        return scale > 0.5 && scale < 4 ? scale : 1;
    }

    static inline function numberField(value:Dynamic, field:String):Float {
        var raw = Reflect.field(value, field);
        return Std.isOfType(raw, Float) || Std.isOfType(raw, Int)
            ? cast(raw, Float) : 0;
    }

    static function font():Bytes {
        if (fontBytes == null) {
            fontBytes = hxd.Res.fonts.jetbrains_mono.entry.getBytes();
        }
        return fontBytes;
    }

    function atlasFor(scale:Float):FloatGlyphAtlas {
        var size = Math.round(12 * scale);
        if (size < 9) size = 9;
        var cached = atlasCache.get(size);
        if (cached != null) return cached;
        var atlas = new FloatGlyphAtlas(font(), size);
        atlasCache.set(size, atlas);
        return atlas;
    }

    static function toNullTerminated(value:String):hl.Bytes {
        var source = Bytes.ofString(value);
        var result = Bytes.alloc(source.length + 1);
        result.blit(0, source, 0, source.length);
        result.set(source.length, 0);
        return @:privateAccess result.b;
    }

    static function logError(message:String):Void {
        Sys.println("[winfloat] " + message);
    }
}
