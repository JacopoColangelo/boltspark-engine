package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.MenuDropdown.MenuItem;

class ConsolePanel extends h2d.Object {
    public static inline var MAX_LINES:Int = 500;

    public var onBackgroundClick:Null<Void->Void>;

    final background:h2d.Graphics;
    final bodySurface:UiSurface;
    final contentMask:h2d.Mask;
    final scrollHit:h2d.Interactive;
    final text:h2d.Text;
    final clearButton:UiButton;
    final scrollBar:ScrollBar;
    /** Full-panel catch for right-click context menu; left/hover pass through. */
    final panelHit:h2d.Interactive;
    final contextMenu:MenuDropdown;
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
        // Icon-only and narrow so it stays clear of the bottom-dock tabs.
        // Eraser reads as "clear the log" without the destructive trash-bin
        // connotation, and the framed style matches the other editor buttons.
        clearButton = new UiButton(ctx, "", 26, 20, this);
        clearButton.setIcon(Eraser).setIconSize(12);
        clearButton.onClick = function() {
            contextMenu.close();
            clear();
        };

        contentMask = new h2d.Mask(0, 0, this);
        contentMask.x = 0;
        scrollHit = new h2d.Interactive(0, 0, contentMask);
        scrollHit.backgroundColor = 0;
        scrollHit.cursor = hxd.Cursor.Default;
        scrollHit.onWheel = function(event) {
            if (!scrollLines(Std.int(Math.round(event.wheelDelta * 3)))) return;
            event.propagate = false;
        };
        scrollHit.onClick = function(event) {
            if (event.button == 0 && onBackgroundClick != null) onBackgroundClick();
        };
        text = new UiText(ctx.monoFont, contentMask);
        text.textColor = Theme.TEXT_SECONDARY;
        text.x = 8;
        text.y = 5;
        text.lineBreak = false;
        scrollBar = new ScrollBar(ctx, this);
        scrollBar.onChange = function(value) {
            firstVisibleLine = Std.int(Math.round(maxFirstVisibleLine() * value));
            refresh();
        };
        scrollBar.onWheel = function(delta) {
            return scrollLines(Std.int(Math.round(delta * 3)));
        };

        // Right-click anywhere in the log opens a small context menu. The
        // catch is transparent and sits above the other controls, so it must
        // pass every event it does not handle through to them; otherwise it
        // would swallow clicks on the Clear button and wheel scrolling.
        panelHit = new h2d.Interactive(0, 0, this);
        panelHit.backgroundColor = 0;
        panelHit.cursor = hxd.Cursor.Default;
        panelHit.enableRightButton = true;
        panelHit.cancelEvents = true;
        panelHit.onPush = function(event) {
            if (event.button != 1) return; // cancelEvents forwards left clicks
            event.propagate = false;
            var point = localToGlobal(new h2d.col.Point(event.relX, event.relY));
            contextMenu.open(point.x, point.y, [{
                label: "Clear Output Log",
                onClick: clear
            }]);
        };
        // The menu lives in the root scene so it can render above the docked
        // console without being clipped by the panel's masks.
        var scene = getScene();
        contextMenu = new MenuDropdown(ctx, scene == null ? this : scene);
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

    /** Plain-text lines for the native HWND panel host snapshot. */
    public function snapshotLines():Array<String> {
        var result:Array<String> = [];
        for (line in lines) result.push(line);
        return result;
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
        background.beginFill(Theme.PANEL_HEADER);
        background.drawRect(0, 0, safeW, 28);
        background.endFill();
        background.lineStyle(1, Theme.BORDER, 1);
        background.moveTo(0, 27.5);
        background.lineTo(safeW, 27.5);
        background.lineStyle();

        clearButton.x = Math.max(0, safeW - 30);
        clearButton.y = 4;
        bodySurface.x = 0;
        bodySurface.y = 28;
        bodySurface.setSize(Math.max(0, safeW), Math.max(0, safeH - 28));
        contentMask.x = 0;
        contentMask.y = 29;
        contentWidth = Math.max(0, safeW - 14);
        contentHeight = Math.max(0, safeH - 30);
        contentMask.width = Std.int(contentWidth);
        contentMask.height = Std.int(contentHeight);
        scrollHit.width = contentMask.width;
        scrollHit.height = contentMask.height;
        visibleLines = Std.int(Math.floor(contentHeight / Math.max(1, lineHeight)));
        scrollBar.setBounds(Math.max(0, safeW - 8), 32, 4, Math.max(0, contentHeight - 6));
        panelHit.x = 0;
        panelHit.y = 0;
        panelHit.width = safeW;
        panelHit.height = safeH;
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
        var maxWidth = Math.max(0, contentWidth - 14);
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
        text.y = 5;
        updateScrollBar();
    }
}
