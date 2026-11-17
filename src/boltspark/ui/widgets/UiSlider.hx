package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/**
 * Compact editor slider shared by UI panels.
 *
 * Visual language: a thin recessed rail, a filled section in the same teal as
 * a selected button's border, a very small rectangular handle, and the current
 * value in an inset field. The whole rail is draggable, not just the handle.
 */
class UiSlider extends h2d.Object {
    public var onChange:Null<Float->Void>;

    static inline var HEIGHT:Float = 20;
    static inline var VALUE_WIDTH:Float = 56;
    static inline var RAIL_Y:Float = 9;
    static inline var RAIL_HEIGHT:Float = 3;

    final ctx:UiContext;
    final valueField:UiSurface;
    final track:h2d.Graphics;
    final valueText:UiText;
    final hit:h2d.Interactive;
    final suffix:String;
    var minValue:Float;
    var maxValue:Float;
    var currentValue:Float;
    var widthValue:Float;
    var railWidth:Float;

    public function new(ctx:UiContext, width:Float, min:Float, max:Float,
            initial:Float, suffix:String, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        this.suffix = suffix;
        minValue = min;
        maxValue = max > min ? max : min + 1;
        currentValue = Math.max(minValue, Math.min(maxValue, initial));

        valueField = new UiSurface(ctx, this);
        valueField.setStyle(Theme.FIELD_BG, Theme.BORDER, 0);
        track = new h2d.Graphics(this);
        valueText = new UiText(ctx.captionFont, this);
        valueText.textColor = Theme.ACCENT;
        valueText.lineBreak = false;
        hit = new h2d.Interactive(1, HEIGHT, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onPush = beginDrag;

        setWidth(width);
        setValue(currentValue);
    }

    public inline function getValue():Float return currentValue;

    public function setValue(value:Float):Void {
        var next = Math.max(minValue, Math.min(maxValue, value));
        if (next == currentValue) {
            redraw();
            return;
        }
        currentValue = next;
        redraw();
        if (onChange != null) onChange(currentValue);
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(80, width);
        railWidth = Math.max(40, widthValue - VALUE_WIDTH - 10);
        hit.width = railWidth;
        hit.height = HEIGHT;
        valueField.x = railWidth + 10;
        valueField.y = 1;
        valueField.setSize(VALUE_WIDTH, HEIGHT - 2);
        redraw();
    }

    function beginDrag(event:hxd.Event):Void {
        applyPointer(event.relX);
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    applyPointer(capturedEvent.relX);
                case ERelease, EReleaseOutside, EFocusLost:
                    hit.stopCapture();
                case _:
            }
            capturedEvent.propagate = false;
        });
        event.propagate = false;
    }

    function applyPointer(relX:Float):Void {
        var ratio = Math.max(0, Math.min(1, relX / railWidth));
        setValue(minValue + ratio * (maxValue - minValue));
    }

    function redraw():Void {
        var ratio = (currentValue - minValue) / (maxValue - minValue);
        var filled = ratio * railWidth;
        track.clear();
        // Inset rail and thin filled portion.
        track.beginFill(Theme.PANEL_EDGE);
        track.drawRect(0, RAIL_Y - 1, railWidth, RAIL_HEIGHT + 2);
        track.endFill();
        track.beginFill(Theme.SURFACE_3);
        track.drawRect(0, RAIL_Y, railWidth, RAIL_HEIGHT);
        track.endFill();
        track.beginFill(Theme.ACCENT);
        track.drawRect(0, RAIL_Y, filled, RAIL_HEIGHT);
        track.endFill();
        // Small thin rectangular handle with a one-pixel edge.
        var handleX = filled - 3;
        track.beginFill(Theme.PANEL_EDGE);
        track.drawRect(handleX - 1, RAIL_Y - 7, 8, 16);
        track.endFill();
        track.beginFill(Theme.ACCENT);
        track.drawRect(handleX, RAIL_Y - 6, 6, 14);
        track.endFill();

        valueText.text = '${Math.round(currentValue)}${suffix}';
        valueText.x = valueField.x
            + Math.round((VALUE_WIDTH - valueText.textWidth) * 0.5);
        valueText.y = Math.round((HEIGHT - 2 - valueText.textHeight) * 0.5);
    }
}
