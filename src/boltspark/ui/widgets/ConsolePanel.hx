package boltspark.ui.widgets;

/**
 * Console panel: a bounded, append-only log shown as one multiline text.
 *
 * Keeps the last maxLines entries; older lines are dropped. The console
 * receives engine/driver diagnostics and editor command results.
 */
class ConsolePanel extends h2d.Object {
    public static inline var MAX_LINES:Int = 9;

    final text:h2d.Text;
    final lines:Array<String> = [];
    final width:Float;

    public function new(ctx:boltspark.ui.UiContext, w:Float, h:Float, ?parent:h2d.Object) {
        super(parent);
        this.width = w;

        var background = new h2d.Graphics(this);
        background.beginFill(boltspark.ui.Theme.CONSOLE_BG);
        background.drawRect(0, 0, w, h);
        background.endFill();
        background.lineStyle(1, boltspark.ui.Theme.PANEL_EDGE, 1);
        background.drawRect(0, 0, w, h);
        background.lineStyle();

        text = new h2d.Text(ctx.font, this);
        text.textColor = boltspark.ui.Theme.MUTED;
        text.x = 10;
        text.y = 8;
        text.maxWidth = w - 20;
    }

    /** Append one log line. Lines are trimmed and bounded. */
    public function log(line:String):Void {
        var stamp = Date.now().toString();
        var t = stamp.substr(11, 8) + "  " + line;
        lines.push(t);
        while (lines.length > MAX_LINES) lines.shift();
        text.text = lines.join("\n");
    }

    /** Re-fit the background when the console area changes size. */
    public function layout(w:Float, h:Float):Void {
        var background = getChildAt(0);
        var g:h2d.Graphics = cast background;
        g.clear();
        g.beginFill(boltspark.ui.Theme.CONSOLE_BG);
        g.drawRect(0, 0, w, h);
        g.endFill();
        g.lineStyle(1, boltspark.ui.Theme.PANEL_EDGE, 1);
        g.drawRect(0, 0, w, h);
        g.lineStyle();
        text.maxWidth = w - 20;
    }
}
