package boltspark.ui;

import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.widgets.AxisValue;
import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.GameObjectPalette;
import boltspark.ui.widgets.HierarchyRow;
import boltspark.ui.widgets.ScrollBar;
import boltspark.ui.widgets.SearchField;
import boltspark.ui.widgets.Stepper;
import boltspark.ui.widgets.SwatchPicker;
import boltspark.ui.widgets.TextInputField;
import boltspark.ui.widgets.UiButton;

/**
 * Retained native editor shell. All controls are Heaps H2D objects rendered in
 * the same DX12 window as the scene; there is no browser or foreign UI layer.
 */
class EditorShell {
    static inline var HIERARCHY_ROW_HEIGHT:Int = 32;
    static inline var INSPECTOR_CONTENT_HEIGHT:Int = 430;

    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;

    // Title/menu bar and editor toolbar.
    final brandMark:h2d.Graphics;
    final appTitle:h2d.Text;
    final projectTitle:h2d.Text;
    final menuButtons:Array<UiButton> = [];
    final addObjectButton:UiButton;
    final deleteObjectsButton:UiButton;
    final transformButtons:Array<UiButton> = [];
    final transportButtons:Array<UiButton> = [];

    // Hierarchy panel.
    final leftContentMask:h2d.Mask;
    final hierarchyTitleIcon:h2d.Graphics;
    final hierarchyTitle:h2d.Text;
    final hierarchyCount:h2d.Text;
    final hierarchySearch:SearchField;
    final hierarchyHit:h2d.Interactive;
    final hierarchyRows:Array<HierarchyRow> = [];
    final allHierarchyEntries:Array<HierarchyEntry> = [];
    final visibleHierarchyEntries:Array<HierarchyEntry> = [];
    final hierarchyScrollBar:ScrollBar;

    // Details panel.
    final rightContentMask:h2d.Mask;
    final inspectorTitleIcon:h2d.Graphics;
    final inspectorTitle:h2d.Text;
    final selectionStatus:h2d.Text;
    final inspectorContentMask:h2d.Mask;
    final inspectorScrollHit:h2d.Interactive;
    final inspectorScrollBar:ScrollBar;

    final identityCard:UiSurface;
    final identityChevron:h2d.Graphics;
    final identityTitle:h2d.Text;
    final objectNameField:TextInputField;

    final transformCard:UiSurface;
    final transformChevron:h2d.Graphics;
    final transformTitle:h2d.Text;
    final transformSubtitle:h2d.Text;
    final transformFields:Array<AxisValue> = [];

    final behaviorCard:UiSurface;
    final behaviorChevron:h2d.Graphics;
    final behaviorTitle:h2d.Text;
    final spinLabel:h2d.Text;
    final spinRow:Stepper;

    final materialCard:UiSurface;
    final materialChevron:h2d.Graphics;
    final materialTitle:h2d.Text;
    final colorLabel:h2d.Text;
    final colorRow:SwatchPicker;

    // Viewport/console/status.
    final viewportHit:h2d.Interactive;
    final viewportHud:h2d.Object;
    final viewportModeSurface:UiSurface;
    final viewportModeIcon:h2d.Graphics;
    final viewportModeText:h2d.Text;
    final viewportHintSurface:UiSurface;
    final viewportHintIcon:h2d.Graphics;
    final viewportHintText:h2d.Text;
    final console:ConsolePanel;
    final statusDot:h2d.Graphics;
    final statusText:h2d.Text;
    final rendererStatus:h2d.Text;
    final inputStatus:h2d.Text;

    final leftSplitter:DockSplitter;
    final rightSplitter:DockSplitter;
    final consoleSplitter:DockSplitter;
    final dockLayout:DockLayout;
    final layoutStore:DockLayoutStore;
    final palette:GameObjectPalette;

