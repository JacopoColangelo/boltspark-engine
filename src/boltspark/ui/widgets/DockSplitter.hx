package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

/**
 * Draggable divider for editor dock regions.
 */
class DockSplitter extends h2d.Object {
    public var onDrag:Null<Float->Void>;
    public var onDragEnd:Null<Void->Void>;

    final context:UiContext;
    final vertical:Bool;
    final hit:h2d.Interactive;
    final graphic:h2d.Graphics;
    var dragging:Bool = false;
    var hovered:Bool = false;
    var lastPointer:Float = 0;
    var nativeCaptureActive:Bool = false;

    public function new(context:UiContext, vertical:Bool, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        this.vertical = vertical;

        graphic = new h2d.Graphics(this);
        hit = new h2d.Interactive(1, 1, this);
        hit.backgroundColor = 0;
        hit.cursor = vertical ? context.resizeHorizontal : context.resizeVertical;
        hit.onOver = function(_) {
            hovered = true;
            redraw(hit.width, hit.height);
        };
        hit.onOut = function(_) {
            hovered = false;
            if (!dragging) context.restoreArrowCursor();
            redraw(hit.width, hit.height);
        };
        hit.onPush = function(_) beginDrag();
    }

    public function setBounds(x:Float, y:Float, width:Float, height:Float):Void {
        this.x = x;
        this.y = y;
        hit.width = width;
        hit.height = height;
        redraw(width, height);
    }

    function beginDrag():Void {
        if (dragging) return;
        dragging = true;
        lastPointer = vertical ? context.mouseX : context.mouseY;
        redraw(hit.width, hit.height);
        hit.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    var pointer = vertical ? context.mouseX : context.mouseY;
                    var delta = pointer - lastPointer;
                    lastPointer = pointer;
                    if (delta != 0 && onDrag != null) onDrag(delta);
                    event.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    event.propagate = false;
                    hit.stopCapture();
                case _:
                    event.propagate = true;
            }
        }, finishDrag);
        // h2d capture only redirects events that actually reach Heaps. Win32
        // capture is required so a release after the cursor leaves the client
        // area is still delivered; otherwise the h2d capture above never ends
        // and the splitter keeps following the pointer with no button held.
        context.setMouseCapture(true);
        nativeCaptureActive = true;
    }

    function finishDrag():Void {
        dragging = false;
        releaseNativeCapture();
        if (!hovered) context.restoreArrowCursor();
        redraw(hit.width, hit.height);
        if (onDragEnd != null) onDragEnd();
    }

    function releaseNativeCapture():Void {
        if (!nativeCaptureActive) return;
        nativeCaptureActive = false;
        context.setMouseCapture(false);
    }

    function redraw(width:Float, height:Float):Void {
        graphic.clear();
        graphic.beginFill(dragging ? Theme.ACCENT : (hovered ? Theme.SPLITTER_HOVER : Theme.PANEL_EDGE));
        if (vertical)
            graphic.drawRect((width - Theme.SPLITTER_VISIBLE_WIDTH) / 2, 0, Theme.SPLITTER_VISIBLE_WIDTH, height);
        else
            graphic.drawRect(0, (height - Theme.SPLITTER_VISIBLE_WIDTH) / 2, width, Theme.SPLITTER_VISIBLE_WIDTH);
        graphic.endFill();
    }
}
