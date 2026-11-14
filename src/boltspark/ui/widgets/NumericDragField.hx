package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;
import boltspark.ui.UiIcons;

/**
 * Compact DCC-style numeric editor.
 *
 * A click focuses the text value, horizontal drag scrubs it in fixed steps,
 * and the narrow right column provides conventional up/down step arrows.
 */
class NumericDragField extends h2d.Object {
    static inline var ARROW_WIDTH:Float = 15;
    static inline var SCRUB_THRESHOLD:Float = 3;
    static inline var PIXELS_PER_STEP:Float = 6;

    public var onValueChanged:Null<Float->Void>;
    public var onEditRejected:Null<String->Void>;

    public var value(default, null):Float;
    public final min:Float;
    public final max:Float;
    public final step:Float;

    final context:UiContext;
    final surface:FieldSurface;
    final prefix:h2d.Text;
    final input:h2d.TextInput;
    final arrowGraphic:h2d.Graphics;
    final upArrow:h2d.Graphics;
    final downArrow:h2d.Graphics;
    final scrubHit:h2d.Interactive;
    final upHit:h2d.Interactive;
    final downHit:h2d.Interactive;
    final format:Float->String;
    final heightValue:Float;

    var widthValue:Float;
    var focused:Bool = false;
    var dragging:Bool = false;
    var nativeCaptureActive:Bool = false;
    var unboundedScrub:Bool = false;
    var endingCapture:Bool = false;
    var skipFocusCommit:Bool = false;
    var scrubStartX:Float = 0;
    var scrubStartValue:Float = 0;
    var upHovered:Bool = false;
    var downHovered:Bool = false;

