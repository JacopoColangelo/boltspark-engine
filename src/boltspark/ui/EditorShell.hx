package boltspark.ui;

import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.Stepper;
import boltspark.ui.widgets.SwatchPicker;
import boltspark.ui.widgets.UiButton;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;

/**
 * Editor chrome: top bar, hierarchy, bounded 3D viewport, inspector,
 * console, and status bar.
 *
 * Layout rules:
 *  - The center column is an interactive, scissored 3D viewport.
 *  - Panel geometry is rebuilt on window resize and dock splitter movement.
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
    final leftSplitter:DockSplitter;
    final rightSplitter:DockSplitter;
    final consoleSplitter:DockSplitter;
    final dockLayout:DockLayout;
    final layoutStore:DockLayoutStore;

    // Widgets.
    final testButton:UiButton;
    final viewportHit:h2d.Interactive;
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
    public var onViewportClick:Null<Float->Float->Void>;
    public var viewportRect(default, null):LayoutRect;

    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    var selected:Bool = false;
    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter) {
        this.ctx = ctx;
        this.input = input;
        this.root = new h2d.Object(parent);
        chrome = new h2d.Graphics(root);

        viewportHit = new h2d.Interactive(1, 1, root);
        viewportHit.backgroundColor = 0;
        viewportHit.onClick = function(event) {
            if (onViewportClick != null) onViewportClick(event.relX, event.relY);
        };

        leftSplitter = new DockSplitter(ctx, true, root);
        leftSplitter.onDrag = function(delta) {
            dockLayout.leftPanelWidth += delta;
            resize();
        };
        leftSplitter.onDragEnd = saveLayout;
        rightSplitter = new DockSplitter(ctx, true, root);
        rightSplitter.onDrag = function(delta) {
            dockLayout.rightPanelWidth -= delta;
            resize();
        };
        rightSplitter.onDragEnd = saveLayout;
        consoleSplitter = new DockSplitter(ctx, false, root);
        consoleSplitter.onDrag = function(delta) {
            dockLayout.consoleHeight -= delta;
            resize();
        };
        consoleSplitter.onDragEnd = saveLayout;

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
            setSampleCubeSelected(true);
            log("hierarchy: sampleCube selected");
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
        spinRow.onEditRejected = function(message:String) log("inspector: " + message);

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

        dockLayout = new DockLayout();
        layoutStore = new DockLayoutStore();
        var layoutError = layoutStore.load(dockLayout);
        if (layoutError != null) log("layout: " + layoutError);

        resize();
    }

    /** Editor console access. */
    public function log(line:String):Void {
        console.log(line);
    }

    /** Called once per app frame; re-layout when the native window is resized. */
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
        var splitterSize = Theme.SPLITTER_SIZE;
        var geometry = dockLayout.calculate(width, height);
        viewportRect = geometry.viewport;
        var leftWidth = geometry.leftPanel.width;
        var rightX = geometry.rightPanel.x;
        var consoleH = geometry.console.height;
        var consoleY = geometry.console.y;

        lastWidth = width;
        lastHeight = height;

        chrome.clear();

        // The viewport stays unfilled so the scissored 3D scene remains visible.

        chrome.beginFill(Theme.TOP_BAR);
        chrome.drawRect(0, 0, width, Theme.TOP_BAR_HEIGHT);
        chrome.endFill();

        chrome.beginFill(Theme.PANEL);
        chrome.drawRect(
            geometry.leftPanel.x, geometry.leftPanel.y,
            geometry.leftPanel.width, geometry.leftPanel.height);
        chrome.drawRect(
            geometry.rightPanel.x, geometry.rightPanel.y,
            geometry.rightPanel.width, geometry.rightPanel.height);
        chrome.drawRect(
            geometry.console.x, geometry.console.y,
            geometry.console.width, geometry.console.height);
        chrome.drawRect(0, height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT);
        chrome.endFill();

        chrome.lineStyle(1, Theme.PANEL_EDGE, 1);
        chrome.moveTo(geometry.leftSplitter.x + splitterSize / 2, geometry.leftSplitter.y);
        chrome.lineTo(
            geometry.leftSplitter.x + splitterSize / 2,
            height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(geometry.rightSplitter.x + splitterSize / 2, geometry.rightSplitter.y);
        chrome.lineTo(
            geometry.rightSplitter.x + splitterSize / 2,
            height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(0, bodyTop);
        chrome.lineTo(width, bodyTop);
        chrome.moveTo(
            geometry.consoleSplitter.x,
            geometry.consoleSplitter.y + splitterSize / 2);
        chrome.lineTo(
            geometry.consoleSplitter.x + geometry.consoleSplitter.width,
            geometry.consoleSplitter.y + splitterSize / 2);
        chrome.moveTo(0, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineTo(width, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineStyle();

        leftSplitter.setBounds(
            geometry.leftSplitter.x, geometry.leftSplitter.y,
            geometry.leftSplitter.width, geometry.leftSplitter.height);
        rightSplitter.setBounds(
            geometry.rightSplitter.x, geometry.rightSplitter.y,
            geometry.rightSplitter.width, geometry.rightSplitter.height);
        consoleSplitter.setBounds(
            geometry.consoleSplitter.x, geometry.consoleSplitter.y,
            geometry.consoleSplitter.width, geometry.consoleSplitter.height);
        viewportHit.x = geometry.viewport.x;
        viewportHit.y = geometry.viewport.y;
        viewportHit.width = Math.max(0, geometry.viewport.width);
        viewportHit.height = Math.max(0, geometry.viewport.height);

        appTitle.x = 16;
        appTitle.y = 15;

        hierarchyTitle.x = 16;
        hierarchyTitle.y = bodyTop + 16;

        hierarchyItemBg.width = Math.max(0, leftWidth - 24);
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

        console.x = geometry.console.x + 8;
        console.y = consoleY + 8;
        console.layout(geometry.console.width - 16, consoleH - 16);

        statusText.x = 12;
        statusText.y = height - Theme.STATUS_BAR_HEIGHT + 5;

        inputStatus.x = width - 420;
        inputStatus.y = height - Theme.STATUS_BAR_HEIGHT + 5;
    }

    function saveLayout():Void {
        var error = layoutStore.save(dockLayout);
        if (error != null) log("layout: " + error);
    }

    public function setSampleCubeSelected(value:Bool):Void {
        selected = value;
        hierarchyItemBg.backgroundColor = selected ? Theme.BUTTON_ACTIVE : 0;
        hierarchyItem.textColor = selected ? Theme.ACCENT : Theme.TEXT;
    }
}
