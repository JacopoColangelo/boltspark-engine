package boltspark.ui;

import boltspark.diagnostics.FrameStats;
import boltspark.editor.EditorCameraController;
import boltspark.editor.EditorViewport;
import boltspark.editor.GridSnapping;
import boltspark.engine.ComponentTypeInfo;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.inspector.AssetType;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.ui.AssetDragSession;
import boltspark.ui.AssetDropRect;
import boltspark.ui.AssetDropTarget;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.DockLayoutStore;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.layout.BoxLayout;
import boltspark.ui.dock.DockingManager;
import boltspark.ui.dock.DockPanelView;
import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.PanelRegistry;
import boltspark.ui.core.UiFrame;
import boltspark.ui.windows.ApplicationWindowKind;
import boltspark.platform.FloatWindowManager;
import boltspark.ui.widgets.BottomDockTab;
import boltspark.ui.widgets.ConsolePanel;
import boltspark.ui.widgets.ComponentInspectorSection;
import boltspark.ui.widgets.GameObjectPalette;
import boltspark.ui.widgets.HierarchyRow;
import boltspark.ui.widgets.InspectorSection;
import boltspark.ui.widgets.AssetBrowser;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.MenuDropdown.MenuItem;
import boltspark.ui.widgets.UiTooltip;
import boltspark.project.EngineAssetCatalog;
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
    static inline var HIERARCHY_SORT_WIDTH:Int = 40;
    static inline var HIERARCHY_SORT_ICON_WIDTH:Int = 26;
    static inline var INSPECTOR_ROW_HEIGHT:Int = 28;

    final ctx:UiContext;
    final input:InputAdapter;
    final root:h2d.Object;
    final chrome:h2d.Graphics;
    final chromeRenderer:EditorChromeRenderer;
    final editorBackgroundHit:h2d.Interactive;
    /** All dockable panel hosts live here, below dock chrome but above scene. */
    final panelLayer:h2d.Object;

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
    final hierarchySortButton:UiButton;
    final hierarchyHit:h2d.Interactive;
    final hierarchyRows:Array<HierarchyRow> = [];
    final allHierarchyEntries:Array<HierarchyEntry> = [];
    final visibleHierarchyEntries:Array<HierarchyEntry> = [];
    final hierarchyScrollBar:ScrollBar;
    final hierarchyDropFeedback:h2d.Graphics;
    final hierarchyExpanded:Map<Int, Bool> = [];
    /** Last known parent for each id, used to detect reparents. */
    final hierarchyParentById:Map<Int, Int> = [];

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
    /** View-mode popup: FOV field plus the grid and performance-stats toggles. */
    final fovPopupRoot:h2d.Object;
    final fovPopupSurface:UiSurface;
    final fovPopupCatch:h2d.Interactive;
    final fovTitleText:UiText;
    final fovInput:NumericDragField;
    final fovDegreeText:UiText;
    final fovGridCheck:UiCheckbox;
    final fovPerfCheck:UiCheckbox;
    var fovPopupOpen:Bool = false;
    /** Optional viewport overlay driven by the camera-settings toggle. */
    final perfText:UiText;
    var perfStats:FrameStats = new FrameStats(0.5);
    var perfVisible:Bool = false;
    final cameraSpeedSurface:UiSurface;
    final cameraSpeedText:UiText;
    /** Floating label naming the object/material slot under an asset drag. */
    final viewportDropHintSurface:UiSurface;
    final viewportDropHint:UiText;
    var viewportDropHintWidth:Float = 96;
    /** Speed chip flash state: visible briefly after each speed change. */
    var speedChipShown:Bool = false;
    var speedChipTimer:Float = 0;
    /** How long the speed chip stays fully visible after a change. */
    static inline var SPEED_CHIP_VISIBLE:Float = 1.2;
    /** Closing fade duration at the end of the flash. */
    static inline var SPEED_CHIP_FADE:Float = 0.35;
    /** FOV popup geometry and the continuous range offered by its slider. */
    static inline var FOV_POPUP_WIDTH:Int = 220;
    static inline var POPUP_MARGIN:Int = 8;
    static inline var POPUP_TITLE_H:Int = 14;
    static inline var POPUP_ROW_H:Int = 24;
    static inline var POPUP_ROW_GAP:Int = 8;
    static inline var FOV_POPUP_HEIGHT:Int = POPUP_MARGIN * 2 + POPUP_TITLE_H
        + POPUP_ROW_GAP + 3 * POPUP_ROW_H + 2 * POPUP_ROW_GAP;
    static inline var FOV_MIN_DEG:Float = 30.0;
    static inline var FOV_MAX_DEG:Float = 140.0;
    /** Viewport performance readout. */
    static inline var PERF_WIDTH:Int = 176;

    static inline function popupRowY(index:Int):Int {
        return POPUP_MARGIN + POPUP_TITLE_H + POPUP_ROW_GAP
            + index * (POPUP_ROW_H + POPUP_ROW_GAP);
    }
    final console:ConsolePanel;
    final bottomTabs:h2d.Object;
    final logTab:BottomDockTab;
    final assetsTab:BottomDockTab;
    final bottomTabLine:h2d.Graphics;
    var activeBottomTab:Int = 0;
    final statusDot:h2d.Graphics;
    final statusText:h2d.Text;
    final rendererStatus:h2d.Text;
    final inputStatus:h2d.Text;

    final dockLayout:DockLayout;
    final layoutStore:DockLayoutStore;
    final dockRegistry:PanelRegistry;
    final dockWindowManager:FloatWindowManager;
    public var dockManager(default, null):DockingManager;
    var hierarchyDockHost:h2d.Object;
    var inspectorDockHost:h2d.Object;
    final palette:GameObjectPalette;
    final menuDropdown:MenuDropdown;
    final tooltip:UiTooltip;
    final assetBrowser:AssetBrowser;

    /** Create a primitive in front of the viewport camera (Add menu click). */
    public var onCreatePrimitive:Null<String->Void>;
    /** Add an empty object in front of the viewport camera. */
    public var onAddEmptyObjectInFront:Null<Void->Void>;
    /** Create a primitive by mesh asset id at viewport coordinates (menu drag/drop). */
    public var onDropPrimitive:Null<String->Float->Float->Void>;
    /** Create a primitive dropped on the hierarchy: mesh id + target parent id. */
    public var onCreatePrimitiveInHierarchy:Null<String->Int->Void>;
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
    public var onQueryEngineAssets:Null<Void->Array<AssetFileInfo>>;
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
    /** Current grid visibility, used to mirror the checkbox state. */
    public var onQueryGridVisible:Null<Void->Bool>;
    /** Inspector rows for a floating native panel, supplied by Main. */
    public var onQueryNativeInspector:Null<Void->Dynamic>;
    /** Fired with the new horizontal FOV whenever the FOV field is edited. */
    public var onFovChanged:Null<Float->Void>;
    /** F: frame the primary selection in the active viewport. */
    public var onFocusSelection:Null<Void->Void>;
    public var viewportRect(default, null):LayoutRect = new LayoutRect(0, 0, 0, 0);

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
    /** Uses HierarchyOrder.AUTHORED / NAME / TYPE. */
    var hierarchySortKey:Int = HierarchyOrder.AUTHORED;
    var hierarchySortAsc:Bool = true;
    var hierarchyDragIds:Array<Int> = [];
    var hierarchyDropParentId:Int = -1;
    var hierarchyDropSiblingIndex:Int = 0;
    var hierarchyDropMode:Int = HierarchyRow.DROP_NONE;
    var hierarchyDropValid:Bool = false;
    var hierarchyDropRow:Null<HierarchyRow>;
    /** True while an engine mesh asset is being dragged over the editor. */
    var hierarchyAssetDragActive:Bool = false;
    var hierarchyAssetDropTarget:Null<AssetDropTarget>;
    var hierarchyFeedbackDrawn:Bool = false;
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

        // Panel hosts sit above the background catcher but below dock chrome.
        panelLayer = new h2d.Object(root);
        viewportHit = new h2d.Interactive(1, 1, panelLayer);
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

        leftContentMask = new h2d.Mask(0, 0, panelLayer);
        rightContentMask = new h2d.Mask(0, 0, panelLayer);

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
            } else if (menuName == "Window") {
                // Built lazily so show/hide state always reflects the live tree.
                button.onClick = function() {
                    if (menuDropdown.isOpen) {
                        menuDropdown.close();
                        return;
                    }
                    closePaletteIfOpen();
                    var items:Array<MenuItem> = [{label: "Panels", section: true}];
                    for (id in dockRegistry.ids()) {
                        var descriptor = dockRegistry.descriptor(id);
                        if (descriptor == null || descriptor.fixed == true) continue;
                        var capturedId = id;
                        var displayed = dockManager.isOpen(capturedId);
                        items.push({
                            label: descriptor.displayName,
                            selected: displayed,
                            onClick: function() {
                                input.clearFocus();
                                if (dockManager.isOpen(capturedId)) {
                                    dockManager.close(capturedId);
                                } else {
                                    dockManager.open(capturedId);
                                }
                            }
                        });
                    }
                    items.push({label: "", separator: true});
                    items.push({
                        label: "Reset Layout",
                        onClick: function() {
                            input.clearFocus();
                            dockManager.reset();
                        }
                    });
                    items.push({
                        label: "Save Layout",
                        onClick: function() {
                            input.clearFocus();
                            dockManager.save();
                            log("layout: docking layout saved");
                        }
                    });
                    items.push({
                        label: "Load Layout",
                        onClick: function() {
                            input.clearFocus();
                            dockManager.reload();
                        }
                    });
                    items.push({label: "", separator: true});
                    items.push({
                        label: "Float Focused Panel",
                        onClick: function() {
                            input.clearFocus();
                            dockManager.floatFocused();
                        }
                    });
                    items.push({
                        label: "Dock Floating Windows",
                        onClick: function() {
                            input.clearFocus();
                            dockManager.dockAllFloating();
                        }
                    });
                    menuDropdown.open(capturedButton.x, Theme.TITLE_BAR_HEIGHT, items);
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
        addObjectButton.onClick = openAddObjectMenu;
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
        hierarchySearch = new SearchField(ctx, "Search Entities", 100, 24, leftContentMask);
        hierarchySearch.onChange = function(value) applyHierarchyFilter(value);
        hierarchySortButton = new UiButton(ctx, "", HIERARCHY_SORT_WIDTH, 20, leftContentMask);
        hierarchySortButton.setIcon(Sort);
        hierarchySortButton.setIconSize(14);
        hierarchySortButton.setDropdown();
        hierarchySortButton.onClick = openHierarchySortMenu;

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

        // Engine primitive assets can be dropped here to create a new object
        // in front of the camera, parented to the hovered hierarchy row.
        hierarchyAssetDropTarget = new AssetDropTarget(
            AssetType.MeshAsset, hierarchyHit, hierarchyAssetDropRect,
            function(active) {
                hierarchyAssetDragActive = active;
                if (!active) clearHierarchyDropFeedback();
            }, function(payload) {
                var parentId = hierarchyAssetParentAt(ctx.mouseX,
                    ctx.mouseY);
                clearHierarchyDropFeedback();
                if (onCreatePrimitiveInHierarchy != null) {
                    onCreatePrimitiveInHierarchy(payload.assetId, parentId);
                }
            });
        AssetDragSession.add(hierarchyAssetDropTarget);

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
        // The enabled box sits immediately left of the name field on a single
        // compact row; neither control carries a text label.
        objectNameField = new TextInputField(ctx, "", Theme.RIGHT_PANEL_WIDTH - 36,
            Theme.CONTROL_HEIGHT, "", objectSection.content);
        objectNameField.setLabelWidth(0);
        objectNameField.onCommit = function(name:String) {
            if (onObjectNameChanged != null) onObjectNameChanged(name);
        };
        objectNameField.onCancel = function() log("inspector: name edit cancelled");
        enabledCheckbox = new UiCheckbox(ctx, "", objectSection.content);
        // The name field starts right after the box, so keep the checkbox hit
        // region on the box only instead of spanning the whole inspector row.
        enabledCheckbox.setBoxOnlyHit();
        enabledCheckbox.onChanged = function(value) {
            if (onSetObjectEnabled != null) onSetObjectEnabled(selectedObjectId, value);
        };

        addComponentButton = new UiButton(ctx, "Add Component",
            Theme.RIGHT_PANEL_WIDTH - 16, Theme.CONTROL_HEIGHT,
            inspectorContentMask);
        addComponentButton.setIcon(Add);
        addComponentButton.onClick = openComponentMenu;

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
        UiIcons.draw(viewportModeIcon, Camera, 0, 0, 12, Theme.TEXT_SECONDARY);
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
        fovTitleText.x = POPUP_MARGIN;
        fovTitleText.y = POPUP_MARGIN;

        fovInput = new NumericDragField(ctx, 128, POPUP_ROW_H,
            FOV_MIN_DEG, FOV_MAX_DEG, 1, EditorViewport.VIEW_FOV_DEG,
            function(value:Float):String return Std.string(Std.int(Math.round(value))),
            "", Theme.TEXT, fovPopupRoot);
        fovInput.x = POPUP_MARGIN;
        fovInput.y = popupRowY(0);
        fovInput.onValueChanged = applyFov;
        fovInput.onEditRejected = function(message) log("viewport: " + message);

        fovDegreeText = new UiText(ctx.captionFont, fovPopupRoot);
        fovDegreeText.text = "°";
        fovDegreeText.textColor = Theme.MUTED;
        fovDegreeText.lineBreak = false;
        fovDegreeText.x = POPUP_MARGIN + 128 + 6;
        fovDegreeText.y = popupRowY(0)
            + Math.round((POPUP_ROW_H - fovDegreeText.textHeight) * 0.5);

        var toggleWidth = FOV_POPUP_WIDTH - POPUP_MARGIN * 2;
        var checkboxY = POPUP_ROW_H - 22; // UiCheckbox uses a 22px inner row.

        fovGridCheck = new UiCheckbox(ctx, "Editor Grid  (G)", fovPopupRoot,
            ctx.captionFont);
        fovGridCheck.x = POPUP_MARGIN;
        fovGridCheck.y = popupRowY(1) + Math.round(checkboxY * 0.5);
        fovGridCheck.setWidth(toggleWidth);
        fovGridCheck.onChanged = function(value) {
            if (onToggleGrid != null) onToggleGrid();
        };

        fovPerfCheck = new UiCheckbox(ctx, "Performance Stats", fovPopupRoot,
            ctx.captionFont);
        fovPerfCheck.x = POPUP_MARGIN;
        fovPerfCheck.y = popupRowY(2) + Math.round(checkboxY * 0.5);
        fovPerfCheck.setWidth(toggleWidth);
        fovPerfCheck.onChanged = setPerfVisible;

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

        viewportDropHintSurface = new UiSurface(ctx, root);
        // Opaque fill: the label must never let panel text show through it.
        viewportDropHintSurface.setStyle(Theme.PANEL_ALT, Theme.ACCENT, 0);
        viewportDropHintSurface.setSize(viewportDropHintWidth, 22);
        viewportDropHint = new UiText(ctx.captionFont, viewportDropHintSurface);
        viewportDropHint.textColor = Theme.TEXT;
        viewportDropHint.lineBreak = false;
        viewportDropHint.x = 6;
        viewportDropHint.y = 4;
        viewportDropHintSurface.visible = false;

        // Optional performance readout in the viewport's top-right corner.
        // Plain text with no surface/frame, placed on whole pixels so the
        // exact-size FreeType atlas stays crisp.
        perfText = new UiText(ctx.monoFont, viewportHud);
        perfText.textColor = Theme.TEXT_SECONDARY;
        perfText.lineBreak = true;
        perfText.visible = false;

        // Ctrl+End routes from the window-level input adapter, which sees key
        // events even when full-window interactives consume pointer input.
        input.onSnapToGridPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onSnapToGrid != null) onSnapToGrid();
        };

        console = new ConsolePanel(ctx, panelLayer);
        console.onBackgroundClick = closePaletteIfOpen;

        // Bottom dock tabs: Asset Browser first, Output Log second.
        bottomTabs = new h2d.Object(root);
        assetsTab = new BottomDockTab(ctx, "Asset Browser", Folder, 108, 22, bottomTabs);
        assetsTab.onClick = function() setBottomTab(0);
        logTab = new BottomDockTab(ctx, "Output Log", Console, 92, 22, bottomTabs);
        logTab.onClick = function() setBottomTab(1);
        bottomTabLine = new h2d.Graphics(bottomTabs);

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
            // Deleting the selected scene object is the default. The Asset
            // Browser only intercepts Delete when the user has explicitly
            // selected an asset or folder tile there; merely browsing into a
            // folder must never turn Delete into a folder-delete command.
            if (activeBottomTab == 0 && assetBrowser.hasSelection()
                    && assetBrowser.deleteSelection()) {
                return;
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
            // A docking drag owns Escape first so it can be cancelled without
            // also dismissing unrelated popups or changing selection.
            if (dockManager != null && dockManager.isDragActive()) {
                dockManager.cancelDrag();
                return;
            }
            if (menuDropdown.isOpen) {
                menuDropdown.close();
                return;
            }
            if (activeBottomTab == 0 && !anyTextCaptureActive()) {
                assetBrowser.clearSelection();
            }
            closePaletteIfOpen();
        };
        // G (rebindable) toggles the independent editor grid from anywhere in
        // the editor; only active text entry suppresses it.
        input.onToggleGridPressed = function() {
            if (anyTextCaptureActive()) return;
            if (onToggleGrid != null) onToggleGrid();
            fovGridCheck.value = onQueryGridVisible != null && onQueryGridVisible();
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

        // Dock content is created first; the shared popup layer is created at
        // the end of this constructor so its full-window dismiss catch and menu
        // rows stay above every panel interactive.
        assetBrowser = new AssetBrowser(ctx, panelLayer, root);
        assetBrowser.visible = activeBottomTab == 0;
        assetBrowser.onQueryAssets = function() {
            return onQueryAssets != null ? onQueryAssets() : [];
        };
        assetBrowser.onQueryEngineAssets = function() {
            return onQueryEngineAssets != null ? onQueryEngineAssets() : [];
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

        // The full docking system replaces the three fixed splitters and the
        // hardcoded bottom tab strip. It is created only after every panel
        // content object exists, and before the shared popup layer so menus
        // remain topmost.
        dockRegistry = new PanelRegistry();
        registerDockPanels();
        var dockChromeLayer = new h2d.Object(root);
        var dockFloatPanelLayer = new h2d.Object(root);
        var dockFloatLayer = new h2d.Object(root);
        var dockOverlayLayer = new h2d.Object(root);
        MenuDropdown.overlayLayer = dockOverlayLayer;
        // Popups created earlier in the constructor must also sit above the
        // dock chrome, otherwise tab bars draw over their content.
        dockOverlayLayer.addChild(fovPopupRoot);
        dockOverlayLayer.addChild(palette);
        dockOverlayLayer.addChild(viewportDropHintSurface);
        dockWindowManager = new FloatWindowManager(ctx);
        dockManager = new DockingManager(ctx, input, dockRegistry, panelLayer,
            dockFloatPanelLayer, dockChromeLayer, dockFloatLayer, dockOverlayLayer,
            dockWindowManager);
        dockManager.onSnapshotRequest = buildNativePanelSnapshot;
        dockManager.onDockPanelEdit = applyNativePanelEdit;
        dockManager.onBottomTabChanged = setBottomTabFromDock;
        dockManager.onGeometryChanged = function() {
            // Geometry can change synchronously from a float event (an asset
            // drop rebuilds the Inspector). `ctx.width/height` are temporarily
            // overridden to the float's client size in that call stack; using
            // them here redraws only a 480x372 slice of the main chrome and
            // leaves dark frames over the viewport.
            drawChrome(ctx.windowWidth, ctx.windowHeight,
                dockManager.geometry());
        };
        dockManager.onBeforeSave = syncLegacyDockSizes;
        dockManager.onLayoutSaved = saveLayout;
        dockManager.onLayoutReset = resetLegacyLayout;
        bottomTabs.visible = false;
        // Bind hosts before initialize: a restored floating panel needs its
        // real H2D view available when the native HWND is created.
        dockManager.bindHostId("boltspark.hierarchy", hierarchyDockHost);
        dockManager.bindHostId("boltspark.inspector", inspectorDockHost);
        dockManager.bindHostId("boltspark.console", console);
        dockManager.bindHostId("boltspark.assets", assetBrowser);
        dockManager.initialize(dockLayout);
        activeBottomTab = dockManager.legacySizes().bottomTab;
        console.visible = activeBottomTab == 1;
        assetBrowser.visible = activeBottomTab == 0;

        // Created last so the popup/dismiss hit targets are topmost: clicks in
        // the Asset Browser or palette reach the dismiss catch and close an
        // open menu instead of being consumed by dock interactives.
        menuDropdown = new MenuDropdown(ctx, root);
        // Topmost shared tooltip for the hierarchy and Asset Browser.
        tooltip = new UiTooltip(ctx, root);
        assetBrowser.tooltip = tooltip;

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
                        ctx.mouseX - viewportRect.x,
                        ctx.mouseY - viewportRect.y);
                    captured.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    captured.propagate = false;
                    endGizmoCapture();
                    if (onViewportRelease != null) onViewportRelease(
                        ctx.mouseX - viewportRect.x,
                        ctx.mouseY - viewportRect.y);
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
                        ctx.mouseX - viewportRect.x,
                        ctx.mouseY - viewportRect.y);
                    captured.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    captured.propagate = false;
                    endViewportCameraGesture(kind,
                        ctx.mouseX - viewportRect.x,
                        ctx.mouseY - viewportRect.y);
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

    public inline function log(line:String):Void {
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] log: ' + line);
        }
        console.log(line);
        // Mirror into native floats so Help/console output appears immediately
        // in an already-open Output Log HWND without waiting for a snapshot.
        if (dockWindowManager != null) dockWindowManager.log(line);
    }

    /**
     * Show the viewport drop hint near the cursor, clamped inside the viewport
     * so it never covers the hierarchy or Inspector panels.
     */
    public function showViewportDropHint(text:String, x:Float, y:Float,
            viewport:LayoutRect):Void {
        // An empty label is the "no drag" signal. Leaving the surface visible
        // with stale text clearance paints a dark rectangle in the viewport.
        if (text == null || text == "") {
            hideViewportDropHint();
            return;
        }
        if (viewportDropHint.text != text) {
            viewportDropHint.text = text;
            viewportDropHintWidth = Math.max(96,
                Math.round(viewportDropHint.textWidth + 20));
            viewportDropHintSurface.setSize(viewportDropHintWidth, 22);
        }
        var margin = 6.0;
        var px = Math.max(viewport.x + margin,
            Math.min(x, viewport.x + viewport.width - viewportDropHintWidth - margin));
        var py = Math.max(viewport.y + margin,
            Math.min(y, viewport.y + viewport.height - 22 - margin));
        viewportDropHintSurface.x = Math.round(px);
        viewportDropHintSurface.y = Math.round(py);
        viewportDropHintSurface.visible = true;
    }

    public function hideViewportDropHint():Void {
        if (viewportDropHintSurface.visible) viewportDropHintSurface.visible = false;
    }

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

    /** Toggle the viewport performance overlay from the camera settings popup. */
    function setPerfVisible(value:Bool):Void {
        if (perfVisible == value) return;
        perfVisible = value;
        perfText.visible = value;
        if (value) {
            // Start a fresh window so the first readout is not skewed by the
            // time the overlay spent hidden.
            perfStats = new FrameStats(0.5);
            perfText.text = "FPS     --\nFRAME   -- ms\nMIN/MAX -- / -- ms";
        }
    }

    static inline function oneDecimal(value:Float):String {
        var text = Std.string(Math.round(value * 10) / 10);
        return text.indexOf(".") < 0 ? text + ".0" : text;
    }

    function refreshPerfText(report:FrameStatsReport):Void {
        perfText.text = 'FPS     ${oneDecimal(report.fps)}'
            + '\nFRAME   ${oneDecimal(report.averageMs)} ms'
            + '\nMIN/MAX ${oneDecimal(report.minimumMs)} / '
            + '${oneDecimal(report.maximumMs)} ms';
    }

    /** Keep the numeric field and both checkboxes in sync with editor state. */
    function refreshFovPopupValue():Void {
        fovInput.setValue(EditorViewport.VIEW_FOV_DEG);
        fovGridCheck.value = onQueryGridVisible != null && onQueryGridVisible();
        fovPerfCheck.value = perfVisible;
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
        updateBottomTabState();
        if (index == 0) assetBrowser.refresh();
        saveLayout();
        Sys.println('[probe] bottom tab=${index == 0 ? "assets" : "log"}');
    }

    /** Frameless tabs: only the icon/text tint and a 2px accent rule mark active. */
    function updateBottomTabState():Void {
        assetsTab.setActive(activeBottomTab == 0);
        logTab.setActive(activeBottomTab == 1);
        var tab = activeBottomTab == 0 ? assetsTab : logTab;
        bottomTabLine.clear();
        bottomTabLine.beginFill(Theme.ACCENT);
        bottomTabLine.drawRect(tab.x, 22, tab.width, 2);
        bottomTabLine.endFill();
    }

    /** Refresh the docked Asset Browser after a project asset changes. */
    public function refreshAssetBrowser():Void {
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
        if (dockManager != null) dockManager.update(dt);
        tooltip.update(dt);
        if (ctx.windowWidth != lastWidth || ctx.windowHeight != lastHeight) resize();
        if (hierarchyAssetDragActive) {
            updateHierarchyAssetDropFeedback(ctx.mouseX, ctx.mouseY);
        }
        if (perfVisible) {
            var report = perfStats.sample(dt);
            if (report != null) refreshPerfText(report);
        }
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
        if (inputStatus.visible) inputStatus.x = Math.max(0, ctx.windowWidth - inputStatus.textWidth - 10);
    }

    public function resize():Void {
        // Never use ctx.width/height here: float event dispatch temporarily
        // overrides them for menu/tooltip clamping, and an inspector rebuild
        // inside that dispatch calls resize() synchronously.
        var width = ctx.windowWidth;
        var height = ctx.windowHeight;
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] editor resize ${Std.int(width)}x${Std.int(height)}');
        }
        lastWidth = width;
        lastHeight = height;
        editorBackgroundHit.width = Math.max(0, width);
        editorBackgroundHit.height = Math.max(0, height);
        layoutTopBars(width);

        if (dockManager != null) {
            var body = new LayoutRect(0, Theme.TOP_BAR_HEIGHT, width,
                Math.max(0, height - Theme.TOP_BAR_HEIGHT - Theme.STATUS_BAR_HEIGHT));
            dockManager.layout(body);
            var sizes = dockManager.legacySizes();
            dockLayout.setPreferred(sizes.left, sizes.right, sizes.console);
            dockLayout.bottomTab = sizes.bottomTab;
            lastGeometry = dockManager.geometry();
            viewportRect = dockManager.viewportBody();
            // onGeometryChanged already redrew chrome through the manager.
        }

        var statusY = height - Theme.STATUS_BAR_HEIGHT;
        statusDot.x = 8;
        statusDot.y = statusY + 7;
        statusText.x = 18;
        statusText.y = statusY + 2;
        rendererStatus.x = 70;
        rendererStatus.y = statusY + 2;
        inputStatus.visible = false;
    }

    /**
     * Position every viewport overlay from the docking tree's live rect.
     * Called by the viewport panel view, never directly from resize().
     */
    public function layoutViewportForDock(rect:LayoutRect):Void {
        var rx = Math.round(rect.x);
        var ry = Math.round(rect.y);
        var rw = Math.round(Math.max(0, rect.width));
        var rh = Math.round(Math.max(0, rect.height));
        viewportRect = new LayoutRect(rx, ry, rw, rh);
        viewportHit.x = rx;
        viewportHit.y = ry;
        viewportHit.width = rw;
        viewportHit.height = rh;

        viewportHud.visible = rw >= 290 && rh >= 80;
        viewportHud.x = rx + 8;
        viewportHud.y = ry + 8;
        // The view-mode strip keeps its original visual inset, but its hit
        // area starts a little further in so corner picks reach the viewport.
        viewportModeHit.x = 20;
        viewportHintSurface.x = Math.max(142, rw - 88);
        viewportHintIcon.x = viewportHintSurface.x + 7;
        viewportHintIcon.y = 6;
        viewportHintText.x = viewportHintSurface.x + 25;
        viewportHintText.y = 4;
        viewportHintHit.x = viewportHintSurface.x;
        viewportHintHit.y = 0;

        perfText.x = Math.round(Math.max(0, rw - PERF_WIDTH - 16));
        perfText.y = 30;

        snapBar.x = viewModeStripWidth + 8;
        snapBar.y = 0;
        snapBar.visible = viewportHud.visible
            && rw >= viewModeStripWidth + 8 + 248 + 96;
        cameraSpeedSurface.visible = viewportHud.visible && speedChipShown;
        cameraSpeedText.visible = viewportHud.visible && speedChipShown;
        cameraSpeedSurface.x = 0;
        cameraSpeedSurface.y = Math.max(0, rh - 40);
        snapBar.setContainerHeight(Math.max(0, rh - 16));
    }

    public function setViewportPanelVisible(value:Bool):Void {
        viewportHit.visible = value;
        viewportHud.visible = value && viewportRect.width >= 290
            && viewportRect.height >= 80;
    }

    public function layoutHierarchyForDock(width:Float):Void {
        layoutHierarchy(width, Theme.TOP_BAR_HEIGHT);
    }

    public function layoutInspectorForDock(width:Float):Void {
        layoutInspector(width, Theme.TOP_BAR_HEIGHT);
    }

    function drawChrome(width:Float, height:Float, geometry:DockLayoutGeometry):Void {
        chromeRenderer.draw(chrome, width, height, geometry,
            inspectorContentMask.visible,
            dockManager == null ? null : dockManager.panelBackgroundRects());
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
        var toolsFit = width >= 94 + 90 + 8;
        for (index in 0...transformButtons.length) {
            var button = transformButtons[index];
            button.visible = toolsFit;
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
        // The dock tab bar now owns the panel title; suppress the old header
        // label so the same name is never drawn twice.
        hierarchyTitleIcon.visible = false;
        hierarchyTitle.visible = false;
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
        refreshHierarchySortButton(leftWidth);
        hierarchySortButton.x = Math.max(29, leftWidth - hierarchySortButton.width - 9);
        hierarchySortButton.y = bodyTop + 4;
        hierarchyCount.x = Math.max(42,
            hierarchySortButton.x - hierarchyCount.textWidth - 8);
        hierarchyCount.visible = hierarchyCount.x > hierarchyTitle.x
            + hierarchyTitle.textWidth + 2;
        hierarchyCount.y = bodyTop + 8;

        hierarchySearch.x = 8;
        hierarchySearch.y = bodyTop + 37;
        hierarchySearch.setWidth(Math.max(0, leftWidth - 16));
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
        // The dock tab bar owns the title; avoid duplicate label text.
        inspectorTitleIcon.visible = false;
        inspectorTitle.visible = false;
        inspectorTitleIcon.x = 8;
        inspectorTitleIcon.y = bodyTop + 9;
        inspectorTitle.x = 29;
        inspectorTitle.y = bodyTop + 6;
        // A selection adds a meta row with the object type; with none, the
        // header stays short and the hint is centered in the panel body.
        var expanded = inspectorContentMask.visible;
        selectionStatus.visible = true;
        fitText(selectionStatus, selectionStatusValue, Math.max(0, rightWidth - 16));
        selectionStatus.x = expanded ? 8
            : Math.round((rightWidth - selectionStatus.textWidth) * 0.5);
        selectionStatus.y = expanded ? bodyTop + 35
            : bodyTop + Math.round((rightContentMask.height - bodyTop
                - selectionStatus.textHeight) * 0.5);

        inspectorContentMask.x = 0;
        inspectorContentMask.y = bodyTop + Theme.PANEL_HEADER_HEIGHT
            + (expanded ? Theme.PANEL_META_HEIGHT : 0);
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
        // The enabled box and name field share one compact unlabeled row.
        objectSection.contentHeight = INSPECTOR_ROW_HEIGHT;

        var width = Math.max(0, inspectorContentMask.width);
        var y:Float = 0;
        for (index in 0...inspectorSections.length) {
            var section = inspectorSections[index];
            // Give each component its own breathing room instead of stacking
            // headers and rows into one dense, continuous strip.
            if (index > 0) y += Theme.SPACING;
            section.x = 0;
            section.y = Math.round(y);
            section.setWidth(width);
            y += section.totalHeight();
        }

        // Object: enabled checkbox on the left, name field filling the rest.
        enabledCheckbox.x = 8;
        // Center the 22px checkbox body within the 24px name field row at y=2.
        enabledCheckbox.y = 3;
        objectNameField.x = 32;
        objectNameField.y = 2;
        objectNameField.setWidth(Math.max(0, width - 40));

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
        // A focused TextInput draws its cursor/selection tiles inside this
        // scrolling mask. Blur first so a fast wheel cannot leave those tiles
        // with a stale clip transform for a frame (white / oversized flashes).
        input.clearFocus();
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
            var reparented = hierarchyParentById.exists(entry.id)
                && hierarchyParentById.get(entry.id) != entry.parentId;
            if (!entry.hasChildren) {
                // A leaf must not keep a fold flag. If a reparent later gives
                // it children it should start expanded, not stay collapsed.
                hierarchyExpanded.remove(entry.id);
            } else if (reparented || !hierarchyExpanded.exists(entry.id)) {
                hierarchyExpanded.set(entry.id, true);
            }
            hierarchyParentById.set(entry.id, entry.parentId);
        }
        var stale:Array<Int> = [];
        for (id in hierarchyExpanded.keys()) if (!live.exists(id)) stale.push(id);
        for (id in stale) hierarchyExpanded.remove(id);
        for (id in hierarchyParentById.keys()) if (!live.exists(id)) hierarchyParentById.remove(id);
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

    function refreshHierarchySortButton(leftWidth:Float):Void {
        var compact = leftWidth < 225;
        // A 26px button has no room for the chevron without overlapping the icon.
        hierarchySortButton.setDropdown(!compact);
        hierarchySortButton.setWidth(compact
            ? HIERARCHY_SORT_ICON_WIDTH : HIERARCHY_SORT_WIDTH);
        // Icon-only dropdowns stay quiet at Tree order and light up when sorted.
        hierarchySortButton.setSelected(hierarchySortKey != HierarchyOrder.AUTHORED);
    }

    function openHierarchySortMenu():Void {
        var items:Array<MenuItem> = [{label: "Sort By", section: true}];
        var choices = [
            {key: HierarchyOrder.AUTHORED, label: "Tree"},
            {key: HierarchyOrder.NAME, label: "Name"},
            {key: HierarchyOrder.TYPE, label: "Type"}
        ];
        for (choice in choices) {
            var captured = choice.key;
            items.push({
                label: choice.label,
                selected: hierarchySortKey == captured,
                radio: true,
                onClick: function() {
                    hierarchySortKey = captured;
                    refreshHierarchySortButton(leftContentMask.width);
                    rebuildFilteredHierarchy();
                }
            });
        }
        items.push({label: "", separator: true});
        items.push({label: "Sort Direction", section: true});
        var directions = [{label: "Ascending", ascending: true},
            {label: "Descending", ascending: false}];
        for (direction in directions) {
            var capturedAsc = direction.ascending;
            items.push({
                label: direction.label,
                selected: hierarchySortAsc == capturedAsc,
                radio: true,
                onClick: function() {
                    if (hierarchySortAsc == capturedAsc) return;
                    hierarchySortAsc = capturedAsc;
                    refreshHierarchySortButton(leftContentMask.width);
                    rebuildFilteredHierarchy();
                }
            });
        }
        menuDropdown.open(ctx.mouseX, ctx.mouseY, items);
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
        for (entry in HierarchyOrder.order(allHierarchyEntries,
                hierarchySortKey, hierarchySortAsc)) {
            // Search must still respect fold state: a match under a collapsed
            // parent stays hidden, and toggling that parent's chevron really
            // collapses/expands it instead of only swapping the glyph.
            var matches = hierarchyFilter.length == 0 || included.exists(entry.id);
            var visible = matches && ancestorsExpanded(entry, byId);
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
                row.onHover = function(id, hovering) {
                    if (hovering) {
                        UiTooltip.active(tooltip).schedule(hierarchyObjectPath(id),
                            ctx.mouseX, ctx.mouseY);
                    } else {
                        UiTooltip.active(tooltip).cancel();
                    }
                };
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

    /** Slash-separated scene path used by the hierarchy hover tooltip. */
    function hierarchyObjectPath(id:Int):String {
        var byId:Map<Int, HierarchyEntry> = [];
        for (entry in allHierarchyEntries) byId.set(entry.id, entry);
        var names:Array<String> = [];
        var current = byId.get(id);
        while (current != null) {
            names.unshift(current.name);
            current = current.parentId < 0 ? null : byId.get(current.parentId);
        }
        return names.length == 0 ? "" : "/" + names.join("/");
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
            // The Name field already shows the object's name; the header meta
            // line carries the type instead.
            selectionStatusValue = selectedObjectIds.length > 1
                ? "Multiple Game Objects" : "Game Object";
        }
        selectionStatus.text = selectionStatusValue;
        inspectorScrollValue = 0;
        inspectorContentMask.scrollY = 0;
        // A float checkbox toggles on EPush and synchronously rebuilds these
        // sections. Native-float tabs are intentionally skipped by the main
        // dock layout pass, so lay the new children out immediately using the
        // mask's current (float) dimensions instead of rendering one or more
        // frames at their default 0,0 positions.
        layoutInspectorProperties();
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
            section.onAssetBrowse = function(propertyId) {
                browseInspectorAsset(component, propertyId);
            };
            section.onAssetDrop = function(propertyId, assetId) {
                if (onInspectorAssetChanged != null) {
                    onInspectorAssetChanged(componentIndex, propertyId, assetId);
                }
            };
            section.onAssetClear = function(propertyId) {
                if (onInspectorAssetChanged != null) {
                    onInspectorAssetChanged(componentIndex, propertyId, "");
                }
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
        menuDropdown.open(ctx.mouseX, ctx.mouseY, items);
    }

    /**
     * Magnifier action on an asset slot: open (or focus) the Asset Browser and
     * select the assigned asset. Engine assets use their virtual `engine://`
     * source; the browser enables the engine-content opt-in when necessary.
     */
    function browseInspectorAsset(component:ComponentInspectorData,
            propertyId:String):Void {
        var property:Null<ComponentPropertyData> = null;
        for (candidate in component.properties) {
            if (candidate.id == propertyId) {
                property = candidate;
                break;
            }
        }
        if (property == null) return;
        dockManager.open("boltspark.assets");
        assetBrowser.revealAsset(assetSourceFor(property));
        // A floated Asset Browser renders from pushed snapshots; refresh it so
        // the newly selected tile appears there too.
        dockManager.refreshNativePanels();
    }

    /** Browser source for an inspector asset property, or "" when unassigned. */
    static function assetSourceFor(property:ComponentPropertyData):String {
        var id = property.assetId;
        if (id == null || id == "") return "";
        if (property.assetType == AssetType.MeshAsset
                && PrimitiveMeshes.find(id) != null) {
            return EngineAssetCatalog.sourceFor(AssetType.MeshAsset, id);
        }
        if (property.assetType == AssetType.MaterialAsset
                && boltspark.engine.Material.find(id) != null) {
            return EngineAssetCatalog.sourceFor(AssetType.MaterialAsset, id);
        }
        // Project assets carry their browser source directly.
        return id;
    }

    static inline function componentSectionKey(index:Int, typeId:String):String {
        return index + ":" + typeId;
    }

    function selectHierarchyRow(id:Int, control:Bool, shift:Bool):Void {
        UiTooltip.active(tooltip).cancel();
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

    /** Window-space rectangle of the hierarchy rows, used as an asset drop slot. */
    function hierarchyAssetDropRect():AssetDropRect {
        var origin = hierarchyHit.localToGlobal(new h2d.col.Point(0, 0));
        return {
            x: origin.x, y: origin.y,
            width: hierarchyHit.width, height: hierarchyHit.height
        };
    }

    /** Parent the dropped primitive would get from the current cursor row. */
    function hierarchyAssetParentAt(mouseX:Float, mouseY:Float):Int {
        if (mouseX < hierarchyHit.x || mouseX > hierarchyHit.x + hierarchyHit.width
                || mouseY < hierarchyHit.y
                || mouseY > hierarchyHit.y + hierarchyHit.height) return -1;
        for (row in hierarchyRows) {
            if (!row.visible || mouseY < row.y
                    || mouseY >= row.y + HIERARCHY_ROW_HEIGHT) continue;
            var entry = findVisibleHierarchyEntry(row.objectId);
            if (entry == null) return -1;
            var relativeY = mouseY - row.y;
            if (relativeY < HIERARCHY_ROW_HEIGHT * 0.28) return entry.parentId;
            if (relativeY > HIERARCHY_ROW_HEIGHT * 0.72) return entry.parentId;
            return entry.id;
        }
        return -1;
    }

    /** Show the same before/after/child feedback used by object reparenting. */
    function updateHierarchyAssetDropFeedback(mouseX:Float, mouseY:Float):Void {
        clearHierarchyDropFeedback();
        if (mouseX < hierarchyHit.x || mouseX > hierarchyHit.x + hierarchyHit.width
                || mouseY < hierarchyHit.y
                || mouseY > hierarchyHit.y + hierarchyHit.height) return;

        var targetRow:Null<HierarchyRow> = null;
        for (row in hierarchyRows) {
            if (!row.visible) continue;
            if (mouseY >= row.y && mouseY < row.y + HIERARCHY_ROW_HEIGHT) {
                targetRow = row;
                break;
            }
        }
        if (targetRow == null) {
            var lineY = hierarchyHit.y + Math.min(hierarchyHit.height - 2,
                Math.max(2, visibleRowsHeight()));
            hierarchyDropFeedback.lineStyle(2, Theme.ACCENT, 1);
            hierarchyDropFeedback.moveTo(4, lineY);
            hierarchyDropFeedback.lineTo(Math.max(4, hierarchyHit.width - 4), lineY);
            hierarchyDropFeedback.lineStyle();
            hierarchyFeedbackDrawn = true;
            return;
        }
        var entry = findVisibleHierarchyEntry(targetRow.objectId);
        if (entry == null) return;
        var relativeY = mouseY - targetRow.y;
        if (relativeY < HIERARCHY_ROW_HEIGHT * 0.28) {
            hierarchyDropMode = HierarchyRow.DROP_BEFORE;
        } else if (relativeY > HIERARCHY_ROW_HEIGHT * 0.72) {
            hierarchyDropMode = HierarchyRow.DROP_AFTER;
        } else {
            hierarchyDropMode = HierarchyRow.DROP_CHILD;
        }
        hierarchyDropValid = true;
        hierarchyDropRow = targetRow;
        targetRow.setDropFeedback(hierarchyDropMode, true);
    }

    inline function hierarchyReorderEnabled():Bool {
        return hierarchySortKey == HierarchyOrder.AUTHORED;
    }

    function beginHierarchyDrag(sourceId:Int):Void {
        closePaletteIfOpen();
        hierarchyDragIds.resize(0);
        clearHierarchyDropFeedback();
        if (!hierarchyReorderEnabled()) {
            // A sorted view is display-only: dropping would target authored
            // sibling indices and move rows somewhere unexpected.
            log("hierarchy: switch to Tree order to reorder objects");
            return;
        }
        hierarchyDragIds = selectedObjectIds.indexOf(sourceId) >= 0
            ? selectedObjectIds.copy() : [sourceId];
    }

    function updateHierarchyDrag(sourceId:Int, mouseX:Float, mouseY:Float):Void {
        clearHierarchyDropFeedback();
        if (!hierarchyReorderEnabled()) return;
        if (hierarchyDragIds.length == 0) hierarchyDragIds = [sourceId];
        if (mouseX < hierarchyHit.x || mouseX > hierarchyHit.x + hierarchyHit.width
                || mouseY < hierarchyHit.y
                || mouseY > hierarchyHit.y + hierarchyHit.height) {
            // Never keep a stale target from an earlier move: releasing outside
            // the hierarchy must not reparent into a row we no longer hover.
            hierarchyDropParentId = -1;
            hierarchyDropSiblingIndex = -1;
            hierarchyDropMode = HierarchyRow.DROP_NONE;
            hierarchyDropValid = false;
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
        if (!hierarchyReorderEnabled()) {
            hierarchyDragIds.resize(0);
            clearHierarchyDropFeedback();
            return;
        }
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
        if (hierarchyFeedbackDrawn) {
            hierarchyFeedbackDrawn = false;
            hierarchyDropFeedback.clear();
        }
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

    /** Primitive choices shared by the child, root, and toolbar Add menus. */
    function primitiveMenuItems(parentId:Int, ?palettePlacement:Bool):Array<MenuItem> {
        var items:Array<MenuItem> = [];
        for (mesh in PrimitiveMeshes.all()) {
            var meshId = mesh.id;
            items.push({
                label: mesh.name,
                dragMeshId: meshId,
                onClick: function() {
                    if (parentId >= 0) hierarchyExpanded.set(parentId, true);
                    if (palettePlacement && onCreatePrimitive != null) {
                        // Same staggered placement the old toolbar palette used.
                        onCreatePrimitive(meshId);
                    } else if (onCreateChildPrimitive != null) {
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
        menuDropdown.dropViewport = null;
        menuDropdown.onDropPrimitive = null;
        menuDropdown.open(ctx.mouseX, ctx.mouseY, items);
    }

    inline function hasObjectClipboard():Bool {
        return onQueryObjectClipboard != null && onQueryObjectClipboard();
    }

    /** Inspector Add Component: a searchable list of every addable component,
     *  anchored under the button and sized to its width. */
    function openComponentMenu():Void {
        if (availableComponentTypes.length == 0) return;
        var items:Array<MenuItem> = [];
        for (entry in availableComponentTypes) {
            var captured = entry;
            items.push({
                label: captured.label,
                onClick: function() {
                    if (onAddComponent != null) onAddComponent(captured.typeId);
                }
            });
        }
        closeFovPopup();
        // This menu has no draggable rows; clear state left by the toolbar menu.
        menuDropdown.dropViewport = null;
        menuDropdown.onDropPrimitive = null;
        // Derive window coordinates from the button's real transform: the
        // inspector can be docked/floated anywhere, so mask-local arithmetic
        // no longer describes its on-screen position. localToGlobal also
        // accounts for the scrolling mask's offset.
        var topLeft = addComponentButton.localToGlobal(new h2d.col.Point(0, 0));
        var bottomLeft = addComponentButton.localToGlobal(
            new h2d.col.Point(0, addComponentButton.height));
        menuDropdown.open(bottomLeft.x, bottomLeft.y,
            items, "Search components...", addComponentButton.width, topLeft.y);
    }

    /** Toolbar Add: a searchable creation menu covering every object kind. */
    function openAddObjectMenu():Void {
        closeFovPopup();
        snapBar.closePopup();
        if (palette.visible) palette.close();
        var items:Array<MenuItem> = [{
            label: "Empty Game Object",
            onClick: function() {
                if (onAddEmptyObjectInFront != null) onAddEmptyObjectInFront();
            }
        }, {
            label: "Primitives",
            submenu: primitiveMenuItems(-1, true)
        }];
        // Primitive rows can be dragged out of the menu and dropped into the
        // viewport; a plain click creates the object in front of the camera.
        menuDropdown.dropViewport = viewportRect;
        menuDropdown.onDropPrimitive = function(meshId, x, y) {
            if (onDropPrimitive != null) onDropPrimitive(meshId, x, y);
        };
        menuDropdown.open(addObjectButton.x + 4, addObjectButton.y + 31,
            items, "Search objects...");
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
        menuDropdown.dropViewport = null;
        menuDropdown.onDropPrimitive = null;
        menuDropdown.open(ctx.mouseX, ctx.mouseY, items);
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
        if (menuDropdown.isSearchFocused()) return true;
        for (row in hierarchyRows) if (row.isRenaming()) return true;
        for (section in componentSections) if (section.isEditing()) return true;
        return false;
    }

    function closePaletteIfOpen():Void {
        UiTooltip.active(tooltip).cancel();
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

    // ------------------------------------------------------------------
    // Docking panel registration
    // ------------------------------------------------------------------

    function registerDockPanels():Void {
        hierarchyDockHost = new h2d.Object(panelLayer);
        leftContentMask.remove();
        hierarchyDockHost.addChild(leftContentMask);
        inspectorDockHost = new h2d.Object(panelLayer);
        rightContentMask.remove();
        inspectorDockHost.addChild(rightContentMask);

        dockRegistry.register({
            id: "boltspark.hierarchy", displayName: "Scene Hierarchy", icon: 15,
            factory: function() return new HierarchyDockView(this, hierarchyDockHost),
            defaultSide: DockSide.Left, minWidth: Theme.MIN_LEFT_PANEL_WIDTH,
            minHeight: 120, canClose: true, canFloat: true, canDock: true
        });
        dockRegistry.register({
            id: "boltspark.viewport", displayName: "Scene View", icon: 39,
            factory: function() return new ViewportDockView(this),
            defaultSide: DockSide.Center, minWidth: Theme.MIN_CENTER_PANEL_WIDTH,
            minHeight: 140, canClose: false, canFloat: false, canDock: false,
            fixed: true
        });
        dockRegistry.register({
            id: "boltspark.inspector", displayName: "Inspector", icon: 14,
            factory: function() return new InspectorDockView(this, inspectorDockHost),
            defaultSide: DockSide.Right, minWidth: Theme.MIN_RIGHT_PANEL_WIDTH,
            minHeight: 120, canClose: true, canFloat: true, canDock: true
        });
        dockRegistry.register({
            id: "boltspark.console", displayName: "Output Log", icon: 13,
            factory: function() return new ConsoleDockView(this, console),
            defaultSide: DockSide.Bottom, minWidth: 200, minHeight: 110,
            canClose: true, canFloat: true, canDock: true
        });
        dockRegistry.register({
            id: "boltspark.assets", displayName: "Asset Browser", icon: 24,
            factory: function() return new AssetDockView(this, assetBrowser),
            defaultSide: DockSide.Bottom, minWidth: 240, minHeight: 130,
            canClose: true, canFloat: true, canDock: true
        });
    }

    function setBottomTabFromDock(index:Int):Void {
        if (activeBottomTab == index) return;
        activeBottomTab = index;
        dockLayout.bottomTab = index;
        console.visible = index == 1;
        assetBrowser.visible = index == 0;
        updateBottomTabState();
        Sys.println('[probe] bottom tab=${index == 0 ? "assets" : "log"}');
        saveLayout();
    }

    function syncLegacyDockSizes():Void {
        var sizes = dockManager.legacySizes();
        dockLayout.setPreferred(sizes.left, sizes.right, sizes.console);
        dockLayout.bottomTab = sizes.bottomTab;
    }

    function resetLegacyLayout():Void {
        dockLayout.setPreferred(Theme.LEFT_PANEL_WIDTH,
            Theme.RIGHT_PANEL_WIDTH, Theme.CONSOLE_HEIGHT);
        dockLayout.bottomTab = 0;
        saveLayout();
    }

    // ------------------------------------------------------------------
    // Native HWND floating panel snapshots and edit routing
    // ------------------------------------------------------------------

    function buildNativePanelSnapshot(panelId:String):Dynamic {
        switch (panelId) {
            case "boltspark.console":
                return {title: "Output Log", lines: console.snapshotLines()};
            case "boltspark.hierarchy":
                var rows:Array<Dynamic> = [];
                for (entry in allHierarchyEntries) {
                    rows.push({
                        id: "h:" + entry.id,
                        kind: "action",
                        label: entry.name,
                        depth: entry.depth,
                        selected: entry.id == selectedObjectId
                    });
                }
                return {title: "Scene Hierarchy", rows: rows};
            case "boltspark.assets":
                var rows:Array<Dynamic> = [];
                var assets = onQueryAssets != null ? onQueryAssets() : [];
                for (asset in assets) {
                    rows.push({
                        id: "a:" + asset.source,
                        kind: "action",
                        label: asset.name + "  ·  " + asset.kindLabel,
                        depth: 0,
                        selected: false
                    });
                }
                return {title: "Asset Browser", rows: rows};
            case "boltspark.inspector":
                if (onQueryNativeInspector != null) {
                    var snapshot = onQueryNativeInspector();
                    if (snapshot != null) return snapshot;
                }
                return {title: "Inspector", rows: []};
            default:
                return {title: "Panel", rows: []};
        }
    }

    function applyNativePanelEdit(panelId:String, id:String,
            value:Dynamic):Void {
        if (StringTools.startsWith(id, "h:")) {
            var objectId = Std.parseInt(id.substr(2));
            if (objectId == null) return;
            if (onObjectsSelected != null) onObjectsSelected([objectId], objectId);
            return;
        }
        if (StringTools.startsWith(id, "a:")) {
            if (onOpenAsset != null) onOpenAsset(id.substr(2));
            return;
        }
        if (panelId == "boltspark.inspector") {
            applyNativeInspectorEdit(id, value);
        }
    }

    function applyNativeInspectorEdit(id:String, value:Dynamic):Void {
        // Encoded as p:<componentIndex>:<propertyId>:<axis>.
        if (!StringTools.startsWith(id, "p:")) return;
        var parts = id.split(":");
        if (parts.length < 3) return;
        var componentIndex = Std.parseInt(parts[1]);
        var propertyId = parts[2];
        if (componentIndex == null) return;
        if (Std.isOfType(value, Float) || Std.isOfType(value, Int)) {
            var axis = parts.length > 3 ? Std.parseInt(parts[3]) : 0;
            if (axis == null) axis = 0;
            if (onInspectorNumberChanged != null) {
                onInspectorNumberChanged(componentIndex, propertyId, axis, value);
            }
            return;
        }
        if (Std.isOfType(value, Bool)) {
            if (onInspectorBoolChanged != null) {
                onInspectorBoolChanged(componentIndex, propertyId, value);
            }
            return;
        }
        if (Std.isOfType(value, String)) {
            if (onInspectorAssetChanged != null) {
                onInspectorAssetChanged(componentIndex, propertyId, value);
            }
        }
    }

    /** Called by Main after editor state changes to refresh native floats. */
    public function refreshNativePanels():Void {
        if (dockManager != null) dockManager.refreshNativePanels();
    }

    public function shutdownDockWindows():Void {
        if (dockManager != null) dockManager.shutdown();
    }
}

/** Retained H2D adapter: Scene Hierarchy lives in its own movable host. */
private class HierarchyDockView implements DockPanelView {
    public var panelId(default, null):String = "boltspark.hierarchy";
    final shell:EditorShell;
    final host:h2d.Object;
    final mask:h2d.Mask;

    public function new(shell:EditorShell, host:h2d.Object) {
        this.shell = shell;
        this.host = host;
        mask = cast(host.getChildAt(0), h2d.Mask);
    }

    public function layout(rect:LayoutRect):Void {
        // Whole-pixel origins keep the FreeType text atlas crisp.
        host.x = Math.round(rect.x);
        // Internal hierarchy coordinates include the title/toolbar offset, so
        // shifting the host by that amount maps them to any absolute rect.
        host.y = Math.round(rect.y - Theme.TOP_BAR_HEIGHT);
        mask.width = Std.int(Math.max(0, rect.width));
        mask.height = Std.int(Math.max(0, rect.height + Theme.TOP_BAR_HEIGHT));
        mask.visible = rect.width >= 140 && rect.height > 0;
        shell.layoutHierarchyForDock(rect.width);
    }

    public function setVisible(value:Bool):Void host.visible = value;

    public function serializeState():Dynamic return null;

    public function restoreState(state:Dynamic):Void {}
}

private class InspectorDockView implements DockPanelView {
    public var panelId(default, null):String = "boltspark.inspector";
    final shell:EditorShell;
    final host:h2d.Object;
    final mask:h2d.Mask;

    public function new(shell:EditorShell, host:h2d.Object) {
        this.shell = shell;
        this.host = host;
        mask = cast(host.getChildAt(0), h2d.Mask);
    }

    public function layout(rect:LayoutRect):Void {
        host.x = Math.round(rect.x);
        host.y = Math.round(rect.y - Theme.TOP_BAR_HEIGHT);
        mask.width = Std.int(Math.max(0, rect.width));
        mask.height = Std.int(Math.max(0, rect.height + Theme.TOP_BAR_HEIGHT));
        mask.visible = rect.width >= 180 && rect.height > 0;
        shell.layoutInspectorForDock(rect.width);
    }

    public function setVisible(value:Bool):Void host.visible = value;

    public function serializeState():Dynamic return null;

    public function restoreState(state:Dynamic):Void {}
}

private class ViewportDockView implements DockPanelView {
    public var panelId(default, null):String = "boltspark.viewport";
    final shell:EditorShell;

    public function new(shell:EditorShell) this.shell = shell;

    public function layout(rect:LayoutRect):Void shell.layoutViewportForDock(rect);

    public function setVisible(value:Bool):Void shell.setViewportPanelVisible(value);

    public function serializeState():Dynamic return null;

    public function restoreState(state:Dynamic):Void {}
}

private class ConsoleDockView implements DockPanelView {
    public var panelId(default, null):String = "boltspark.console";
    final shell:EditorShell;
    final panel:ConsolePanel;

    public function new(shell:EditorShell, panel:ConsolePanel) {
        this.shell = shell;
        this.panel = panel;
    }

    public function layout(rect:LayoutRect):Void {
        panel.x = Math.round(rect.x);
        panel.y = Math.round(rect.y);
        panel.layout(Math.max(0, rect.width), Math.max(0, rect.height));
    }

    public function setVisible(value:Bool):Void panel.visible = value;

    public function serializeState():Dynamic return null;

    public function restoreState(state:Dynamic):Void {}
}

private class AssetDockView implements DockPanelView {
    public var panelId(default, null):String = "boltspark.assets";
    final shell:EditorShell;
    final browser:AssetBrowser;

    public function new(shell:EditorShell, browser:AssetBrowser) {
        this.shell = shell;
        this.browser = browser;
    }

    public function layout(rect:LayoutRect):Void {
        browser.layout(Math.round(rect.x), Math.round(rect.y),
            Math.max(0, rect.width), Math.max(0, rect.height));
    }

    public function setVisible(value:Bool):Void browser.visible = value;

    public function serializeState():Dynamic return null;

    public function restoreState(state:Dynamic):Void {}
}
