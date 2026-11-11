package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;

class ScrollBar extends h2d.Object {
    public var onChange:Null<Float->Void>;

    final context:UiContext;
    final trackSurface:UiSurface;
    final thumbSurface:UiSurface;
    final track:h2d.Interactive;
    final thumb:h2d.Interactive;
    var trackHeight:Float = 0;
    var thumbHeight:Float = 0;
    var scrollValue:Float = 0;
    var contentRatio:Float = 1;
    var dragPointerY:Float = 0;
    var dragScrollValue:Float = 0;
    var hovered:Bool = false;
    var dragging:Bool = false;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        trackSurface = new UiSurface(context, this);
        thumbSurface = new UiSurface(context, this);
        track = new h2d.Interactive(1, 1, this);
        track.backgroundColor = 0;
        track.cursor = hxd.Cursor.Button;
        track.onClick = function(event) {
            if (thumbHeight >= trackHeight || trackHeight <= 0) return;
            scrollValue = clamp01((event.relY - thumbHeight * 0.5) / (trackHeight - thumbHeight));
            refresh();
            if (onChange != null) onChange(scrollValue);
        };

        thumb = new h2d.Interactive(1, 1, this);
        thumb.backgroundColor = 0;
        thumb.cursor = hxd.Cursor.Button;
        thumb.onOver = function(_) {
            hovered = true;
            refresh();
        };
        thumb.onOut = function(_) {
            hovered = false;
            refresh();
        };
        thumb.onPush = function(_) beginDrag();
    }

    public function setBounds(x:Float, y:Float, width:Float, height:Float):Void {
        this.x = x;
        this.y = y;
        track.width = Math.max(0, width);
        track.height = Math.max(0, height);
        trackHeight = track.height;
        refresh();
    }

    public function setMetrics(visibleRatio:Float, value:Float):Void {
        contentRatio = clamp01(visibleRatio);
        scrollValue = clamp01(value);
        refresh();
    }

    function beginDrag():Void {
        if (thumbHeight >= trackHeight || trackHeight <= 0) return;
        dragging = true;
        dragPointerY = context.window.mouseY;
        dragScrollValue = scrollValue;
        refresh();
        thumb.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    var travel = trackHeight - thumbHeight;
                    if (travel > 0) {
                        scrollValue = clamp01(dragScrollValue
                            + (context.window.mouseY - dragPointerY) / travel);
                        refresh();
                        if (onChange != null) onChange(scrollValue);
                    }
                    event.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    dragging = false;
                    event.propagate = false;
                    thumb.stopCapture();
                    refresh();
                case _:
                    event.propagate = false;
            }
        });
    }

    function refresh():Void {
        var width = track.width;
        var enabled = contentRatio < 1 && trackHeight > 0;
        visible = enabled;
        thumbHeight = enabled
            ? Math.min(trackHeight, Math.max(28, trackHeight * contentRatio))
            : trackHeight;
        var travel = Math.max(0, trackHeight - thumbHeight);
        thumb.x = 0;
        thumb.y = travel * scrollValue;
        thumb.width = width;
        thumb.height = thumbHeight;

        trackSurface.setSize(width, trackHeight);
        trackSurface.setStyle(Theme.SCROLL_TRACK, Theme.SCROLL_TRACK, 0, 0);
        thumbSurface.x = 0;
        thumbSurface.y = thumb.y;
        thumbSurface.setSize(width, thumbHeight);
        var thumbColor = hovered || dragging ? Theme.SCROLL_THUMB_HOVER : Theme.SCROLL_THUMB;
        thumbSurface.setStyle(thumbColor, thumbColor, 0, 0);
    }

    static inline function clamp01(value:Float):Float {
        return Math.max(0, Math.min(1, value));
    }
}
