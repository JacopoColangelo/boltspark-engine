package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

class ConsolePanel extends h2d.Object {
    public static inline var MAX_LINES:Int = 500;

    final background:h2d.Graphics;
    final contentMask:h2d.Mask;
    final scrollHit:h2d.Interactive;
    final text:h2d.Text;
    final title:h2d.Text;
    final clearButton:UiButton;
    final scrollBar:ScrollBar;
    final lines:Array<String> = [];
    final lineHeight:Float;
    var contentWidth:Float = 0;
    var contentHeight:Float = 0;
    var visibleLines:Int = 0;
    var firstVisibleLine:Int = 0;

    public function new(ctx:UiContext, ?parent:h2d.Object) {
        super(parent);
        lineHeight = ctx.font.lineHeight;

        background = new h2d.Graphics(this);
        title = new h2d.Text(ctx.font, this);
        title.text = "CONSOLE";
        title.textColor = Theme.MUTED;
        title.lineBreak = false;
        title.x = 2;
        title.y = 2;

        clearButton = new UiButton(ctx, "Clear all", 76, 22, this);
        clearButton.onClick = clear;

        contentMask = new h2d.Mask(0, 0, this);
        contentMask.x = 0;
        scrollHit = new h2d.Interactive(0, 0, contentMask);
        scrollHit.backgroundColor = 0;
        scrollHit.onWheel = function(event) {
            if (!scrollLines(Std.int(-event.wheelDelta * 3))) return;
            event.propagate = false;
        };
        text = new h2d.Text(ctx.font, contentMask);
        text.textColor = Theme.MUTED;
        text.x = 6;
        text.y = 2;
        text.lineBreak = false;
        scrollBar = new ScrollBar(ctx, this);
        scrollBar.onChange = function(value) {
            firstVisibleLine = Std.int(Math.round(maxFirstVisibleLine() * value));
            refresh();
        };
    }

    public function log(line:String):Void {
        var stamp = Date.now().toString();
        var wasAtBottom = firstVisibleLine >= maxFirstVisibleLine();
        lines.push(stamp.substr(11, 8) + "  " + StringTools.replace(line, "\n", " "));
        while (lines.length > MAX_LINES) {
            lines.shift();
            if (firstVisibleLine > 0) firstVisibleLine--;
        }
        if (wasAtBottom) firstVisibleLine = maxFirstVisibleLine();
        refresh();
    }

    public function clear():Void {
        lines.resize(0);
        firstVisibleLine = 0;
        refresh();
    }

    public function layout(w:Float, h:Float):Void {
        var safeW = Math.max(0, w);
        var safeH = Math.max(0, h);
        background.clear();
        background.beginFill(Theme.CONSOLE_BG);
        background.drawRect(0, 0, safeW, safeH);
        background.endFill();
        background.lineStyle(1, Theme.PANEL_EDGE, 1);
        background.drawRect(0, 0, safeW, safeH);
        background.lineStyle();

        clearButton.x = Math.max(0, safeW - 80);
        clearButton.y = 1;
        contentMask.x = 0;
        contentMask.y = 25;
        contentWidth = Math.max(0, safeW - 18);
        contentHeight = Math.max(0, safeH - 27);
        contentMask.width = Std.int(contentWidth);
        contentMask.height = Std.int(contentHeight);
        scrollHit.width = contentMask.width;
        scrollHit.height = contentMask.height;
        visibleLines = Std.int(Math.floor(contentHeight / Math.max(1, lineHeight)));
        scrollBar.setBounds(Math.max(0, safeW - 12), 27, 8, contentHeight);
        updateScrollBar();
        refresh();
    }

    function scrollLines(delta:Int):Bool {
        if (maxFirstVisibleLine() <= 0) return false;
        firstVisibleLine = Std.int(Math.max(0, Math.min(
            maxFirstVisibleLine(), firstVisibleLine + delta)));
        refresh();
        return true;
    }

    function maxFirstVisibleLine():Int {
        return Std.int(Math.max(0, lines.length - visibleLines));
    }

    function updateScrollBar():Void {
        var ratio = lines.length == 0 ? 1 : Math.min(1, visibleLines / lines.length);
        var maxFirst = maxFirstVisibleLine();
        scrollBar.setMetrics(ratio, maxFirst == 0 ? 0 : firstVisibleLine / maxFirst);
    }

    function refresh():Void {
        var maxWidth = Math.max(0, contentWidth - 12);
        var displayLines = [];
        for (line in lines) {
            var value = line;
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
        firstVisibleLine = Std.int(Math.max(0, Math.min(maxFirstVisibleLine(), firstVisibleLine)));
        text.y = 2 - firstVisibleLine * lineHeight;
        updateScrollBar();
    }
}
