package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

/**
 * Numeric stepper widget: [-] value [+].
 *
 * Edits a bounded float in fixed steps and reports changes through
 * onValueChanged. Used by the inspector for editable object properties.
 */
class Stepper extends h2d.Object {
    public var onValueChanged:Null<Float->Void>;
    public var onEditRejected:Null<String->Void>;

    public var value(default, null):Float;
    public final min:Float;
    public final max:Float;
    public final step:Float;

    final minus:UiButton;
    final plus:UiButton;
    final valueInput:h2d.TextInput;
    final fieldBackground:FieldSurface;
    final format:Float->String;
    var width:Float;
    final height:Float;
    var fieldFocused:Bool = false;

    public function new(ctx:UiContext, w:Float, h:Float,
            min:Float, max:Float, step:Float, initial:Float,
            format:Float->String, ?parent:h2d.Object) {
        super(parent);
        this.width = w;
        this.height = h;
        this.min = min;
        this.max = max;
        this.step = step;
        this.value = initial;
        this.format = format;

        var buttonSize = h;
        fieldBackground = new FieldSurface(this);
        minus = new UiButton(ctx, "-", buttonSize, h, this);
        minus.setQuiet();
        minus.onClick = function() {
            value = clamp(value - step);
            refresh(true);
        };

        plus = new UiButton(ctx, "+", buttonSize, h, this);
        plus.setQuiet();
        plus.onClick = function() {
            value = clamp(value + step);
            refresh(true);
        };

        valueInput = new h2d.TextInput(ctx.monoFont, this);
        valueInput.textColor = Theme.TEXT;
        valueInput.lineBreak = false;
        valueInput.inputWidth = Std.int(Math.max(0, width - buttonSize * 2 - 12));
        valueInput.useSoftwareKeyboard = false;
        valueInput.onTextInput = function(event) {
            if (!allowsCharacter(event.charCode)) event.cancel = true;
        };
        valueInput.onChange = updateFieldStyle;
        valueInput.onFocus = function(_) {
            fieldFocused = true;
            updateFieldStyle();
        };
        valueInput.onFocusLost = function(_) {
            fieldFocused = false;
            if (skipFocusCommit) {
                skipFocusCommit = false;
            } else {
                commitEdit();
            }
            updateFieldStyle();
        };
        valueInput.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ENTER || event.keyCode == hxd.Key.NUMPAD_ENTER) {
                skipFocusCommit = true;
                commitEdit();
            } else if (event.keyCode == hxd.Key.ESCAPE) {
                skipFocusCommit = true;
                valueInput.text = format(value);
            }
        };

        refresh();
    }

    public function setValue(v:Float):Void {
        value = clamp(v);
        refresh();
    }

    public function setWidth(w:Float):Void {
        width = Math.max(0, w);
        refresh();
    }

    public function isEditing():Bool {
        return fieldFocused;
    }

    function clamp(v:Float):Float {
        if (v < min) v = min;
        if (v > max) v = max;
        return v;
    }

    function refresh(notify:Bool = false):Void {
        valueInput.text = format(value);
        var buttonSize = height;
        minus.setPosition(0, 0);
        plus.setPosition(width - buttonSize, 0);
        valueInput.x = buttonSize + 6;
        valueInput.y = Math.max(0, (height - valueInput.font.lineHeight) / 2);
        valueInput.maxWidth = null;
        valueInput.inputWidth = Std.int(Math.max(0, width - buttonSize * 2 - 12));
        fieldBackground.x = buttonSize + 4;
        fieldBackground.setSize(Math.max(0, width - buttonSize * 2 - 8), height);
        updateFieldStyle();
        if (notify && onValueChanged != null) onValueChanged(value);
    }

    var skipFocusCommit:Bool = false;

    function allowsCharacter(charCode:Int):Bool {
        if (charCode == 0) return true;
        var char = String.fromCharCode(charCode);
        if (char != "." && char != "-" && (char < "0" || char > "9")) return false;
        var start = valueInput.cursorIndex;
        var end = start;
        if (valueInput.selectionRange != null) {
            start = valueInput.selectionRange.start;
            end = start + valueInput.selectionRange.length;
        }
        var candidate = valueInput.text.substr(0, start) + char + valueInput.text.substr(end);
        if (min >= 0 && candidate.indexOf("-") >= 0) return false;
        return ~/^-?\d*\.?\d*$/.match(candidate);
    }

    function commitEdit():Void {
        var entered = StringTools.trim(valueInput.text);
        if (!~/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.match(entered)) {
            valueInput.text = format(value);
            if (onEditRejected != null) onEditRejected("Enter a valid number.");
            return;
        }

        var parsed = Std.parseFloat(entered);
        if (parsed < min || parsed > max) {
            valueInput.text = format(value);
            if (onEditRejected != null) onEditRejected('Value must be between ${min} and ${max}.');
            return;
        }

        value = parsed;
        refresh();
        if (onValueChanged != null) onValueChanged(value);
    }

    function updateFieldStyle():Void {
        fieldBackground.setStyle(
            fieldFocused ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            fieldFocused ? Theme.ACCENT : Theme.BORDER);
    }
}
