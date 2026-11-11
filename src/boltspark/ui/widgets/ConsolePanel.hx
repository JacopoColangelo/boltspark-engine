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
        text.lineBreak = false;
    }

    /** Append one log line. Lines are trimmed and bounded. */
    public function log(line:String):Void {
        var stamp = Date.now().toString();
        var t = stamp.substr(11, 8) + "  " + line;
        lines.push(t);
        while (lines.length > MAX_LINES) lines.shift();
        refresh();
    }

    /** Re-fit the background when the console area changes size. */
    public function layout(w:Float, h:Float):Void {
        var safeW = Math.max(0, w);
        var safeH = Math.max(0, h);
        background.clear();
        background.beginFill(boltspark.ui.Theme.CONSOLE_BG);
        background.drawRect(0, 0, safeW, safeH);
        background.endFill();
        background.lineStyle(1, boltspark.ui.Theme.PANEL_EDGE, 1);
        background.drawRect(0, 0, safeW, safeH);
        background.lineStyle();

        contentMask.width = Std.int(Math.max(0, safeW - 2));
        contentMask.height = Std.int(Math.max(0, safeH - 2));
        text.maxWidth = null;
        maxVisibleLines = Std.int(Math.floor(Math.max(0, safeH - 16) / Math.max(1, lineHeight)));
        if (maxVisibleLines > MAX_LINES) maxVisibleLines = MAX_LINES;
        refresh();
    }

    function refresh():Void {
        var maxWidth = Math.max(0, contentMask.width - 18);
        var displayLines = [];
        for (line in lines) {
            var value = StringTools.replace(line, "\n", " ");
            if (text.calcTextWidth(value) > maxWidth) {
                var fitted = "";
                for (i in 0...value.length) {
                    var candidate = value.substr(0, i + 1) + "...";
                    if (text.calcTextWidth(candidate) > maxWidth) break;
                    fitted = candidate;
                }
                value = fitted;
            }
            displayLines.push(value);
        }
        text.text = displayLines.join("\n");
        var visibleLines = Math.max(1, maxVisibleLines);
        text.y = 7 - Math.max(0, lines.length - visibleLines) * lineHeight;
    }
}
