package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiTextInput;
import hxd.Key;

/**
 * Compact editor slider with a typeable numeric readout.
 *
 * Visual language: a thin recessed rail, a filled section in the same teal as
 * a selected button's border, a very small rectangular handle, and the current
 * value in an inset field. The rail is draggable; the inset field is a real
 * text input so an exact value can be typed and committed with Enter.
 */
class UiSlider extends h2d.Object {
    public var onChange:Null<Float->Void>;
    /** Decimal places used by the inset value readout. */
    public var displayDecimals:Int = 0;

    static inline var HEIGHT:Float = 20;
    static inline var VALUE_WIDTH:Float = 56;
    static inline var RAIL_Y:Float = 9;
    static inline var RAIL_HEIGHT:Float = 3;

    final ctx:UiContext;
    final valueField:UiSurface;
    final track:h2d.Graphics;
    final valueInput:UiTextInput;
    final valueHit:h2d.Interactive;
    final hit:h2d.Interactive;
    final suffix:String;
    var minValue:Float;
    var maxValue:Float;
    var currentValue:Float;
    var widthValue:Float;
    var railWidth:Float;
    var editing:Bool = false;

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
        valueInput = new UiTextInput(ctx.monoFont, this);
        valueInput.textColor = Theme.ACCENT;
        valueInput.lineBreak = false;
        valueInput.useSoftwareKeyboard = false;
        valueInput.onFocus = function(_) {
            editing = true;
            valueField.setStyle(Theme.FIELD_FOCUS, Theme.ACCENT);
        };
        valueInput.onFocusLost = function(_) {
            editing = false;
            commitText();
            valueField.setStyle(Theme.FIELD_BG, Theme.BORDER);
        };
        valueInput.onKeyDown = function(event) {
            if (event.keyCode == Key.ENTER || event.keyCode == Key.NUMPAD_ENTER) {
                commitText();
                blurValueInput();
                event.propagate = false;
            } else if (event.keyCode == Key.ESCAPE) {
                valueInput.text = formatValue(currentValue);
                blurValueInput();
                event.propagate = false;
            }
        };
        valueHit = new h2d.Interactive(VALUE_WIDTH, HEIGHT - 2, this);
        valueHit.backgroundColor = 0;
        valueHit.cursor = hxd.Cursor.TextInput;
        // This catch sits above the TextInput's own interactive; without
        // propagation it would swallow ETextInput/EKeyDown events.
        valueHit.propagateEvents = true;
        valueHit.onPush = function(_) valueInput.focus();

        hit = new h2d.Interactive(1, HEIGHT, this);
        hit.backgroundColor = 0;
        // Same horizontal-scrub affordance as NumericDragField, including the
        // native hldx resize cursor rather than the generic pointing hand.
        hit.cursor = ctx.resizeHorizontal;
        hit.onOut = function(_) {
            if (!editing) ctx.restoreArrowCursor();
        };
        hit.onPush = beginDrag;

        setWidth(width);
        redraw();
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
        var next = Math.max(80, width);
        if (next == widthValue) return;
        widthValue = next;
        railWidth = Math.max(40, widthValue - VALUE_WIDTH - 10);
        hit.width = railWidth;
        hit.height = HEIGHT;
        valueField.x = railWidth + 10;
        valueField.y = 1;
        valueField.setSize(VALUE_WIDTH, HEIGHT - 2);
        valueHit.x = valueField.x;
        valueHit.y = valueField.y;
        valueInput.x = valueField.x + 5;
        valueInput.y = Math.max(0, Math.round((HEIGHT - 2 - valueInput.font.lineHeight) * 0.5));
        valueInput.inputWidth = Std.int(Math.max(8, VALUE_WIDTH - 10));
        redraw();
    }

    function beginDrag(event:hxd.Event):Void {
        if (editing) return;
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

    inline function formatValue(value:Float):String {
        var decimals = displayDecimals < 0 ? 0 : (displayDecimals > 4 ? 4 : displayDecimals);
        var scale = Math.pow(10, decimals);
        return '${Math.round(value * scale) / scale}${suffix}';
    }

    function blurValueInput():Void {
        var scene = getScene();
        if (scene == null) return;
        var focused = scene.getFocus();
        if (focused != null) focused.blur();
    }

    function commitText():Void {
        var parsed = Std.parseFloat(StringTools.trim(valueInput.text));
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] slider commit text=${valueInput.text}'
                + ' parsed=${parsed} focused=${valueInput.hasFocus()}');
        }
        if (Math.isFinite(parsed)) {
            setValue(parsed);
        } else {
            valueInput.text = formatValue(currentValue);
        }
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
        if (!editing) valueInput.text = formatValue(currentValue);
    }
}
