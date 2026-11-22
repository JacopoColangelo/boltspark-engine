package boltspark.ui.dock;

import boltspark.ui.UiContext;
import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockPanelView.PanelSlot;

/**
 * Owns one panel-tab drag from press to release. Uses both H2D capture and the
 * native Win32 capture helper so the drag survives leaving the client area,
 * shows docking previews, and can be cancelled with Escape.
 */
class DockDragController {
    static inline var DRAG_THRESHOLD:Float = 5;

    final manager:DockingManager;
    final ctx:UiContext;
    final catcher:h2d.Interactive;

    var sourceTab:Null<TabNode> = null;
    var sourceIndex:Int = -1;
    var slot:Null<PanelSlot> = null;
    var startX:Float = 0;
    var startY:Float = 0;
    var pending:Bool = false;
    var active:Bool = false;
    var nativeCapture:Bool = false;
    var plan:Null<DockDropPlan> = null;

    public var isActive(default, null):Bool = false;

    public function new(manager:DockingManager, ctx:UiContext, overlayLayer:h2d.Object) {
        this.manager = manager;
        this.ctx = ctx;
        catcher = new h2d.Interactive(1, 1, overlayLayer);
        catcher.backgroundColor = 0;
        catcher.cursor = hxd.Cursor.Default;
        catcher.visible = false;
    }

    public function begin(tab:TabNode, index:Int, x:Float, y:Float):Void {
        if (pending || isActive) return;
        var candidate = index >= 0 && index < tab.slots.length ? tab.slots[index] : null;
        if (candidate == null || candidate.locked) return;
        sourceTab = tab;
        sourceIndex = index;
        slot = candidate;
        startX = x;
        startY = y;
        pending = true;
        isActive = true;
        installCapture();
    }

    function installCapture():Void {
        catcher.x = 0;
        catcher.y = 0;
        catcher.width = ctx.width;
        catcher.height = ctx.height;
        catcher.visible = true;
        catcher.startCapture(onCaptured, cancel);
        if (!nativeCapture) {
            ctx.setMouseCapture(true);
            nativeCapture = true;
        }
    }

    function onCaptured(event:hxd.Event):Void {
        switch (event.kind) {
            case EMove:
                var x = ctx.mouseX;
                var y = ctx.mouseY;
                if (!active) {
                    var distance = Math.sqrt((x - startX) * (x - startX)
                        + (y - startY) * (y - startY));
                    if (distance < DRAG_THRESHOLD) return;
                    active = true;
                }
                updatePreview(x, y);
                event.propagate = false;
            case ERelease, EReleaseOutside:
                var committable = active;
                var x = ctx.mouseX;
                var y = ctx.mouseY;
                if (committable) {
                    updatePreview(x, y);
                    commit();
                } else if (sourceTab != null && sourceIndex >= 0) {
                    sourceTab.activeIndex = sourceIndex;
                    manager.onTabActivated();
                }
                finish();
                event.propagate = false;
            case EFocusLost:
                cancel();
                event.propagate = false;
            case EKeyDown:
                if (event.keyCode == hxd.Key.ESCAPE) cancel();
                event.propagate = false;
            case _:
                event.propagate = true;
        }
    }

    function updatePreview(x:Float, y:Float):Void {
        if (slot == null) return;
        plan = manager.resolveDrop(slot, x, y, sourceTab);
        if (plan == null) {
            manager.renderer.setPreview(null);
            manager.renderer.setDragGhost(null, x, y);
            return;
        }
        manager.renderer.setPreview(plan.preview);
        var descriptor = manager.registry.descriptor(slot.view.panelId);
        var label = descriptor == null ? slot.view.panelId : descriptor.displayName;
        manager.renderer.setDragGhost(label, x, y);
    }

    function commit():Void {
        if (plan == null || slot == null) return;
        if (plan.floating) {
            manager.floatSlot(slot, plan.preview.rect);
        } else if (plan.target != null) {
            if (plan.side == DockSide.Center && sourceTab == plan.target
                    && sourceIndex >= 0) {
                manager.reorder(plan.target, sourceIndex, plan.index);
            } else {
                manager.moveSlot(slot, plan.target, plan.side, plan.index);
            }
        }
    }

    public function cancel():Void {
        if (!isActive) return;
        plan = null;
        manager.renderer.setPreview(null);
        manager.renderer.setDragGhost(null, 0, 0);
        finish();
    }

    function finish():Void {
        // Clear the guard first: stopCapture() may invoke the cancel callback.
        isActive = false;
        pending = false;
        active = false;
        // A committed drop must clear the feedback just like a cancel does.
        manager.renderer.setPreview(null);
        manager.renderer.setDragGhost(null, 0, 0);
        if (nativeCapture) {
            ctx.setMouseCapture(false);
            nativeCapture = false;
        }
        catcher.visible = false;
        catcher.stopCapture();
        sourceTab = null;
        sourceIndex = -1;
        slot = null;
        plan = null;
        ctx.restoreArrowCursor();
    }
}
