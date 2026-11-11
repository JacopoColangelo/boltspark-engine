package boltspark.ui.widgets;

/**
 * Native button widget: an h2d.Interactive hit region with a centered label.
 *
 * Hover/pressed states are handled here; click callbacks are forwarded to
 * the owner (editor commands), which keeps widget code free of engine state.
 */
class UiButton extends h2d.Object {
    public var onClick:Null<Void->Void>;

    final bg:h2d.Interactive;
    final label:h2d.Text;
    final width:Float;
    final height:Float;

    public function new(ctx:boltspark.ui.UiContext, text:String, w:Float, h:Float, ?parent:h2d.Object) {
        super(parent);
        this.width = w;
        this.height = h;

        bg = new h2d.Interactive(w, h, this);
        bg.backgroundColor = boltspark.ui.Theme.BUTTON;
        bg.cursor = hxd.Cursor.Button;
        bg.onOver = function(_) bg.backgroundColor = boltspark.ui.Theme.BUTTON_HOVER;
        bg.onOut = function(_) bg.backgroundColor = boltspark.ui.Theme.BUTTON;
        bg.onPush = function(_) bg.backgroundColor = boltspark.ui.Theme.BUTTON_ACTIVE;
        // On release (inside or outside), restore the resting color; only a
        // release inside the control counts as a click.
        bg.onRelease = function(_) {
            bg.backgroundColor = boltspark.ui.Theme.BUTTON;
            if (onClick != null) onClick();
        };
        bg.onReleaseOutside = function(_) bg.backgroundColor = boltspark.ui.Theme.BUTTON;

        label = new h2d.Text(ctx.font, bg);
        label.text = text;
        label.textColor = boltspark.ui.Theme.TEXT;
        bg.addChild(label);
    }

    /** Set text and re-center; call after the widget is positioned. */
    public function setText(text:String):Void {
        label.text = text;
        center();
    }

    public function center():Void {
        label.x = Math.max(0, (width - label.textWidth) / 2);
        label.y = Math.max(0, (height - label.textHeight) / 2);
    }
}
