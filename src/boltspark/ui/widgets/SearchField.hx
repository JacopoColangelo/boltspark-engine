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
    /** h2d.TextInput clips its text horizontally but not its selection rect,
     *  which otherwise spills above and below the field frame. */
    final textMask:h2d.Mask;
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
        textMask = new h2d.Mask(1, 1, this);

        placeholder = new UiText(ctx.font, textMask);
        placeholder.text = placeholderText;
        placeholder.textColor = Theme.MUTED;
        placeholder.lineBreak = false;

        input = new UiTextInput(ctx.font, textMask);
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

    /** Focus the underlying text input (used by the Asset Browser Ctrl+F). */
    public function focusInput():Void {
        input.focus();
    }

    public function setWidth(value:Float):Void {
        widthValue = Math.max(0, value);
        layout();
    }

    function layout():Void {
        surface.setSize(widthValue, heightValue);
        textMask.x = 0;
        textMask.y = 0;
        textMask.width = Std.int(Math.max(1, widthValue));
        textMask.height = Std.int(Math.max(1, heightValue));
        icon.x = 7;
        icon.y = Math.round((heightValue - 14) * 0.5);
        input.x = 27;
        // Use the same center metric for the glyph icon and the text lines so
        // the placeholder does not sit a pixel off from the magnifier.
        input.y = Math.max(0, Math.round((heightValue - input.font.lineHeight) * 0.5));
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
