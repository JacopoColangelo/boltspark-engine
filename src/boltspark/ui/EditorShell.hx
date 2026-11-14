package boltspark.ui;

import boltspark.editor.GridSnapping;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.windows.ApplicationWindowKind;
import boltspark.ui.widgets.AxisValue;
import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.GameObjectPalette;
import boltspark.ui.widgets.HierarchyRow;
import boltspark.ui.widgets.InspectorSection;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.ScrollBar;
import boltspark.ui.widgets.SearchField;
import boltspark.ui.widgets.TextInputField;
import boltspark.ui.widgets.UiButton;
import boltspark.ui.widgets.ViewportSnapBar;

/**
 * Retained native editor shell. All controls are Heaps H2D objects rendered in
 * the same DX12 window as the scene; there is no browser or foreign UI layer.
 */
class EditorShell {
    static inline var HIERARCHY_ROW_HEIGHT:Int = 22;
    static inline var INSPECTOR_ROW_HEIGHT:Int = 28;
    static inline var TRANSFORM_ACTION_WIDTH:Int = 22;

    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;
    final editorBackgroundHit:h2d.Interactive;

    // Title/menu bar and editor toolbar.
    final brandMark:h2d.Bitmap;
    final projectTitle:h2d.Text;
    final menuButtons:Array<UiButton> = [];
    final addObjectButton:UiButton;
    final transformButtons:Array<UiButton> = [];
    final transportButtons:Array<UiButton> = [];

    // Hierarchy panel.
    final leftContentMask:h2d.Mask;
    final hierarchyPanelHit:h2d.Interactive;
    final hierarchyTitleIcon:h2d.Graphics;
    final hierarchyTitle:h2d.Text;
    final hierarchyCount:h2d.Text;
    final hierarchySearch:SearchField;
    final hierarchyAddButton:UiButton;
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
    final inspectorSections:Array<InspectorSection>;
    var inspectorContentHeight:Float = 0;

    final objectSection:InspectorSection;
    final objectNameField:TextInputField;

    final transformSection:InspectorSection;
    final transformLabels:Array<h2d.Text> = [];
    final transformFields:Array<AxisValue> = [];
    final rotationFields:Array<AxisValue> = [];
    final scaleFields:Array<AxisValue> = [];
    final transformResetButtons:Array<UiButton> = [];
    final scaleLinkButton:UiButton;

    // Viewport/console/status.
    final viewportHit:h2d.Interactive;
    final viewportHud:h2d.Object;
    final viewportModeSurface:UiSurface;
    final viewportModeIcon:h2d.Graphics;
    final viewportModeText:h2d.Text;
    final viewportHintSurface:UiSurface;
    final viewportHintIcon:h2d.Graphics;
    final viewportHintText:h2d.Text;
    final viewportHintHit:h2d.Interactive;
    final snapBar:ViewportSnapBar;
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
    final menuDropdown:MenuDropdown;

