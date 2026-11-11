package boltspark.ui.widgets;

/**
 * Console panel: a bounded, append-only log shown as one multiline text.
 *
 * Keeps the last maxLines entries; older lines are dropped. The console
 * receives engine/driver diagnostics and editor command results.
 */
class ConsolePanel extends h2d.Object {
    public static inline var MAX_LINES:Int = 9;

    final background:h2d.Graphics;
    final contentMask:h2d.Mask;
    final text:h2d.Text;
    final lines:Array<String> = [];
    final lineHeight:Float;
    var maxVisibleLines:Int = MAX_LINES;

    public function new(ctx:boltspark.ui.UiContext, ?parent:h2d.Object) {
        super(parent);
        lineHeight = ctx.font.lineHeight;

        background = new h2d.Graphics(this);
        contentMask = new h2d.Mask(0, 0, this);
        contentMask.x = 1;
        contentMask.y = 1;

        text = new h2d.Text(ctx.font, contentMask);
        text.textColor = boltspark.ui.Theme.MUTED;
        text.x = 9;
        text.y = 7;
    }

    /** Append one log line. Lines are trimmed and bounded. */
    public function log(line:String):Void {
        var stamp = Date.now().toString();
        var t = stamp.substr(11, 8) + "  " + line;
        lines.push(t);
        refresh();
    }

    /** Re-fit the background when the console area changes size. */
    public function layout(w:Float, h:Float):Void {
        background.clear();
        background.beginFill(boltspark.ui.Theme.CONSOLE_BG);
        background.drawRect(0, 0, w, h);
        background.endFill();
        background.lineStyle(1, boltspark.ui.Theme.PANEL_EDGE, 1);
        background.drawRect(0, 0, w, h);
        background.lineStyle();

        contentMask.width = Std.int(Math.max(0, w - 2));
        contentMask.height = Std.int(Math.max(0, h - 2));
        text.maxWidth = w - 20;
        maxVisibleLines = Std.int(Math.floor(Math.max(0, h - 16) / lineHeight));
        if (maxVisibleLines > MAX_LINES) maxVisibleLines = MAX_LINES;
        refresh();
    }

    function refresh():Void {
        while (lines.length > maxVisibleLines) lines.shift();
        text.text = lines.join("\n");
    }
}
