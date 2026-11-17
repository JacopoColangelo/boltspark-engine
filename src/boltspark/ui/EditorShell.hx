package boltspark.ui;

import boltspark.editor.EditorCameraController;
import boltspark.editor.EditorViewport;
import boltspark.editor.GridSnapping;
import boltspark.engine.ComponentTypeInfo;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.layout.BoxLayout;
import boltspark.ui.core.UiFrame;
import boltspark.ui.windows.ApplicationWindowKind;
import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.ComponentInspectorSection;
import boltspark.ui.widgets.DockSplitter;
import boltspark.ui.widgets.GameObjectPalette;
import boltspark.ui.widgets.HierarchyRow;
import boltspark.ui.widgets.InspectorSection;
import boltspark.ui.widgets.AssetBrowser;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.MenuDropdown.MenuItem;
import boltspark.project.ProjectSession.AssetDetails;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.widgets.NumericDragField;
import boltspark.ui.widgets.ScrollBar;
import boltspark.ui.widgets.SearchField;
import boltspark.ui.widgets.TextInputField;
import boltspark.ui.widgets.UiButton;
import boltspark.ui.widgets.UiCheckbox;
import boltspark.ui.widgets.ViewportSnapBar;

/**
 * Retained native editor shell. All controls are Heaps H2D objects rendered in
 * the same DX12 window as the scene; there is no browser or foreign UI layer.
 */
class EditorShell {
    static inline var HIERARCHY_ROW_HEIGHT:Int = 22;
    static inline var INSPECTOR_ROW_HEIGHT:Int = 28;

    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;
    final chromeRenderer:EditorChromeRenderer;
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
    final hierarchyDropFeedback:h2d.Graphics;
    final hierarchyExpanded:Map<Int, Bool> = [];

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
    final enabledCheckbox:UiCheckbox;

    final componentSections:Array<ComponentInspectorSection> = [];
    final componentSectionExpanded:Map<String, Bool> = [];
    final addComponentButton:UiButton;
    var availableComponentTypes:Array<ComponentTypeInfo> = [];

    // Viewport/console/status.
    final viewportHit:h2d.Interactive;
    final viewportHud:h2d.Object;
    final viewportModeSurface:UiSurface;
    final viewportModeIcon:h2d.Graphics;
    final viewportModeText:h2d.Text;
    final viewportModeHit:h2d.Interactive;
    /** Width of the PERSPECTIVE · LIT strip, tracked for snap-bar layout. */
    var viewModeStripWidth:Float = 134;
    final viewportHintSurface:UiSurface;
    final viewportHintIcon:h2d.Graphics;
    final viewportHintText:h2d.Text;
    final viewportHintHit:h2d.Interactive;
    final snapBar:ViewportSnapBar;
    /** View-mode popup: transform-style FOV field plus the grid toggle. */
    final fovPopupRoot:h2d.Object;
    final fovPopupSurface:UiSurface;
    final fovPopupCatch:h2d.Interactive;
    final fovTitleText:UiText;
    final fovInput:NumericDragField;
    final fovDegreeText:UiText;
    final fovGridSurface:UiSurface;
    final fovGridHit:h2d.Interactive;
    final fovGridText:UiText;
    var fovPopupOpen:Bool = false;
    final cameraSpeedSurface:UiSurface;
    final cameraSpeedText:UiText;
    /** Speed chip flash state: visible briefly after each speed change. */
    var speedChipShown:Bool = false;
    var speedChipTimer:Float = 0;
    /** How long the speed chip stays fully visible after a change. */
    static inline var SPEED_CHIP_VISIBLE:Float = 1.2;
    /** Closing fade duration at the end of the flash. */
    static inline var SPEED_CHIP_FADE:Float = 0.35;
    /** FOV popup geometry and the continuous range offered by its slider. */
    static inline var FOV_POPUP_WIDTH:Int = 200;
    static inline var FOV_POPUP_HEIGHT:Int = 96;
    static inline var FOV_MIN_DEG:Float = 30.0;
    static inline var FOV_MAX_DEG:Float = 140.0;
    final console:ConsolePanel;
    final bottomTabs:h2d.Object;
    final logTab:UiButton;
    final assetsTab:UiButton;
    var activeBottomTab:Int = 0;
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
    final assetBrowser:AssetBrowser;

    /** Create a primitive by mesh asset id (palette click). */
    public var onCreatePrimitive:Null<String->Void>;
    /** Create a primitive by mesh asset id at viewport coordinates (palette drop). */
    public var onDropPrimitive:Null<String->Float->Float->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onHierarchyObjectNameChanged:Null<Int->String->Void>;
    public var onCreateChildObject:Null<Int->Bool->Void>;
    /** Parent id (-1 for root) plus the primitive mesh asset id. */
    public var onCreateChildPrimitive:Null<Int->String->Void>;
    public var onCreateEmptyParent:Null<Array<Int>->Void>;
    public var onDuplicateObjects:Null<Array<Int>->Void>;
    public var onCopyObjects:Null<Array<Int>->Void>;
    /** Parent ID, or -1 for root/default placement. */
    public var onPasteObjects:Null<Int->Void>;
    /** Query for context-aware Paste entries; omitted means nothing to paste. */
    public var onQueryObjectClipboard:Null<Void->Bool>;
    public var onUnparentObjects:Null<Array<Int>->Void>;
    public var onToggleObjectVisibility:Null<Int->Void>;
    public var onSetObjectEnabled:Null<Int->Bool->Void>;
    public var onSelectSubtree:Null<Int->Void>;
    public var onCanHierarchyDrop:Null<Array<Int>->Int->Bool>;
    /** IDs, parent ID, insertion index, preserve world. */
    public var onHierarchyDrop:Null<Array<Int>->Int->Int->Bool->Void>;
    /** Generic component-property command callbacks. */
    public var onInspectorNumberChanged:Null<Int->String->Int->Float->Void>;
    public var onInspectorTextChanged:Null<Int->String->String->Void>;
    /** `(componentIndex, propertyId, assetId)` from a type-aware asset picker. */
    public var onInspectorAssetChanged:Null<Int->String->String->Void>;
    public var onInspectorBoolChanged:Null<Int->String->Bool->Void>;
    public var onInspectorEditBegin:Null<Int->String->Int->Void>;
    public var onInspectorEditEnd:Null<Int->String->Int->Void>;
    public var onInspectorReset:Null<Int->String->Void>;
    public var onInspectorLinkChanged:Null<Int->String->Bool->Void>;
    public var onAddComponent:Null<String->Void>;
    /** Component index whose header remove action was clicked. */
    public var onRemoveComponent:Null<Int->Void>;
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
    /** Project/scene file commands routed upward to Main; never direct I/O. */
    public var onFileNewProject:Null<Void->Void>;
    public var onFileOpenProject:Null<Void->Void>;
    public var onFileSaveProject:Null<Void->Void>;
    public var onFileSaveProjectAs:Null<Void->Void>;
    public var onFileSaveScene:Null<Void->Void>;
    public var onFileSaveAll:Null<Void->Void>;
    /** Asset Browser data and actions, routed upward to ProjectSession. */
    public var onQueryAssets:Null<Void->Array<AssetFileInfo>>;
    public var onOpenAsset:Null<String->Void>;
    public var onNewScene:Null<String->String->Void>;
    public var onRenameAsset:Null<String->String->Void>;
    public var onRenameFolder:Null<String->String->String>;
    public var onDeleteAsset:Null<String->Void>;
    public var onQueryFolders:Null<Void->Array<String>>;
    public var onNewFolder:Null<String->String>;
    public var onMoveAsset:Null<String->String->Void>;
    public var onCopyAsset:Null<String->String->Void>;
    public var onQueryAssetDetails:Null<String->AssetDetails>;
    public var onDeleteAssets:Null<Array<String>->Void>;
    public var onDuplicateAsset:Null<String->Void>;
    public var onDeleteFolder:Null<String->Bool->Void>;
    public var onMoveFolder:Null<String->String->Void>;
    public var onRevealAsset:Null<String->Void>;
    public var onCopyAssetPath:Null<String->Void>;
    /** Application-level dialogs are routed upward and hosted in native windows. */
    public var onOpenApplicationWindow:Null<ApplicationWindowKind->Void>;
    /** Opportunistically initialize a hidden host before its menu command runs. */
    public var onPrepareApplicationWindow:Null<ApplicationWindowKind->Void>;
    public var onUndo:Null<Void->Void>;
    public var onRedo:Null<Void->Void>;
    public var onViewportHover:Null<Float->Float->Void>;
    public var onViewportPush:Null<Float->Float->Bool>;
    public var onViewportDrag:Null<Float->Float->Void>;
    public var onViewportRelease:Null<Float->Float->Void>;
    /** Mouse wheel over the viewport (positive delta scrolls down). */
    public var onViewportWheel:Null<Float->Void>;
    /** Camera gesture start: GESTURE_* kind + viewport-local pointer.
        Returns true when the gesture was accepted. */
    public var onViewportCameraBegin:Null<Int->Float->Float->Bool>;
    /** Camera gesture movement: kind + viewport-local pointer. */
    public var onViewportCameraMove:Null<Int->Float->Float->Void>;
    /** Camera gesture end: kind + viewport-local pointer (-1 when cancelled). */
    public var onViewportCameraEnd:Null<Int->Float->Float->Void>;
    /** Viewport contextual focus (hover or owned gesture) changed. */
    public var onViewportFocusChanged:Null<Bool->Void>;
    /** The native window lost keyboard focus. */
    public var onWindowFocusLost:Null<Void->Void>;
    /** G: toggle the independent editor grid. */
    public var onToggleGrid:Null<Void->Void>;
    /** Fired with the new horizontal FOV whenever the FOV field is edited. */
    public var onFovChanged:Null<Float->Void>;
    /** F: frame the primary selection in the active viewport. */
    public var onFocusSelection:Null<Void->Void>;
    public var viewportRect(default, null):LayoutRect;

    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    /** Right edge available to the project title, captured by layout. */
    var titleAnchorX:Float = 0;
    var selectedObjectIds:Array<Int> = [];
    var selectedObjectId:Int = -1;
    /** Stable object anchor; its visible row index can change as trees fold. */
    var selectionAnchorId:Int = -1;
    var firstVisibleHierarchyRow:Int = 0;
    var inspectorScrollValue:Float = 0;
    var hierarchyFilter:String = "";
    var hierarchyDragIds:Array<Int> = [];
    var hierarchyDropParentId:Int = -1;
    var hierarchyDropSiblingIndex:Int = 0;
    var hierarchyDropMode:Int = HierarchyRow.DROP_NONE;
    var hierarchyDropValid:Bool = false;
    var hierarchyDropRow:Null<HierarchyRow>;
    var selectionStatusValue:String = "Select an object to inspect";
    var localTransformSpace:Bool = false;
    var transformSpaceHovered:Bool = false;
    var scaleLinked:Bool = false;
    /** Whether a hold-to-disable press was actually forwarded past the text guard. */
    var snapHoldForwarded:Bool = false;
    // Viewport focus and camera-gesture ownership. Contextual focus is hover
    // or an active pointer capture (used by commands such as the G grid
    // toggle); fly-camera keys separately require an RMB look capture.
    var viewportHovered:Bool = false;
    var cameraGesture:Int = -1;
    var gizmoCaptureActive:Bool = false;
    var viewportFocusNotified:Bool = false;
    var lastGeometry:Null<DockLayoutGeometry>;
    var historyUndoLabel:Null<String>;
    var historyRedoLabel:Null<String>;

