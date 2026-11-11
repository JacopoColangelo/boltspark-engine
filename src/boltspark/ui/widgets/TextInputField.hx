package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

/**
 * Compact text field for inspector and editor metadata. It exposes a focusable
 * input widget with an immutable label and commit-on-blur behavior.
 */
class TextInputField extends h2d.Object {
    public var onCommit:Null<String->Void>;
    public var onCancel:Null<Void->Void>;

    final label:h2d.Text;
    final fieldBackground:h2d.Graphics;
    final input:h2d.TextInput;
    var widthValue:Float;
    final heightValue:Float;
    var focused:Bool = false;
    var lastCommitted:String;

    public function new(ctx:UiContext, labelText:String, width:Float, height:Float, initialValue:String, ?parent:h2d.Object) {
        super(parent);
        widthValue = width;
        heightValue = height;
        lastCommitted = initialValue;

        label = new h2d.Text(ctx.font, this);
        label.text = labelText;
        label.textColor = Theme.MUTED;
        label.lineBreak = false;

        fieldBackground = new h2d.Graphics(this);
        input = new h2d.TextInput(ctx.font, this);
        input.text = initialValue;
        input.textColor = Theme.TEXT;
        input.inputWidth = Std.int(Math.max(0, width));
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
            } else if (event.keyCode == hxd.Key.ENTER) {
                commitValue();
            }
        };
        input.onChange = function() {
            updateFieldStyle();
        };

        refresh();
    }

    public function setValue(value:String):Void {
        input.text = value;
        lastCommitted = value;
    }

    public function getValue():String {
        return input.text;
    }

    public function isFocused():Bool {
        return focused;
    }

    public function setLabelText(text:String):Void {
        label.text = text;
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
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
        label.x = 0;
        label.y = 0;
        input.x = 0;
        input.y = label.textHeight + 8;
        fieldBackground.clear();
        fieldBackground.beginFill(focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG);
        fieldBackground.drawRect(0, label.textHeight + 8, widthValue, heightValue);
        fieldBackground.endFill();
        fieldBackground.lineStyle(1, focused ? Theme.ACCENT : Theme.PANEL_EDGE, 1);
        fieldBackground.drawRect(0, label.textHeight + 8, widthValue, heightValue);
        fieldBackground.lineStyle();

        label.maxWidth = null;
        label.lineBreak = false;
        input.x = 8;
        input.y = label.textHeight + 8 + Math.max(0, (heightValue - input.font.lineHeight) * 0.5);
        input.maxWidth = null;
        input.inputWidth = Std.int(Math.max(0, widthValue - 16));
    }

    function updateFieldStyle():Void {
        fieldBackground.clear();
        fieldBackground.beginFill(focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG);
        fieldBackground.drawRect(0, label.textHeight + 8, widthValue, heightValue);
        fieldBackground.endFill();
        fieldBackground.lineStyle(1, focused ? Theme.ACCENT : Theme.PANEL_EDGE, 1);
        fieldBackground.drawRect(0, label.textHeight + 8, widthValue, heightValue);
        fieldBackground.lineStyle();
    }
}
