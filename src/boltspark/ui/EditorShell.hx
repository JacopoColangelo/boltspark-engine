package boltspark.ui;

import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.Stepper;
import boltspark.ui.widgets.SwatchPicker;
import boltspark.ui.widgets.UiButton;

/**
 * Editor chrome: top bar, hierarchy, transparent 3D viewport, inspector,
 * console, and status bar.
 *
 * Layout rules:
 *  - The center column (viewport) is intentionally NOT filled by the UI so
 *    the native h3d scene shows through the h2d overlay.
 *  - Static panel geometry is rebuilt only when the OS window resizes.
 *  - Widgets issue editor commands through callbacks; they never mutate
 *    engine state directly.
 */
class EditorShell {
    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;

    // Top bar / panels.
    final appTitle:h2d.Text;
    final hierarchyTitle:h2d.Text;
    final inspectorTitle:h2d.Text;
    final statusText:h2d.Text;
    final inputStatus:h2d.Text;

    // Widgets.
    final testButton:UiButton;
    final hierarchyItemBg:h2d.Interactive;
    final hierarchyItem:h2d.Text;
    final spinRow:Stepper;
    final colorRow:SwatchPicker;
    final spinLabel:h2d.Text;
    final colorLabel:h2d.Text;
    final console:ConsolePanel;