    public function new(parent:h2d.Object, ctx:UiContext, input:InputAdapter,
            snapping:GridSnapping) {
        this.ctx = ctx;
        this.input = input;
        root = new h2d.Object(parent);
        chrome = new h2d.Graphics(root);
        chromeRenderer = new EditorChromeRenderer();

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
        // Right/middle button pushes and releases reach the handlers below
        // so the editor camera controller can own look/pan gestures.
        viewportHit.enableRightButton = true;
        viewportHit.onOver = function(_) setViewportHover(true);
        viewportHit.onOut = function(_) setViewportHover(false);
        viewportHit.onWheel = function(event) {
            if (onViewportWheel != null) onViewportWheel(event.wheelDelta);
            event.propagate = false;
        };
        viewportHit.onMove = function(event) {
            if (onViewportHover != null) onViewportHover(event.relX, event.relY);
        };
        viewportHit.onPush = function(event) {
            switch (event.button) {
                case 0: handleViewportPrimaryPush(event);
                case 1:
                    beginViewportCameraGesture(
                        EditorCameraController.GESTURE_LOOK, event);
                default:
                    beginViewportCameraGesture(
                        EditorCameraController.GESTURE_PAN, event);
            }
        };
        viewportHit.onClick = function(event) {
            // Right/middle clicks are camera gestures, never object picks.
            if (event.button != 0) return;
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
                    menuDropdown.open(capturedButton.x, Theme.TITLE_BAR_HEIGHT, [
                        {
                            label: "New Project…",
                            onClick: function() {
                                input.clearFocus();
                                if (onFileNewProject != null) onFileNewProject();
                            }
                        }, {
                            label: "Open Project…",
                            onClick: function() {
                                input.clearFocus();
                                if (onFileOpenProject != null) onFileOpenProject();
                            }
                        }, {
                            label: "Save Project",
                            onClick: function() {
                                input.clearFocus();
                                if (onFileSaveProject != null) onFileSaveProject();
                            }
                        }, {
                            label: "Save Project As…",
                            onClick: function() {
                                input.clearFocus();
                                if (onFileSaveProjectAs != null) onFileSaveProjectAs();
                            }
                        }, {
                            label: "Save Current Scene",
                            onClick: function() {
                                input.clearFocus();
                                if (onFileSaveScene != null) onFileSaveScene();
                            }
                        }, {
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
                        }
                    ]);
                };
            } else if (menuName == "Edit") {
                button.onClick = function() {
                    if (menuDropdown.isOpen) {
                        menuDropdown.close();
                        return;
                    }
                    closePaletteIfOpen();
                    menuDropdown.open(capturedButton.x, Theme.TITLE_BAR_HEIGHT, [{
                        label: historyUndoLabel == null
                            ? "Undo"
                            : "Undo " + historyUndoLabel,
                        onClick: function() {
                            input.clearFocus();
                            if (onUndo != null) onUndo();
                        }
                    }, {
                        label: historyRedoLabel == null
                            ? "Redo"
                            : "Redo " + historyRedoLabel,
                        onClick: function() {
                            input.clearFocus();
                            if (onRedo != null) onRedo();
                        }
                    }, {
                        label: "Copy",
                        onClick: copySelection
                    }, {
                        label: "Paste",
                        onClick: function() {
                            if (onPasteObjects != null) onPasteObjects(-2);
                        }
                    }, {
                        label: "Duplicate",
                        onClick: duplicateSelection
                    }]);
                };
            } else if (menuName == "Scene") {
                button.onClick = function() {
                    if (menuDropdown.isOpen) {
                        menuDropdown.close();
                        return;
                    }
                    closePaletteIfOpen();
                    menuDropdown.open(capturedButton.x, Theme.TITLE_BAR_HEIGHT, [{
                        label: "Create Empty",
                        onClick: function() {
                            if (onCreateChildObject != null) onCreateChildObject(-1, true);
                        }
                    }, {
                        label: "Expand All",
                        onClick: expandAllHierarchy
                    }, {
                        label: "Collapse All",
                        onClick: collapseAllHierarchy
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
        hierarchyDropFeedback = new h2d.Graphics(leftContentMask);

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
        enabledCheckbox = new UiCheckbox(ctx, "Enabled", objectSection.content);
        enabledCheckbox.onChanged = function(value) {
            if (onSetObjectEnabled != null) onSetObjectEnabled(selectedObjectId, value);
        };

        addComponentButton = new UiButton(ctx, "Add Component",
            Theme.RIGHT_PANEL_WIDTH - 16, Theme.CONTROL_HEIGHT,
            inspectorContentMask);
        addComponentButton.setIcon(Add);
        addComponentButton.onClick = function() {
            if (availableComponentTypes.length == 0) return;
            var items:Array<MenuItem> = [];
            for (entry in availableComponentTypes) {
                var captured = entry;
                items.push({
                    label: captured.label,
                    onClick: function() {
                        if (onAddComponent != null) {
                            onAddComponent(captured.typeId);
                        }
                    }
                });
            }
            closeFovPopup();
            menuDropdown.open(ctx.window.mouseX, ctx.window.mouseY, items);
        };

        inspectorSections = [objectSection];
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
        // The strip doubles as the camera/visualization settings menu button
        // (Unreal-style viewport label dropdown).
        viewportModeHit = new h2d.Interactive(134, 24, viewportHud);
        viewportModeHit.backgroundColor = 0;
        viewportModeHit.cursor = hxd.Cursor.Default;
        viewportModeHit.onOver = function(_) {
            viewportModeSurface.setStyle(Theme.SURFACE_3, Theme.ACCENT, 0);
        };
        viewportModeHit.onOut = function(_) {
            viewportModeSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0);
        };
        viewportModeHit.onClick = function(event) {
            if (event.button != 0) return;
            openViewModeMenu();
            event.propagate = false;
        };

        // Clicking the PERSPECTIVE strip opens a compact settings popup. The
        // field of view uses the same transform-style numeric drag field as
        // the Inspector: click to type an exact value, drag to scrub, or use
        // the arrow buttons to step. No preset list is involved.
        fovPopupRoot = new h2d.Object(root);
        fovPopupRoot.visible = false;
        fovPopupSurface = new UiSurface(ctx, fovPopupRoot);
        fovPopupSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        fovPopupSurface.setSize(FOV_POPUP_WIDTH, FOV_POPUP_HEIGHT);
        fovPopupCatch = new h2d.Interactive(
            FOV_POPUP_WIDTH, FOV_POPUP_HEIGHT, fovPopupRoot);
        fovPopupCatch.backgroundColor = 0;
        // h2d.Interactive defaults to Cursor.Button (the native pointing hand),
        // so every popup catcher must opt into the ordinary arrow cursor.
        fovPopupCatch.cursor = hxd.Cursor.Default;
        // Swallow presses on the popup body so they never reach viewport
        // picking, while the numeric field's interactives stay above the catch.
        fovPopupCatch.onPush = function(event) event.propagate = false;

        fovTitleText = new UiText(ctx.captionFont, fovPopupRoot);
        fovTitleText.text = "Field of View";
        fovTitleText.textColor = Theme.TEXT;
        fovTitleText.lineBreak = false;
        fovTitleText.x = 10;
        fovTitleText.y = 8;

        fovInput = new NumericDragField(ctx, 128, 24,
            FOV_MIN_DEG, FOV_MAX_DEG, 1, EditorViewport.VIEW_FOV_DEG,
            function(value:Float):String return Std.string(Std.int(Math.round(value))),
            "", Theme.TEXT, fovPopupRoot);
        fovInput.x = 10;
        fovInput.y = 30;
        fovInput.onValueChanged = applyFov;
        fovInput.onEditRejected = function(message) log("viewport: " + message);

        fovDegreeText = new UiText(ctx.captionFont, fovPopupRoot);
        fovDegreeText.text = "°";
        fovDegreeText.textColor = Theme.MUTED;
        fovDegreeText.lineBreak = false;
        fovDegreeText.x = 144;
        fovDegreeText.y = 36;

        fovGridSurface = new UiSurface(ctx, fovPopupRoot);
        fovGridSurface.setSize(FOV_POPUP_WIDTH - 12, 22);
        fovGridSurface.x = 6;
        fovGridSurface.y = FOV_POPUP_HEIGHT - 28;
        fovGridSurface.setStyle(Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
        fovGridHit = new h2d.Interactive(
            FOV_POPUP_WIDTH - 12, 22, fovPopupRoot);
        fovGridHit.backgroundColor = 0;
        fovGridHit.cursor = hxd.Cursor.Default;
        fovGridHit.x = 6;
        fovGridHit.y = FOV_POPUP_HEIGHT - 28;
        fovGridHit.onOver = function(_) fovGridSurface.setStyle(
            Theme.SURFACE_3, Theme.ACCENT, 0);
        fovGridHit.onOut = function(_) fovGridSurface.setStyle(
            Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
        fovGridHit.onPush = function(event) {
            event.propagate = false;
            closeFovPopup();
            if (onToggleGrid != null) onToggleGrid();
        };
        fovGridText = new UiText(ctx.captionFont, fovPopupRoot);
        fovGridText.text = "Toggle Editor Grid  (G)";
        fovGridText.textColor = Theme.TEXT_SECONDARY;
        fovGridText.lineBreak = false;
        fovGridText.x = 16;
        fovGridText.y = FOV_POPUP_HEIGHT - 22;

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
        viewportHintHit.cursor = hxd.Cursor.Default;
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
        refreshViewModeLabel();

        // Unobtrusive camera-speed chip in the viewport's bottom-left corner,
        // refreshed by Main from the editor camera controller. The text is a
        // child of the chip surface so it moves with it — parenting it to the
        // HUD would draw it at the HUD's top-left, over the view-mode strip.
        cameraSpeedSurface = new UiSurface(ctx, viewportHud);
        cameraSpeedSurface.setStyle(Theme.TITLE_BAR, Theme.BORDER_STRONG, 0);
        cameraSpeedSurface.setSize(110, 24);
        cameraSpeedText = new UiText(ctx.captionFont, cameraSpeedSurface);
        cameraSpeedText.text = "SPEED —";
        cameraSpeedText.textColor = Theme.TEXT_SECONDARY;
        cameraSpeedText.lineBreak = false;
        cameraSpeedText.x = 8;
        cameraSpeedText.y = 4;
        // Hidden until a real speed change flashes it (see setCameraSpeedLabel).
        cameraSpeedSurface.visible = false;
        cameraSpeedText.visible = false;
        // Ctrl+End routes from the window-level input adapter, which sees key
        // events even when full-window interactives consume pointer input.
        input.onSnapToGridPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onSnapToGrid != null) onSnapToGrid();
        };

        console = new ConsolePanel(ctx, root);
        console.onBackgroundClick = closePaletteIfOpen;

        // Bottom dock tabs: Asset Browser first, Output Log second.
        bottomTabs = new h2d.Object(root);
        assetsTab = new UiButton(ctx, "Asset Browser", 108, 22, bottomTabs);
        assetsTab.setQuiet();
        assetsTab.onClick = showAssetBrowser;
        logTab = new UiButton(ctx, "Output Log", 92, 22, bottomTabs);
        logTab.setQuiet();
        logTab.onClick = function() setBottomTab(1);

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
            if (activeBottomTab == 0) {
                if (assetBrowser.hasSelection()) {
                    assetBrowser.deleteSelection();
                    return;
                }
                if (assetBrowser.hasFolderSelection()) {
                    assetBrowser.deleteSelectedFolder();
                    return;
                }
            }
            deleteSelection();
        };
        input.onUndoPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onUndo != null) onUndo();
        };
        input.onRedoPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onRedo != null) onRedo();
        };
        input.onCopyPressed = function() {
            if (anyTextCaptureActive()) return;
            if (activeBottomTab == 0 && assetBrowser.hasSelection()) {
                assetBrowser.copyToClipboard();
                return;
            }
            copySelection();
        };
        input.onPastePressed = function() {
            if (anyTextCaptureActive()) return;
            if (activeBottomTab == 0 && assetBrowser.hasClipboard()) {
                assetBrowser.pasteClipboard();
                return;
            }
            if (onPasteObjects != null) onPasteObjects(-2);
        };
        input.onCutPressed = function() {
            if (anyTextCaptureActive() || activeBottomTab != 0) return;
            assetBrowser.cutToClipboard();
        };
        input.onDuplicatePressed = function() {
            if (anyTextCaptureActive()) return;
            duplicateSelection();
        };
        input.onRenamePressed = function() {
            if (anyTextCaptureActive()) return;
            // F2 in the Asset Browser renames the selected asset or folder.
            if (activeBottomTab == 0 && assetBrowser.beginRename()) return;
            if (selectedObjectId < 0) return;
            beginRenameFor(selectedObjectId);
        };
        // Asset Browser contextual shortcuts. These are deliberately not added
        // to the rebindable registry: they act only while the browser tab is
        // frontmost, and the text-capture guard keeps them out of text fields.
        input.onRawKeyDown = function(keyCode) {
            if (activeBottomTab != 0 || anyTextCaptureActive()) return;
            if (assetBrowser.handleShortcut(keyCode,
                    hxd.Key.isDown(hxd.Key.CTRL), hxd.Key.isDown(hxd.Key.SHIFT),
                    hxd.Key.isDown(hxd.Key.ALT))) return;
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
            if (activeBottomTab == 0 && !anyTextCaptureActive()) {
                assetBrowser.clearSelection();
            }
            closePaletteIfOpen();
        };
        // G (rebindable) toggles the independent editor grid; only accepted
        // while the viewport owns focus, never while typing into a field.
        input.onToggleGridPressed = function() {
            if (!isViewportFocused()) return;
            if (onToggleGrid != null) onToggleGrid();
        };
        // Focus is a selection command, not viewport navigation: it stays
        // available while the pointer is over any panel, as long as something
        // is selected. Text entry and an in-progress viewport gesture are the
        // only reasons to suppress it (typing "f" must not move the camera).
        input.onFocusSelectionPressed = function() {
            if (anyTextCaptureActive() || cameraGesture >= 0
                    || selectedObjectIds.length == 0) return;
            if (onFocusSelection != null) onFocusSelection();
        };
        input.onSaveCurrentScenePressed = function() {
            if (anyTextCaptureActive()) return;
            if (onFileSaveScene != null) onFileSaveScene();
        };
        input.onSaveAllPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onFileSaveAll != null) onFileSaveAll();
        };
        input.onWindowFocusLost = function() {
            if (onWindowFocusLost != null) onWindowFocusLost();
        };

        dockLayout = new DockLayout();
        layoutStore = new DockLayoutStore();
        var layoutError = layoutStore.load(dockLayout);
        activeBottomTab = dockLayout.bottomTab;
        console.visible = activeBottomTab == 1;

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
        assetBrowser = new AssetBrowser(ctx, root, root);
        assetBrowser.visible = activeBottomTab == 0;
        assetBrowser.onQueryAssets = function() {
            return onQueryAssets != null ? onQueryAssets() : [];
        };
        assetBrowser.onOpenAsset = function(source) {
            if (onOpenAsset != null) onOpenAsset(source);
        };
        assetBrowser.onNewScene = function(folder, name) {
            if (onNewScene != null) onNewScene(folder, name);
        };
        assetBrowser.onRenameAsset = function(source, name) {
            if (onRenameAsset != null) onRenameAsset(source, name);
        };
        assetBrowser.onDeleteAsset = function(source) {
            if (onDeleteAsset != null) onDeleteAsset(source);
        };
        assetBrowser.onRenameFolder = function(source, name) {
            return onRenameFolder != null ? onRenameFolder(source, name) : null;
        };
        assetBrowser.onQueryFolders = function() {
            return onQueryFolders != null ? onQueryFolders() : [];
        };
        assetBrowser.onNewFolder = function(parent) {
            return onNewFolder != null ? onNewFolder(parent) : null;
        };
        assetBrowser.onMoveAsset = function(source, folder) {
            if (onMoveAsset != null) onMoveAsset(source, folder);
        };
        assetBrowser.onCopyAsset = function(source, folder) {
            if (onCopyAsset != null) onCopyAsset(source, folder);
        };
        assetBrowser.onDeleteAssets = function(sources) {
            if (onDeleteAssets != null) onDeleteAssets(sources);
        };
        assetBrowser.onQueryAssetDetails = function(source) {
            return onQueryAssetDetails != null ? onQueryAssetDetails(source) : null;
        };
        assetBrowser.onDuplicateAsset = function(source) {
            if (onDuplicateAsset != null) onDuplicateAsset(source);
        };
        assetBrowser.onDeleteFolder = function(folder, recursive) {
            if (onDeleteFolder != null) onDeleteFolder(folder, recursive);
        };
        assetBrowser.onMoveFolder = function(source, parent) {
            if (onMoveFolder != null) onMoveFolder(source, parent);
        };
        assetBrowser.onRevealAsset = function(source) {
            if (onRevealAsset != null) onRevealAsset(source);
        };
        assetBrowser.onCopyAssetPath = function(source) {
            if (onCopyAssetPath != null) onCopyAssetPath(source);
        };
        palette = new GameObjectPalette(ctx, root);
        palette.onCreatePrimitive = function(meshId) {
            if (onCreatePrimitive != null) onCreatePrimitive(meshId);
        };
        palette.onDropPrimitive = function(meshId, x, y) {
            if (onDropPrimitive != null) onDropPrimitive(meshId, x, y);
        };

        if (layoutError != null) log("layout: " + layoutError);
        selectionStatus.text = selectionStatusValue;
        inspectorContentMask.visible = false;
        resize();
    }

    // ------------------------------------------------------------------
    // Viewport pointer gestures and focus
    // ------------------------------------------------------------------

    /** Left-button viewport press: Alt+LMB orbits, otherwise object
        picking / transform gizmo drags run as before. */
    function handleViewportPrimaryPush(event:hxd.Event):Void {
        if (hxd.Key.isDown(hxd.Key.ALT)) {
            // Alt+LMB orbits the camera around the navigation pivot; the
            // press never reaches object picking or the transform gizmo.
            closePaletteIfOpen();
            beginViewportCameraGesture(
                EditorCameraController.GESTURE_ORBIT, event);
            return;
        }
        // Any viewport press dismisses the snap preset dropdown, the FOV
        // settings popup, and the File menu before the press is processed.
        snapBar.closePopup();
        menuDropdown.close();
        closeFovPopup();
        var gizmoConsumed = onViewportPush != null
            && onViewportPush(event.relX, event.relY);
        if (!gizmoConsumed) return;
        // A gizmo drag owns this press: the release must not fall through
        // to onClick (which would re-run object picking).
        gizmoCaptureActive = true;
        notifyViewportFocus();
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
                    endGizmoCapture();
                    if (onViewportRelease != null) onViewportRelease(
                        ctx.window.mouseX - viewportRect.x,
                        ctx.window.mouseY - viewportRect.y);
                case _:
                    captured.propagate = true;
            }
        });
    }

    function endGizmoCapture():Void {
        viewportHit.stopCapture();
        gizmoCaptureActive = false;
        notifyViewportFocus();
    }

    /** Start a camera gesture (look/pan/orbit) with pointer capture so the
        release is always observed. Gestures never overlap gizmo drags. */
    function beginViewportCameraGesture(kind:Int, event:hxd.Event):Void {
        if (cameraGesture >= 0 || gizmoCaptureActive) return;
        if (onViewportCameraBegin == null) return;
        if (!onViewportCameraBegin(kind, event.relX, event.relY)) return;
        viewportHit.preventClick();
        cameraGesture = kind;
        notifyViewportFocus();
        viewportHit.startCapture(function(captured) {
            switch (captured.kind) {
                case EMove:
                    if (onViewportCameraMove != null) onViewportCameraMove(kind,
                        ctx.window.mouseX - viewportRect.x,
                        ctx.window.mouseY - viewportRect.y);
                    captured.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    captured.propagate = false;
                    endViewportCameraGesture(kind,
                        ctx.window.mouseX - viewportRect.x,
                        ctx.window.mouseY - viewportRect.y);
                case _:
                    captured.propagate = true;
            }
        }, function() endViewportCameraGesture(kind, -1, -1));
    }

    function endViewportCameraGesture(kind:Int, x:Float, y:Float):Void {
        if (cameraGesture != kind) return;
        cameraGesture = -1;
        // When invoked from the capture callback this stops the capture and
        // re-enters through onCancel, which early-outs on the guard above.
        viewportHit.stopCapture();
        notifyViewportFocus();
        if (onViewportCameraEnd != null) onViewportCameraEnd(kind, x, y);
    }

    function setViewportHover(hovered:Bool):Void {
        if (viewportHovered == hovered) return;
        viewportHovered = hovered;
        notifyViewportFocus();
    }

    function notifyViewportFocus():Void {
        var focused = isViewportFocused();
        if (viewportFocusNotified == focused) return;
        viewportFocusNotified = focused;
        if (onViewportFocusChanged != null) onViewportFocusChanged(focused);
    }

    /**
     * Keyboard-facing contextual focus: the pointer hovers the viewport or a
     * pointer gesture owns it, and no text field captures typing. This is for
     * viewport commands such as G, not permission to fly the camera.
     */
    public function isViewportFocused():Bool {
        if (anyTextCaptureActive()) return false;
        return viewportHovered || cameraGesture >= 0 || gizmoCaptureActive;
    }

    /** Unreal-style fly navigation is active only for the RMB look capture. */
    public function isViewportNavigationActive():Bool {
        if (anyTextCaptureActive()) return false;
        return cameraGesture == EditorCameraController.GESTURE_LOOK;
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

    /**
     * PERSPECTIVE · LIT strip: camera and visualization settings. The field
     * of view applies to the shared horizontal FOV that the viewport pass
     * and the camera controller's pan scale both read. It is edited with a
     * continuous slider so arbitrary values are available, not just presets.
     */
    function openViewModeMenu():Void {
        var wasOpen = fovPopupOpen;
        closePaletteIfOpen();
        if (wasOpen) return;
        refreshFovPopupValue();
        fovPopupRoot.x = Math.max(4,
            Math.min(viewportHud.x, ctx.width - FOV_POPUP_WIDTH - 4));
        fovPopupRoot.y = Math.max(4,
            Math.min(viewportHud.y + 26, ctx.height - FOV_POPUP_HEIGHT - 4));
        fovPopupRoot.visible = true;
        fovPopupOpen = true;
    }

    function closeFovPopup():Void {
        if (!fovPopupOpen) return;
        fovPopupOpen = false;
        fovPopupRoot.visible = false;
        // A typed value may still own keyboard focus; release it so shortcuts
        // and the next popup open start from a clean input state.
        input.clearFocus();
    }

    /** Keep the numeric field in sync with the shared FOV. */
    function refreshFovPopupValue():Void {
        fovInput.setValue(EditorViewport.VIEW_FOV_DEG);
    }

    /** Single write path for FOV edits from the transform-style field. */
    function applyFov(value:Float):Void {
        var rounded:Float = Math.round(value);
        if (rounded < FOV_MIN_DEG) rounded = FOV_MIN_DEG;
        if (rounded > FOV_MAX_DEG) rounded = FOV_MAX_DEG;
        if (rounded == EditorViewport.VIEW_FOV_DEG) {
            refreshFovPopupValue();
            return;
        }
        EditorViewport.VIEW_FOV_DEG = rounded;
        refreshFovPopupValue();
        refreshViewModeLabel();
        // Probe telemetry only; changing a slider value must not spam the
        // editor's Output Log on every drag step.
        if (onFovChanged != null) onFovChanged(rounded);
    }

    /** Rebuild the strip label with the live FOV and keep neighbors placed. */
    function refreshViewModeLabel():Void {
        viewportModeText.text = 'PERSPECTIVE ${Math.round(EditorViewport.VIEW_FOV_DEG)}° · LIT';
        viewModeStripWidth = Math.ceil(25 + viewportModeText.textWidth + 8);
        viewportModeSurface.setSize(viewModeStripWidth, 24);
        viewportModeHit.width = viewModeStripWidth;
        viewportModeHit.height = 24;
        snapBar.x = viewModeStripWidth + 8;
    }

    /** Small viewport overlay showing the current camera movement speed.
        The chip is hidden by default and flashes briefly whenever the speed
        changes, fading out after SPEED_CHIP_VISIBLE seconds. */
    public function setCameraSpeedLabel(text:String):Void {
        if (cameraSpeedText.text == text) return;
        // The startup synchronization ("SPEED —" → live value) must not
        // flash the chip; only real speed changes do.
        var initial = cameraSpeedText.text == "SPEED —";
        cameraSpeedText.text = text;
        if (initial) return;
        speedChipShown = true;
        speedChipTimer = SPEED_CHIP_VISIBLE;
        cameraSpeedSurface.alpha = 1;
        cameraSpeedText.alpha = 1;
        cameraSpeedSurface.visible = viewportHud.visible;
        cameraSpeedText.visible = viewportHud.visible;
    }

    function setBottomTab(index:Int):Void {
        activeBottomTab = index;
        dockLayout.bottomTab = index;
        console.visible = index == 1;
        assetBrowser.visible = index == 0;
        if (index == 0) assetBrowser.refresh();
        saveLayout();
    }

    /** Refresh the docked Asset Browser after a project asset changes. */
    public function refreshAssetBrowser():Void {
        assetBrowser.refresh();
    }

    /** Show the Asset Browser bottom tab and rebuild its listing. */
    function showAssetBrowser():Void {
        setBottomTab(0);
        assetBrowser.refresh();
    }

    /** UI font for editor overlay text (viewport axis gizmo letters). */
    public function viewportFont():h2d.Font {
        return ctx.font;
    }

    public function setHistoryState(undoLabel:Null<String>,
            redoLabel:Null<String>):Void {
        historyUndoLabel = undoLabel;
        historyRedoLabel = redoLabel;
    }

    /** Title-strip project/scene label, including the unsaved marker. */
    public function setProjectTitle(text:String):Void {
        projectTitle.text = text;
        if (titleAnchorX > 0) {
            projectTitle.x = Math.max(titleAnchorX - projectTitle.textWidth,
                titleAnchorX - 200);
        }
    }

    public function update(dt:Float):Void {
        if (ctx.width != lastWidth || ctx.height != lastHeight) resize();
        if (speedChipShown) {
            speedChipTimer -= dt;
            if (speedChipTimer <= 0) {
                speedChipShown = false;
                cameraSpeedSurface.visible = false;
                cameraSpeedText.visible = false;
            } else if (speedChipTimer < SPEED_CHIP_FADE) {
                // Fade the last moments instead of popping out.
                var alpha = speedChipTimer / SPEED_CHIP_FADE;
                cameraSpeedSurface.alpha = alpha;
                cameraSpeedText.alpha = alpha;
            }
        }
        if (inputStatus.visible) inputStatus.x = Math.max(0, ctx.width - inputStatus.textWidth - 10);
    }

    public function resize():Void {
        var width = ctx.width;
        var height = ctx.height;

        var bodyTop = Theme.TOP_BAR_HEIGHT;
        var geometry = dockLayout.calculate(width, height);
        lastGeometry = geometry;
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

        // Tabs occupy the top of the bottom dock; content starts below them.
        var tabHeight:Float = 24;
        bottomTabs.x = geometry.console.x;
        bottomTabs.y = geometry.console.y;
        assetsTab.x = 0;
        assetsTab.y = 0;
        logTab.x = 110;
        logTab.y = 0;
        var contentY = geometry.console.y + tabHeight;
        var contentHeight = Math.max(0, geometry.console.height - tabHeight);
        console.x = geometry.console.x;
        console.y = contentY;
        console.layout(Math.max(0, geometry.console.width), contentHeight);
        assetBrowser.layout(geometry.console.x, contentY,
            Math.max(0, geometry.console.width), contentHeight);

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

        // Snap toolbar sits right of the view-mode strip and before the
        // right-aligned World/Local control; hidden on very narrow viewports.
        snapBar.x = viewModeStripWidth + 8;
        snapBar.y = 0;
        snapBar.visible = viewportHud.visible
            && geometry.viewport.width >= viewModeStripWidth + 8 + 248 + 96;
        // Camera-speed chip sits under the view-mode strip in the
        // viewport's bottom-left corner (viewportHud is at viewport + 8).
        // It only shows while flashing after a speed change.
        cameraSpeedSurface.visible = viewportHud.visible && speedChipShown;
        cameraSpeedText.visible = viewportHud.visible && speedChipShown;
        cameraSpeedSurface.x = 0;
        cameraSpeedSurface.y = Math.max(0, geometry.viewport.height - 40);
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
        chromeRenderer.draw(chrome, width, height, geometry);
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
        titleAnchorX = Math.max(menuX + 10, width - 16);
        projectTitle.visible = width >= 860;
        projectTitle.x = Math.max(menuX + 10, width - projectTitle.textWidth - 16);
        projectTitle.y = 5;

        var toolbarY = Theme.TITLE_BAR_HEIGHT + 4;
        addObjectButton.x = 8;
        addObjectButton.y = toolbarY;

        var toolRects = BoxLayout.row(
            new LayoutRect(94, toolbarY, 90, 28), [28, 28, 28], 3);
        for (index in 0...transformButtons.length) {
            var button = transformButtons[index];
            button.x = toolRects[index].x;
            button.y = toolRects[index].y;
        }
        var toolX = 187.0;
        var transportX = Math.max(toolX + 16, width * 0.5 - 48);
        for (button in transportButtons) {
            button.x = transportX;
            button.y = toolbarY;
            button.visible = width > 620;
            transportX += 33;
        }
    }

    /**
     * Declare stable identities for the retained shell in the shared frame
     * registry. Retained H2D objects still own rendering/hit behavior while the
     * core supplies diagnostics and a migration-safe persistent state key.
     */
    public function registerFrame(frame:UiFrame):Void {
        var geometry = lastGeometry;
        if (geometry == null) return;
        frame.pushScope("editor-shell");
        frame.register("hierarchy-panel", geometry.leftPanel);
        frame.register("viewport", geometry.viewport);
        frame.register("output-console", geometry.console);
        frame.register("inspector-panel", geometry.rightPanel);

        frame.pushScope("toolbar");
        frame.register("add-object", new LayoutRect(
            addObjectButton.x, addObjectButton.y, 78, 28));
        var toolNames = ["move", "rotate", "scale"];
        for (index in 0...transformButtons.length) {
            var button = transformButtons[index];
            frame.register(toolNames[index], new LayoutRect(
                button.x, button.y, 28, 28));
        }
        frame.popScope();

        frame.pushScope("hierarchy");
        var visibleRows = hierarchyVisibleRowCount();
        var last = Std.int(Math.min(hierarchyRows.length,
            firstVisibleHierarchyRow + visibleRows));
        for (index in firstVisibleHierarchyRow...last) {
            var row = hierarchyRows[index];
            frame.register('entity-${row.objectId}', new LayoutRect(
                0, row.y, Math.max(0, geometry.leftPanel.width - 8),
                HIERARCHY_ROW_HEIGHT));
        }
        frame.popScope();
        frame.popScope();
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
        objectSection.contentHeight = INSPECTOR_ROW_HEIGHT * 2;

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
        enabledCheckbox.x = 10;
        enabledCheckbox.y = INSPECTOR_ROW_HEIGHT + 4;
        enabledCheckbox.setWidth(Math.max(0, width - 20));

        addComponentButton.x = 8;
        addComponentButton.y = Math.round(y + 8);
        addComponentButton.setWidth(Math.max(0, width - 16));
        addComponentButton.visible = inspectorContentMask.visible;
        y += Theme.CONTROL_HEIGHT + 16;

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
        var live:Map<Int, Bool> = [];
        for (entry in entries) {
            allHierarchyEntries.push(entry);
            live.set(entry.id, true);
            if (!hierarchyExpanded.exists(entry.id)) {
                hierarchyExpanded.set(entry.id, true);
            }
        }
        var stale:Array<Int> = [];
        for (id in hierarchyExpanded.keys()) if (!live.exists(id)) stale.push(id);
        for (id in stale) hierarchyExpanded.remove(id);
        if (selectionAnchorId >= 0 && !live.exists(selectionAnchorId)) {
            selectionAnchorId = -1;
        }
        rebuildFilteredHierarchy();
        rendererStatus.text = "DX12  ·  Native  ·  " + entries.length
            + (entries.length == 1 ? " object" : " objects");
    }

    function applyHierarchyFilter(value:String):Void {
        hierarchyFilter = StringTools.trim(value).toLowerCase();
        firstVisibleHierarchyRow = 0;
        selectionAnchorId = -1;
        rebuildFilteredHierarchy();
    }

    function rebuildFilteredHierarchy():Void {
        visibleHierarchyEntries.resize(0);
        var byId:Map<Int, HierarchyEntry> = [];
        for (entry in allHierarchyEntries) byId.set(entry.id, entry);
        var included:Map<Int, Bool> = [];
        if (hierarchyFilter.length > 0) {
            // Search results keep their complete ancestor path visible, while
            // expansion state remains untouched for when filtering ends.
            for (entry in allHierarchyEntries) {
                if (entry.name.toLowerCase().indexOf(hierarchyFilter) < 0) continue;
                var current:Null<HierarchyEntry> = entry;
                while (current != null && !included.exists(current.id)) {
                    included.set(current.id, true);
                    current = current.parentId < 0 ? null : byId.get(current.parentId);
                }
            }
        }
        for (entry in allHierarchyEntries) {
            var visible = hierarchyFilter.length > 0
                ? included.exists(entry.id)
                : ancestorsExpanded(entry, byId);
            if (visible) {
                visibleHierarchyEntries.push(entry);
            }
        }
        while (hierarchyRows.length > visibleHierarchyEntries.length) {
            var removed = hierarchyRows.pop();
            removed.cancelRename();
            removed.remove();
        }
        for (index in 0...visibleHierarchyEntries.length) {
            var entry = visibleHierarchyEntries[index];
            var row:HierarchyRow;
            if (index < hierarchyRows.length) {
                row = hierarchyRows[index];
            } else {
                row = new HierarchyRow(ctx, entry.id, entry.name, leftContentMask);
                row.onSelect = selectHierarchyRow;
                row.onWheel = function(delta) scrollHierarchy(delta);
                row.onToggle = toggleHierarchyEntry;
                row.onToggleVisibility = function(id) {
                    if (onToggleObjectVisibility != null) onToggleObjectVisibility(id);
                };
                row.onContextMenu = openHierarchyContextMenu;
                row.onRename = renameHierarchyObject;
                row.onDragStart = beginHierarchyDrag;
                row.onDragMove = updateHierarchyDrag;
                row.onDragEnd = finishHierarchyDrag;
                hierarchyRows.push(row);
            }
            row.setEntry(entry, hierarchyExpanded.get(entry.id) != false);
        }
        clearHierarchyDropFeedback();
        resize();
    }

    function ancestorsExpanded(entry:HierarchyEntry,
            byId:Map<Int, HierarchyEntry>):Bool {
        var parentId = entry.parentId;
        while (parentId >= 0) {
            if (hierarchyExpanded.get(parentId) == false) return false;
            var parent = byId.get(parentId);
            if (parent == null) return false;
            parentId = parent.parentId;
        }
        return true;
    }

    function revealHierarchyObject(id:Int):Bool {
        var byId:Map<Int, HierarchyEntry> = [];
        for (entry in allHierarchyEntries) byId.set(entry.id, entry);
        var entry = byId.get(id);
        if (entry == null) return false;
        var changed = false;
        var parentId = entry.parentId;
        while (parentId >= 0) {
            if (hierarchyExpanded.get(parentId) == false) {
                hierarchyExpanded.set(parentId, true);
                changed = true;
            }
            var parent = byId.get(parentId);
            if (parent == null) break;
            parentId = parent.parentId;
        }
        return changed;
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, ?components:Array<ComponentInspectorData>,
            ?availableTypes:Array<ComponentTypeInfo>, enabled:Bool = true):Void {
        selectedObjectIds = ids.copy();
        selectedObjectId = primaryId;
        availableComponentTypes = availableTypes == null
            ? [] : availableTypes.copy();
        if (selectedObjectIds.length == 1) {
            var rowFound = false;
            for (index in 0...hierarchyRows.length) {
                if (hierarchyRows[index].objectId != primaryId) continue;
                rowFound = true;
                var visibleRows = hierarchyVisibleRowCount();
                if (index < firstVisibleHierarchyRow) firstVisibleHierarchyRow = index;
                else if (index >= firstVisibleHierarchyRow + visibleRows)
                    firstVisibleHierarchyRow = index - visibleRows + 1;
                break;
            }
            if (!rowFound && hierarchyFilter.length == 0
                    && revealHierarchyObject(primaryId)) {
                rebuildFilteredHierarchy();
                for (index in 0...hierarchyRows.length) {
                    if (hierarchyRows[index].objectId != primaryId) continue;
                    var visibleRows = hierarchyVisibleRowCount();
                    if (index < firstVisibleHierarchyRow) firstVisibleHierarchyRow = index;
                    else if (index >= firstVisibleHierarchyRow + visibleRows) {
                        firstVisibleHierarchyRow = index - visibleRows + 1;
                    }
                    break;
                }
            }
        }
        if (selectedObjectIds.length == 0) {
            rebuildInspectorComponents([]);
            inspectorContentMask.visible = false;
            selectionStatusValue = "Select an object to inspect";
        } else {
            // Multi-selections keep the shared components visible. Values that
            // differ are rendered as "Multiple Values" by the property rows.
            objectNameField.setValue(name);
            enabledCheckbox.value = enabled;
            rebuildInspectorComponents(components == null ? [] : components);
            inspectorContentMask.visible = true;
            selectionStatusValue = selectedObjectIds.length > 1
                ? name
                : name + "  ·  Game Object";
        }
        selectionStatus.text = selectionStatusValue;
        inspectorScrollValue = 0;
        inspectorContentMask.scrollY = 0;
        layoutHierarchyRows();
        resize();
    }

    public inline function setObjectName(value:String):Void objectNameField.setValue(value);

    /** Live component-vector update while a viewport gizmo drag is active. */
    public function updateInspectorVector(componentIndex:Int,
            propertyId:String, x:Float, y:Float, z:Float):Void {
        updateInspectorVectorMixed(componentIndex, propertyId,
            [x, y, z], [false, false, false]);
    }

    /** Live vector update for a multi-object drag, including mixed axes. */
    public function updateInspectorVectorMixed(componentIndex:Int,
            propertyId:String, values:Array<Float>, mixed:Array<Bool>):Void {
        for (section in componentSections) {
            if (section.componentIndex == componentIndex) {
                section.updateVectorMixed(propertyId, values, mixed);
                return;
            }
        }
    }

    /** Toggle ratio-preserving scale edits without changing current values. */
    function setScaleLinked(value:Bool):Void {
        if (scaleLinked == value) return;
        scaleLinked = value;
        for (section in componentSections) {
            section.setLinkState("scale", scaleLinked);
        }
    }

    function rebuildInspectorComponents(data:Array<ComponentInspectorData>):Void {
        for (section in componentSections) {
            componentSectionExpanded.set(componentSectionKey(
                section.componentIndex, section.typeId), section.expanded);
            section.remove();
        }
        componentSections.resize(0);
        inspectorSections.resize(1);

        for (component in data) {
            var section = new ComponentInspectorSection(ctx, component,
                scaleLinked, inspectorContentMask);
            var componentIndex = component.componentIndex;
            var sectionKey = componentSectionKey(componentIndex, component.typeId);
            if (componentSectionExpanded.exists(sectionKey)) {
                section.setExpanded(componentSectionExpanded.get(sectionKey));
            }
            section.onNumberCommit = function(propertyId, axis, value) {
                if (onInspectorNumberChanged != null) {
                    onInspectorNumberChanged(componentIndex, propertyId, axis, value);
                }
            };
            section.onNumberEditBegin = function(propertyId, axis) {
                if (onInspectorEditBegin != null) {
                    onInspectorEditBegin(componentIndex, propertyId, axis);
                }
            };
            section.onNumberEditEnd = function(propertyId, axis) {
                if (onInspectorEditEnd != null) {
                    onInspectorEditEnd(componentIndex, propertyId, axis);
                }
            };
            section.onTextCommit = function(propertyId, value) {
                if (onInspectorTextChanged != null) {
                    onInspectorTextChanged(componentIndex, propertyId, value);
                }
            };
            section.onAssetPick = function(propertyId) {
                openAssetPicker(component, propertyId, componentIndex);
            };
            section.onBoolCommit = function(propertyId, value) {
                if (onInspectorBoolChanged != null) {
                    onInspectorBoolChanged(componentIndex, propertyId, value);
                }
            };
            section.onReset = function(propertyId) {
                if (onInspectorReset != null) {
                    onInspectorReset(componentIndex, propertyId);
                }
            };
            section.onLinkChanged = function(propertyId, linked) {
                setScaleLinked(linked);
                if (onInspectorLinkChanged != null) {
                    onInspectorLinkChanged(componentIndex, propertyId, linked);
                }
            };
            section.onEditRejected = function(message) log("inspector: " + message);
            section.onRemoveRequested = function(index) {
                if (onRemoveComponent != null) onRemoveComponent(index);
            };
            var capturedSection = section;
            var capturedKey = sectionKey;
            section.onToggle = function() {
                componentSectionExpanded.set(capturedKey, capturedSection.expanded);
                layoutInspectorProperties();
            };
            componentSections.push(section);
            inspectorSections.push(section);
        }
    }

    /**
     * Open the shared dropdown with the options published by the asset
     * property. The property itself carries the type-aware choice list, so
     * this stays generic for meshes, materials, and future asset families.
     */
    function openAssetPicker(component:ComponentInspectorData,
            propertyId:String, componentIndex:Int):Void {
        var property:Null<ComponentPropertyData> = null;
        for (candidate in component.properties) {
            if (candidate.id == propertyId) {
                property = candidate;
                break;
            }
        }
        if (property == null || !property.editable || property.options.length == 0) return;
        var items:Array<MenuItem> = [];
        var mixed = property.isMixed(0);
        for (option in property.options) {
            var captured = option;
            items.push({
                label: captured.label,
                selected: captured.id == property.assetId && !mixed,
                mixed: mixed && captured.id == property.assetId,
                onClick: function() {
                    if (onInspectorAssetChanged != null) {
                        onInspectorAssetChanged(componentIndex, propertyId, captured.id);
                    }
                }
            });
        }
        closePaletteIfOpen();
        menuDropdown.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    static inline function componentSectionKey(index:Int, typeId:String):String {
        return index + ":" + typeId;
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

        var anchorIndex = -1;
        if (shift && selectionAnchorId >= 0) {
            for (index in 0...hierarchyRows.length) {
                if (hierarchyRows[index].objectId == selectionAnchorId) {
                    anchorIndex = index;
                    break;
                }
            }
        }
        var selection = control ? selectedObjectIds.copy() : [];
        if (shift && anchorIndex >= 0) {
            selection = [];
            var first = Std.int(Math.min(anchorIndex, clickedIndex));
            var last = Std.int(Math.max(anchorIndex, clickedIndex));
            for (index in first...(last + 1)) selection.push(hierarchyRows[index].objectId);
        } else if (control) {
            if (selection.indexOf(id) >= 0) selection.remove(id) else selection.push(id);
            selectionAnchorId = id;
        } else {
            selection = [id];
            selectionAnchorId = id;
        }

        var primary = selection.indexOf(id) >= 0 ? id
            : (selection.length == 0 ? -1 : selection[selection.length - 1]);
        if (onObjectsSelected != null) onObjectsSelected(selection, primary);
    }

    function toggleHierarchyEntry(id:Int):Void {
        hierarchyExpanded.set(id, hierarchyExpanded.get(id) == false);
        rebuildFilteredHierarchy();
    }

    function expandAllHierarchy():Void {
        for (entry in allHierarchyEntries) hierarchyExpanded.set(entry.id, true);
        rebuildFilteredHierarchy();
    }

    function collapseAllHierarchy():Void {
        for (entry in allHierarchyEntries) {
            if (entry.hasChildren) hierarchyExpanded.set(entry.id, false);
        }
        rebuildFilteredHierarchy();
    }

    function renameHierarchyObject(id:Int, value:String):Void {
        if (onHierarchyObjectNameChanged != null) {
            onHierarchyObjectNameChanged(id, value);
        }
    }

    function beginRenameFor(id:Int):Void {
        for (row in hierarchyRows) {
            if (row.objectId == id) {
                row.beginRename();
                return;
            }
        }
    }

    function beginHierarchyDrag(sourceId:Int):Void {
        closePaletteIfOpen();
        hierarchyDragIds = selectedObjectIds.indexOf(sourceId) >= 0
            ? selectedObjectIds.copy() : [sourceId];
        clearHierarchyDropFeedback();
    }

    function updateHierarchyDrag(sourceId:Int, mouseX:Float, mouseY:Float):Void {
        clearHierarchyDropFeedback();
        if (hierarchyDragIds.length == 0) hierarchyDragIds = [sourceId];
        if (mouseX < hierarchyHit.x || mouseX > hierarchyHit.x + hierarchyHit.width
                || mouseY < hierarchyHit.y
                || mouseY > hierarchyHit.y + hierarchyHit.height) {
            return;
        }

        // Keep long-tree drag/drop usable without releasing the capture. Each
        // pointer move near an edge advances one row and recomputes hit rows.
        var edge = 12.0;
        if (mouseY < hierarchyHit.y + edge && firstVisibleHierarchyRow > 0) {
            firstVisibleHierarchyRow--;
            layoutHierarchyRows();
        } else if (mouseY > hierarchyHit.y + hierarchyHit.height - edge
                && firstVisibleHierarchyRow < maxFirstVisibleHierarchyRow()) {
            firstVisibleHierarchyRow++;
            layoutHierarchyRows();
        }

        var targetRow:Null<HierarchyRow> = null;
        for (row in hierarchyRows) {
            if (!row.visible) continue;
            if (mouseY >= row.y && mouseY < row.y + HIERARCHY_ROW_HEIGHT) {
                targetRow = row;
                break;
            }
        }
        if (targetRow == null) {
            hierarchyDropParentId = -1;
            hierarchyDropSiblingIndex = rootEntryCount();
            hierarchyDropMode = HierarchyRow.DROP_AFTER;
            hierarchyDropValid = onCanHierarchyDrop != null
                && onCanHierarchyDrop(hierarchyDragIds, -1);
            var lineY = hierarchyHit.y + Math.min(hierarchyHit.height - 2,
                Math.max(2, visibleRowsHeight()));
            hierarchyDropFeedback.lineStyle(2,
                hierarchyDropValid ? Theme.ACCENT : Theme.DANGER, 1);
            hierarchyDropFeedback.moveTo(4, lineY);
            hierarchyDropFeedback.lineTo(Math.max(4, hierarchyHit.width - 4), lineY);
            hierarchyDropFeedback.lineStyle();
            return;
        }

        var entry = findVisibleHierarchyEntry(targetRow.objectId);
        if (entry == null) return;
        var relativeY = mouseY - targetRow.y;
        if (relativeY < HIERARCHY_ROW_HEIGHT * 0.28) {
            hierarchyDropMode = HierarchyRow.DROP_BEFORE;
            hierarchyDropParentId = entry.parentId;
            hierarchyDropSiblingIndex = entry.siblingIndex;
        } else if (relativeY > HIERARCHY_ROW_HEIGHT * 0.72) {
            hierarchyDropMode = HierarchyRow.DROP_AFTER;
            hierarchyDropParentId = entry.parentId;
            hierarchyDropSiblingIndex = entry.siblingIndex + 1;
        } else {
            hierarchyDropMode = HierarchyRow.DROP_CHILD;
            hierarchyDropParentId = entry.id;
            hierarchyDropSiblingIndex = entry.childCount;
        }
        hierarchyDropValid = onCanHierarchyDrop != null
            && onCanHierarchyDrop(hierarchyDragIds, hierarchyDropParentId);
        hierarchyDropRow = targetRow;
        targetRow.setDropFeedback(hierarchyDropMode, hierarchyDropValid);
    }

    function finishHierarchyDrag(sourceId:Int, mouseX:Float, mouseY:Float):Void {
        updateHierarchyDrag(sourceId, mouseX, mouseY);
        if (hierarchyDropValid && onHierarchyDrop != null) {
            // Default behavior matches Unity/Unreal: preserve world. Holding
            // Alt explicitly requests local-transform preservation.
            var preserveWorld = !hxd.Key.isDown(hxd.Key.ALT);
            if (hierarchyDropMode == HierarchyRow.DROP_CHILD
                    && hierarchyDropParentId >= 0) {
                hierarchyExpanded.set(hierarchyDropParentId, true);
            }
            onHierarchyDrop(hierarchyDragIds.copy(), hierarchyDropParentId,
                hierarchyDropSiblingIndex, preserveWorld);
        }
        hierarchyDragIds.resize(0);
        clearHierarchyDropFeedback();
    }

    function clearHierarchyDropFeedback():Void {
        if (hierarchyDropRow != null) {
            hierarchyDropRow.setDropFeedback(HierarchyRow.DROP_NONE, false);
        }
        hierarchyDropRow = null;
        hierarchyDropMode = HierarchyRow.DROP_NONE;
        hierarchyDropValid = false;
        hierarchyDropFeedback.clear();
    }

    function findVisibleHierarchyEntry(id:Int):Null<HierarchyEntry> {
        for (entry in visibleHierarchyEntries) if (entry.id == id) return entry;
        return null;
    }

    function rootEntryCount():Int {
        var count = 0;
        for (entry in allHierarchyEntries) if (entry.parentId < 0) count++;
        return count;
    }

    function visibleRowsHeight():Float {
        return Math.min(hierarchyRows.length, hierarchyVisibleRowCount())
            * HIERARCHY_ROW_HEIGHT;
    }

    function layoutHierarchyRows():Void {
        var visibleRows = hierarchyVisibleRowCount();
        firstVisibleHierarchyRow = Std.int(Math.max(0, Math.min(
            maxFirstVisibleHierarchyRow(), firstVisibleHierarchyRow)));
        for (index in 0...hierarchyRows.length) {
            var row = hierarchyRows[index];
            var visibleIndex = index - firstVisibleHierarchyRow;
            var isVisible = visibleIndex >= 0 && visibleIndex < visibleRows;
            if (!isVisible && row.isRenaming()) row.cancelRename();
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

    /** Primitive choices shared by the child and root creation menus. */
    function primitiveMenuItems(parentId:Int):Array<MenuItem> {
        var items:Array<MenuItem> = [];
        for (mesh in PrimitiveMeshes.all()) {
            var meshId = mesh.id;
            items.push({
                label: mesh.name,
                onClick: function() {
                    if (parentId >= 0) hierarchyExpanded.set(parentId, true);
                    if (onCreateChildPrimitive != null) {
                        onCreateChildPrimitive(parentId, meshId);
                    }
                }
            });
        }
        return items;
    }

    function openHierarchyContextMenu(id:Int):Void {
        var entry = findVisibleHierarchyEntry(id);
        if (entry == null) return;
        var actionIds = selectedObjectIds.indexOf(id) >= 0
            ? selectedObjectIds.copy() : [id];
        var createItems:Array<MenuItem> = [{
            label: "Empty Game Object",
            onClick: function() {
                hierarchyExpanded.set(id, true);
                if (onCreateChildObject != null) onCreateChildObject(id, true);
            }
        }, {
            label: "Primitives",
            submenu: primitiveMenuItems(id)
        }];
        // Grouped by intent: create, edit, structure, destroy. Entries that
        // cannot apply to the current object or clipboard are omitted.
        var items:Array<MenuItem> = [{
            label: "Create New...",
            submenu: createItems
        }, {
            label: "Create Empty Parent",
            onClick: function() {
                if (onCreateEmptyParent != null) onCreateEmptyParent(actionIds);
            }
        }, { label: "", separator: true }, {
            label: "Rename",
            onClick: function() beginRenameFor(id)
        }, {
            label: "Duplicate",
            onClick: function() {
                if (onDuplicateObjects != null) onDuplicateObjects(actionIds);
            }
        }, {
            label: "Copy",
            onClick: function() {
                if (onCopyObjects != null) onCopyObjects(actionIds);
            }
        }];
        if (hasObjectClipboard()) {
            items.push({
                label: "Paste as Child",
                onClick: function() {
                    hierarchyExpanded.set(id, true);
                    if (onPasteObjects != null) onPasteObjects(id);
                }
            });
        }
        if (entry.parentId >= 0 || entry.hasChildren) {
            items.push({ label: "", separator: true });
            if (entry.parentId >= 0) {
                items.push({
                    label: "Unparent",
                    onClick: function() {
                        if (onUnparentObjects != null) onUnparentObjects(actionIds);
                    }
                });
            }
            if (entry.hasChildren) {
                items.push({
                    label: "Select Subtree",
                    onClick: function() {
                        if (onSelectSubtree != null) onSelectSubtree(id);
                    }
                });
                items.push({
                    label: hierarchyExpanded.get(id) == false ? "Expand" : "Collapse",
                    onClick: function() toggleHierarchyEntry(id)
                });
            }
        }
        items.push({ label: "", separator: true });
        items.push({
            label: "Delete",
            onClick: function() {
                if (onDeleteObjects != null) onDeleteObjects(actionIds);
            }
        });
        closeFovPopup();
        menuDropdown.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    inline function hasObjectClipboard():Bool {
        return onQueryObjectClipboard != null && onQueryObjectClipboard();
    }

    function openHierarchyRootContextMenu():Void {
        var createItems:Array<MenuItem> = [{
            label: "Empty Game Object",
            onClick: function() {
                if (onCreateChildObject != null) onCreateChildObject(-1, true);
            }
        }, {
            label: "Primitives",
            submenu: primitiveMenuItems(-1)
        }];
        var items:Array<MenuItem> = [{
            label: "Create New...",
            submenu: createItems
        }];
        if (hasObjectClipboard()) {
            items.push({ label: "", separator: true });
            items.push({
                label: "Paste at Root",
                onClick: function() {
                    if (onPasteObjects != null) onPasteObjects(-1);
                }
            });
        }
        items.push({ label: "", separator: true });
        items.push({ label: "Expand All", onClick: expandAllHierarchy });
        items.push({ label: "Collapse All", onClick: collapseAllHierarchy });
        closeFovPopup();
        menuDropdown.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    function handleHierarchyBackgroundClick(event:hxd.Event):Void {
        if (event.button == 1) {
            openHierarchyRootContextMenu();
        } else if (event.button == 0) {
            closePaletteIfOpen();
            input.clearFocus();
            selectionAnchorId = -1;
            if (onObjectsSelected != null) onObjectsSelected([], -1);
        } else return;
        event.propagate = false;
    }

    /** True while any text-entry control owns the keyboard. */
    function anyTextCaptureActive():Bool {
        if (assetBrowser.isRenaming() || assetBrowser.isSearchFocused()) return true;
        if (fovInput.isEditing()) return true;
        if (objectNameField.isFocused() || hierarchySearch.isFocused()) return true;
        for (row in hierarchyRows) if (row.isRenaming()) return true;
        for (section in componentSections) if (section.isEditing()) return true;
        return false;
    }

    function closePaletteIfOpen():Void {
        if (palette.visible) palette.close();
        snapBar.closePopup();
        menuDropdown.close();
        closeFovPopup();
        assetBrowser.closeMenus();
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

    function duplicateSelection():Void {
        if (selectedObjectIds.length > 0 && onDuplicateObjects != null) {
            onDuplicateObjects(selectedObjectIds.copy());
        }
    }

    function copySelection():Void {
        if (selectedObjectIds.length > 0 && onCopyObjects != null) {
            onCopyObjects(selectedObjectIds.copy());
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
