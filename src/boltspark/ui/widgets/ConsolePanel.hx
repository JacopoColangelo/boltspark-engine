package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;

class ConsolePanel extends h2d.Object {
    public static inline var MAX_LINES:Int = 500;

    final background:h2d.Graphics;
    final bodySurface:UiSurface;
    final contentMask:h2d.Mask;
    final scrollHit:h2d.Interactive;
    final text:h2d.Text;
    final title:h2d.Text;
    final titleIcon:h2d.Graphics;
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
        lineHeight = ctx.monoFont.lineHeight;

        background = new h2d.Graphics(this);
        bodySurface = new UiSurface(ctx, this);
        bodySurface.setStyle(Theme.CONSOLE_BG, Theme.BORDER, 0);
        titleIcon = new h2d.Graphics(this);
        UiIcons.draw(titleIcon, Console, 0, 0, 15, Theme.TEXT_SECONDARY);
        title = new h2d.Text(ctx.semiboldFont, this);
        title.text = "Output Log";
        title.textColor = Theme.TEXT;
        title.lineBreak = false;
        title.x = 24;
        title.y = 4;

        clearButton = new UiButton(ctx, "Clear", 76, 26, this);
        clearButton.setIcon(Trash).setQuiet();
        clearButton.onClick = clear;

        contentMask = new h2d.Mask(0, 0, this);
        contentMask.x = 0;
        scrollHit = new h2d.Interactive(0, 0, contentMask);
        scrollHit.backgroundColor = 0;
        scrollHit.onWheel = function(event) {
            if (!scrollLines(Std.int(-event.wheelDelta * 3))) return;
            event.propagate = false;
        };
        text = new h2d.Text(ctx.monoFont, contentMask);
        text.textColor = Theme.TEXT_SECONDARY;
        text.x = 10;
        text.y = 7;
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
        background.beginFill(Theme.PANEL);
        background.drawRect(0, 0, safeW, safeH);
        background.endFill();
        background.lineStyle(1, Theme.BORDER, 1);
        background.moveTo(0, 34);
        background.lineTo(safeW, 34);
        background.lineStyle();

        titleIcon.x = 2;
        titleIcon.y = 7;
        clearButton.x = Math.max(0, safeW - 80);
        clearButton.y = 3;
        bodySurface.x = 0;
        bodySurface.y = 38;
        bodySurface.setSize(Math.max(0, safeW), Math.max(0, safeH - 38));
        contentMask.x = 0;
        contentMask.y = 38;
        contentWidth = Math.max(0, safeW - 18);
        contentHeight = Math.max(0, safeH - 40);
        contentMask.width = Std.int(contentWidth);
        contentMask.height = Std.int(contentHeight);
        scrollHit.width = contentMask.width;
        scrollHit.height = contentMask.height;
        visibleLines = Std.int(Math.floor(contentHeight / Math.max(1, lineHeight)));
        scrollBar.setBounds(Math.max(0, safeW - 11), 43, 6, Math.max(0, contentHeight - 9));
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
        var maxWidth = Math.max(0, contentWidth - 18);
        var displayLines = [];
        firstVisibleLine = Std.int(Math.max(0, Math.min(maxFirstVisibleLine(), firstVisibleLine)));
        var lastVisibleLine = Std.int(Math.min(lines.length, firstVisibleLine + visibleLines));
        for (index in firstVisibleLine...lastVisibleLine) {
            var value = lines[index];
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
        text.y = 7;
        updateScrollBar();
    }
}
