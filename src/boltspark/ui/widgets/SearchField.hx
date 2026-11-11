package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiIcons;
import boltspark.ui.widgets.FieldSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;

/** Compact search input used by hierarchy filtering. */
class SearchField extends h2d.Object {
    public var onChange:Null<String->Void>;

    final surface:FieldSurface;
    final icon:h2d.Graphics;
    final input:h2d.TextInput;
    final placeholder:h2d.Text;
    var widthValue:Float;
    final heightValue:Float;
    var focused:Bool = false;

    public function new(ctx:UiContext, placeholderText:String, width:Float, height:Float,
            ?parent:h2d.Object) {
        super(parent);
        widthValue = width;
        heightValue = height;
        surface = new FieldSurface(this);
        icon = new h2d.Graphics(this);
        UiIcons.draw(icon, Search, 0, 0, 14, Theme.MUTED);

        placeholder = new UiText(ctx.font, this);
        placeholder.text = placeholderText;
        placeholder.textColor = Theme.MUTED;
        placeholder.lineBreak = false;

        input = new UiTextInput(ctx.font, this);
        input.textColor = Theme.TEXT;
        input.useSoftwareKeyboard = false;
        input.onChange = function() {
            placeholder.visible = input.text.length == 0;
            if (onChange != null) onChange(input.text);
        };
        input.onFocus = function(_) {
            focused = true;
            redraw();
        };
        input.onFocusLost = function(_) {
            focused = false;
            redraw();
        };
        input.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ESCAPE && input.text.length > 0) {
                input.text = "";
                placeholder.visible = true;
                if (onChange != null) onChange("");
            }
        };
        layout();
    }

    public inline function isFocused():Bool return focused;

    public function setWidth(value:Float):Void {
        widthValue = Math.max(0, value);
        layout();
    }

    function layout():Void {
        surface.setSize(widthValue, heightValue);
        icon.x = 7;
        icon.y = (heightValue - 14) * 0.5;
        input.x = 27;
        input.y = Math.max(0, Math.round((heightValue - input.font.lineHeight) * 0.5 - 1));
        input.inputWidth = Std.int(Math.max(0, widthValue - 34));
        placeholder.x = input.x;
        placeholder.y = input.y;
        redraw();
    }

    function redraw():Void {
        surface.setStyle(focused ? Theme.FIELD_FOCUS : Theme.FIELD_BG,
            focused ? Theme.ACCENT : Theme.BORDER);
    }
}