    public function new(ctx:UiContext, width:Float, height:Float,
            min:Float, max:Float, step:Float, initial:Float,
            format:Float->String, prefixText:String = "", prefixColor:Int = Theme.TEXT,
            ?parent:h2d.Object) {
        super(parent);
        context = ctx;
        widthValue = width;
        heightValue = height;
        this.min = min;
        this.max = max;
        this.step = Math.max(0.000001, step);
        this.format = format;
        value = clamp(initial);

        surface = new FieldSurface(this);

        prefix = new UiText(ctx.semiboldFont, this);
        prefix.text = prefixText;
        prefix.textColor = prefixColor;
        prefix.lineBreak = false;

        input = new UiTextInput(ctx.monoFont, this);
        input.text = format(value);
        input.textColor = Theme.TEXT;
        input.lineBreak = false;
        input.useSoftwareKeyboard = false;
        input.onTextInput = function(event) {
            if (!allowsCharacter(event.charCode)) event.cancel = true;
        };
        input.onChange = updateFieldStyle;
        input.onFocus = function(_) {
            focused = true;
            scrubHit.visible = false;
            context.showTextInputCursor();
            updateFieldStyle();
        };
        input.onFocusLost = function(_) {
            focused = false;
            scrubHit.visible = true;
            if (skipFocusCommit) skipFocusCommit = false else commitEdit();
            updateFieldStyle();
        };
        input.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ENTER || event.keyCode == hxd.Key.NUMPAD_ENTER) {
                skipFocusCommit = true;
                commitEdit();
            } else if (event.keyCode == hxd.Key.ESCAPE) {
                skipFocusCommit = true;
                input.text = format(value);
            }
        };

        arrowGraphic = new h2d.Graphics(this);
        upArrow = new h2d.Graphics(this);
        downArrow = new h2d.Graphics(this);

        scrubHit = new h2d.Interactive(1, height, this);
        scrubHit.backgroundColor = 0;
        scrubHit.cursor = ctx.resizeHorizontal;
        scrubHit.onPush = beginScrub;
        scrubHit.onOut = function(_) {
            // The hldx resize cursor is installed by a native callback. Force
            // the Win32 arrow back because Heaps can otherwise keep its
            // cached Default cursor while the native SizeWE cursor remains.
            if (!dragging) context.restoreArrowCursor();
        };

        upHit = new h2d.Interactive(1, 1, this);
        upHit.backgroundColor = 0;
        upHit.cursor = hxd.Cursor.Default;
        upHit.onOver = function(_) {
            upHovered = true;
            redrawArrows();
        };
        upHit.onOut = function(_) {
            upHovered = false;
            redrawArrows();
        };
        upHit.onClick = function(_) stepBy(1);

        downHit = new h2d.Interactive(1, 1, this);
        downHit.backgroundColor = 0;
        downHit.cursor = hxd.Cursor.Default;
        downHit.onOver = function(_) {
            downHovered = true;
            redrawArrows();
        };
        downHit.onOut = function(_) {
            downHovered = false;
            redrawArrows();
        };
        downHit.onClick = function(_) stepBy(-1);

        refreshLayout();
    }

    public function setValue(next:Float):Void {
        value = clamp(next);
        if (!focused && !dragging) input.text = format(value);
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        refreshLayout();
    }

    public inline function isEditing():Bool return focused || dragging;

    function beginScrub(event:hxd.Event):Void {
        if (event.button != 0) return;
        dragging = false;
        scrubStartX = context.window.mouseX;
        scrubStartValue = value;
        scrubHit.startCapture(function(captured) {
            switch (captured.kind) {
                case EMove:
                    var delta = context.window.mouseX - scrubStartX;
                    if (!dragging && Math.abs(delta) >= SCRUB_THRESHOLD) {
                        dragging = true;
                        beginUnboundedScrub();
                    }
                    if (dragging) {
                        var steps = Math.round(delta / PIXELS_PER_STEP);
                        applyValue(scrubStartValue + steps * step, true);
                    }
                    captured.propagate = false;
                case ERelease, EReleaseOutside:
                    var pointerInside = captured.relX >= 0 && captured.relX < scrubHit.width
                        && captured.relY >= 0 && captured.relY < scrubHit.height;
                    var wasDragging = dragging;
                    endScrubCapture();
                    dragging = false;
                    if (!wasDragging && pointerInside) {
                        focusInput();
                    } else if (!pointerInside) {
                        context.restoreArrowCursor();
                    }
                    captured.propagate = false;
                case EFocusLost:
                    dragging = false;
                    endScrubCapture();
                    context.restoreArrowCursor();
                    captured.propagate = false;
                case _:
                    captured.propagate = false;
            }
        }, onScrubCaptureCancelled);
        // Heaps capture above redirects scene events, while native capture
        // makes Win32 continue sending those events outside a windowed client.
        context.setMouseCapture(true);
        nativeCaptureActive = true;
        event.propagate = false;
    }

    function endScrubCapture():Void {
        endUnboundedScrub();
        endingCapture = true;
        scrubHit.stopCapture();
        endingCapture = false;
        releaseNativeCapture();
    }

    function onScrubCaptureCancelled():Void {
        endUnboundedScrub();
        releaseNativeCapture();
        if (endingCapture) return;
        dragging = false;
        context.restoreArrowCursor();
    }

    function releaseNativeCapture():Void {
        if (!nativeCaptureActive) return;
        nativeCaptureActive = false;
        context.setMouseCapture(false);
    }

    /** Switch from finite screen coordinates to hldx raw mouse deltas. */
    function beginUnboundedScrub():Void {
        unboundedScrub = false;
        try {
            // AbsoluteUnbound keeps feeding virtual absolute EMove positions
            // into the existing h2d capture while hldx hides/clips the OS
            // cursor and obtains motion from Windows Raw Input. This is the
            // same edge-independent input path used by viewport gizmo drags.
            context.window.mouseMode = hxd.impl.MouseMode.AbsoluteUnbound(true);
            unboundedScrub = switch (context.window.mouseMode) {
                case AbsoluteUnbound(_): true;
                case _: false;
            };
            if (!unboundedScrub) {
                Sys.println('[numeric] unbounded mouse mode was rejected; using absolute fallback');
            }
        } catch (error:Dynamic) {
            Sys.println('[numeric] unbounded mouse mode unavailable: ${Std.string(error)}');
        }
    }

    function endUnboundedScrub():Void {
        if (!unboundedScrub) return;
        // Preserve the virtual endpoint before Absolute mode stops consuming
        // raw deltas. The locked hldx path does not restore this position, so
        // park the visible cursor explicitly just like the transform gizmo.
        var endX = context.window.mouseX;
        var endY = context.window.mouseY;
        unboundedScrub = false;
        try {
            context.window.mouseMode = hxd.impl.MouseMode.Absolute;
            context.window.setCursorPos(Math.round(endX), Math.round(endY));
        } catch (error:Dynamic) {
            Sys.println('[numeric] mouse mode restore failed: ${Std.string(error)}');
        }
    }

    function focusInput():Void {
        input.focus();
        context.showTextInputCursor();
    }

    function stepBy(direction:Int):Void {
        applyValue(value + direction * step, true);
    }

    function applyValue(next:Float, notify:Bool):Void {
        var clamped = clamp(next);
        // Keep repeated fractional steps stable enough for exact display and
        // command comparisons without changing the configured step itself.
        // Round only the fractional remainder: multiplying the complete value
        // by 1,000,000 overflowed HashLink's 32-bit Math.round result above
        // 2147.483647 and could turn a large positive transform negative.
        clamped = stableRound(clamped);
        var changed = Math.abs(clamped - value) > 0.0000001;
        value = clamped;
        input.text = format(value);
        if (notify && changed && onValueChanged != null) {
            onValueChanged(value);
            // Command handlers can synchronously constrain a transform and
            // push the applied value back through setValue(). Reflect that
            // result immediately instead of leaving the requested value in a
            // focused field until it is selected again.
            input.text = format(value);
        }
    }

    function commitEdit():Void {
        var entered = StringTools.trim(input.text);
        if (!~/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.match(entered)) {
            input.text = format(value);
            if (onEditRejected != null) onEditRejected("Enter a valid number.");
            return;
        }
        var parsed = Std.parseFloat(entered);
        if (!Math.isFinite(parsed)) {
            input.text = format(value);
            if (onEditRejected != null) onEditRejected("Enter a finite number.");
            return;
        }
        if (parsed < min || parsed > max) {
            input.text = format(value);
            if (onEditRejected != null) onEditRejected('Value must be between ${min} and ${max}.');
            return;
        }
        applyValue(parsed, true);
    }

    function allowsCharacter(charCode:Int):Bool {
        if (charCode == 0) return true;
        var char = String.fromCharCode(charCode);
        if (char != "." && char != "-" && (char < "0" || char > "9")) return false;
        var start = input.cursorIndex;
        var end = start;
        if (input.selectionRange != null) {
            start = input.selectionRange.start;
            end = start + input.selectionRange.length;
        }
        var candidate = input.text.substr(0, start) + char + input.text.substr(end);
        if (min >= 0 && candidate.indexOf("-") >= 0) return false;
        return ~/^-?\d*\.?\d*$/.match(candidate);
    }

    function clamp(next:Float):Float {
        if (next < min) return min;
        if (next > max) return max;
        return next;
    }

    static function stableRound(value:Float):Float {
        if (!Math.isFinite(value) || Math.abs(value) >= 1000000) return value;
        var whole = value < 0 ? Math.ceil(value) : Math.floor(value);
        return whole + Math.round((value - whole) * 1000000) / 1000000;
    }

    function refreshLayout():Void {
        surface.setSize(widthValue, heightValue);
        var arrowWidth = Math.min(ARROW_WIDTH, Math.max(0, widthValue));
        var prefixWidth = prefix.text.length == 0 ? 0.0 : 20.0;
        prefix.x = 6;
        prefix.y = Math.max(0, Math.round((heightValue - prefix.textHeight) * 0.5 - 1));
        input.x = prefixWidth + 6;
        input.y = Math.max(0, Math.round((heightValue - input.font.lineHeight) * 0.5 - 1));
        input.maxWidth = null;
        input.inputWidth = Std.int(Math.max(0,
            widthValue - arrowWidth - prefixWidth - 10));

        scrubHit.x = 0;
        scrubHit.y = 0;
        scrubHit.width = Math.max(0, widthValue - arrowWidth);
        scrubHit.height = heightValue;

        var half = heightValue * 0.5;
        upHit.x = widthValue - arrowWidth;
        upHit.y = 0;
        upHit.width = arrowWidth;
        upHit.height = half;
        downHit.x = widthValue - arrowWidth;
        downHit.y = half;
        downHit.width = arrowWidth;
        downHit.height = heightValue - half;
        updateFieldStyle();
        redrawArrows();
    }

    function updateFieldStyle():Void {
        surface.setStyle(
            focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            focused ? Theme.ACCENT : Theme.BORDER);
    }

    function redrawArrows():Void {
        arrowGraphic.clear();
        upArrow.removeChildren();
        downArrow.removeChildren();
        if (widthValue <= 0 || heightValue <= 0) return;
        var arrowWidth = Math.min(ARROW_WIDTH, widthValue);
        var x = widthValue - arrowWidth;
        var half = heightValue * 0.5;

        arrowGraphic.beginFill(Theme.SURFACE_1);
        arrowGraphic.drawRect(x + 1, 1, Math.max(0, arrowWidth - 2), Math.max(0, heightValue - 2));
        arrowGraphic.endFill();
        if (upHovered) {
            arrowGraphic.beginFill(Theme.SURFACE_3);
            arrowGraphic.drawRect(x + 1, 1, Math.max(0, arrowWidth - 2), Math.max(0, half - 1));
            arrowGraphic.endFill();
        }
        if (downHovered) {
            arrowGraphic.beginFill(Theme.SURFACE_3);
            arrowGraphic.drawRect(x + 1, half, Math.max(0, arrowWidth - 2), Math.max(0, heightValue - half - 1));
            arrowGraphic.endFill();
        }
        arrowGraphic.lineStyle(1, Theme.BORDER, 1);
        arrowGraphic.moveTo(x + 0.5, 1);
        arrowGraphic.lineTo(x + 0.5, heightValue - 1);
        arrowGraphic.moveTo(x + 1, half);
        arrowGraphic.lineTo(widthValue - 1, half);
        arrowGraphic.lineStyle();

        var centerX = x + arrowWidth * 0.5;
        var upY = half * 0.5;
        var downY = half + (heightValue - half) * 0.5;
        upArrow.clear();
        UiIcons.draw(upArrow, ChevronUp, 0, 0, 8,
            upHovered ? Theme.TEXT : Theme.MUTED);
        upArrow.x = Math.round(centerX - 4);
        upArrow.y = Math.round(upY - 4);
        downArrow.clear();
        UiIcons.draw(downArrow, ChevronDown, 0, 0, 8,
            downHovered ? Theme.TEXT : Theme.MUTED);
        downArrow.x = Math.round(centerX - 4);
        downArrow.y = Math.round(downY - 4);
    }
}
