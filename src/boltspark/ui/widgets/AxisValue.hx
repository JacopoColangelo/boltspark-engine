package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.widgets.FieldSurface;

/**
 * Editable axis-aligned numeric field used by the inspector transform row.
 * Rendered as a dark inset field with a colored axis glyph on the left, in the
 * Unreal/CryEngine property-editor style. Commits on Enter or focus loss and
 * reports through onCommit(axisIndex handled by the owner).
 */
class AxisValue extends h2d.Object {
    public var onCommit:Null<Float->Void>;
    public var onEditRejected:Null<String->Void>;

    final surface:FieldSurface;
    final axis:h2d.Text;
    final input:h2d.TextInput;
    final heightValue:Float;
    var widthValue:Float;
    var value:Float = 0;
    var focused:Bool = false;
    var skipFocusCommit:Bool = false;

    public function new(ctx:UiContext, axisName:String, axisColor:Int, width:Float,
            height:Float, ?parent:h2d.Object) {
        super(parent);
        heightValue = height;
        surface = new FieldSurface(this);
        surface.setStyle(Theme.FIELD_BG, Theme.BORDER);

        axis = new h2d.Text(ctx.semiboldFont, this);
        axis.text = axisName;
        axis.textColor = axisColor;
        axis.lineBreak = false;

        input = new h2d.TextInput(ctx.monoFont, this);
        input.textColor = Theme.TEXT;
        input.lineBreak = false;
        input.useSoftwareKeyboard = false;
        input.onTextInput = function(event) {
            if (!allowsCharacter(event.charCode)) event.cancel = true;
        };
        input.onChange = updateFieldStyle;
        input.onFocus = function(_) {
            focused = true;
            updateFieldStyle();
        };
        input.onFocusLost = function(_) {
            focused = false;
            if (skipFocusCommit) {
                skipFocusCommit = false;
            } else {
                commitEdit();
            }
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

        setWidth(width);
        setValue(0);
    }

    public function setWidth(width:Float):Void {
        widthValue = Math.max(0, width);
        surface.setSize(widthValue, heightValue);
        axis.x = 6;
        axis.y = Math.max(0, Math.round((heightValue - axis.textHeight) * 0.5 - 1));
        input.x = 20;
        input.y = Math.max(0, Math.round((heightValue - input.font.lineHeight) * 0.5 - 1));
        input.inputWidth = Std.int(Math.max(0, widthValue - 25));
    }

    public function setValue(value:Float):Void {
        this.value = value;
        if (!focused) input.text = format(value);
    }

    public function isEditing():Bool {
        return focused;
    }

    static function format(value:Float):String {
        return Std.string(Math.round(value * 100) / 100);
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
        return ~/^-?\d*\.?\d*$/.match(candidate);
    }

    function commitEdit():Void {
        var entered = StringTools.trim(input.text);
        if (!~/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.match(entered)) {
            input.text = format(value);
            if (onEditRejected != null) onEditRejected("Enter a valid number.");
            return;
        }
        value = Std.parseFloat(entered);
        input.text = format(value);
        if (onCommit != null) onCommit(value);
    }

    function updateFieldStyle():Void {
        surface.setStyle(
            focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            focused ? Theme.ACCENT : Theme.BORDER);
    }
}
