package boltspark.ui;

import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.Stepper;
import boltspark.ui.widgets.SwatchPicker;
import boltspark.ui.widgets.TextInputField;
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
    final leftContentMask:h2d.Mask;
    final rightContentMask:h2d.Mask;
    final dockLayout:DockLayout;
    final layoutStore:DockLayoutStore;

    // Widgets.
    final testButton:UiButton;
    final viewportHit:h2d.Interactive;
    final hierarchyItemBg:h2d.Interactive;
    final hierarchyItem:h2d.Text;
    final spinRow:Stepper;
    final colorRow:SwatchPicker;
    final objectNameField:TextInputField;
    final objectNameLabel:h2d.Text;
    final spinLabel:h2d.Text;
    final colorLabel:h2d.Text;
    final console:ConsolePanel;

    // Editor commands (wired by Main to engine objects).
    public var onTestAction:Null<Void->Void>;
    public var onSpinSpeedChanged:Null<Float->Void>;
    public var onColorChanged:Null<Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onViewportClick:Null<Float->Float->Void>;
    public var viewportRect(default, null):LayoutRect;

    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    var selected:Bool = false;
    var hierarchyItemFullText:String = "sampleCube";
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

        leftContentMask = new h2d.Mask(0, 0, root);
        rightContentMask = new h2d.Mask(0, 0, root);

        appTitle = new h2d.Text(ctx.font, root);
        appTitle.text = "BOLTSPARK";
        appTitle.textColor = Theme.ACCENT;
        appTitle.lineBreak = false;

        hierarchyTitle = new h2d.Text(ctx.font, leftContentMask);
        hierarchyTitle.text = "HIERARCHY";
        hierarchyTitle.textColor = Theme.MUTED;
        hierarchyTitle.lineBreak = false;

        inspectorTitle = new h2d.Text(ctx.font, rightContentMask);
        inspectorTitle.text = "INSPECTOR";
        inspectorTitle.textColor = Theme.MUTED;
        inspectorTitle.lineBreak = false;

        hierarchyItemBg = new h2d.Interactive(Theme.LEFT_PANEL_WIDTH - 24, 26, leftContentMask);
        hierarchyItemBg.cursor = hxd.Cursor.Button;
        hierarchyItemBg.backgroundColor = 0;
        hierarchyItemBg.onClick = function(_) {
            setSampleCubeSelected(true);
            log("hierarchy: sampleCube selected");
        };

        hierarchyItem = new h2d.Text(ctx.font, leftContentMask);
        hierarchyItem.text = "sampleCube";
        hierarchyItem.textColor = Theme.TEXT;
        hierarchyItem.lineBreak = false;

        spinLabel = new h2d.Text(ctx.font, rightContentMask);
        spinLabel.text = "Spin speed (rad/s)";
        spinLabel.textColor = Theme.MUTED;
        spinLabel.lineBreak = false;

        spinRow = new Stepper(ctx, Theme.RIGHT_PANEL_WIDTH - 32, Theme.CONTROL_HEIGHT,
            0.0, 4.0, 0.25, 0.35,
            function(v:Float) {
                var hundredths = Math.round(v * 100);
                var fractional = hundredths % 100;
                return Std.string(Std.int(hundredths / 100)) + "."
                    + (fractional < 10 ? "0" : "") + Std.string(fractional);
            },
            rightContentMask);
        spinRow.onValueChanged = function(v:Float) {
            if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        };
        spinRow.onEditRejected = function(message:String) log("inspector: " + message);

        colorLabel = new h2d.Text(ctx.font, rightContentMask);
        colorLabel.text = "Base color";
        colorLabel.textColor = Theme.MUTED;
        colorLabel.lineBreak = false;

        colorRow = new SwatchPicker(ctx,
            [Theme.CUBE_ORANGE, Theme.CUBE_STEEL, Theme.CUBE_MOSS, Theme.CUBE_VIOLET],
            22, 8, rightContentMask);
        colorRow.onColorChanged = function(color:Int) {
            if (onColorChanged != null) onColorChanged(color);
        };

        objectNameLabel = new h2d.Text(ctx.font, rightContentMask);
        objectNameLabel.text = "Object name";
        objectNameLabel.textColor = Theme.MUTED;
        objectNameLabel.lineBreak = false;

        objectNameField = new TextInputField(ctx, "", Theme.RIGHT_PANEL_WIDTH - 32, Theme.CONTROL_HEIGHT, "sampleCube", rightContentMask);
        objectNameField.onCommit = function(name:String) {
            if (onObjectNameChanged != null) onObjectNameChanged(name);
        };
        objectNameField.onCancel = function() {
            log("inspector: object name edit cancelled");
        };

        testButton = new UiButton(ctx, "Test native input", Theme.BUTTON_WIDTH, Theme.BUTTON_HEIGHT, leftContentMask);
        testButton.onClick = function() {
            if (onTestAction != null) onTestAction();
        };

        console = new ConsolePanel(ctx, root);

        statusText = new h2d.Text(ctx.font, root);
        statusText.text = "Native window | HashLink | Heaps | BoltUI";
        statusText.textColor = Theme.MUTED;
        statusText.lineBreak = false;

        inputStatus = new h2d.Text(ctx.font, root);
        inputStatus.textColor = Theme.MUTED;
        inputStatus.lineBreak = false;
        input.bindReport(inputStatus);

        dockLayout = new DockLayout();
        layoutStore = new DockLayoutStore();
        var layoutError = layoutStore.load(dockLayout);
        if (layoutError != null) log("layout: " + layoutError);

        resize();
    }

    function fitText(target:h2d.Text, value:String, maxWidth:Float):Void {
        target.lineBreak = false;
        target.maxWidth = null;
        if (maxWidth <= 0) {
            target.text = "";
            return;
        }
        if (target.calcTextWidth(value) <= maxWidth) {
            target.text = value;
            return;
        }
        var suffix = "...";
        var fitted = "";
        for (i in 0...value.length) {
            var candidate = value.substr(0, i + 1) + suffix;
            if (target.calcTextWidth(candidate) > maxWidth) break;
            fitted = candidate;
        }
        target.text = fitted;
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
        var rightWidth = Math.max(0, geometry.rightPanel.width);
        var rightX = geometry.rightPanel.x;
        var consoleH = geometry.console.height;
        var consoleY = geometry.console.y;
        var rightContentWidth = Math.max(0, rightWidth - 32);
        var leftContentWidth = Math.max(0, leftWidth - 24);

        lastWidth = width;
        lastHeight = height;

        leftContentMask.width = Std.int(Math.max(0, leftWidth));
        leftContentMask.height = Std.int(Math.max(0, height - Theme.STATUS_BAR_HEIGHT));
        leftContentMask.visible = leftWidth >= 120;
        rightContentMask.x = rightX;
        rightContentMask.width = Std.int(Math.max(0, rightWidth));
        rightContentMask.height = Std.int(Math.max(0, height - Theme.STATUS_BAR_HEIGHT));
        rightContentMask.visible = rightWidth >= 144;

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
        fitText(appTitle, "BOLTSPARK", Math.max(0, width - 32));

        hierarchyTitle.x = 16;
        hierarchyTitle.y = bodyTop + 16;
        fitText(hierarchyTitle, "HIERARCHY", Math.max(0, leftWidth - 24));

        hierarchyItemBg.width = leftContentWidth;
        hierarchyItemBg.x = 12;
        hierarchyItemBg.y = bodyTop + 46;

        hierarchyItem.x = 24;
        hierarchyItem.y = hierarchyItemBg.y + 6;
        fitText(hierarchyItem, hierarchyItemFullText, Math.max(0, leftContentWidth - 16));

        var buttonWidth = Math.min(Theme.BUTTON_WIDTH, leftContentWidth);
        testButton.setWidth(buttonWidth);
        testButton.x = 12;
        testButton.y = bodyTop + 92;
        testButton.center();

        inspectorTitle.x = 16;
        inspectorTitle.y = bodyTop + 16;
        fitText(inspectorTitle, "INSPECTOR", Math.max(0, rightWidth - 24));

        spinLabel.x = 16;
        spinLabel.y = bodyTop + 48;
        fitText(spinLabel, "Spin speed (rad/s)", rightContentWidth);

        spinRow.setWidth(rightContentWidth);
        spinRow.x = 16;
        spinRow.y = bodyTop + 72;

        colorLabel.x = 16;
        colorLabel.y = bodyTop + 124;
        fitText(colorLabel, "Base color", rightContentWidth);

        colorRow.x = 16;
        colorRow.y = bodyTop + 148;

        objectNameLabel.x = 16;
        objectNameLabel.y = bodyTop + 190;
        fitText(objectNameLabel, "Object name", rightContentWidth);
        objectNameField.setWidth(rightContentWidth);
        objectNameField.x = 16;
        objectNameField.y = bodyTop + 212;

        console.x = geometry.console.x + 8;
        console.y = consoleY + 8;
        console.layout(geometry.console.width - 16, consoleH - 16);

        statusText.x = 12;
        statusText.y = height - Theme.STATUS_BAR_HEIGHT + 5;
        inputStatus.visible = width >= 700;
        fitText(statusText, "Native window | HashLink | Heaps | BoltUI",
            Math.max(0, width - (inputStatus.visible ? 444 : 24)));

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

    public function setObjectName(value:String):Void {
        if (value == null || value.length == 0) {
            value = "sampleCube";
        }
        hierarchyItemFullText = value;
        fitText(hierarchyItem, hierarchyItemFullText, Math.max(0, leftContentMask.width - 40));
        objectNameField.setValue(value);
    }
}
