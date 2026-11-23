package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.widgets.FieldSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;

/** Two-column inspector text field with commit-on-blur behavior. */
class TextInputField extends h2d.Object {
    public var onCommit:Null<String->Void>;
    public var onCancel:Null<Void->Void>;

    final label:h2d.Text;
    final fieldBackground:FieldSurface;
    final input:h2d.TextInput;
    var widthValue:Float;
    final heightValue:Float;
    var labelWidth:Float = 82;
    var focused:Bool = false;
    var lastCommitted:String;

    public function new(ctx:UiContext, labelText:String, width:Float, height:Float,
            initialValue:String, ?parent:h2d.Object) {
        super(parent);
        widthValue = width;
        heightValue = height;
        lastCommitted = initialValue;

        fieldBackground = new FieldSurface(this);
        label = new UiText(ctx.labelFont, this);
        label.text = labelText;
        label.textColor = Theme.TEXT_SECONDARY;
        label.lineBreak = false;

        input = new UiTextInput(ctx.font, this);
        input.text = initialValue;
        input.textColor = Theme.TEXT;
        input.useSoftwareKeyboard = false;
        input.onFocus = function(_) {
            focused = true;
            updateFieldStyle();
        };
        input.onFocusLost = function(_) {
            focused = false;
            updateFieldStyle();
            commitValue();
        };
        input.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ESCAPE) {
                input.text = lastCommitted;
                if (onCancel != null) onCancel();
            } else if (event.keyCode == hxd.Key.ENTER
                    || event.keyCode == hxd.Key.NUMPAD_ENTER) {
                commitValue();
            }
        };
        refresh();
    }

    public function setValue(value:String):Void {
        input.text = value;
        lastCommitted = value;
    }

    public inline function getValue():String return input.text;
    public inline function isFocused():Bool return focused;

    public function setLabelText(text:String):Void {
        label.text = text;
        refresh();
    }

    public function setLabelWidth(width:Float):Void {
        var next = Math.max(0, width);
        if (next == labelWidth) return;
        labelWidth = next;
        refresh();
    }

    public function setWidth(width:Float):Void {
        var next = Math.max(0, width);
        if (next == widthValue) return;
        widthValue = next;
        refresh();
    }

    function commitValue():Void {
        var current = input.text;
        if (current != lastCommitted) {
            lastCommitted = current;
            if (onCommit != null) onCommit(current);
        }
    }

    function refresh():Void {
        var fieldX = Math.min(labelWidth, widthValue);
        var fieldWidth = Math.max(0, widthValue - fieldX);
        label.x = 0;
        label.y = Math.max(0, Math.round((heightValue - label.textHeight) * 0.5 - 1));
        fieldBackground.x = fieldX;
        fieldBackground.setSize(fieldWidth, heightValue);
        input.x = fieldX + 6;
        input.y = Math.max(0, Math.round((heightValue - input.font.lineHeight) * 0.5 - 1));
        input.maxWidth = null;
        input.inputWidth = Std.int(Math.max(0, fieldWidth - 12));
        updateFieldStyle();
    }

    function updateFieldStyle():Void {
        fieldBackground.setStyle(
            focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            focused ? Theme.ACCENT : Theme.BORDER);
    }
}
