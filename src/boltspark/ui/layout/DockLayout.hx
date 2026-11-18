package boltspark.ui.layout;

import boltspark.ui.Theme;

typedef DockLayoutGeometry = {
    final leftPanel:LayoutRect;
    final leftSplitter:LayoutRect;
    final viewport:LayoutRect;
    final consoleSplitter:LayoutRect;
    final console:LayoutRect;
    final rightSplitter:LayoutRect;
    final rightPanel:LayoutRect;
}

class DockLayout {
    /** Effective sizes for the current window, clamped by `calculate()`. */
    public var leftPanelWidth:Float;
    public var rightPanelWidth:Float;
    public var consoleHeight:Float;
    /** Remembered sizes; a temporary small window must never destroy these. */
    public var preferredLeftPanelWidth:Float;
    public var preferredRightPanelWidth:Float;
    public var preferredConsoleHeight:Float;
    /** Active bottom dock tab: 0 = Output Log, 1 = Asset Browser. */
    public var bottomTab:Int = 0;

    public function new(
        leftPanelWidth:Float = Theme.LEFT_PANEL_WIDTH,
        rightPanelWidth:Float = Theme.RIGHT_PANEL_WIDTH,
        consoleHeight:Float = Theme.CONSOLE_HEIGHT
    ) {
        preferredLeftPanelWidth = leftPanelWidth;
        preferredRightPanelWidth = rightPanelWidth;
        preferredConsoleHeight = consoleHeight;
        this.leftPanelWidth = leftPanelWidth;
        this.rightPanelWidth = rightPanelWidth;
        this.consoleHeight = consoleHeight;
    }

    /** Restore persisted dimensions as the new user preference. */
    public function setPreferred(left:Float, right:Float, console:Float):Void {
        preferredLeftPanelWidth = left;
        preferredRightPanelWidth = right;
        preferredConsoleHeight = console;
    }

    public function calculate(width:Float, height:Float):DockLayoutGeometry {
        var bodyTop = Theme.TOP_BAR_HEIGHT;
        var bodyHeight = Math.max(0, height - Theme.TOP_BAR_HEIGHT - Theme.STATUS_BAR_HEIGHT);
        var splitterSize = Theme.SPLITTER_SIZE;
        var panelSpace = Math.max(0, width - splitterSize * 2);

        var leftWidth:Float;
        var rightWidth:Float;
        var viewportWidth:Float;
        if (panelSpace >= Theme.MIN_LEFT_PANEL_WIDTH + Theme.MIN_CENTER_PANEL_WIDTH + Theme.MIN_RIGHT_PANEL_WIDTH) {
            var maxLeft = panelSpace - Theme.MIN_CENTER_PANEL_WIDTH - Theme.MIN_RIGHT_PANEL_WIDTH;
            leftPanelWidth = clamp(preferredLeftPanelWidth, Theme.MIN_LEFT_PANEL_WIDTH, maxLeft);
            var maxRight = panelSpace - leftPanelWidth - Theme.MIN_CENTER_PANEL_WIDTH;
            rightPanelWidth = clamp(preferredRightPanelWidth, Theme.MIN_RIGHT_PANEL_WIDTH, maxRight);
            leftWidth = leftPanelWidth;
            rightWidth = rightPanelWidth;
            viewportWidth = Math.max(0, panelSpace - leftWidth - rightWidth);
        } else {
            leftWidth = Math.min(Theme.MIN_LEFT_PANEL_WIDTH, Math.max(0, panelSpace * 0.3));
            rightWidth = Math.min(Theme.MIN_RIGHT_PANEL_WIDTH, Math.max(0, panelSpace * 0.35));
            viewportWidth = Math.max(0, panelSpace - leftWidth - rightWidth);
        }

        var viewportX = leftWidth + splitterSize;
        var rightX = width - rightWidth;
        var consoleHeight:Float;
        var viewportHeight:Float;
        if (bodyHeight >= 168 + splitterSize + 96) {
            this.consoleHeight = clamp(preferredConsoleHeight, 140, bodyHeight - 168 - splitterSize);
            consoleHeight = this.consoleHeight;
            viewportHeight = bodyHeight - consoleHeight - splitterSize;
        } else {
            consoleHeight = bodyHeight * 0.4;
            viewportHeight = Math.max(0, bodyHeight - consoleHeight - splitterSize);
        }
        var consoleY = bodyTop + viewportHeight + splitterSize;

        return {
            leftPanel: new LayoutRect(0, bodyTop, leftWidth, bodyHeight),
            leftSplitter: new LayoutRect(leftWidth, bodyTop, splitterSize, bodyHeight),
            viewport: new LayoutRect(viewportX, bodyTop, viewportWidth, viewportHeight),
            consoleSplitter: new LayoutRect(viewportX, bodyTop + viewportHeight, viewportWidth, splitterSize),
            console: new LayoutRect(viewportX, consoleY, viewportWidth, consoleHeight),
            rightSplitter: new LayoutRect(rightX - splitterSize, bodyTop, splitterSize, bodyHeight),
            rightPanel: new LayoutRect(rightX, bodyTop, rightWidth, bodyHeight)
        };
    }

    static function clamp(value:Float, min:Float, max:Float):Float {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}