    // Editor commands (wired by Main to engine objects).
    public var onTestAction:Null<Void->Void>;
    public var onSpinSpeedChanged:Null<Float->Void>;
    public var onColorChanged:Null<Int->Void>;

    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    var selected:Bool = false;

    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter) {
        this.ctx = ctx;
        this.input = input;
        this.root = new h2d.Object(parent);
        chrome = new h2d.Graphics(root);

        appTitle = new h2d.Text(ctx.font, root);
        appTitle.text = "BOLTSPARK";
        appTitle.textColor = Theme.ACCENT;

        hierarchyTitle = new h2d.Text(ctx.font, root);
        hierarchyTitle.text = "HIERARCHY";
        hierarchyTitle.textColor = Theme.MUTED;

        inspectorTitle = new h2d.Text(ctx.font, root);
        inspectorTitle.text = "INSPECTOR";
        inspectorTitle.textColor = Theme.MUTED;

        hierarchyItemBg = new h2d.Interactive(Theme.LEFT_PANEL_WIDTH - 24, 26, root);
        hierarchyItemBg.cursor = hxd.Cursor.Button;
        hierarchyItemBg.backgroundColor = 0;
        hierarchyItemBg.onClick = function(_) {
            selected = !selected;
            hierarchyItemBg.backgroundColor = selected ? Theme.BUTTON_ACTIVE : 0;
            hierarchyItem.textColor = selected ? Theme.ACCENT : Theme.TEXT;
            log("hierarchy: sampleCube " + (selected ? "selected" : "deselected"));
        };

        hierarchyItem = new h2d.Text(ctx.font, root);
        hierarchyItem.text = "sampleCube";
        hierarchyItem.textColor = Theme.TEXT;

        spinLabel = new h2d.Text(ctx.font, root);
        spinLabel.text = "Spin speed (rad/s)";
        spinLabel.textColor = Theme.MUTED;

        spinRow = new Stepper(ctx, Theme.RIGHT_PANEL_WIDTH - 32, Theme.CONTROL_HEIGHT,
            0.0, 4.0, 0.25, 0.35,
            function(v:Float) {
                var hundredths = Math.round(v * 100);
                var fractional = hundredths % 100;
                return Std.string(Std.int(hundredths / 100)) + "."
                    + (fractional < 10 ? "0" : "") + Std.string(fractional);
            },
            root);
        spinRow.onValueChanged = function(v:Float) {
            if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        };

        colorLabel = new h2d.Text(ctx.font, root);
        colorLabel.text = "Base color";
        colorLabel.textColor = Theme.MUTED;

        colorRow = new SwatchPicker(ctx,
            [Theme.CUBE_ORANGE, Theme.CUBE_STEEL, Theme.CUBE_MOSS, Theme.CUBE_VIOLET],
            22, 8, root);
        colorRow.onColorChanged = function(color:Int) {
            if (onColorChanged != null) onColorChanged(color);
        };

        testButton = new UiButton(ctx, "Test native input", Theme.BUTTON_WIDTH, Theme.BUTTON_HEIGHT, root);
        testButton.onClick = function() {
            if (onTestAction != null) onTestAction();
        };

        console = new ConsolePanel(ctx, root);

        statusText = new h2d.Text(ctx.font, root);
        statusText.text = "Native window | HashLink | Heaps | BoltUI";
        statusText.textColor = Theme.MUTED;

        inputStatus = new h2d.Text(ctx.font, root);
        inputStatus.textColor = Theme.MUTED;
        input.bindReport(inputStatus);

        resize();
    }

    /** Editor console access. */
    public function log(line:String):Void {
        console.log(line);
    }

    /** Called once per app frame; re-layout only on native window resize. */
    public function update(dt:Float):Void {
        if (ctx.width != lastWidth || ctx.height != lastHeight) {
            resize();
        }
    }

    /** Rebuild static 2D chrome in response to a native window resize. */
    public function resize():Void {
        var width = ctx.width;
        var height = ctx.height;
        var bodyTop = Theme.TOP_BAR_HEIGHT;
        var bodyHeight = height - Theme.TOP_BAR_HEIGHT - Theme.STATUS_BAR_HEIGHT;
        var viewportX = Theme.LEFT_PANEL_WIDTH;
        var viewportW = width - Theme.LEFT_PANEL_WIDTH - Theme.RIGHT_PANEL_WIDTH;
        var consoleH = Theme.CONSOLE_HEIGHT;
        var viewportH = bodyHeight - consoleH;
        var rightX = width - Theme.RIGHT_PANEL_WIDTH;

        lastWidth = width;
        lastHeight = height;

        chrome.clear();

        // NOTE: no full-window background fill — the viewport area stays
        // transparent so the native h3d scene renders through the overlay.

        chrome.beginFill(Theme.TOP_BAR);
        chrome.drawRect(0, 0, width, Theme.TOP_BAR_HEIGHT);
        chrome.endFill();

        chrome.beginFill(Theme.PANEL);
        chrome.drawRect(0, bodyTop, Theme.LEFT_PANEL_WIDTH, bodyHeight);
        chrome.drawRect(rightX, bodyTop, Theme.RIGHT_PANEL_WIDTH, bodyHeight);
        chrome.drawRect(viewportX, bodyTop + viewportH, viewportW, consoleH);
        chrome.drawRect(0, height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT);
        chrome.endFill();

        chrome.lineStyle(1, Theme.PANEL_EDGE, 1);
        chrome.moveTo(Theme.LEFT_PANEL_WIDTH, bodyTop);
        chrome.lineTo(Theme.LEFT_PANEL_WIDTH, height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(rightX, bodyTop);
        chrome.lineTo(rightX, height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(0, bodyTop);
        chrome.lineTo(width, bodyTop);
        chrome.moveTo(viewportX, bodyTop + viewportH);
        chrome.lineTo(width - Theme.RIGHT_PANEL_WIDTH, bodyTop + viewportH);
        chrome.moveTo(0, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineTo(width, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineStyle();

        appTitle.x = 16;
        appTitle.y = 15;

        hierarchyTitle.x = 16;
        hierarchyTitle.y = bodyTop + 16;

        hierarchyItemBg.x = 12;
        hierarchyItemBg.y = bodyTop + 46;

        hierarchyItem.x = 24;
        hierarchyItem.y = hierarchyItemBg.y + 6;

        testButton.x = 16;
        testButton.y = bodyTop + 92;
        testButton.center();

        inspectorTitle.x = rightX + 16;
        inspectorTitle.y = bodyTop + 16;

        spinLabel.x = rightX + 16;
        spinLabel.y = bodyTop + 48;

        spinRow.x = rightX + 16;
        spinRow.y = bodyTop + 72;

        colorLabel.x = rightX + 16;
        colorLabel.y = bodyTop + 124;

        colorRow.x = rightX + 16;
        colorRow.y = bodyTop + 148;

        console.x = viewportX + 8;
        console.y = bodyTop + viewportH + 8;
        console.layout(viewportW - 16, consoleH - 16);

        statusText.x = 12;
        statusText.y = height - Theme.STATUS_BAR_HEIGHT + 5;

        inputStatus.x = width - 420;
        inputStatus.y = height - Theme.STATUS_BAR_HEIGHT + 5;
    }
}
