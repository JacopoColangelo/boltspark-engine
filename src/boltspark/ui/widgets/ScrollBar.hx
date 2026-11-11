package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

class ScrollBar extends h2d.Object {
    public var onChange:Null<Float->Void>;

    final context:UiContext;
    final graphic:h2d.Graphics;
    final track:h2d.Interactive;
    final thumb:h2d.Interactive;
    var trackHeight:Float = 0;
    var thumbHeight:Float = 0;
    var scrollValue:Float = 0;
    var contentRatio:Float = 1;
    var dragPointerY:Float = 0;
    var dragScrollValue:Float = 0;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        graphic = new h2d.Graphics(this);
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
        thumb.cursor = hxd.Cursor.Move;
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
        dragPointerY = context.window.mouseY;
        dragScrollValue = scrollValue;
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
                    event.propagate = false;
                    thumb.stopCapture();
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
            ? Math.min(trackHeight, Math.max(24, trackHeight * contentRatio))
            : trackHeight;
        var travel = Math.max(0, trackHeight - thumbHeight);
        thumb.x = 0;
        thumb.y = travel * scrollValue;
        thumb.width = width;
        thumb.height = thumbHeight;

        graphic.clear();
        if (!enabled) return;
        graphic.beginFill(Theme.FIELD_BG);
        graphic.drawRect(0, 0, width, trackHeight);
        graphic.endFill();
        graphic.beginFill(Theme.SCROLL_THUMB);
        graphic.drawRect(0, thumb.y, width, thumbHeight);
        graphic.endFill();
        graphic.lineStyle(1, Theme.PANEL_EDGE, 1);
        graphic.drawRect(0, 0, width, trackHeight);
        graphic.lineStyle();
        thumb.visible = true;
    }

    static function clamp01(value:Float):Float {
        return Math.max(0, Math.min(1, value));
    }
}