    public var onCreateObject:Null<Void->Void>;
    public var onCreateObjectAt:Null<Float->Float->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onTransformChanged:Null<Int->Float->Void>;
    public var onRotationChanged:Null<Int->Float->Void>;
    public var onScaleChanged:Null<Int->Float->Void>;
    /** Row index: 0 Position, 1 Rotation, 2 Scale. */
    public var onTransformReset:Null<Int->Void>;
    public var onScaleLinkChanged:Null<Bool->Void>;
    public var onViewportClick:Null<Float->Float->Void>;
    public var onToolChanged:Null<Int->Void>;
    /** `true` selects Local axes; `false` selects World axes. */
    public var onTransformSpaceChanged:Null<Bool->Void>;
    /** Fired when the viewport snap bar toggles or changes a preset. */
    public var onSnapChanged:Null<Int->Void>;
    /** Ctrl+End: snap the primary selection onto the translation grid. */
    public var onSnapToGrid:Null<Void->Void>;
    /** Hold key (default V): true while held to suspend translation snapping. */
    public var onSnapHoldChanged:Null<Bool->Void>;
    /** Application-level dialogs are routed upward and hosted in native windows. */
    public var onOpenApplicationWindow:Null<ApplicationWindowKind->Void>;
    /** Opportunistically initialize a hidden host before its menu command runs. */
    public var onPrepareApplicationWindow:Null<ApplicationWindowKind->Void>;
    public var onViewportHover:Null<Float->Float->Void>;
    public var onViewportPush:Null<Float->Float->Bool>;
    public var onViewportDrag:Null<Float->Float->Void>;
    public var onViewportRelease:Null<Float->Float->Void>;
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
    var localTransformSpace:Bool = false;
    var transformSpaceHovered:Bool = false;
    var scaleLinked:Bool = false;
    /** Whether a hold-to-disable press was actually forwarded past the text guard. */
    var snapHoldForwarded:Bool = false;

    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter,
            snapping:GridSnapping) {
        this.ctx = ctx;
        this.input = input;
        root = new h2d.Object(parent);
        chrome = new h2d.Graphics(root);

        // Lowest interactive layer: catches otherwise uncovered editor chrome
        // without taking clicks away from controls created above it.
        editorBackgroundHit = new h2d.Interactive(1, 1, root);
        editorBackgroundHit.backgroundColor = 0;
        editorBackgroundHit.cursor = hxd.Cursor.Default;
        editorBackgroundHit.onClick = function(event) {
            if (event.button == 0) closePaletteIfOpen();
        };

        viewportHit = new h2d.Interactive(1, 1, root);
        viewportHit.backgroundColor = 0;
        viewportHit.cursor = hxd.Cursor.Default;
        viewportHit.onMove = function(event) {
            if (onViewportHover != null) onViewportHover(event.relX, event.relY);
        };
        viewportHit.onPush = function(event) {
            if (event.button != 0) return;
            // Any viewport press dismisses the snap preset dropdown and the
            // File menu before the press is processed.
            snapBar.closePopup();
            menuDropdown.close();
            var gizmoConsumed = onViewportPush != null
                && onViewportPush(event.relX, event.relY);
            if (!gizmoConsumed) return;
            // A gizmo drag owns this press: the release must not fall through
            // to onClick (which would re-run object picking).
            closePaletteIfOpen();
            viewportHit.preventClick();
            viewportHit.startCapture(function(captured) {
                switch (captured.kind) {
                    case EMove:
                        if (onViewportDrag != null) onViewportDrag(
                            ctx.window.mouseX - viewportRect.x,
                            ctx.window.mouseY - viewportRect.y);
                        captured.propagate = false;
                    case ERelease, EReleaseOutside, EFocusLost:
                        captured.propagate = false;
                        viewportHit.stopCapture();
                        if (onViewportRelease != null) onViewportRelease(
                            ctx.window.mouseX - viewportRect.x,
                            ctx.window.mouseY - viewportRect.y);
                    case _:
                        captured.propagate = true;
                }
            });
        };
        viewportHit.onClick = function(event) {
            closePaletteIfOpen();
            if (onViewportClick != null) onViewportClick(event.relX, event.relY);
        };

        leftContentMask = new h2d.Mask(0, 0, root);
        rightContentMask = new h2d.Mask(0, 0, root);

        // Backdrop interaction covers otherwise empty hierarchy chrome. All
        // actual controls and rows are created later and remain above it.
        hierarchyPanelHit = new h2d.Interactive(1, 1, leftContentMask);
        hierarchyPanelHit.backgroundColor = 0;
        hierarchyPanelHit.cursor = hxd.Cursor.Default;
        hierarchyPanelHit.enableRightButton = true;
        hierarchyPanelHit.onClick = handleHierarchyBackgroundClick;
        hierarchyPanelHit.onWheel = function(event) {
            if (!scrollHierarchy(event.wheelDelta)) return;
            event.propagate = false;
        };

        // Native title/menu bar.
        brandMark = new h2d.Bitmap(AppIcon.getTitleBarTile(), root);
        projectTitle = new UiText(ctx.font, root);
        projectTitle.text = "Untitled Scene";
        projectTitle.textColor = Theme.MUTED;
        projectTitle.lineBreak = false;

        for (menuName in ["File", "Edit", "Scene", "Window", "Help"]) {
            var menuWidth = switch (menuName) {
                case "Scene": 52;
                case "Window": 68;
                default: menuName == "Help" ? 46 : 44;
            };
            var button = new UiButton(ctx, menuName, menuWidth, 24, root);
            button.setQuiet();
            var capturedButton = button;
            var capturedMenuName = menuName;
            if (menuName == "File") {
                button.onClick = function() {
                    if (menuDropdown.isOpen) {
                        menuDropdown.close();
                        return;
                    }
                    closePaletteIfOpen();
                    if (onPrepareApplicationWindow != null) {
                        onPrepareApplicationWindow(EditorKeybindings);
                    }
                    // Drop straight down from the button into the body area.
                    menuDropdown.open(capturedButton.x, Theme.TITLE_BAR_HEIGHT,
                        [{
                            label: "Editor Settings",
                            submenu: [{
                                label: "Editor Keybindings…",
                                onClick: function() {
                                    input.clearFocus();
                                    if (onOpenApplicationWindow != null) {
                                        onOpenApplicationWindow(EditorKeybindings);
                                    }
                                }
                            }]
                        }]);
                };
            } else {
                button.onClick = function() {
                    closePaletteIfOpen();
                    log(capturedMenuName + " menu: command surface reserved");
                };
            }
            menuButtons.push(button);
        }

        // Main toolbar.
        addObjectButton = new UiButton(ctx, "Add", 78, 28, root);
        addObjectButton.setIcon(Add).setPrimary();
        addObjectButton.onClick = function() {
            if (viewportRect != null) {
                palette.toggleAt(addObjectButton.x, addObjectButton.y + 31, viewportRect);
            }
        };
        var transformKinds:Array<UiIconKind> = [Move, Rotate, Scale];
        for (index in 0...transformKinds.length) {
            var modeButton = new UiButton(ctx, "", 28, 28, root);
            modeButton.setIcon(transformKinds[index]).setQuiet().setSelected(index == 0);
            var capturedIndex = index;
            modeButton.onClick = function() selectTool(capturedIndex);
            transformButtons.push(modeButton);
        }

        for (transport in [
            {kind: Play, name: "Play"},
            {kind: Pause, name: "Pause"},
            {kind: Stop, name: "Stop"}
        ]) {
            var transportButton = new UiButton(ctx, "", 30, 28, root);
            transportButton.setIcon(transport.kind).setQuiet();
            var command = transport.name;
            transportButton.onClick = function() log(command + " mode is reserved for the runtime milestone");
            transportButtons.push(transportButton);
        }

        // Hierarchy header, search, and rows.
        hierarchyTitleIcon = new h2d.Graphics(leftContentMask);
        UiIcons.draw(hierarchyTitleIcon, Hierarchy, 0, 0, 14, Theme.TEXT_SECONDARY);
        hierarchyTitle = new UiText(ctx.semiboldFont, leftContentMask);
        hierarchyTitle.text = "Scene Hierarchy";
        hierarchyTitle.textColor = Theme.TEXT;
        hierarchyTitle.lineBreak = false;
        hierarchyCount = new UiText(ctx.captionFont, leftContentMask);
        hierarchyCount.textColor = Theme.MUTED;
        hierarchyCount.lineBreak = false;
        hierarchyAddButton = new UiButton(ctx, "", 24, 24, leftContentMask);
        hierarchyAddButton.setIcon(Add).setQuiet();
        hierarchyAddButton.onClick = function() {
            if (viewportRect != null) {
                palette.toggleAt(hierarchyAddButton.x,
                    hierarchyAddButton.y + Theme.CONTROL_HEIGHT + 3, viewportRect);
            }
        };
        hierarchySearch = new SearchField(ctx, "Search Entities", 100, 24, leftContentMask);
        hierarchySearch.onChange = function(value) applyHierarchyFilter(value);

        hierarchyHit = new h2d.Interactive(1, 1, leftContentMask);
        hierarchyHit.backgroundColor = 0;
        hierarchyHit.cursor = hxd.Cursor.Default;
        hierarchyHit.enableRightButton = true;
        hierarchyHit.onWheel = function(event) {
            if (!scrollHierarchy(event.wheelDelta)) return;
            event.propagate = false;
        };
        hierarchyHit.onClick = function(event) {
            handleHierarchyBackgroundClick(event);
        };
        hierarchyScrollBar = new ScrollBar(ctx, leftContentMask);
        hierarchyScrollBar.onChange = function(value) {
            firstVisibleHierarchyRow = Std.int(Math.round(maxFirstVisibleHierarchyRow() * value));
            layoutHierarchyRows();
        };
        hierarchyScrollBar.onWheel = scrollHierarchy;

        // Inspector panel header.
        inspectorTitleIcon = new h2d.Graphics(rightContentMask);
        UiIcons.draw(inspectorTitleIcon, Sliders, 0, 0, 14, Theme.TEXT_SECONDARY);
        inspectorTitle = new UiText(ctx.semiboldFont, rightContentMask);
        inspectorTitle.text = "Inspector";
        inspectorTitle.textColor = Theme.TEXT;
        inspectorTitle.lineBreak = false;
        selectionStatus = new UiText(ctx.captionFont, rightContentMask);
        selectionStatus.textColor = Theme.MUTED;
        selectionStatus.lineBreak = false;

        inspectorContentMask = new h2d.Mask(0, 0, rightContentMask);
        // Keep the wheel catcher outside the scrolling mask. If it is a child
        // of the mask, scrollY moves the catcher with the properties and leaves
        // part of the visible panel unable to receive wheel input.
        inspectorScrollHit = new h2d.Interactive(1, 1, rightContentMask);
        inspectorScrollHit.backgroundColor = 0;
        // This transparent routing layer must not override the I-beam or other
        // cursors supplied by the actual property control underneath it.
        inspectorScrollHit.cursor = null;
        // The fixed catcher sits above property controls for wheel routing but
        // lets clicks and focus events continue to the controls underneath.
        inspectorScrollHit.propagateEvents = true;
        inspectorScrollHit.onWheel = function(event) {
            if (!scrollInspector(event.wheelDelta)) return;
            event.propagate = false;
        };
        inspectorScrollHit.onClick = function(event) {
            if (event.button == 0) closePaletteIfOpen();
        };

        objectSection = new InspectorSection(ctx, "Object", inspectorContentMask);
        objectNameField = new TextInputField(ctx, "Name", Theme.RIGHT_PANEL_WIDTH - 36,
            Theme.CONTROL_HEIGHT, "", objectSection.content);
        objectNameField.setLabelWidth(66);
        objectNameField.onCommit = function(name:String) {
            if (onObjectNameChanged != null) onObjectNameChanged(name);
        };
        objectNameField.onCancel = function() log("inspector: name edit cancelled");

        transformSection = new InspectorSection(ctx, "Transform", inspectorContentMask);
        var axisNames = ["X", "Y", "Z"];
        var axisColors = [Theme.AXIS_X, Theme.AXIS_Y, Theme.AXIS_Z];
        var rowNames = ["Position", "Rotation", "Scale"];
        for (rowIndex in 0...rowNames.length) {
            var rowLabel = new UiText(ctx.labelFont, transformSection.content);
            rowLabel.text = rowNames[rowIndex];
            rowLabel.textColor = Theme.TEXT_SECONDARY;
            rowLabel.lineBreak = false;
            transformLabels.push(rowLabel);
            var rowFields = rowIndex == 0 ? transformFields
                : (rowIndex == 1 ? rotationFields : scaleFields);
            for (index in 0...axisNames.length) {
                var field = new AxisValue(ctx, axisNames[index], axisColors[index], 60,
                    Theme.CONTROL_HEIGHT, transformSection.content);
                var capturedRow = rowIndex;
                var capturedIndex = index;
                field.onCommit = function(value:Float) {
                    if (capturedRow == 0) {
                        if (onTransformChanged != null) onTransformChanged(capturedIndex, value);
                    } else if (capturedRow == 1) {
                        if (onRotationChanged != null) onRotationChanged(capturedIndex, value);
                    } else if (onScaleChanged != null) onScaleChanged(capturedIndex, value);
                };
                field.onEditRejected = function(message:String) log("inspector: " + message);
                rowFields.push(field);
            }
            var resetRow = rowIndex;
            var resetButton = new UiButton(ctx, "", TRANSFORM_ACTION_WIDTH,
                Theme.CONTROL_HEIGHT, transformSection.content);
            resetButton.setIcon(Reset);
            resetButton.onClick = function() {
                if (onTransformReset != null) onTransformReset(resetRow);
            };
            transformResetButtons.push(resetButton);
        }

        scaleLinkButton = new UiButton(ctx, "", TRANSFORM_ACTION_WIDTH,
            Theme.CONTROL_HEIGHT, transformSection.content);
        scaleLinkButton.setIcon(Unlink);
        scaleLinkButton.onClick = function() {
            setScaleLinked(!scaleLinked, true);
        };

        inspectorSections = [objectSection, transformSection];
        for (section in inspectorSections) {
            section.onToggle = function() layoutInspectorProperties();
        }

        inspectorScrollBar = new ScrollBar(ctx, rightContentMask);
        inspectorScrollBar.onChange = function(value) {
            inspectorScrollValue = value;
            inspectorContentMask.scrollY = maxInspectorScroll() * value;
        };
        inspectorScrollBar.onWheel = scrollInspector;

        // Subtle viewport HUD drawn above the scene but below popups.
        viewportHud = new h2d.Object(root);
        viewportModeSurface = new UiSurface(ctx, viewportHud);
        viewportModeSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0);
        viewportModeSurface.setSize(134, 24);
        viewportModeIcon = new h2d.Graphics(viewportHud);
        UiIcons.draw(viewportModeIcon, Grid, 0, 0, 12, Theme.TEXT_SECONDARY);
        viewportModeIcon.x = 7;
        viewportModeIcon.y = 6;
        viewportModeText = new UiText(ctx.captionFont, viewportHud);
        viewportModeText.text = "PERSPECTIVE  ·  LIT";
        viewportModeText.textColor = Theme.TEXT_SECONDARY;
        viewportModeText.lineBreak = false;
        viewportModeText.x = 25;
        viewportModeText.y = 4;

        viewportHintSurface = new UiSurface(ctx, viewportHud);
        viewportHintSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0);
        viewportHintSurface.setSize(80, 24);
        viewportHintIcon = new h2d.Graphics(viewportHud);
        UiIcons.draw(viewportHintIcon, Move, 0, 0, 12, Theme.TEXT_SECONDARY);
        viewportHintText = new UiText(ctx.captionFont, viewportHud);
        viewportHintText.text = "WORLD";
        viewportHintText.textColor = Theme.TEXT_SECONDARY;
        viewportHintText.lineBreak = false;
        viewportHintHit = new h2d.Interactive(80, 24, viewportHud);
        viewportHintHit.backgroundColor = 0;
        viewportHintHit.cursor = hxd.Cursor.Button;
        viewportHintHit.onOver = function(_) {
            transformSpaceHovered = true;
            refreshTransformSpaceControl();
        };
        viewportHintHit.onOut = function(_) {
            transformSpaceHovered = false;
            refreshTransformSpaceControl();
        };
        viewportHintHit.onClick = function(event) {
            if (event.button != 0) return;
            localTransformSpace = !localTransformSpace;
            refreshTransformSpaceControl();
            if (onTransformSpaceChanged != null) {
                onTransformSpaceChanged(localTransformSpace);
            }
            event.propagate = false;
        };

        // Unreal-style snap toolbar: toggle/value pairs for translation,
        // rotation, and scale, sitting next to the view-mode control.
        snapBar = new ViewportSnapBar(ctx, snapping, viewportHud);
        snapBar.onSnapChanged = function(mode) {
            closePaletteIfOpen();
            if (onSnapChanged != null) onSnapChanged(mode);
        };
        // Ctrl+End routes from the window-level input adapter, which sees key
        // events even when full-window interactives consume pointer input.
        input.onSnapToGridPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onSnapToGrid != null) onSnapToGrid();
        };

        console = new ConsolePanel(ctx, root);
        console.onBackgroundClick = closePaletteIfOpen;

        statusDot = new h2d.Graphics(root);
        UiIcons.draw(statusDot, StatusDot, 0, 0, 6, Theme.SUCCESS);
        statusText = new UiText(ctx.captionFont, root);
        statusText.text = "Ready";
        statusText.textColor = Theme.TEXT_SECONDARY;
        statusText.lineBreak = false;
        rendererStatus = new UiText(ctx.captionFont, root);
        rendererStatus.text = "DX12  ·  Native  ·  1 object";
        rendererStatus.textColor = Theme.MUTED;
        rendererStatus.lineBreak = false;
        inputStatus = new UiText(ctx.captionFont, root);
        inputStatus.textColor = Theme.MUTED;
        inputStatus.lineBreak = false;
        // Input diagnostics are intentionally not surfaced in the shipped status bar.
        input.onDeletePressed = function() {
            if (anyTextCaptureActive()) return;
            deleteSelection();
        };
        // Tool shortcuts (1 Move / E Rotate / R Scale by default) share the
        // text-capture guard: typing in a field must not hijack the keypress.
        input.onShortcutPressed = function(tool:Int) {
            if (anyTextCaptureActive()) return;
            selectTool(tool);
        };
        // Hold-to-suspend translation snapping: engage only outside text
        // capture, but always release on key-up so the state never sticks.
        input.onSnapHoldChanged = function(active:Bool) {
            if (active) {
                if (anyTextCaptureActive()) return;
                snapHoldForwarded = true;
                if (onSnapHoldChanged != null) onSnapHoldChanged(true);
                snapBar.refresh();
                return;
            }
            // A press rejected by the text guard has no matching state to
            // release (and should not emit a misleading "resumed" log line).
            if (!snapHoldForwarded) return;
            snapHoldForwarded = false;
            if (onSnapHoldChanged != null) onSnapHoldChanged(false);
            snapBar.refresh();
        };
        // Escape closes the most specific transient popup. Application-level
        // windows receive Escape through their own native input adapter.
        input.onEscapePressed = function() {
            if (menuDropdown.isOpen) {
                menuDropdown.close();
                return;
            }
            closePaletteIfOpen();
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

        // Transient popup layers are created after dock content/splitters so
        // their surfaces and hit targets cannot end up behind the viewport or
        // panel interactives. Application windows are separate native HWNDs.
        menuDropdown = new MenuDropdown(ctx, root);
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
        if (inputStatus.visible) inputStatus.x = Math.max(0, ctx.width - inputStatus.textWidth - 10);
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
        editorBackgroundHit.width = Math.max(0, width);
        editorBackgroundHit.height = Math.max(0, height);
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

        console.x = geometry.console.x;
        console.y = geometry.console.y;
        console.layout(Math.max(0, geometry.console.width),
            Math.max(0, geometry.console.height));

        viewportHud.visible = geometry.viewport.width >= 290 && geometry.viewport.height >= 80;
        viewportHud.x = geometry.viewport.x + 8;
        viewportHud.y = geometry.viewport.y + 8;
        viewportHintSurface.x = Math.max(142, geometry.viewport.width - 88);
        viewportHintIcon.x = viewportHintSurface.x + 7;
        viewportHintIcon.y = 6;
        viewportHintText.x = viewportHintSurface.x + 25;
        viewportHintText.y = 4;
        viewportHintHit.x = viewportHintSurface.x;
        viewportHintHit.y = 0;

        // Snap toolbar sits right of the 134px view-mode strip and before the
        // right-aligned World/Local control; hidden on very narrow viewports.
        snapBar.x = 142;
        snapBar.y = 0;
        snapBar.visible = viewportHud.visible
            && geometry.viewport.width >= 142 + 248 + 96;
        // Real, splitter-aware container height for popup clamping: the
        // console splitter can shrink the viewport at any time, so the popup
        // bounds are derived from the live layout, never a fixed estimate.
        snapBar.setContainerHeight(Math.max(0, geometry.viewport.height - 16));
        var statusY = height - Theme.STATUS_BAR_HEIGHT;
        statusDot.x = 8;
        statusDot.y = statusY + 7;
        statusText.x = 18;
        statusText.y = statusY + 2;
        rendererStatus.x = 70;
        rendererStatus.y = statusY + 2;
        inputStatus.visible = false;
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
            geometry.leftPanel.width, Theme.PANEL_HEADER_HEIGHT);
        chrome.drawRect(geometry.rightPanel.x, geometry.rightPanel.y,
            geometry.rightPanel.width, Theme.PANEL_HEADER_HEIGHT + Theme.PANEL_META_HEIGHT);
        chrome.endFill();
        // Active dock tabs use the same restrained top marker as desktop DCC
        // editors, rather than rounded floating panel cards.
        chrome.beginFill(Theme.ACCENT);
        chrome.drawRect(geometry.leftPanel.x, geometry.leftPanel.y,
            Math.min(112, geometry.leftPanel.width), 2);
        chrome.drawRect(geometry.rightPanel.x, geometry.rightPanel.y,
            Math.min(88, geometry.rightPanel.width), 2);
        chrome.endFill();
        chrome.beginFill(Theme.TITLE_BAR);
        chrome.drawRect(0, height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT);
        chrome.endFill();

        chrome.lineStyle(1, Theme.BORDER, 1);
        chrome.moveTo(0, Theme.TITLE_BAR_HEIGHT);
        chrome.lineTo(width, Theme.TITLE_BAR_HEIGHT);
        chrome.moveTo(0, Theme.TOP_BAR_HEIGHT);
        chrome.lineTo(width, Theme.TOP_BAR_HEIGHT);
        chrome.moveTo(geometry.leftPanel.x,
            geometry.leftPanel.y + Theme.PANEL_HEADER_HEIGHT - 0.5);
        chrome.lineTo(geometry.leftPanel.x + geometry.leftPanel.width,
            geometry.leftPanel.y + Theme.PANEL_HEADER_HEIGHT - 0.5);
        chrome.moveTo(geometry.rightPanel.x,
            geometry.rightPanel.y + Theme.PANEL_HEADER_HEIGHT + Theme.PANEL_META_HEIGHT - 0.5);
        chrome.lineTo(geometry.rightPanel.x + geometry.rightPanel.width,
            geometry.rightPanel.y + Theme.PANEL_HEADER_HEIGHT + Theme.PANEL_META_HEIGHT - 0.5);
        chrome.moveTo(0, height - Theme.STATUS_BAR_HEIGHT);
        chrome.lineTo(width, height - Theme.STATUS_BAR_HEIGHT);
        chrome.drawRect(geometry.viewport.x, geometry.viewport.y,
            geometry.viewport.width, geometry.viewport.height);
        chrome.lineStyle();
    }

    function layoutTopBars(width:Float):Void {
        brandMark.x = 5;
        brandMark.y = 3;

        var menuX = 38.0;
        for (index in 0...menuButtons.length) {
            var button = menuButtons[index];
            button.x = menuX;
            button.y = 3;
            button.visible = width > menuX + 78;
            menuX += switch (index) {
                case 2: 54;
                case 3: 70;
                case 4: 48;
                default: 46;
            };
        }
        projectTitle.visible = width >= 860;
        projectTitle.x = Math.max(menuX + 10, width - projectTitle.textWidth - 16);
        projectTitle.y = 5;

        var toolbarY = Theme.TITLE_BAR_HEIGHT + 4;
        addObjectButton.x = 8;
        addObjectButton.y = toolbarY;

        var toolX = 94.0;
        for (button in transformButtons) {
            button.x = toolX;
            button.y = toolbarY;
            toolX += 31;
        }
        var transportX = Math.max(toolX + 16, width * 0.5 - 48);
        for (button in transportButtons) {
            button.x = transportX;
            button.y = toolbarY;
            button.visible = width > 620;
            transportX += 33;
        }
    }

    function layoutHierarchy(leftWidth:Float, bodyTop:Float):Void {
        hierarchyPanelHit.x = 0;
        hierarchyPanelHit.y = bodyTop;
        hierarchyPanelHit.width = Math.max(0, leftWidth);
        hierarchyPanelHit.height = Math.max(0, leftContentMask.height - bodyTop);
        hierarchyTitleIcon.x = 8;
        hierarchyTitleIcon.y = bodyTop + 9;
        hierarchyTitle.x = 29;
        hierarchyTitle.y = bodyTop + 6;
        hierarchyCount.text = hierarchyFilter.length == 0
            ? Std.string(allHierarchyEntries.length)
            : visibleHierarchyEntries.length + "/" + allHierarchyEntries.length;
        hierarchyCount.x = Math.max(42, leftWidth - hierarchyCount.textWidth - 9);
        hierarchyCount.y = bodyTop + 8;

        hierarchySearch.x = 34;
        hierarchySearch.y = bodyTop + 37;
        hierarchySearch.setWidth(Math.max(0, leftWidth - 40));
        hierarchyAddButton.x = 6;
        hierarchyAddButton.y = bodyTop + 37;
        hierarchyAddButton.visible = leftWidth >= 180;
        hierarchyHit.x = 0;
        hierarchyHit.y = bodyTop + 66;
        hierarchyHit.width = Math.max(0, leftWidth - 7);
        hierarchyHit.height = Math.max(0,
            leftContentMask.height - hierarchyHit.y - 4);
        hierarchyScrollBar.setBounds(Math.max(0, leftWidth - 6), hierarchyHit.y,
            3, hierarchyHit.height);
        layoutHierarchyRows();
    }

    function layoutInspector(rightWidth:Float, bodyTop:Float):Void {
        inspectorTitleIcon.x = 8;
        inspectorTitleIcon.y = bodyTop + 9;
        inspectorTitle.x = 29;
        inspectorTitle.y = bodyTop + 6;
        selectionStatus.x = 8;
        selectionStatus.y = bodyTop + 35;
        fitText(selectionStatus, selectionStatusValue, Math.max(0, rightWidth - 16));
        if (!inspectorContentMask.visible && rightWidth > 220) {
            // Unreal-style empty state: centered hint inside the panel body.
            selectionStatus.x = Math.round((rightWidth - selectionStatus.textWidth) * 0.5);
            selectionStatus.y = bodyTop + Math.round((rightContentMask.height - bodyTop) * 0.35);
        }

        inspectorContentMask.x = 0;
        inspectorContentMask.y = bodyTop + Theme.PANEL_HEADER_HEIGHT + Theme.PANEL_META_HEIGHT;
        inspectorContentMask.width = Std.int(Math.max(0, rightWidth - 7));
        inspectorContentMask.height = Std.int(Math.max(0,
            rightContentMask.height - inspectorContentMask.y - 4));
        inspectorScrollHit.x = inspectorContentMask.x;
        inspectorScrollHit.y = inspectorContentMask.y;
        inspectorScrollHit.width = inspectorContentMask.width;
        inspectorScrollHit.height = inspectorContentMask.height;
        inspectorScrollHit.visible = inspectorContentMask.visible;
        inspectorScrollBar.setBounds(Math.max(0, rightWidth - 6),
            inspectorContentMask.y, 3, inspectorContentMask.height);
        layoutInspectorProperties();
    }

    function layoutInspectorProperties():Void {
        objectSection.contentHeight = INSPECTOR_ROW_HEIGHT;
        // Transform holds Position, Rotation, and Scale rows with per-row
        // reset actions and a scale-proportion link on the Scale row.
        transformSection.contentHeight = INSPECTOR_ROW_HEIGHT * 3;

        var width = Math.max(0, inspectorContentMask.width);
        var y:Float = 0;
        for (section in inspectorSections) {
            section.x = 0;
            section.y = Math.round(y);
            section.setWidth(width);
            y += section.totalHeight();
        }

        // Object: label-left, field-right row inside the section content.
        objectNameField.x = 8;
        objectNameField.y = 2;
        objectNameField.setWidth(Math.max(0, width - 16));

        // Transform: DCC-style property rows (label left, three axis fields).
        var fieldStart = 72.0;
        var axisGap = 4.0;
        var actionGap = 3.0;
        var resetX = Math.max(fieldStart, width - 8 - TRANSFORM_ACTION_WIDTH);
        var linkX = resetX - actionGap - TRANSFORM_ACTION_WIDTH;
        var fieldEnd = linkX - axisGap;
        var axisWidth = Math.max(0, (fieldEnd - fieldStart - axisGap * 2) / 3);
        var rowGroups = [transformFields, rotationFields, scaleFields];
        for (rowIndex in 0...rowGroups.length) {
            var rowFields = rowGroups[rowIndex];
            var rowY = 2 + rowIndex * INSPECTOR_ROW_HEIGHT;
            var label = transformLabels[rowIndex];
            label.x = 8;
            label.y = rowY + Math.round((Theme.CONTROL_HEIGHT - label.textHeight) * 0.5 - 1);
            for (index in 0...rowFields.length) {
                rowFields[index].x = fieldStart + index * (axisWidth + axisGap);
                rowFields[index].y = rowY;
                rowFields[index].setWidth(axisWidth);
            }
            transformResetButtons[rowIndex].x = resetX;
            transformResetButtons[rowIndex].y = rowY;
        }
        scaleLinkButton.x = linkX;
        scaleLinkButton.y = 2 + 2 * INSPECTOR_ROW_HEIGHT;

        inspectorContentHeight = Math.round(y);
        var ratio = Math.min(1, inspectorContentMask.height / Math.max(1, inspectorContentHeight));
        inspectorScrollBar.setMetrics(ratio, inspectorScrollValue);
        inspectorScrollBar.visible = inspectorContentMask.visible && ratio < 1;
        inspectorContentMask.scrollY = maxInspectorScroll() * inspectorScrollValue;
    }

    function maxInspectorScroll():Float {
        return Math.max(0, inspectorContentHeight - inspectorContentMask.height);
    }

    function scrollInspector(delta:Float):Bool {
        if (maxInspectorScroll() <= 0) return false;
        // HashLink/Windows normalizes a downward wheel step to a positive
        // delta, so increasing the offset must move toward later properties.
        inspectorScrollValue = Math.max(0, Math.min(1,
            inspectorScrollValue + delta * 36 / maxInspectorScroll()));
        inspectorContentMask.scrollY = maxInspectorScroll() * inspectorScrollValue;
        inspectorScrollBar.setMetrics(
            inspectorContentMask.height / Math.max(1, inspectorContentHeight), inspectorScrollValue);
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
                row.onContextMenu = openHierarchyPalette;
                hierarchyRows.push(row);
            }
        }
        resize();
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, posX:Float = 0, posY:Float = 0, posZ:Float = 0,
            rotX:Float = 0, rotY:Float = 0, rotZ:Float = 0,
            scaleX:Float = 1, scaleY:Float = 1, scaleZ:Float = 1):Void {
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
            transformFields[0].setValue(posX);
            transformFields[1].setValue(posY);
            transformFields[2].setValue(posZ);
            rotationFields[0].setValue(rotX);
            rotationFields[1].setValue(rotY);
            rotationFields[2].setValue(rotZ);
            scaleFields[0].setValue(scaleX);
            scaleFields[1].setValue(scaleY);
            scaleFields[2].setValue(scaleZ);
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

    /** Live transform update while a viewport gizmo drag moves the selection. */
    public function updateTransformValues(posX:Float, posY:Float, posZ:Float,
            rotX:Float, rotY:Float, rotZ:Float,
            scaleX:Float, scaleY:Float, scaleZ:Float):Void {
        transformFields[0].setValue(posX);
        transformFields[1].setValue(posY);
        transformFields[2].setValue(posZ);
        rotationFields[0].setValue(rotX);
        rotationFields[1].setValue(rotY);
        rotationFields[2].setValue(rotZ);
        scaleFields[0].setValue(scaleX);
        scaleFields[1].setValue(scaleY);
        scaleFields[2].setValue(scaleZ);
    }

    /** Toggle ratio-preserving scale edits without changing current values. */
    function setScaleLinked(value:Bool, notify:Bool):Void {
        if (scaleLinked == value && !notify) return;
        scaleLinked = value;
        scaleLinkButton.setIcon(scaleLinked ? Link : Unlink);
        scaleLinkButton.setSelected(scaleLinked);
        if (notify && onScaleLinkChanged != null) onScaleLinkChanged(scaleLinked);
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
                row.setBounds(3, hierarchyHit.y + visibleIndex * HIERARCHY_ROW_HEIGHT,
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
            firstVisibleHierarchyRow + delta * 3)));
        layoutHierarchyRows();
        return true;
    }

    function openHierarchyPalette():Void {
        if (viewportRect != null) {
            palette.openAt(ctx.window.mouseX, ctx.window.mouseY, viewportRect);
        }
    }

    function handleHierarchyBackgroundClick(event:hxd.Event):Void {
        if (event.button == 1) {
            openHierarchyPalette();
        } else if (event.button == 0) {
            closePaletteIfOpen();
            input.clearFocus();
            selectionAnchorIndex = -1;
            if (onObjectsSelected != null) onObjectsSelected([], -1);
        } else return;
        event.propagate = false;
    }

    /** True while any text-entry control owns the keyboard. */
    function anyTextCaptureActive():Bool {
        if (objectNameField.isFocused() || hierarchySearch.isFocused()) return true;
        for (field in transformFields) if (field.isEditing()) return true;
        for (field in rotationFields) if (field.isEditing()) return true;
        for (field in scaleFields) if (field.isEditing()) return true;
        return false;
    }

    function closePaletteIfOpen():Void {
        if (palette.visible) palette.close();
        snapBar.closePopup();
        menuDropdown.close();
    }

    /** Redraw the clickable viewport World/Local axis-space control. */
    function refreshTransformSpaceControl():Void {
        var color = transformSpaceHovered ? Theme.ACCENT_HOVER : Theme.TEXT_SECONDARY;
        viewportHintSurface.setStyle(
            transformSpaceHovered ? Theme.BUTTON_HOVER : Theme.TITLE_BAR,
            transformSpaceHovered ? Theme.ACCENT : Theme.BORDER_STRONG, 0);
        viewportHintText.text = localTransformSpace ? "LOCAL" : "WORLD";
        viewportHintText.textColor = color;
        UiIcons.draw(viewportHintIcon, Move, 0, 0, 12, color);
    }

    function deleteSelection():Void {
        if (selectedObjectIds.length > 0 && onDeleteObjects != null) {
            onDeleteObjects(selectedObjectIds.copy());
        }
    }

    /** Shared toolbar/shortcut tool switch (0 Move, 1 Rotate, 2 Scale). */
    function selectTool(tool:Int):Void {
        for (index in 0...transformButtons.length) {
            transformButtons[index].setSelected(index == tool);
        }
        if (onToolChanged != null) onToolChanged(tool);
    }
}
