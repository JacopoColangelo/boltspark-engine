package boltspark.ui;

import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.GameObjectPalette;
import boltspark.ui.widgets.HierarchyRow;
import boltspark.ui.widgets.ScrollBar;
import boltspark.ui.widgets.Stepper;
import boltspark.ui.widgets.SwatchPicker;
import boltspark.ui.widgets.TextInputField;
import boltspark.ui.widgets.UiButton;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;

class EditorShell {
    static inline var HIERARCHY_ROW_HEIGHT:Int = 30;
    static inline var INSPECTOR_CONTENT_HEIGHT:Int = 300;

    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;
    final appTitle:h2d.Text;
    final hierarchyTitle:h2d.Text;
    final hierarchyHit:h2d.Interactive;
    final hierarchyRows:Array<HierarchyRow> = [];
    final hierarchyScrollBar:ScrollBar;
    final inspectorTitle:h2d.Text;
    final selectionStatus:h2d.Text;
    final statusText:h2d.Text;
    final inputStatus:h2d.Text;
    final leftSplitter:DockSplitter;
    final rightSplitter:DockSplitter;
    final consoleSplitter:DockSplitter;
    final leftContentMask:h2d.Mask;
    final rightContentMask:h2d.Mask;
    final inspectorContentMask:h2d.Mask;
    final inspectorScrollHit:h2d.Interactive;
    final inspectorScrollBar:ScrollBar;
    final dockLayout:DockLayout;
    final layoutStore:DockLayoutStore;
    final addObjectButton:UiButton;
    final deleteObjectsButton:UiButton;
    final palette:GameObjectPalette;
    final viewportHit:h2d.Interactive;
    final spinRow:Stepper;
    final colorRow:SwatchPicker;
    final objectNameField:TextInputField;
    final spinLabel:h2d.Text;
    final colorLabel:h2d.Text;
    final nameCard:h2d.Graphics;
    final spinCard:h2d.Graphics;
    final colorCard:h2d.Graphics;
    final console:ConsolePanel;

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

    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter) {
        this.ctx = ctx;
        this.input = input;
        root = new h2d.Object(parent);
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

        addObjectButton = new UiButton(ctx, "Add Game Object", 148, 34, root);
        addObjectButton.onClick = function() {
            if (viewportRect != null) {
                palette.toggleAt(addObjectButton.x, addObjectButton.y + 38, viewportRect);
            }
        };
        deleteObjectsButton = new UiButton(ctx, "Delete selected", 148, 34, root);
        deleteObjectsButton.visible = false;
        deleteObjectsButton.onClick = deleteSelection;

        hierarchyTitle = new h2d.Text(ctx.font, leftContentMask);
        hierarchyTitle.text = "HIERARCHY";
        hierarchyTitle.textColor = Theme.MUTED;
        hierarchyTitle.lineBreak = false;

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

        inspectorTitle = new h2d.Text(ctx.font, rightContentMask);
        inspectorTitle.text = "INSPECTOR";
        inspectorTitle.textColor = Theme.MUTED;
        inspectorTitle.lineBreak = false;
        selectionStatus = new h2d.Text(ctx.font, rightContentMask);
        selectionStatus.textColor = Theme.MUTED;
        selectionStatus.lineBreak = false;

        inspectorContentMask = new h2d.Mask(0, 0, rightContentMask);
        inspectorScrollHit = new h2d.Interactive(1, 1, inspectorContentMask);
        inspectorScrollHit.backgroundColor = 0;
        inspectorScrollHit.onWheel = function(event) {
            if (!scrollInspector(event.wheelDelta)) return;
            event.propagate = false;
        };
        nameCard = new h2d.Graphics(inspectorContentMask);
        spinCard = new h2d.Graphics(inspectorContentMask);
        colorCard = new h2d.Graphics(inspectorContentMask);

        objectNameField = new TextInputField(ctx, "Object name", Theme.RIGHT_PANEL_WIDTH - 56,
            Theme.CONTROL_HEIGHT, "", inspectorContentMask);
        objectNameField.onCommit = function(name:String) {
            if (onObjectNameChanged != null) onObjectNameChanged(name);
        };
        objectNameField.onCancel = function() log("inspector: object name edit cancelled");

        spinLabel = new h2d.Text(ctx.font, inspectorContentMask);
        spinLabel.text = "Spin speed (rad/s)";
        spinLabel.textColor = Theme.MUTED;
        spinLabel.lineBreak = false;
        spinRow = new Stepper(ctx, Theme.RIGHT_PANEL_WIDTH - 56, Theme.CONTROL_HEIGHT,
            0.0, 4.0, 0.25, 0.35,
            function(v:Float) {
                var hundredths = Math.round(v * 100);
                var fractional = hundredths % 100;
                return Std.string(Std.int(hundredths / 100)) + "."
                    + (fractional < 10 ? "0" : "") + Std.string(fractional);
            },
            inspectorContentMask);
        spinRow.onValueChanged = function(v:Float) {
            if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        };
        spinRow.onEditRejected = function(message:String) log("inspector: " + message);

        colorLabel = new h2d.Text(ctx.font, inspectorContentMask);
        colorLabel.text = "Base color";
        colorLabel.textColor = Theme.MUTED;
        colorLabel.lineBreak = false;
        colorRow = new SwatchPicker(ctx,
            [Theme.CUBE_ORANGE, Theme.CUBE_STEEL, Theme.CUBE_MOSS, Theme.CUBE_VIOLET],
            22, 8, inspectorContentMask);
        colorRow.onColorChanged = function(color:Int) {
            if (onColorChanged != null) onColorChanged(color);
        };

        inspectorScrollBar = new ScrollBar(ctx, rightContentMask);
        inspectorScrollBar.onChange = function(value) {
            inspectorScrollValue = value;
            inspectorContentMask.scrollY = maxInspectorScroll() * value;
        };

        palette = new GameObjectPalette(ctx, root);
        palette.onCreateCube = function() {
            if (onCreateObject != null) onCreateObject();
        };
        palette.onDropCube = function(x, y) {
            if (onCreateObjectAt != null) onCreateObjectAt(x, y);
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
        input.onDeletePressed = function() {
            if (objectNameField.isFocused() || spinRow.isEditing()) return;
            deleteSelection();
        };

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
        var fitted = "";
        for (i in 0...value.length) {
            var candidate = value.substr(0, i + 1) + "...";
            if (target.calcTextWidth(candidate) > maxWidth) break;
            fitted = candidate;
        }
        target.text = fitted;
    }

    public function log(line:String):Void {
        console.log(line);
    }

    public function update(dt:Float):Void {
        if (ctx.width != lastWidth || ctx.height != lastHeight) resize();
    }

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
        chrome.beginFill(Theme.TOP_BAR);
        chrome.drawRect(0, 0, width, Theme.TOP_BAR_HEIGHT);
        chrome.endFill();
        chrome.beginFill(Theme.PANEL);
        chrome.drawRect(geometry.leftPanel.x, geometry.leftPanel.y,
            geometry.leftPanel.width, geometry.leftPanel.height);
        chrome.drawRect(geometry.rightPanel.x, geometry.rightPanel.y,
            geometry.rightPanel.width, geometry.rightPanel.height);
        chrome.drawRect(geometry.console.x, geometry.console.y,
            geometry.console.width, geometry.console.height);
        chrome.drawRect(0, height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT);
        chrome.endFill();
        chrome.lineStyle(1, Theme.PANEL_EDGE, 1);
        chrome.moveTo(geometry.leftSplitter.x + splitterSize / 2, geometry.leftSplitter.y);
        chrome.lineTo(geometry.leftSplitter.x + splitterSize / 2, height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(geometry.rightSplitter.x + splitterSize / 2, geometry.rightSplitter.y);
        chrome.lineTo(geometry.rightSplitter.x + splitterSize / 2, height - Theme.STATUS_BAR_HEIGHT);
        chrome.moveTo(0, bodyTop);
        chrome.lineTo(width, bodyTop);
        chrome.moveTo(geometry.consoleSplitter.x, geometry.consoleSplitter.y + splitterSize / 2);
        chrome.lineTo(geometry.consoleSplitter.x + geometry.consoleSplitter.width,
            geometry.consoleSplitter.y + splitterSize / 2);
        chrome.moveTo(0, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineTo(width, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineStyle();

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

        appTitle.x = 16;
        appTitle.y = 15;
        fitText(appTitle, "BOLTSPARK", Math.max(0, width - 32));
        addObjectButton.x = 154;
        addObjectButton.y = 7;
        deleteObjectsButton.x = 310;
        deleteObjectsButton.y = 7;
        deleteObjectsButton.visible = selectedObjectIds.length > 0;
        deleteObjectsButton.setText(selectedObjectIds.length > 1
            ? 'Delete ${selectedObjectIds.length} selected'
            : "Delete selected");

        hierarchyTitle.x = 16;
        hierarchyTitle.y = bodyTop + 16;
        fitText(hierarchyTitle, "HIERARCHY", Math.max(0, leftWidth - 24));
        hierarchyHit.x = 10;
        hierarchyHit.y = bodyTop + 48;
        hierarchyHit.width = Math.max(0, leftWidth - 28);
        hierarchyHit.height = Math.max(0, leftContentMask.height - hierarchyHit.y - 12);
        hierarchyScrollBar.setBounds(Math.max(0, leftWidth - 14), hierarchyHit.y,
            8, hierarchyHit.height);
        layoutHierarchyRows();

        inspectorTitle.x = 16;
        inspectorTitle.y = bodyTop + 16;
        fitText(inspectorTitle, "INSPECTOR", Math.max(0, rightWidth - 24));
        selectionStatus.x = 16;
        selectionStatus.y = bodyTop + 48;
        inspectorContentMask.x = 0;
        inspectorContentMask.y = bodyTop + 76;
        inspectorContentMask.width = Std.int(Math.max(0, rightWidth - 28));
        inspectorContentMask.height = Std.int(Math.max(0,
            rightContentMask.height - inspectorContentMask.y - 12));
        inspectorScrollHit.width = inspectorContentMask.width;
        inspectorScrollHit.height = inspectorContentMask.height;
        inspectorScrollBar.setBounds(Math.max(0, rightWidth - 14),
            inspectorContentMask.y, 8, inspectorContentMask.height);
        layoutInspectorProperties();

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

    function layoutInspectorProperties():Void {
        var width = Math.max(0, inspectorContentMask.width - 12);
        drawPropertyCard(nameCard, width, 88);
        drawPropertyCard(spinCard, width, 88);
        drawPropertyCard(colorCard, width, 88);
        nameCard.x = 8;
        nameCard.y = 4;
        spinCard.x = 8;
        spinCard.y = 102;
        colorCard.x = 8;
        colorCard.y = 200;
        objectNameField.x = 18;
        objectNameField.y = 13;
        objectNameField.setWidth(Math.max(0, width - 20));
        spinLabel.x = 18;
        spinLabel.y = 110;
        fitText(spinLabel, "Spin speed (rad/s)", Math.max(0, width - 20));
        spinRow.setWidth(Math.max(0, width - 20));
        spinRow.x = 18;
        spinRow.y = 132;
        colorLabel.x = 18;
        colorLabel.y = 208;
        colorRow.x = 18;
        colorRow.y = 232;
        var ratio = Math.min(1, inspectorContentMask.height / INSPECTOR_CONTENT_HEIGHT);
        inspectorScrollBar.setMetrics(ratio, inspectorScrollValue);
        inspectorScrollBar.visible = inspectorContentMask.visible && ratio < 1;
        inspectorContentMask.scrollY = maxInspectorScroll() * inspectorScrollValue;
    }

    function drawPropertyCard(graphic:h2d.Graphics, width:Float, height:Float):Void {
        graphic.clear();
        graphic.beginFill(Theme.PROPERTY_BG);
        graphic.drawRect(0, 0, width, height);
        graphic.endFill();
        graphic.lineStyle(1, Theme.PANEL_EDGE, 1);
        graphic.drawRect(0, 0, width, height);
        graphic.lineStyle();
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
        while (hierarchyRows.length > entries.length) hierarchyRows.pop().remove();
        if (selectionAnchorIndex >= entries.length) selectionAnchorIndex = entries.length - 1;
        for (index in 0...entries.length) {
            var entry = entries[index];
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
            name:String, speed:Float, color:Int):Void {
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
            inspectorContentMask.visible = true;
            selectionStatus.text = "Selected object properties";
        } else {
            inspectorContentMask.visible = false;
            if (selectedObjectIds.length > 1) {
                selectionStatus.text = '${selectedObjectIds.length} objects selected — select one to edit properties.';
            } else {
                selectionStatus.text = "Select an object to view its properties.";
            }
        }
        inspectorScrollValue = 0;
        inspectorContentMask.scrollY = 0;
        layoutHierarchyRows();
        resize();
    }

    public function setObjectName(value:String):Void {
        objectNameField.setValue(value);
    }

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
            if (selection.indexOf(id) >= 0) selection.remove(id);
            else selection.push(id);
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
            var visible = visibleIndex >= 0 && visibleIndex < visibleRows;
            row.visible = visible;
            if (visible) {
                row.setBounds(12, hierarchyHit.y + visibleIndex * HIERARCHY_ROW_HEIGHT,
                    hierarchyHit.width - 2, selectedObjectIds.indexOf(row.objectId) >= 0);
            }
        }
        var ratio = hierarchyRows.length == 0 ? 1
            : Math.min(1, visibleRows / hierarchyRows.length);
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