    public var onCreateObject:Null<Void->Void>;
    public var onCreateObjectAt:Null<Float->Float->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onSpinSpeedChanged:Null<Float->Void>;
    public var onColorChanged:Null<Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onViewportClick:Null<Float->Float->Void>;
    public var viewportRect(default, null):LayoutRect;

    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    var selectedObjectIds:Array<Int> = [];
    var selectedObjectId:Int = -1;
    var selectionAnchorIndex:Int = -1;
    var firstVisibleHierarchyRow:Int = 0;
    var inspectorScrollValue:Float = 0;
    var hierarchyFilter:String = "";
    var selectionStatusValue:String = "Select an object to inspect";

    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter) {
        this.ctx = ctx;
        this.input = input;
        root = new h2d.Object(parent);
        chrome = new h2d.Graphics(root);

        viewportHit = new h2d.Interactive(1, 1, root);
        viewportHit.backgroundColor = 0;
        viewportHit.enableRightButton = true;
        viewportHit.onClick = function(event) {
            if (event.button == 1) {
                palette.openAt(ctx.window.mouseX, ctx.window.mouseY, viewportRect);
                event.propagate = false;
            } else if (onViewportClick != null) {
                onViewportClick(event.relX, event.relY);
            }
        };

        leftContentMask = new h2d.Mask(0, 0, root);
        rightContentMask = new h2d.Mask(0, 0, root);

        // Native title/menu bar.
        brandMark = new h2d.Graphics(root);
        drawBrandMark();
        appTitle = new h2d.Text(ctx.titleFont, root);
        appTitle.text = "BOLTSPARK";
        appTitle.textColor = Theme.TEXT;
        appTitle.lineBreak = false;
        projectTitle = new h2d.Text(ctx.font, root);
        projectTitle.text = "Untitled Scene";
        projectTitle.textColor = Theme.MUTED;
        projectTitle.lineBreak = false;

        for (menuName in ["File", "Edit", "Scene", "Window", "Help"]) {
            var menuWidth = switch (menuName) {
                case "Scene": 60;
                case "Window": 70;
                default: 52;
            };
            var button = new UiButton(ctx, menuName, menuWidth, 26, root);
            button.setQuiet();
            button.onClick = function() log(menuName + " menu: command surface reserved");
            menuButtons.push(button);
        }

        // Main toolbar.
        addObjectButton = new UiButton(ctx, "Add", 100, 32, root);
        addObjectButton.setIcon(Add).setPrimary();
        addObjectButton.onClick = function() {
            if (viewportRect != null) {
                palette.toggleAt(addObjectButton.x, addObjectButton.y + 36, viewportRect);
            }
        };
        deleteObjectsButton = new UiButton(ctx, "Delete", 104, 32, root);
        deleteObjectsButton.setIcon(Trash).setDanger();
        deleteObjectsButton.visible = false;
        deleteObjectsButton.onClick = deleteSelection;

        var transformKinds:Array<UiIconKind> = [Move, Rotate, Scale];
        var transformNames = ["Move", "Rotate", "Scale"];
        for (index in 0...transformKinds.length) {
            var modeButton = new UiButton(ctx, "", 34, 32, root);
            modeButton.setIcon(transformKinds[index]).setQuiet().setSelected(index == 0);
            var capturedIndex = index;
            modeButton.onClick = function() {
                for (i in 0...transformButtons.length) transformButtons[i].setSelected(i == capturedIndex);
                log("viewport tool: " + transformNames[capturedIndex]);
            };
            transformButtons.push(modeButton);
        }

        for (transport in [
            {kind: Play, name: "Play"},
            {kind: Pause, name: "Pause"},
            {kind: Stop, name: "Stop"}
        ]) {
            var transportButton = new UiButton(ctx, "", 36, 32, root);
            transportButton.setIcon(transport.kind).setQuiet();
            var command = transport.name;
            transportButton.onClick = function() log(command + " mode is reserved for the runtime milestone");
            transportButtons.push(transportButton);
        }

        // Hierarchy header, search, and rows.
        hierarchyTitleIcon = new h2d.Graphics(leftContentMask);
        UiIcons.draw(hierarchyTitleIcon, Hierarchy, 0, 0, 17, Theme.TEXT_SECONDARY);
        hierarchyTitle = new h2d.Text(ctx.semiboldFont, leftContentMask);
        hierarchyTitle.text = "Scene Hierarchy";
        hierarchyTitle.textColor = Theme.TEXT;
        hierarchyTitle.lineBreak = false;
        hierarchyCount = new h2d.Text(ctx.captionFont, leftContentMask);
        hierarchyCount.textColor = Theme.MUTED;
        hierarchyCount.lineBreak = false;
        hierarchySearch = new SearchField(ctx, "Search scene objects", 100, 30, leftContentMask);
        hierarchySearch.onChange = function(value) applyHierarchyFilter(value);

        hierarchyHit = new h2d.Interactive(1, 1, leftContentMask);
        hierarchyHit.backgroundColor = 0;
        hierarchyHit.enableRightButton = true;
        hierarchyHit.onWheel = function(event) {
            if (!scrollHierarchy(event.wheelDelta)) return;
            event.propagate = false;
        };
        hierarchyHit.onClick = function(event) {
            if (event.button == 1) {
                palette.openAt(ctx.window.mouseX, ctx.window.mouseY, viewportRect);
                event.propagate = false;
            }
        };
        hierarchyScrollBar = new ScrollBar(ctx, leftContentMask);
        hierarchyScrollBar.onChange = function(value) {
            firstVisibleHierarchyRow = Std.int(Math.round(maxFirstVisibleHierarchyRow() * value));
            layoutHierarchyRows();
        };

        // Inspector panel header.
        inspectorTitleIcon = new h2d.Graphics(rightContentMask);
        UiIcons.draw(inspectorTitleIcon, Sliders, 0, 0, 17, Theme.TEXT_SECONDARY);
        inspectorTitle = new h2d.Text(ctx.semiboldFont, rightContentMask);
        inspectorTitle.text = "Details";
        inspectorTitle.textColor = Theme.TEXT;
        inspectorTitle.lineBreak = false;
        selectionStatus = new h2d.Text(ctx.captionFont, rightContentMask);
        selectionStatus.textColor = Theme.MUTED;
        selectionStatus.lineBreak = false;

        inspectorContentMask = new h2d.Mask(0, 0, rightContentMask);
        inspectorScrollHit = new h2d.Interactive(1, 1, inspectorContentMask);
        inspectorScrollHit.backgroundColor = 0;
        inspectorScrollHit.onWheel = function(event) {
            if (!scrollInspector(event.wheelDelta)) return;
            event.propagate = false;
        };

        identityCard = new UiSurface(ctx, inspectorContentMask);
        identityChevron = makeSectionChevron(inspectorContentMask);
        identityTitle = makeSectionTitle("IDENTITY", inspectorContentMask);
        objectNameField = new TextInputField(ctx, "Name", Theme.RIGHT_PANEL_WIDTH - 36,
            Theme.CONTROL_HEIGHT, "", inspectorContentMask);
        objectNameField.setLabelWidth(66);
        objectNameField.onCommit = function(name:String) {
            if (onObjectNameChanged != null) onObjectNameChanged(name);
        };
        objectNameField.onCancel = function() log("inspector: name edit cancelled");

        transformCard = new UiSurface(ctx, inspectorContentMask);
        transformChevron = makeSectionChevron(inspectorContentMask);
        transformTitle = makeSectionTitle("TRANSFORM", inspectorContentMask);
        transformSubtitle = new h2d.Text(ctx.captionFont, inspectorContentMask);
        transformSubtitle.text = "World position";
        transformSubtitle.textColor = Theme.MUTED;
        transformSubtitle.lineBreak = false;
        transformFields.push(new AxisValue(ctx, "X", Theme.AXIS_X, 60, 30, inspectorContentMask));
        transformFields.push(new AxisValue(ctx, "Y", Theme.AXIS_Y, 60, 30, inspectorContentMask));
        transformFields.push(new AxisValue(ctx, "Z", Theme.AXIS_Z, 60, 30, inspectorContentMask));

        behaviorCard = new UiSurface(ctx, inspectorContentMask);
        behaviorChevron = makeSectionChevron(inspectorContentMask);
        behaviorTitle = makeSectionTitle("BEHAVIOR", inspectorContentMask);
        spinLabel = new h2d.Text(ctx.font, inspectorContentMask);
        spinLabel.text = "Spin speed";
        spinLabel.textColor = Theme.TEXT_SECONDARY;
        spinLabel.lineBreak = false;
        spinRow = new Stepper(ctx, Theme.RIGHT_PANEL_WIDTH - 124, Theme.CONTROL_HEIGHT,
            0.0, 4.0, 0.25, 0.35,
            function(v:Float) {
                var hundredths = Math.round(v * 100);
                var fractional = hundredths % 100;
                return Std.string(Std.int(hundredths / 100)) + "."
                    + (fractional < 10 ? "0" : "") + Std.string(fractional);
            }, inspectorContentMask);
        spinRow.onValueChanged = function(v:Float) {
            if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        };
        spinRow.onEditRejected = function(message:String) log("inspector: " + message);

        materialCard = new UiSurface(ctx, inspectorContentMask);
        materialChevron = makeSectionChevron(inspectorContentMask);
        materialTitle = makeSectionTitle("MATERIAL", inspectorContentMask);
        colorLabel = new h2d.Text(ctx.font, inspectorContentMask);
        colorLabel.text = "Base color";
        colorLabel.textColor = Theme.TEXT_SECONDARY;
        colorLabel.lineBreak = false;
        colorRow = new SwatchPicker(ctx,
            [Theme.CUBE_ORANGE, Theme.CUBE_STEEL, Theme.CUBE_MOSS, Theme.CUBE_VIOLET],
            24, 8, inspectorContentMask);
        colorRow.onColorChanged = function(color:Int) {
            if (onColorChanged != null) onColorChanged(color);
        };

        inspectorScrollBar = new ScrollBar(ctx, rightContentMask);
        inspectorScrollBar.onChange = function(value) {
            inspectorScrollValue = value;
            inspectorContentMask.scrollY = maxInspectorScroll() * value;
        };

        // Subtle viewport HUD drawn above the scene but below popups.
        viewportHud = new h2d.Object(root);
        viewportModeSurface = new UiSurface(ctx, viewportHud);
        viewportModeSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0.25);
        viewportModeSurface.setSize(148, 28);
        viewportModeIcon = new h2d.Graphics(viewportHud);
        UiIcons.draw(viewportModeIcon, Grid, 0, 0, 14, Theme.TEXT_SECONDARY);
        viewportModeIcon.x = 9;
        viewportModeIcon.y = 7;
        viewportModeText = new h2d.Text(ctx.captionFont, viewportHud);
        viewportModeText.text = "PERSPECTIVE  ·  LIT";
        viewportModeText.textColor = Theme.TEXT_SECONDARY;
        viewportModeText.lineBreak = false;
        viewportModeText.x = 31;
        viewportModeText.y = 6;

        viewportHintSurface = new UiSurface(ctx, viewportHud);
        viewportHintSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0.25);
        viewportHintSurface.setSize(98, 28);
        viewportHintIcon = new h2d.Graphics(viewportHud);
        UiIcons.draw(viewportHintIcon, Move, 0, 0, 14, Theme.TEXT_SECONDARY);
        viewportHintText = new h2d.Text(ctx.captionFont, viewportHud);
        viewportHintText.text = "LOCAL";
        viewportHintText.textColor = Theme.TEXT_SECONDARY;
        viewportHintText.lineBreak = false;

        console = new ConsolePanel(ctx, root);

        statusDot = new h2d.Graphics(root);
        statusDot.beginFill(Theme.SUCCESS);
        statusDot.drawCircle(4, 4, 4, 12);
        statusDot.endFill();
        statusText = new h2d.Text(ctx.captionFont, root);
        statusText.text = "Ready";
        statusText.textColor = Theme.TEXT_SECONDARY;
        statusText.lineBreak = false;
        rendererStatus = new h2d.Text(ctx.captionFont, root);
        rendererStatus.text = "DX12  ·  Native  ·  1 object";
        rendererStatus.textColor = Theme.MUTED;
        rendererStatus.lineBreak = false;
        inputStatus = new h2d.Text(ctx.captionFont, root);
        inputStatus.textColor = Theme.MUTED;
        inputStatus.lineBreak = false;
        input.bindReport(inputStatus);
        input.onDeletePressed = function() {
            if (objectNameField.isFocused() || spinRow.isEditing() || hierarchySearch.isFocused()) return;
            deleteSelection();
        };

        dockLayout = new DockLayout();
        layoutStore = new DockLayoutStore();
        var layoutError = layoutStore.load(dockLayout);

        // Splitters are created late so their interactive hit zones remain on
        // top of panel content.
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

        palette = new GameObjectPalette(ctx, root);
        palette.onCreateCube = function() {
            if (onCreateObject != null) onCreateObject();
        };
        palette.onDropCube = function(x, y) {
            if (onCreateObjectAt != null) onCreateObjectAt(x, y);
        };

        if (layoutError != null) log("layout: " + layoutError);
        selectionStatus.text = selectionStatusValue;
        inspectorContentMask.visible = false;
        resize();
    }

    function makeSectionChevron(parent:h2d.Object):h2d.Graphics {
        var graphic = new h2d.Graphics(parent);
        UiIcons.draw(graphic, ChevronDown, 0, 0, 11, Theme.MUTED);
        return graphic;
    }

    function makeSectionTitle(value:String, parent:h2d.Object):h2d.Text {
        var result = new h2d.Text(ctx.captionFont, parent);
        result.text = value;
        result.textColor = Theme.TEXT_SECONDARY;
        result.lineBreak = false;
        return result;
    }

    function drawBrandMark():Void {
        brandMark.clear();
        brandMark.beginFill(Theme.BRAND);
        brandMark.drawRoundedRect(0, 0, 22, 22, 6, 5);
        brandMark.endFill();
        brandMark.beginFill(0x161A20);
        brandMark.moveTo(12, 3);
        brandMark.lineTo(6, 12);
        brandMark.lineTo(11, 12);
        brandMark.lineTo(9, 20);
        brandMark.lineTo(17, 9);
        brandMark.lineTo(12, 9);
        brandMark.lineTo(12, 3);
        brandMark.endFill();
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
        var fitted = "";
        for (i in 0...value.length) {
            var candidate = value.substr(0, i + 1) + "…";
            if (target.calcTextWidth(candidate) > maxWidth) break;
            fitted = candidate;
        }
        target.text = fitted;
    }

    public inline function log(line:String):Void console.log(line);

    public function update(dt:Float):Void {
        if (ctx.width != lastWidth || ctx.height != lastHeight) resize();
        if (inputStatus.visible) inputStatus.x = Math.max(0, ctx.width - inputStatus.textWidth - 16);
    }

    public function resize():Void {
        var width = ctx.width;
        var height = ctx.height;
        var bodyTop = Theme.TOP_BAR_HEIGHT;
        var geometry = dockLayout.calculate(width, height);
        viewportRect = geometry.viewport;
        var leftWidth = geometry.leftPanel.width;
        var rightWidth = Math.max(0, geometry.rightPanel.width);
        var rightX = geometry.rightPanel.x;

        lastWidth = width;
        lastHeight = height;
        leftContentMask.width = Std.int(Math.max(0, leftWidth));
        leftContentMask.height = Std.int(Math.max(0, height - Theme.STATUS_BAR_HEIGHT));
        leftContentMask.visible = leftWidth >= 140;
        rightContentMask.x = rightX;
        rightContentMask.width = Std.int(rightWidth);
        rightContentMask.height = Std.int(Math.max(0, height - Theme.STATUS_BAR_HEIGHT));
        rightContentMask.visible = rightWidth >= 180;

        drawChrome(width, height, geometry);

        leftSplitter.setBounds(geometry.leftSplitter.x, geometry.leftSplitter.y,
            geometry.leftSplitter.width, geometry.leftSplitter.height);
        rightSplitter.setBounds(geometry.rightSplitter.x, geometry.rightSplitter.y,
            geometry.rightSplitter.width, geometry.rightSplitter.height);
        consoleSplitter.setBounds(geometry.consoleSplitter.x, geometry.consoleSplitter.y,
            geometry.consoleSplitter.width, geometry.consoleSplitter.height);

        viewportHit.x = geometry.viewport.x;
        viewportHit.y = geometry.viewport.y;
        viewportHit.width = Math.max(0, geometry.viewport.width);
        viewportHit.height = Math.max(0, geometry.viewport.height);

        layoutTopBars(width);
        layoutHierarchy(leftWidth, bodyTop);
        layoutInspector(rightWidth, bodyTop);

        console.x = geometry.console.x + 8;
        console.y = geometry.console.y + 5;
        console.layout(Math.max(0, geometry.console.width - 16),
            Math.max(0, geometry.console.height - 10));

        viewportHud.visible = geometry.viewport.width >= 290 && geometry.viewport.height >= 80;
        viewportHud.x = geometry.viewport.x + 12;
        viewportHud.y = geometry.viewport.y + 12;
        viewportHintSurface.x = Math.max(156, geometry.viewport.width - 122);
        viewportHintIcon.x = viewportHintSurface.x + 10;
        viewportHintIcon.y = 7;
        viewportHintText.x = viewportHintSurface.x + 33;
        viewportHintText.y = 6;

        var statusY = height - Theme.STATUS_BAR_HEIGHT;
        statusDot.x = 12;
        statusDot.y = statusY + 9;
        statusText.x = 26;
        statusText.y = statusY + 4;
        rendererStatus.x = 92;
        rendererStatus.y = statusY + 4;
        inputStatus.visible = width >= 930;
        if (inputStatus.visible) {
            inputStatus.x = Math.max(0, width - inputStatus.textWidth - 16);
            inputStatus.y = statusY + 4;
        }
    }

    function drawChrome(width:Float, height:Float, geometry:DockLayoutGeometry):Void {
        chrome.clear();
        chrome.beginFill(Theme.TITLE_BAR);
        chrome.drawRect(0, 0, width, Theme.TITLE_BAR_HEIGHT);
        chrome.endFill();
        chrome.beginFill(Theme.TOOLBAR);
        chrome.drawRect(0, Theme.TITLE_BAR_HEIGHT, width, Theme.TOOLBAR_HEIGHT);
        chrome.endFill();
        chrome.beginFill(Theme.PANEL);
        chrome.drawRect(geometry.leftPanel.x, geometry.leftPanel.y,
            geometry.leftPanel.width, geometry.leftPanel.height);
        chrome.drawRect(geometry.rightPanel.x, geometry.rightPanel.y,
            geometry.rightPanel.width, geometry.rightPanel.height);
        chrome.drawRect(geometry.console.x, geometry.console.y,
            geometry.console.width, geometry.console.height);
        chrome.endFill();
        chrome.beginFill(Theme.PANEL_HEADER);
        chrome.drawRect(geometry.leftPanel.x, geometry.leftPanel.y,
            geometry.leftPanel.width, 43);
        chrome.drawRect(geometry.rightPanel.x, geometry.rightPanel.y,
            geometry.rightPanel.width, 63);
        chrome.endFill();
        chrome.beginFill(Theme.TITLE_BAR);
        chrome.drawRect(0, height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT);
        chrome.endFill();

        chrome.lineStyle(1, Theme.BORDER, 1);
        chrome.moveTo(0, Theme.TITLE_BAR_HEIGHT);
        chrome.lineTo(width, Theme.TITLE_BAR_HEIGHT);
        chrome.moveTo(0, Theme.TOP_BAR_HEIGHT);
        chrome.lineTo(width, Theme.TOP_BAR_HEIGHT);
        chrome.moveTo(0, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineTo(width, height - Theme.STATUS_BAR_HEIGHT);
        chrome.drawRect(geometry.viewport.x, geometry.viewport.y,
            geometry.viewport.width, geometry.viewport.height);
        chrome.lineStyle();
    }

    function layoutTopBars(width:Float):Void {
        brandMark.x = 13;
        brandMark.y = 7;
        appTitle.x = 44;
        appTitle.y = 6;

        var menuX = 152.0;
        for (index in 0...menuButtons.length) {
            var button = menuButtons[index];
            button.x = menuX;
            button.y = 5;
            button.visible = width > menuX + 90;
            menuX += switch (index) {
                case 2: 62;
                case 3: 72;
                default: 54;
            };
        }
        projectTitle.visible = width >= 860;
        projectTitle.x = Math.max(menuX + 10, width - projectTitle.textWidth - 16);
        projectTitle.y = 8;

        var toolbarY = Theme.TITLE_BAR_HEIGHT + 7;
        addObjectButton.x = 12;
        addObjectButton.y = toolbarY;
        deleteObjectsButton.x = 120;
        deleteObjectsButton.y = toolbarY;
        deleteObjectsButton.visible = selectedObjectIds.length > 0;
        deleteObjectsButton.setText(selectedObjectIds.length > 1
            ? 'Delete (${selectedObjectIds.length})' : "Delete");

        var toolX = deleteObjectsButton.visible ? 236.0 : 128.0;
        for (button in transformButtons) {
            button.x = toolX;
            button.y = toolbarY;
            toolX += 38;
        }
        var transportX = Math.max(toolX + 20, width * 0.5 - 58);
        for (button in transportButtons) {
            button.x = transportX;
            button.y = toolbarY;
            button.visible = width > 620;
            transportX += 40;
        }
    }

    function layoutHierarchy(leftWidth:Float, bodyTop:Float):Void {
        hierarchyTitleIcon.x = 14;
        hierarchyTitleIcon.y = bodyTop + 13;
        hierarchyTitle.x = 40;
        hierarchyTitle.y = bodyTop + 9;
        hierarchyCount.text = hierarchyFilter.length == 0
            ? Std.string(allHierarchyEntries.length)
            : visibleHierarchyEntries.length + "/" + allHierarchyEntries.length;
        hierarchyCount.x = Math.max(42, leftWidth - hierarchyCount.textWidth - 15);
        hierarchyCount.y = bodyTop + 12;

        hierarchySearch.x = 12;
        hierarchySearch.y = bodyTop + 51;
        hierarchySearch.setWidth(Math.max(0, leftWidth - 24));
        hierarchyHit.x = 8;
        hierarchyHit.y = bodyTop + 91;
        hierarchyHit.width = Math.max(0, leftWidth - 22);
        hierarchyHit.height = Math.max(0,
            leftContentMask.height - hierarchyHit.y - 10);
        hierarchyScrollBar.setBounds(Math.max(0, leftWidth - 10), hierarchyHit.y,
            5, hierarchyHit.height);
        layoutHierarchyRows();
    }

    function layoutInspector(rightWidth:Float, bodyTop:Float):Void {
        inspectorTitleIcon.x = 14;
        inspectorTitleIcon.y = bodyTop + 13;
        inspectorTitle.x = 40;
        inspectorTitle.y = bodyTop + 9;
        selectionStatus.x = 14;
        selectionStatus.y = bodyTop + 36;
        fitText(selectionStatus, selectionStatusValue, Math.max(0, rightWidth - 28));

        inspectorContentMask.x = 0;
        inspectorContentMask.y = bodyTop + 68;
        inspectorContentMask.width = Std.int(Math.max(0, rightWidth - 16));
        inspectorContentMask.height = Std.int(Math.max(0,
            rightContentMask.height - inspectorContentMask.y - 10));
        inspectorScrollHit.width = inspectorContentMask.width;
        inspectorScrollHit.height = inspectorContentMask.height;
        inspectorScrollBar.setBounds(Math.max(0, rightWidth - 10),
            inspectorContentMask.y, 5, inspectorContentMask.height);
        layoutInspectorProperties();
    }

    function layoutInspectorProperties():Void {
        var width = Math.max(0, inspectorContentMask.width - 10);
        var cardX = 5.0;
        layoutCard(identityCard, identityChevron, identityTitle, cardX, 4, width, 78);
        objectNameField.x = cardX + 12;
        objectNameField.y = 42;
        objectNameField.setWidth(Math.max(0, width - 24));

        layoutCard(transformCard, transformChevron, transformTitle, cardX, 90, width, 112);
        transformSubtitle.x = cardX + 14;
        transformSubtitle.y = 121;
        var axisGap = 6.0;
        var axisWidth = Math.max(0, (width - 28 - axisGap * 2) / 3);
        for (index in 0...transformFields.length) {
            transformFields[index].x = cardX + 14 + index * (axisWidth + axisGap);
            transformFields[index].y = 157;
            transformFields[index].setWidth(axisWidth);
        }

        layoutCard(behaviorCard, behaviorChevron, behaviorTitle, cardX, 210, width, 94);
        spinLabel.x = cardX + 14;
        spinLabel.y = 258;
        var spinWidth = Math.max(84, width - 112);
        spinRow.x = cardX + width - spinWidth - 14;
        spinRow.y = 250;
        spinRow.setWidth(spinWidth);

        layoutCard(materialCard, materialChevron, materialTitle, cardX, 312, width, 100);
        colorLabel.x = cardX + 14;
        colorLabel.y = 363;
        colorRow.x = cardX + Math.max(92, width - 142);
        colorRow.y = 352;

        var ratio = Math.min(1, inspectorContentMask.height / INSPECTOR_CONTENT_HEIGHT);
        inspectorScrollBar.setMetrics(ratio, inspectorScrollValue);
        inspectorScrollBar.visible = inspectorContentMask.visible && ratio < 1;
        inspectorContentMask.scrollY = maxInspectorScroll() * inspectorScrollValue;
    }

    function layoutCard(card:UiSurface, chevron:h2d.Graphics, title:h2d.Text,
            x:Float, y:Float, width:Float, height:Float):Void {
        card.x = x;
        card.y = y;
        card.setSize(width, height);
        card.setStyle(Theme.PANEL_ALT, Theme.BORDER, 0.10);
        chevron.x = x + 12;
        chevron.y = y + 13;
        title.x = x + 31;
        title.y = y + 10;
    }

    function maxInspectorScroll():Float {
        return Math.max(0, INSPECTOR_CONTENT_HEIGHT - inspectorContentMask.height);
    }

    function scrollInspector(delta:Float):Bool {
        if (maxInspectorScroll() <= 0) return false;
        inspectorScrollValue = Math.max(0, Math.min(1,
            inspectorScrollValue - delta * 36 / maxInspectorScroll()));
        inspectorContentMask.scrollY = maxInspectorScroll() * inspectorScrollValue;
        inspectorScrollBar.setMetrics(
            inspectorContentMask.height / INSPECTOR_CONTENT_HEIGHT, inspectorScrollValue);
        return true;
    }

    function saveLayout():Void {
        var error = layoutStore.save(dockLayout);
        if (error != null) log("layout: " + error);
    }

    public function setHierarchyEntries(entries:Array<HierarchyEntry>):Void {
        allHierarchyEntries.resize(0);
        for (entry in entries) allHierarchyEntries.push(entry);
        rebuildFilteredHierarchy();
        rendererStatus.text = "DX12  ·  Native  ·  " + entries.length
            + (entries.length == 1 ? " object" : " objects");
    }

    function applyHierarchyFilter(value:String):Void {
        hierarchyFilter = StringTools.trim(value).toLowerCase();
        firstVisibleHierarchyRow = 0;
        selectionAnchorIndex = -1;
        rebuildFilteredHierarchy();
    }

    function rebuildFilteredHierarchy():Void {
        visibleHierarchyEntries.resize(0);
        for (entry in allHierarchyEntries) {
            if (hierarchyFilter.length == 0
                || entry.name.toLowerCase().indexOf(hierarchyFilter) >= 0) {
                visibleHierarchyEntries.push(entry);
            }
        }
        while (hierarchyRows.length > visibleHierarchyEntries.length) hierarchyRows.pop().remove();
        for (index in 0...visibleHierarchyEntries.length) {
            var entry = visibleHierarchyEntries[index];
            var row:HierarchyRow;
            if (index < hierarchyRows.length) {
                row = hierarchyRows[index];
                row.objectId = entry.id;
                row.setName(entry.name);
            } else {
                row = new HierarchyRow(ctx, entry.id, entry.name, leftContentMask);
                row.onSelect = selectHierarchyRow;
                row.onWheel = function(delta) scrollHierarchy(delta);
                hierarchyRows.push(row);
            }
        }
        resize();
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, speed:Float, color:Int, posX:Float = 0, posY:Float = 0,
            posZ:Float = 0):Void {
        selectedObjectIds = ids.copy();
        selectedObjectId = primaryId;
        if (selectedObjectIds.length == 1) {
            for (index in 0...hierarchyRows.length) {
                if (hierarchyRows[index].objectId != primaryId) continue;
                var visibleRows = hierarchyVisibleRowCount();
                if (index < firstVisibleHierarchyRow) firstVisibleHierarchyRow = index;
                else if (index >= firstVisibleHierarchyRow + visibleRows)
                    firstVisibleHierarchyRow = index - visibleRows + 1;
                break;
            }
            objectNameField.setValue(name);
            spinRow.setValue(speed);
            colorRow.setColor(color);
            transformFields[0].setValue(posX);
            transformFields[1].setValue(posY);
            transformFields[2].setValue(posZ);
            inspectorContentMask.visible = true;
            selectionStatusValue = name + "  ·  Game Object";
        } else {
            inspectorContentMask.visible = false;
            selectionStatusValue = selectedObjectIds.length > 1
                ? selectedObjectIds.length + " objects selected"
                : "Select an object to inspect";
        }
        selectionStatus.text = selectionStatusValue;
        inspectorScrollValue = 0;
        inspectorContentMask.scrollY = 0;
        layoutHierarchyRows();
        resize();
    }

    public inline function setObjectName(value:String):Void objectNameField.setValue(value);

    function selectHierarchyRow(id:Int, control:Bool, shift:Bool):Void {
        var clickedIndex = -1;
        for (index in 0...hierarchyRows.length) {
            if (hierarchyRows[index].objectId == id) {
                clickedIndex = index;
                break;
            }
        }
        if (clickedIndex < 0) return;

        var selection = control ? selectedObjectIds.copy() : [];
        if (shift && selectionAnchorIndex >= 0) {
            selection = [];
            var first = Std.int(Math.min(selectionAnchorIndex, clickedIndex));
            var last = Std.int(Math.max(selectionAnchorIndex, clickedIndex));
            for (index in first...(last + 1)) selection.push(hierarchyRows[index].objectId);
        } else if (control) {
            if (selection.indexOf(id) >= 0) selection.remove(id) else selection.push(id);
            selectionAnchorIndex = clickedIndex;
        } else {
            selection = [id];
            selectionAnchorIndex = clickedIndex;
        }

        var primary = selection.indexOf(id) >= 0 ? id
            : (selection.length == 0 ? -1 : selection[selection.length - 1]);
        if (onObjectsSelected != null) onObjectsSelected(selection, primary);
    }

    function layoutHierarchyRows():Void {
        var visibleRows = hierarchyVisibleRowCount();
        firstVisibleHierarchyRow = Std.int(Math.max(0, Math.min(
            maxFirstVisibleHierarchyRow(), firstVisibleHierarchyRow)));
        for (index in 0...hierarchyRows.length) {
            var row = hierarchyRows[index];
            var visibleIndex = index - firstVisibleHierarchyRow;
            var isVisible = visibleIndex >= 0 && visibleIndex < visibleRows;
            row.visible = isVisible;
            if (isVisible) {
                row.setBounds(10, hierarchyHit.y + visibleIndex * HIERARCHY_ROW_HEIGHT,
                    Math.max(0, hierarchyHit.width - 4),
                    selectedObjectIds.indexOf(row.objectId) >= 0);
            }
        }
        var ratio = hierarchyRows.length == 0 ? 1 : Math.min(1, visibleRows / hierarchyRows.length);
        var maxFirst = maxFirstVisibleHierarchyRow();
        hierarchyScrollBar.setMetrics(ratio, maxFirst == 0 ? 0 : firstVisibleHierarchyRow / maxFirst);
    }

    function hierarchyVisibleRowCount():Int {
        return Std.int(Math.max(1, Math.floor(hierarchyHit.height / HIERARCHY_ROW_HEIGHT)));
    }

    function maxFirstVisibleHierarchyRow():Int {
        return Std.int(Math.max(0, hierarchyRows.length - hierarchyVisibleRowCount()));
    }

    function scrollHierarchy(delta:Float):Bool {
        if (maxFirstVisibleHierarchyRow() <= 0) return false;
        firstVisibleHierarchyRow = Std.int(Math.max(0, Math.min(maxFirstVisibleHierarchyRow(),
            firstVisibleHierarchyRow - delta * 3)));
        layoutHierarchyRows();
        return true;
    }

    function deleteSelection():Void {
        if (selectedObjectIds.length > 0 && onDeleteObjects != null) {
            onDeleteObjects(selectedObjectIds.copy());
        }
    }
}
