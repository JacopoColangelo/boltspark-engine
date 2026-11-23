package boltspark.ui.widgets;

import boltspark.engine.inspector.AssetType;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.EngineAssetCatalog;
import boltspark.project.ProjectSession;
import boltspark.project.ProjectSession.AssetDetails;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.AssetDragSession;
import boltspark.ui.AssetDragPayload;
import boltspark.ui.PrimitiveThumbnails;
import boltspark.ui.Theme;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;
import boltspark.ui.widgets.MenuDropdown.MenuItem;
import boltspark.ui.widgets.UiSlider;
import boltspark.ui.widgets.UiTooltip;
import hxd.Key;

/** One node in the full project asset tree: a folder or a leaf asset. */
typedef AssetTreeNode = {
    var name:String;
    /** Folder path for folders, asset source for leaves. */
    var path:String;
    var isFolder:Bool;
    var entry:Null<AssetFileInfo>;
    var children:Array<AssetTreeNode>;
};

/** A folder or asset shown in the main Asset Panel. */
typedef BrowserItem = {
    var isFolder:Bool;
    /** Folder path for folders, asset source for leaves. */
    var path:String;
    var name:String;
    var entry:Null<AssetFileInfo>;
};

/**
 * Docked, three-pane Asset Browser.
 *
 * All content comes from the real project filesystem through ProjectSession;
 * this widget edits nothing on disk itself. Asset kinds come from
 * AssetTypeRegistry, so the browser advertises exactly the formats the engine
 * can actually load (currently `.boltscene`) and treats everything else as a
 * generic file. The folder column and grid/list area are rebuilt
 * from scan results, and every visible control issues a callback upward.
 *
 * The geometry constants below are intentionally stable: native interaction
 * probes in `tests/native/Test-AssetBrowser.ps1` address tiles and folder rows
 * by their logical positions.
 */
class AssetBrowser extends h2d.Object {
    // Existing commands - forwarded by EditorShell to Main/ProjectSession.
    public var onQueryAssets:Null<Void->Array<AssetFileInfo>>;
    public var onQueryEngineAssets:Null<Void->Array<AssetFileInfo>>;
    public var onOpenAsset:Null<String->Void>;
    public var onNewScene:Null<String->String->Void>;
    public var onRenameAsset:Null<String->String->Void>;
    public var onDeleteAsset:Null<String->Void>;
    public var onDeleteAssets:Null<Array<String>->Void>;
    public var onQueryFolders:Null<Void->Array<String>>;
    public var onNewFolder:Null<String->String>;
    public var onMoveAsset:Null<String->String->Void>;
    public var onCopyAsset:Null<String->String->Void>;
    public var onRenameFolder:Null<String->String->String>;
    // New commands used by the enhanced browser.
    public var onQueryAssetDetails:Null<String->AssetDetails>;
    /** Shared window-space tooltip supplied by EditorShell. */
    public var tooltip:Null<UiTooltip>;
    public var onDuplicateAsset:Null<String->Void>;
    public var onDeleteFolder:Null<String->Bool->Void>;
    public var onMoveFolder:Null<String->String->Void>;
    public var onRevealAsset:Null<String->Void>;
    public var onCopyAssetPath:Null<String->Void>;
    /** Request an external file import into the given folder (empty = default). */
    public var onImportAssets:Null<String->Void>;
    /** Decoded thumbnail tile for a texture asset, or null when unavailable. */
    public var onQueryTextureTile:Null<String->Null<h2d.Tile>>;

    static inline var TOOLBAR_HEIGHT:Float = 26;
    /** The three navigation hits occupy x=4..74 inside the toolbar. */
    static inline var NAV_CLUSTER_END:Float = 76;
    static inline var TOOLBAR_EDGE:Float = 4;
    static inline var TOOLBAR_GAP:Float = 4;
    /** Icon-only toolbar control width (UiButton elides its label below 39 px). */
    static inline var ICON_CONTROL_WIDTH:Float = 26;
    static inline var DROPDOWN_CONTROL_WIDTH:Float = 40;
    static inline var SEARCH_MIN_WIDTH:Float = 64;
    static inline var SEARCH_MAX_WIDTH:Float = 240;

    static inline var ROW_HEIGHT:Float = 22;
    static inline var LIST_ROW_HEIGHT:Float = 20;
    /** Pixels scrolled per wheel notch, independent of how many items exist. */
    static inline var WHEEL_STEP:Float = 48;
    static inline var TILE_GAP:Float = 8;
    /** Space reserved under a grid preview for the name and type caption. */
    static inline var TILE_LABEL_HEIGHT:Float = 32;
    static inline var DETAILS_NAME_WIDTH:Float = 168;
    static inline var DETAILS_COL_WIDTH:Float = 72;

    final ctx:UiContext;
    final store:AssetBrowserStore;
    final background:UiSurface;
    final emptyAreaHit:h2d.Interactive;
    /** Wheel catcher over the hierarchy pane, behind the tree rows. */
    final treeWheelHit:h2d.Interactive;
    final toolbar:UiSurface;
    final titleText:UiText;
    final folderText:UiText;
    final statusText:UiText;
    final addButton:UiButton;
    final addMenu:MenuDropdown;
    final folderSurface:UiSurface;
    final folderTitle:UiText;
    final folderSplitter:h2d.Interactive;
    final folderSplitterGrip:h2d.Graphics;
    final treeMask:h2d.Mask;
    final treeScroll:ScrollBar;
    final listSurface:UiSurface;
    final listMask:h2d.Mask;
    final gridScroll:ScrollBar;

    final backGlyph:h2d.Graphics;
    final forwardGlyph:h2d.Graphics;
    final upGlyph:h2d.Graphics;
    final backButton:h2d.Interactive;
    final forwardButton:h2d.Interactive;
    final upButton:h2d.Interactive;
    final searchField:SearchField;
    final filterButton:UiButton;
    final sortButton:UiButton;
    final viewGridButton:UiButton;
    final viewListButton:UiButton;
    final viewDetailsButton:UiButton;
    final settingsButton:UiButton;
    final settingsPanel:UiSurface;
    final settingsCatch:h2d.Interactive;
    final defaultOverlayParent:h2d.Object;
    final settingsViewTitle:UiText;
    final settingsTitle:UiText;
    final settingsSlider:UiSlider;
    final showEngineAssetsCheckbox:UiCheckbox;
    var settingsOpen:Bool = false;
    final favoriteHeaderStar:h2d.Graphics;
    final favoriteHeaderHit:h2d.Interactive;
    final filterMenu:MenuDropdown;
    final sortMenu:MenuDropdown;
    final favoriteMenu:MenuDropdown;
    final contextMenu:MenuDropdown;
    /** Lists folders hidden by the breadcrumb ellipsis. */
    final breadcrumbMenu:MenuDropdown;

    final renameSurface:UiSurface;
    final renameInput:UiTextInput;
    final dragGhostSurface:UiSurface;
    final dragGhost:UiText;
    final dropHighlight:UiSurface;
    final breadcrumbObjects:Array<h2d.Object> = [];

    var entries:Array<AssetFileInfo> = [];
    var folders:Array<String> = [];
    var folderRows:Array<h2d.Object> = [];
    var folderRowPaths:Array<String> = [];
    var folderRowIsFolder:Array<Bool> = [];
    final expandedFolders:Map<String, Bool> = [];
    var assetRows:Array<h2d.Object> = [];
    var shownEntries:Array<AssetFileInfo> = [];
    /** Folders and assets currently shown in the main Asset Panel. */
    var shownItems:Array<BrowserItem> = [];
    /** Folder drop targets rendered in the main panel (browser-local coords). */
    var assetFolderRects:Array<{
        x:Float, y:Float, width:Float, height:Float, path:String
    }> = [];
    var treeScrollValue:Float = 0;
    /** Full height of the hierarchy rows, before scrolling. */
    var treeContentHeight:Float = 0;

    var selectedSources:Array<String> = [];
    var selectedSource:String = "";
    var selectedFolder:String = "";
    /** Asset selection in the tree outranks the containing folder highlight. */
    var treeAssetSelected:Bool = false;
    /** In-place restyle callbacks for the currently built tree rows. */
    final folderRowStyleUpdaters:Array<Void->Void> = [];
    var folderHistory:Array<String> = [""];
    var folderHistoryIndex:Int = 0;

    var searchText:String = "";
    var statusMessage:String = "";
    var typeFilter:String = "all";
    var showEngineAssets:Bool = false;
    var sortKey:Int = 0;
    var sortAsc:Bool = true;
    var foldersFirst:Bool = true;
    var viewMode:Int = 0;
    var thumbnailSize:Int = 104;

    final detailCache:Map<String, AssetDetails> = [];

    var renamingSource:String = "";
    var renamingOriginal:String = "";
    var renamingIsFolder:Bool = false;
    var renaming:Bool = false;
    var lastClickSource:String = "";
    var lastClickAt:Float = 0;
    var scrollValue:Float = 0;
    var clipboardSource:String = "";
    var clipboardIsCut:Bool = false;
    var dragSources:Array<String> = [];
    var dragging:Bool = false;
    /** The browser owns the current SceneEvents capture. Keep only lifecycle
     *  state here: a tile can be destroyed by refresh while its capture closure
     *  is still installed, so retaining/dereferencing that Interactive is unsafe. */
    var dragCaptureActive:Bool = false;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;
    var widthValue:Float = 0;
    var heightValue:Float = 0;
    var folderWidth:Float = 118;
    /** Remembered user width; `folderWidth` is the clamped on-screen value. */
    var preferredFolderWidth:Float = 118;
    var toolbarSettingsHidden:Bool = false;
    var dropTargetFolder:Null<String> = null;
    var folderDragSource:String = "";

    public function new(ctx:UiContext, ?parent:h2d.Object, ?menuParent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        var menus = menuParent == null ? this : menuParent;
        defaultOverlayParent = menus;
        store = new AssetBrowserStore();
        var loadError = store.load();
        if (loadError != null) Sys.println('[probe] asset browser store load=${loadError}');
        viewMode = store.viewMode;
        thumbnailSize = store.thumbnailSize;
        sortKey = store.sortKey;
        sortAsc = store.sortAsc;
        typeFilter = store.typeFilter;
        showEngineAssets = store.showEngineAssets;
        // The virtual Engine folder and its type subfolders start closed so
        // their assets don't crowd the root tree; users expand them when needed.
        expandedFolders.set(EngineAssetCatalog.FOLDER, false);
        expandedFolders.set(EngineAssetCatalog.MESH_FOLDER, false);
        expandedFolders.set(EngineAssetCatalog.MATERIAL_FOLDER, false);
        foldersFirst = store.foldersFirst;
        preferredFolderWidth = folderWidth = store.folderWidth;

        background = new UiSurface(ctx, this);
        background.setStyle(Theme.PANEL, Theme.BORDER, 0);

        // Sits behind every widget: catches wheel and right-clicks over empty
        // space in both the folder column and the asset area.
        emptyAreaHit = new h2d.Interactive(1, 1, this);
        emptyAreaHit.backgroundColor = 0;
        emptyAreaHit.cursor = hxd.Cursor.Default;
        emptyAreaHit.enableRightButton = true;
        emptyAreaHit.onPush = function(event) {
            event.propagate = false;
            if (event.button == 1) {
                openEmptyAreaMenu();
                return;
            }
            if (!renaming && selectedSource != "") {
                setSelected([]);
                buildAssets();
            }
        };
        emptyAreaHit.onWheel = handleGridWheel;

        // The hierarchy has its own scroll position. This catcher sits behind
        // the tree rows (created later) so row clicks still work, but wheel
        // events over the pane always reach the tree instead of the grid.
        treeWheelHit = new h2d.Interactive(1, 1, this);
        treeWheelHit.backgroundColor = 0;
        treeWheelHit.cursor = hxd.Cursor.Default;
        treeWheelHit.onWheel = handleTreeWheel;

        toolbar = new UiSurface(ctx, this);
        toolbar.setStyle(Theme.PANEL_HEADER, Theme.BORDER, 0);

        titleText = new UiText(ctx.semiboldFont, this);
        titleText.text = "Asset Browser";
        titleText.textColor = Theme.TEXT_SECONDARY;
        titleText.lineBreak = false;
        // The dock tab already carries the panel title; keeping it here would
        // collide with the navigation cluster.
        titleText.visible = false;

        folderText = new UiText(ctx.captionFont, this);
        folderText.textColor = Theme.MUTED;
        folderText.lineBreak = false;

        statusText = new UiText(ctx.captionFont, this);
        statusText.textColor = Theme.MUTED;
        statusText.lineBreak = false;
        statusText.visible = false;

        // Navigation cluster uses pinned Tabler glyphs, tinted by availability.
        backGlyph = new h2d.Graphics(this);
        forwardGlyph = new h2d.Graphics(this);
        upGlyph = new h2d.Graphics(this);
        backButton = makeNavHit(goBack);
        forwardButton = makeNavHit(goForward);
        upButton = makeNavHit(navigateToParent);

        searchField = new SearchField(ctx, "Search assets\u2026", 220, 20, this);
        searchField.onChange = function(value) {
            searchText = StringTools.trim(value.toLowerCase());
            scrollValue = 0;
            buildAssets();
            Sys.println('[probe] asset browser search=${searchText}');
        };

        // Filter and sort stay separate so neither menu has to grow into a
        // catch-all as more options are added later.
        filterButton = new UiButton(ctx, "", DROPDOWN_CONTROL_WIDTH, 20, this);
        filterButton.setIcon(Filter);
        filterButton.setIconSize(14);
        filterButton.setDropdown();
        filterButton.onClick = openFilterMenu;
        sortButton = new UiButton(ctx, "", DROPDOWN_CONTROL_WIDTH, 20, this);
        sortButton.setIcon(Sort);
        sortButton.setIconSize(14);
        sortButton.setDropdown();
        sortButton.onClick = openSortMenu;

        // View modes live in the settings popover, not the toolbar. Framed
        // buttons read as one aligned segmented control (quiet buttons would
        // leave bare icons next to a bordered selected one).
        viewGridButton = makeIconButton(menus, function() setViewMode(0), Grid).setQuiet(false);
        viewListButton = makeIconButton(menus, function() setViewMode(1), List).setQuiet(false);
        viewDetailsButton = makeIconButton(menus, function() setViewMode(2), Table).setQuiet(false);
        settingsButton = makeIconButton(this, openSettings, Settings).setQuiet(false);

        settingsCatch = new h2d.Interactive(1, 1, menus);
        settingsCatch.backgroundColor = 0;
        // The full-window dismiss catch must not show the pointing-hand cursor
        // through transparent parts of the settings popover.
        settingsCatch.cursor = hxd.Cursor.Default;
        settingsCatch.onPush = function(event) {
            // Swallow the press and keep the catch alive: buttons act on
            // release, so closing here would click whatever is underneath.
            event.propagate = false;
        };
        settingsCatch.onRelease = function(event) {
            event.propagate = false;
            closeSettings();
        };
        settingsPanel = new UiSurface(ctx, menus);
        settingsPanel.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        settingsViewTitle = new UiText(ctx.captionFont, menus);
        settingsViewTitle.text = "Asset Browser Settings";
        settingsViewTitle.textColor = Theme.TEXT;
        settingsViewTitle.lineBreak = false;
        settingsTitle = new UiText(ctx.captionFont, menus);
        settingsTitle.text = "Thumbnail size";
        settingsTitle.textColor = Theme.TEXT;
        settingsTitle.lineBreak = false;
        settingsSlider = new UiSlider(ctx, SETTINGS_WIDTH - SETTINGS_MARGIN * 2,
            THUMB_MIN, THUMB_MAX, thumbnailSize, " px", menus);
        settingsSlider.onChange = function(value) {
            thumbnailSize = Std.int(value);
            store.thumbnailSize = thumbnailSize;
            refreshLayout();
        };
        showEngineAssetsCheckbox = new UiCheckbox(ctx, "Show Engine Assets", menus,
            ctx.captionFont);
        showEngineAssetsCheckbox.setWidth(SETTINGS_WIDTH - SETTINGS_MARGIN * 2);
        showEngineAssetsCheckbox.value = showEngineAssets;
        showEngineAssetsCheckbox.onChanged = function(value) {
            showEngineAssets = value;
            store.showEngineAssets = showEngineAssets;
            store.save();
            refresh();
        };
        // The popover surface was created after the buttons; lift them above it.
        menus.addChild(viewGridButton);
        menus.addChild(viewListButton);
        menus.addChild(viewDetailsButton);
        menus.addChild(showEngineAssetsCheckbox);
        settingsCatch.visible = false;
        settingsPanel.visible = false;
        settingsViewTitle.visible = false;
        settingsTitle.visible = false;
        settingsSlider.visible = false;
        showEngineAssetsCheckbox.visible = false;
        viewGridButton.visible = false;
        viewListButton.visible = false;
        viewDetailsButton.visible = false;

        // A compact star in the folder header replaces the old "Fav" toolbar
        // button; it opens the favorites list without adding toolbar text.
        favoriteHeaderStar = new h2d.Graphics(this);
        UiIcons.draw(favoriteHeaderStar, Star, 0, 0, 12, Theme.MUTED);
        favoriteHeaderHit = new h2d.Interactive(16, 16, this);
        favoriteHeaderHit.backgroundColor = 0;
        favoriteHeaderHit.cursor = hxd.Cursor.Default;
        favoriteHeaderHit.onPush = function(event) {
            event.propagate = false;
            openFavoriteMenu();
        };

        addButton = new UiButton(ctx, "Add", 54, 20, this);
        addButton.setIcon(Add);
        addButton.onClick = function() {
            addMenu.open(this.x + addButton.x, this.y + TOOLBAR_HEIGHT, [{
                label: "Scene",
                onClick: function() {
                    var folder = selectedFolder == "" ? "Scenes" : selectedFolder;
                    if (onNewScene != null) onNewScene(folder, "New Scene");
                }
            }, {
                label: "Folder",
                onClick: function() {
                    // Folders are created at the Content root. Nested folders
                    // are an explicit choice via a folder's context menu.
                    var created = onNewFolder != null ? onNewFolder("") : null;
                    if (created != null) {
                        selectedFolder = created;
                        setSelected([]);
                        beginRenameFolder(created);
                    }
                }
            }, {
                // Appended last so native probes that address Scene/Folder by
                // row offset keep working. Import is a command: the picker,
                // copy, and manifest write all live above this widget.
                label: "Import Asset...",
                onClick: importAssets
            }]);
        };
        addMenu = new MenuDropdown(ctx, menus);

        filterMenu = new MenuDropdown(ctx, menus);
        sortMenu = new MenuDropdown(ctx, menus);
        favoriteMenu = new MenuDropdown(ctx, menus);
        contextMenu = new MenuDropdown(ctx, menus);
        breadcrumbMenu = new MenuDropdown(ctx, menus);

        folderSurface = new UiSurface(ctx, this);
        folderSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER, 0);
        folderSplitterGrip = new h2d.Graphics(this);
        // A 5px hit strip was nearly impossible to grab, especially in a
        // floating panel. Use a 14px hit area centered on the pane boundary
        // and keep a visible grip so the target is obvious.
        folderSplitter = new h2d.Interactive(14, 1, this);
        folderSplitter.backgroundColor = 0;
        folderSplitter.cursor = ctx.resizeHorizontal;
        folderSplitter.onOver = function(_) drawFolderSplitterGrip(true);
        folderSplitter.onOut = function(_) {
            drawFolderSplitterGrip(false);
            ctx.restoreArrowCursor();
        };
        folderSplitter.onPush = function(_) beginFolderSplitterDrag();

        folderTitle = new UiText(ctx.captionFont, this);
        folderTitle.text = "PROJECT";
        folderTitle.textColor = Theme.MUTED;
        folderTitle.lineBreak = false;

        // The left pane is a full, scrollable asset hierarchy (folders and the
        // assets inside them), not just a folder-only tree.
        treeMask = new h2d.Mask(1, 1, this);
        treeScroll = new ScrollBar(ctx, this);
        treeScroll.onChange = function(value) {
            treeScrollValue = value;
            Sys.println('[probe] asset browser tree scroll=${value}');
            buildFolders();
        };
        treeScroll.onWheel = function(delta) {
            handleTreeWheelDelta(delta);
            return true;
        };

        listSurface = new UiSurface(ctx, this);
        listSurface.setStyle(Theme.PANEL, Theme.BORDER, 0);
        listMask = new h2d.Mask(1, 1, this);
        gridScroll = new ScrollBar(ctx, this);
        gridScroll.onChange = function(value) {
            scrollValue = value;
            buildAssets();
        };
        gridScroll.onWheel = function(delta) {
            handleWheelDelta(delta);
            return true;
        };

        renameSurface = new UiSurface(ctx, this);
        renameSurface.setStyle(Theme.FIELD_BG, Theme.ACCENT, 0);
        renameSurface.visible = false;
        renameInput = new UiTextInput(ctx.font, this);
        renameInput.textColor = Theme.TEXT;
        renameInput.useSoftwareKeyboard = false;
        renameInput.visible = false;
        renameInput.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ESCAPE) {
                cancelRename();
                event.propagate = false;
            } else if (event.keyCode == hxd.Key.ENTER
                    || event.keyCode == hxd.Key.NUMPAD_ENTER) {
                commitRename();
                event.propagate = false;
            }
        };
        renameInput.onFocusLost = function(_) {
            if (renaming) commitRename();
        };

        dragGhostSurface = new UiSurface(ctx, this);
        dragGhostSurface.setStyle(Theme.PANEL_ALT, Theme.ACCENT, 0);
        dragGhostSurface.setSize(96, 22);
        dragGhost = new UiText(ctx.captionFont, dragGhostSurface);
        dragGhost.textColor = Theme.TEXT;
        dragGhost.lineBreak = false;
        dragGhost.x = 6;
        dragGhost.y = 4;
        dragGhostSurface.visible = false;

        // Drop feedback is a separate overlay: rebuilding folder rows during a
        // drag would detach the captured Interactive and cancel the gesture.
        dropHighlight = new UiSurface(ctx, this);
        dropHighlight.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT_HOVER, 0);
        dropHighlight.visible = false;
    }

    // ------------------------------------------------------------------
    // Small widget helpers
    // ------------------------------------------------------------------

    function makeNavHit(action:Void->Void):h2d.Interactive {
        var hit = new h2d.Interactive(22, 20, this);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.onPush = function(event) {
            event.propagate = false;
            action();
        };
        return hit;
    }

    function makeIconButton(parent:h2d.Object, action:Void->Void,
            icon:UiIconKind):UiButton {
        var button = new UiButton(ctx, "", 26, 20, parent);
        button.setQuiet();
        button.onClick = action;
        button.setIcon(icon);
        // UiButton normally derives the icon size from the control height;
        // a 20px toolbar needs an explicit size to stay legible.
        button.setIconSize(16);
        return button;
    }

    function drawFavoriteIcon(color:Int):Void {
        UiIcons.draw(favoriteHeaderStar, Star, 0, 0, 12, color);
    }

    function redrawNavGlyphs():Void {
        var backColor = folderHistoryIndex > 0 ? Theme.ACCENT : Theme.DISABLED;
        var forwardColor = folderHistoryIndex < folderHistory.length - 1
            ? Theme.ACCENT : Theme.DISABLED;
        UiIcons.draw(backGlyph, ArrowLeft, 8, 6, 14, backColor);
        UiIcons.draw(forwardGlyph, ArrowRight, 32, 6, 14, forwardColor);
        UiIcons.draw(upGlyph, ArrowUp, 56, 6, 14, Theme.TEXT_SECONDARY);
    }

    // ------------------------------------------------------------------
    // Public command surface (used by EditorShell and keyboard routing)
    // ------------------------------------------------------------------

    public inline function isRenaming():Bool return renaming;
    public inline function isSearchFocused():Bool return searchField.isFocused();
    public inline function hasClipboard():Bool return clipboardSource != "";
    public inline function hasSelection():Bool return selectedSource != "";
    public inline function currentFolder():String return selectedFolder;

    public function closeMenus():Void {
        addMenu.close();
        contextMenu.close();
        filterMenu.close();
        sortMenu.close();
        closeSettings();
        favoriteMenu.close();
        breadcrumbMenu.close();
    }

    /** Ctrl+C: remember the selection for a later paste. */
    public function copyToClipboard():Void {
        if (selectedSource == "" || folderFromSelectionKey(selectedSource) != null) return;
        clipboardSource = selectedSource;
        clipboardIsCut = false;
        Sys.println('[probe] asset browser clipboard copy=${selectedSource}');
    }

    /** Ctrl+X: remember the selection for a move-on-paste. */
    public function cutToClipboard():Void {
        if (selectedSource == "" || folderFromSelectionKey(selectedSource) != null) return;
        clipboardSource = selectedSource;
        clipboardIsCut = true;
        Sys.println('[probe] asset browser clipboard cut=${selectedSource}');
    }

    public function pasteClipboard():Void {
        pasteInto(selectedFolder);
    }

    public function pasteInto(folder:String):Void {
        if (clipboardSource == "") return;
        var target = folder == "" ? "Scenes" : folder;
        var source = clipboardSource;
        var isCut = clipboardIsCut;
        // Folder selection markers are UI-only and must never be copied/pasted
        // as asset paths.
        var items:Array<String> = [];
        for (item in selectedSources) {
            if (folderFromSelectionKey(item) == null) items.push(item);
        }
        Sys.println('[probe] asset browser paste source=${source} folder=${target} cut=${isCut}');
        if (isCut) {
            clipboardSource = "";
            for (item in items) if (onMoveAsset != null) onMoveAsset(item, target);
            if (items.length == 0 && onMoveAsset != null) onMoveAsset(source, target);
        } else if (onCopyAsset != null) {
            for (item in items) onCopyAsset(item, target);
            if (items.length == 0) onCopyAsset(source, target);
        }
    }

    /** Ctrl+F: focus the search field. */
    public function focusSearch():Void {
        searchField.focusInput();
    }

    /** Ctrl+A: select every item in the current view. */
    public function selectAll():Void {
        var all:Array<String> = [];
        for (entry in shownEntries) all.push(entry.source);
        setSelected(all);
        Sys.println('[probe] asset browser selectAll=${all.length}');
    }

    /** Escape: clear the asset selection without changing folder navigation. */
    public function clearSelection():Void {
        if (renaming) return;
        if (selectedSource == "") return;
        setSelected([]);
        Sys.println('[probe] asset browser selection cleared');
    }

    /**
     * Reveal one asset: navigate to its folder, expand the Engine tree branch
     * when needed and select its tile. Engine assets are hidden until the
     * settings opt-in or the Engine Asset filter is active, so browsing to one
     * enables the opt-in instead of silently showing nothing.
     */
    public function revealAsset(source:String):Bool {
        if (source == null || source == "") {
            showStatus("No asset assigned to this slot");
            return false;
        }
        var isEngine = StringTools.startsWith(source, EngineAssetCatalog.SOURCE_PREFIX);
        var changed = false;
        if (isEngine && !showEngineAssets && typeFilter != AssetTypeRegistry.KIND_ENGINE) {
            showEngineAssets = true;
            store.showEngineAssets = true;
            store.save();
            showEngineAssetsCheckbox.value = true;
            changed = true;
        }
        if (!isEngine && typeFilter == AssetTypeRegistry.KIND_ENGINE) {
            typeFilter = "all";
            store.typeFilter = typeFilter;
            store.save();
            changed = true;
        }
        if (searchText != "") {
            searchText = "";
            searchField.setText("");
        }
        if (changed) refresh();

        var entry = findEntry(source);
        if (entry == null) {
            showStatus("Asset is not in the current project");
            return false;
        }
        // Expand every ancestor of a virtual Engine subfolder so the revealed
        // asset is visible in the hierarchy, not just in the grid.
        if (isEngineFolder(entry.folder)) {
            var path = "";
            for (part in entry.folder.split("/")) {
                path = path == "" ? part : path + "/" + part;
                expandedFolders.set(path, true);
            }
        }
        applyFolder(entry.folder, true);
        setSelected([source]);

        // Scroll the selected tile into view before the final rebuild so the
        // highlight is actually visible in a small Asset Browser panel.
        var index = -1;
        for (i in 0...shownItems.length) {
            if (!shownItems[i].isFolder && shownItems[i].path == source) {
                index = i;
                break;
            }
        }
        if (index >= 0) {
            var row = viewMode == 0 ? Std.int(index / Math.max(1, gridColumns())) : index;
            var itemY = 4 + row * rowHeight();
            var view = gridViewportHeight();
            var maxScroll = Math.max(0, contentHeight(shownItems.length) - view);
            if (maxScroll > 0) {
                scrollValue = Math.max(0, Math.min(1,
                    (itemY - view * 0.35) / maxScroll));
            }
        }
        buildAssets();
        showStatus('Browsed to ${entry.name}');
        Sys.println('[probe] asset browser reveal source=${source} folder=${entry.folder}');
        return true;
    }

    /** Backspace navigates to the current folder's parent. */
    public function navigateToParent():Void {
        if (selectedFolder == "") {
            if (folderHistoryIndex > 0) goBack();
            return;
        }
        var parts = selectedFolder.split("/");
        parts.pop();
        navigateTo(parts.join("/"));
    }

    public function goBack():Void {
        if (folderHistoryIndex <= 0) return;
        folderHistoryIndex--;
        applyFolder(folderHistory[folderHistoryIndex], false);
        Sys.println('[probe] asset browser history index=${folderHistoryIndex}');
    }

    public function goForward():Void {
        if (folderHistoryIndex >= folderHistory.length - 1) return;
        folderHistoryIndex++;
        applyFolder(folderHistory[folderHistoryIndex], false);
        Sys.println('[probe] asset browser history index=${folderHistoryIndex}');
    }

    /** Contextual shortcut dispatcher. Returns true when a key was consumed. */
    public function handleShortcut(keyCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
        if (renaming) return false;
        if (ctrl) {
            switch (keyCode) {
                case Key.F: focusSearch(); return true;
                case Key.A: selectAll(); return true;
                case Key.R: refresh(); return true;
                default:
            }
        }
        if (alt) {
            if (keyCode == Key.LEFT) { goBack(); return true; }
            if (keyCode == Key.RIGHT) { goForward(); return true; }
        }
        if (!ctrl && !alt) {
            if (keyCode == Key.BACKSPACE) { navigateToParent(); return true; }
            if (keyCode == Key.ENTER || keyCode == Key.NUMPAD_ENTER) {
                openSelected();
                return true;
            }
        }
        return false;
    }

    /** Re-read assets from the project root and rebuild every pane. */
    public function refresh():Void {
        var scanned = onQueryAssets != null ? onQueryAssets() : [];
        // Engine assets stay out of the default view entirely: they are only
        // materialized when the Engine Asset filter or the settings opt-in asks
        // for them. This keeps counts, folders, and filesystem commands clean.
        var engine:Array<AssetFileInfo> = [];
        if (typeFilter == AssetTypeRegistry.KIND_ENGINE || showEngineAssets) {
            engine = onQueryEngineAssets != null ? onQueryEngineAssets() : [];
        }
        entries = scanned.concat(engine);
        detailCache.clear();
        collectFolders();
        printEntries();
        Sys.println('[probe] asset browser folders=${folders.length}');
        if (selectedFolder != "" && folders.indexOf(selectedFolder) < 0) {
            selectedFolder = "";
            syncHistory();
        }
        var stillThere:Array<String> = [];
        for (source in selectedSources) if (findEntry(source) != null) stillThere.push(source);
        setSelected(stillThere);
        rebuildAll();
    }

    public function layout(x:Float, y:Float, width:Float, height:Float):Void {
        this.x = x;
        this.y = y;
        widthValue = Math.max(0, width);
        heightValue = Math.max(0, height);
        // A folder width saved while the dock was wide must not push the folder
        // column (and its rows) past the panel when the window is shrunk. Keep
        // the preference untouched so it returns when there is room again.
        folderWidth = Math.min(preferredFolderWidth, maxFolderWidth());
        refreshLayout();
    }

    function refreshLayout():Void {
        background.setSize(widthValue, heightValue);
        emptyAreaHit.x = 0;
        emptyAreaHit.y = 0;
        emptyAreaHit.width = widthValue;
        emptyAreaHit.height = heightValue;
        toolbar.setSize(widthValue, TOOLBAR_HEIGHT);
        titleText.x = 10;
        titleText.y = 5;

        layoutToolbar();

        folderSurface.y = TOOLBAR_HEIGHT;
        folderSurface.setSize(folderWidth, Math.max(0, heightValue - TOOLBAR_HEIGHT));
        folderTitle.x = 8;
        folderTitle.y = TOOLBAR_HEIGHT + 6;
        fitText(folderTitle, "PROJECT", Math.max(0, folderWidth - 12));

        var treeTop = TOOLBAR_HEIGHT + 22;
        treeMask.x = 0;
        treeMask.y = Std.int(treeTop);
        treeMask.width = Std.int(Math.max(1, folderWidth - 12));
        treeMask.height = Std.int(Math.max(1, heightValue - treeTop - 4));
        treeWheelHit.x = 0;
        treeWheelHit.y = Std.int(treeTop);
        treeWheelHit.width = Std.int(Math.max(1, folderWidth));
        treeWheelHit.height = treeMask.height;
        treeScroll.setBounds(Math.max(0, folderWidth - 9), treeTop, 8,
            Math.max(0, heightValue - treeTop - 4));

        var centerWidth = Math.max(0, widthValue - folderWidth);
        listSurface.x = folderWidth;
        listSurface.y = TOOLBAR_HEIGHT;
        listSurface.setSize(centerWidth, Math.max(0, heightValue - TOOLBAR_HEIGHT));
        listMask.x = folderWidth;
        listMask.y = TOOLBAR_HEIGHT;
        listMask.width = Std.int(Math.max(0, centerWidth - 12));
        listMask.height = Std.int(gridViewportHeight());
        gridScroll.setBounds(Math.max(0, folderWidth + centerWidth - 10),
            TOOLBAR_HEIGHT + 2, 6, Math.max(0, gridViewportHeight() - 4));
        folderSplitter.x = folderWidth - 7;
        folderSplitter.y = TOOLBAR_HEIGHT;
        folderSplitter.width = 14;
        folderSplitter.height = Math.max(0, heightValue - TOOLBAR_HEIGHT);
        folderSplitterGrip.y = TOOLBAR_HEIGHT;
        drawFolderSplitterGrip(false);
        addChild(folderSplitterGrip);
        addChild(folderSplitter);

        buildFolders();
        buildAssets();
        positionRenameOverlay();
    }

    static inline var MIN_FOLDER_WIDTH:Float = 60;

    function maxFolderWidth():Float {
        if (widthValue <= MIN_FOLDER_WIDTH * 2) {
            return Math.max(16, widthValue - TOOLBAR_EDGE * 2);
        }
        return Math.max(MIN_FOLDER_WIDTH, widthValue - MIN_FOLDER_WIDTH);
    }

    function drawFolderSplitterGrip(hover:Bool):Void {
        folderSplitterGrip.clear();
        folderSplitterGrip.x = Math.round(folderWidth) - 1;
        folderSplitterGrip.beginFill(hover ? Theme.ACCENT : Theme.BORDER_STRONG, 1);
        folderSplitterGrip.drawRect(0, 0, 2,
            Math.max(0, heightValue - TOOLBAR_HEIGHT));
        folderSplitterGrip.endFill();
    }

    function beginFolderSplitterDrag():Void {
        var startX = ctx.mouseX;
        var startWidth = preferredFolderWidth;
        var maxWidth = maxFolderWidth();
        var minWidth = Math.min(MIN_FOLDER_WIDTH, maxWidth);
        folderSplitter.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    preferredFolderWidth = Math.max(minWidth,
                        Math.min(maxWidth,
                            startWidth + (ctx.mouseX - startX)));
                    folderWidth = preferredFolderWidth;
                    store.folderWidth = preferredFolderWidth;
                    refreshLayout();
                    event.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    store.save();
                    folderSplitter.stopCapture();
                    event.propagate = false;
                case _:
                    event.propagate = false;
            }
        });
    }

    function layoutToolbar():Void {
        // Lay the right-aligned cluster out from the panel edge. Every tier is
        // chosen so the cluster never crosses the left nav buttons; in a narrow
        // dock the old fixed widths pushed controls over the neighbouring panel.
        var available = widthValue - NAV_CLUSTER_END - TOOLBAR_EDGE * 2;
        var showNav = true;
        var showSettings = true;
        var showFilters = true;
        var showAdd = true;
        var addWidth = 54.0;
        var settingsWidth = ICON_CONTROL_WIDTH;
        var filterWidth = DROPDOWN_CONTROL_WIDTH;
        var sortWidth = DROPDOWN_CONTROL_WIDTH;
        var searchWidth = Math.min(SEARCH_MAX_WIDTH,
            Math.max(130, widthValue * 0.26));

        function clusterWidth():Float {
            var result = searchWidth;
            if (showAdd) result += addWidth + TOOLBAR_GAP;
            if (showSettings) result += settingsWidth + TOOLBAR_GAP;
            if (showFilters) result += filterWidth + sortWidth + TOOLBAR_GAP * 2;
            return result;
        }

        // Filter/sort are always compact icon dropdowns; narrow docks first
        // shrink the search field, then the Add button, then navigation.
        if (clusterWidth() > available) {
            searchWidth = Math.min(150,
                Math.max(SEARCH_MIN_WIDTH, widthValue * 0.26));
        }
        if (clusterWidth() > available) {
            showSettings = false;
            addWidth = ICON_CONTROL_WIDTH;
            searchWidth = SEARCH_MIN_WIDTH;
        }
        if (clusterWidth() > available) {
            showNav = false;
            available = widthValue - TOOLBAR_EDGE * 2;
        }
        if (clusterWidth() > available) showFilters = false;
        if (clusterWidth() > available) {
            // Extreme narrow: keep the search field and drop Add; asset creation
            // remains available from the empty-area context menu.
            showAdd = false;
            searchWidth = Math.min(SEARCH_MIN_WIDTH,
                Math.max(32, available - TOOLBAR_EDGE));
        }
        // Hand any remaining deficit to the search field so the cluster ends
        // exactly at the panel edge instead of spilling into the neighbour.
        var overflow = clusterWidth() - available;
        if (overflow > 0) searchWidth = Math.max(16, searchWidth - overflow);

        backButton.visible = forwardButton.visible = upButton.visible = showNav;
        backGlyph.visible = forwardGlyph.visible = upGlyph.visible = showNav;
        settingsButton.visible = showSettings;
        toolbarSettingsHidden = !showSettings;
        filterButton.visible = showFilters;
        sortButton.visible = showFilters;
        addButton.visible = showAdd;

        var cursor = widthValue - TOOLBAR_EDGE;
        function place(w:Float):Float {
            cursor -= w;
            var result = cursor;
            cursor -= TOOLBAR_GAP;
            return result;
        }
        if (showAdd) {
            addButton.x = place(addWidth);
            addButton.y = 3;
            addButton.setWidth(addWidth);
        }
        if (showSettings) {
            settingsButton.x = place(settingsWidth);
            settingsButton.y = 3;
        }
        if (showFilters) {
            sortButton.x = place(sortWidth);
            sortButton.y = 3;
            sortButton.setWidth(sortWidth);
            filterButton.x = place(filterWidth);
            filterButton.y = 3;
            filterButton.setWidth(filterWidth);
        }
        // Snap to whole pixels: a fractional origin makes the FreeType atlas
        // glyphs sample between texels, so "Search assets..." renders blurry
        // while the integer-aligned hierarchy search field stays crisp.
        searchField.x = Math.round(place(searchWidth));
        searchField.y = 3;
        searchField.setWidth(Math.round(searchWidth));

        backButton.x = 4;
        forwardButton.x = 28;
        upButton.x = 52;
        backButton.y = 3;
        forwardButton.y = 3;
        upButton.y = 3;
        redrawNavGlyphs();

        favoriteHeaderStar.x = folderWidth - 20;
        favoriteHeaderStar.y = TOOLBAR_HEIGHT + 4;
        favoriteHeaderHit.x = folderWidth - 22;
        favoriteHeaderHit.y = TOOLBAR_HEIGHT + 2;
        drawFavoriteIcon(store.favorites.length > 0
            ? Theme.WARNING : Theme.DISABLED);

        var breadcrumbEnd = searchField.x - 6;
        rebuildBreadcrumbs(Math.max(80, breadcrumbEnd));
        statusText.x = Math.max(118, folderWidth + 8);
        statusText.y = heightValue - 16;
        fitStatusText();
        folderText.x = Math.max(80, breadcrumbEnd - 4);
        folderText.y = 6;
        folderText.visible = false;
    }

    // ------------------------------------------------------------------
    // Menus
    // ------------------------------------------------------------------

    /** Type/favorites/recent only. Sorting has its own button and menu so
     *  neither list becomes a growing catch-all. */
    function openFilterMenu():Void {
        var items:Array<MenuItem> = [{label: "Filter By", section: true}];
        var options = [
            {key: "all", label: "All assets"},
            {key: AssetTypeRegistry.KIND_SCENE, label: AssetTypeRegistry.SCENE_INFO_LABEL},
            {key: AssetTypeRegistry.KIND_TEXTURE, label: AssetTypeRegistry.TEXTURE_INFO_LABEL},
            {key: AssetTypeRegistry.KIND_ENGINE, label: AssetTypeRegistry.ENGINE_INFO_LABEL},
            {key: AssetTypeRegistry.KIND_FILE, label: AssetTypeRegistry.FILE_INFO_LABEL},
            {key: "favorites", label: "Favorites"},
            {key: "recent", label: "Recent"}
        ];
        for (option in options) {
            var captured = option.key;
            items.push({
                label: option.label,
                selected: typeFilter == captured,
                radio: true,
                onClick: function() {
                    typeFilter = captured;
                    store.typeFilter = typeFilter;
                    store.save();
                    scrollValue = 0;
                    refresh();
                }
            });
        }
        filterMenu.open(ctx.mouseX, ctx.mouseY, items);
    }

    function openSortMenu():Void {
        var items:Array<MenuItem> = [{label: "Sort By", section: true}];
        var names = ["Name", "Type", "Size", "Modified"];
        for (index in 0...names.length) {
            var capturedIndex = index;
            items.push({
                label: names[index],
                selected: sortKey == index,
                radio: true,
                onClick: function() {
                    if (sortKey != capturedIndex) {
                        sortKey = capturedIndex;
                        sortAsc = true;
                        saveViewState();
                        rebuildAll();
                    }
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
                selected: sortAsc == capturedAsc,
                radio: true,
                onClick: function() {
                    if (sortAsc == capturedAsc) return;
                    sortAsc = capturedAsc;
                    saveViewState();
                    rebuildAll();
                }
            });
        }
        sortMenu.open(ctx.mouseX, ctx.mouseY, items);
    }

    static inline var THUMB_MIN:Int = 64;
    static inline var THUMB_MAX:Int = 192;
    // Match the viewport settings popup: the same 220px panel, 8px margin,
    // 14px title, and 24px rows separated by 8px. The thumbnail label and its
    // slider form one tight group so the value sits just below the text.
    static inline var SETTINGS_WIDTH:Int = 220;
    static inline var SETTINGS_MARGIN:Int = 8;
    static inline var SETTINGS_TITLE_H:Int = 14;
    static inline var SETTINGS_ROW_H:Int = 24;
    static inline var SETTINGS_ROW_GAP:Int = 8;
    static inline var SETTINGS_LABEL_H:Int = 14;
    static inline var SETTINGS_LABEL_GAP:Int = 4;
    static inline var SETTINGS_SLIDER_H:Int = 20;
    static inline var SETTINGS_HEIGHT:Int = SETTINGS_MARGIN * 2 + SETTINGS_TITLE_H
        + SETTINGS_ROW_GAP + SETTINGS_ROW_H
        + SETTINGS_ROW_GAP + SETTINGS_LABEL_H + SETTINGS_LABEL_GAP + SETTINGS_SLIDER_H
        + SETTINGS_ROW_GAP + SETTINGS_ROW_H;

    function openSettings():Void {
        if (settingsOpen) {
            closeSettings();
            return;
        }
        settingsOpen = true;
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset browser settings local='
                + (settingsPanel.getScene() == getScene()));
        }
        settingsCatch.width = ctx.width;
        settingsCatch.height = ctx.height;
        settingsCatch.visible = true;
        // The toolbar button is hidden on narrow docks; anchor the popover to
        // the invoking pointer instead of a stale offscreen button position.
        var px = toolbarSettingsHidden
            ? ctx.mouseX - SETTINGS_WIDTH * 0.5
            : this.x + settingsButton.x - 96;
        var py = this.y + TOOLBAR_HEIGHT;
        settingsPanel.x = Math.max(4, Math.min(px, ctx.width - SETTINGS_WIDTH - 4));
        settingsPanel.y = Math.max(4, Math.min(py, ctx.height - SETTINGS_HEIGHT - 4));
        settingsPanel.setSize(SETTINGS_WIDTH, SETTINGS_HEIGHT);
        settingsViewTitle.x = settingsPanel.x + SETTINGS_MARGIN;
        settingsViewTitle.y = settingsPanel.y + SETTINGS_MARGIN;
        var contentTop = SETTINGS_MARGIN + SETTINGS_TITLE_H + SETTINGS_ROW_GAP;
        for (index in 0...3) {
            var button = [viewGridButton, viewListButton, viewDetailsButton][index];
            button.x = settingsPanel.x + SETTINGS_MARGIN + index * 30;
            button.y = settingsPanel.y + contentTop
                + Math.round((SETTINGS_ROW_H - button.height) * 0.5);
            button.visible = true;
        }
        var labelY = contentTop + SETTINGS_ROW_H + SETTINGS_ROW_GAP;
        settingsTitle.x = settingsPanel.x + SETTINGS_MARGIN;
        settingsTitle.y = settingsPanel.y + labelY
            + Math.round((SETTINGS_LABEL_H - settingsTitle.textHeight) * 0.5);
        var sliderY = labelY + SETTINGS_LABEL_H + SETTINGS_LABEL_GAP;
        settingsSlider.setWidth(SETTINGS_WIDTH - SETTINGS_MARGIN * 2);
        settingsSlider.x = settingsPanel.x + SETTINGS_MARGIN;
        settingsSlider.y = settingsPanel.y + sliderY;
        var checkboxY = sliderY + SETTINGS_SLIDER_H + SETTINGS_ROW_GAP;
        showEngineAssetsCheckbox.setWidth(SETTINGS_WIDTH - SETTINGS_MARGIN * 2);
        showEngineAssetsCheckbox.x = settingsPanel.x + SETTINGS_MARGIN;
        showEngineAssetsCheckbox.y = settingsPanel.y + checkboxY
            + Math.round((SETTINGS_ROW_H - 22) * 0.5);
        showEngineAssetsCheckbox.value = showEngineAssets;
        showEngineAssetsCheckbox.visible = true;
        settingsPanel.visible = true;
        settingsViewTitle.visible = true;
        settingsTitle.visible = true;
        settingsSlider.visible = true;
        updateViewButtons();
    }

    function closeSettings():Void {
        if (!settingsOpen) return;
        settingsOpen = false;
        store.save();
        settingsCatch.visible = false;
        settingsPanel.visible = false;
        settingsViewTitle.visible = false;
        settingsTitle.visible = false;
        settingsSlider.visible = false;
        showEngineAssetsCheckbox.visible = false;
        viewGridButton.visible = false;
        viewListButton.visible = false;
        viewDetailsButton.visible = false;
    }

    function openFavoriteMenu():Void {
        var items:Array<MenuItem> = [];
        if (store.favorites.length == 0) {
            items.push({label: "No favorites yet"});
        } else {
            for (source in store.favorites) {
                var captured = source;
                items.push({
                    label: ProjectSession.folderDisplayName(new haxe.io.Path(source).dir)
                        + " / " + new haxe.io.Path(source).file,
                    onClick: function() {
                        var entry = findEntry(captured);
                        navigateTo(entry == null ? "" : entry.folder);
                        setSelected([captured]);
                    }
                });
            }
        }
        favoriteMenu.open(ctx.mouseX, ctx.mouseY, items);
    }

    function saveViewState():Void {
        store.viewMode = viewMode;
        store.thumbnailSize = thumbnailSize;
        store.sortKey = sortKey;
        store.sortAsc = sortAsc;
        store.save();
        updateToolbarState();
    }

    function setViewMode(mode:Int):Void {
        viewMode = mode;
        scrollValue = 0;
        saveViewState();
        refreshLayout();
    }

    function updateViewButtons():Void {
        viewGridButton.setSelected(viewMode == 0);
        viewListButton.setSelected(viewMode == 1);
        viewDetailsButton.setSelected(viewMode == 2);
    }

    function updateToolbarState():Void {
        // Icon-only dropdowns stay quiet at defaults and light up when the
        // user has chosen a non-default filter or sort.
        filterButton.setSelected(typeFilter != "all");
        sortButton.setSelected(sortKey != 0 || !sortAsc);
        drawFavoriteIcon(store.favorites.length > 0
            ? Theme.WARNING : Theme.DISABLED);
        updateViewButtons();
        redrawNavGlyphs();
    }

    // ------------------------------------------------------------------
    // Navigation, folders, and breadcrumbs
    // ------------------------------------------------------------------

    function navigateTo(folder:String):Void {
        applyFolder(folder, true);
    }

    /**
     * Shared folder state update. Kept separate from the row/grid rebuild so a
     * folder row can record navigation on push and still start a drag from the
     * same, still-live Interactive.
     */
    function setFolderState(folder:String, record:Bool):Void {
        selectedFolder = folder;
        setSelected([]);
        if (record) {
            while (folderHistory.length > folderHistoryIndex + 1) folderHistory.pop();
            if (folderHistory[folderHistoryIndex] != folder) {
                folderHistory.push(folder);
                folderHistoryIndex = folderHistory.length - 1;
            }
        }
        scrollValue = 0;
        refreshBreadcrumb();
        updateToolbarState();
        Sys.println('[probe] asset browser navigate folder=${folder}');
    }

    function refreshBreadcrumb():Void {
        rebuildBreadcrumbs(Math.max(80, searchField.x - 6));
    }

    function applyFolder(folder:String, record:Bool):Void {
        setFolderState(folder, record);
        buildFolders();
        buildAssets();
    }

    function syncHistory():Void {
        folderHistory = [selectedFolder];
        folderHistoryIndex = 0;
    }

    function rebuildBreadcrumbs(availableWidth:Float):Void {
        for (object in breadcrumbObjects) object.remove();
        breadcrumbObjects.resize(0);
        var rawParts = selectedFolder == ""
            ? ["Content"] : ["Content"].concat(selectedFolder.split("/"));

        // Deep paths are elided to "Content / … / parent / current" so they
        // never crowd out the toolbar. The ellipsis navigates to the ancestor
        // before the shown tail, revealing more of the path.
        var parts:Array<String> = [];
        var targets:Array<String> = [];
        var hiddenItems:Array<MenuItem> = [];
        var maxParts = 6;
        if (rawParts.length > maxParts) {
            var tailStart = rawParts.length - (maxParts - 2);
            parts.push(rawParts[0]);
            targets.push("");
            parts.push("\u2026");
            targets.push(tailStart > 1 ? rawParts.slice(1, tailStart).join("/") : "");
            // Every elided folder becomes a menu entry, so the ellipsis is a
            // shortcut to any ancestor rather than just the previous one.
            for (index in 1...tailStart) {
                var hiddenTarget = rawParts.slice(1, index + 1).join("/");
                hiddenItems.push({
                    label: rawParts[index],
                    onClick: function() navigateTo(hiddenTarget)
                });
            }
            for (index in tailStart...rawParts.length) {
                parts.push(rawParts[index]);
                targets.push(rawParts.slice(1, index + 1).join("/"));
            }
        } else {
            for (index in 0...rawParts.length) {
                parts.push(rawParts[index]);
                targets.push(index == 0 ? "" : rawParts.slice(1, index + 1).join("/"));
            }
        }

        var x = 82.0;
        for (index in 0...parts.length) {
            var slash:Null<UiText> = null;
            if (index > 0) {
                slash = new UiText(ctx.captionFont, this);
                slash.text = "/";
                slash.textColor = Theme.DISABLED;
                slash.lineBreak = false;
                slash.x = x;
                slash.y = Math.round((TOOLBAR_HEIGHT - slash.textHeight) * 0.5);
                x += 8;
            }
            var isLast = index == parts.length - 1;
            var label = new UiText(ctx.captionFont, this);
            label.text = parts[index];
            label.textColor = isLast ? Theme.TEXT : Theme.MUTED;
            label.lineBreak = false;
            label.x = x;
            label.y = Math.round((TOOLBAR_HEIGHT - label.textHeight) * 0.5);
            // A label that does not fit must be removed, not just skipped:
            // h2d objects are attached on construction and would otherwise
            // stay visible and leak on every narrow-layout rebuild.
            if (x + label.textWidth > availableWidth) {
                label.remove();
                if (slash != null) slash.remove();
                break;
            }
            if (slash != null) breadcrumbObjects.push(slash);
            var hit = new h2d.Interactive(label.textWidth + 2, 18, this);
            hit.x = x;
            hit.y = 3;
            hit.backgroundColor = 0;
            hit.cursor = hxd.Cursor.Default;
            var captured = targets[index];
            var isEllipsis = parts[index] == "\u2026";
            hit.onPush = function(event) {
                event.propagate = false;
                if (isEllipsis) {
                    breadcrumbMenu.open(ctx.mouseX, ctx.mouseY, hiddenItems);
                    return;
                }
                navigateTo(captured);
            };
            breadcrumbObjects.push(hit);
            breadcrumbObjects.push(label);
            x += label.textWidth + 4;
        }
    }

    function printEntries():Void {
        Sys.println('[probe] asset browser entries=${entries.length}');
    }

    function collectFolders():Void {
        folders.resize(0);
        if (onQueryFolders != null) {
            for (folder in onQueryFolders()) {
                if (folder != "" && folders.indexOf(folder) < 0) folders.push(folder);
            }
        }
        for (entry in entries) {
            if (entry.folder == "" || folders.indexOf(entry.folder) >= 0) continue;
            folders.push(entry.folder);
        }
        // Virtual Engine folders stay in the tree even while engine content is
        // hidden by the filter, so their layout does not jump when enabled.
        for (folder in [EngineAssetCatalog.FOLDER,
                EngineAssetCatalog.MESH_FOLDER,
                EngineAssetCatalog.MATERIAL_FOLDER]) {
            if (folders.indexOf(folder) < 0) folders.push(folder);
        }
        folders.sort(function(a, b) return a < b ? -1 : (a == b ? 0 : 1));
    }

    function findEntry(source:String):Null<AssetFileInfo> {
        for (entry in entries) if (entry.source == source) return entry;
        return null;
    }

    function matchesSearch(entry:AssetFileInfo):Bool {
        if (searchText == "") return true;
        return matchesText(entry.name) || matchesText(entry.source) || matchesText(entry.folder)
            || matchesText(entry.extension) || matchesText(entry.kindLabel)
            || matchesText(entry.kind);
    }

    function matchesText(value:String):Bool {
        return value != null && value.toLowerCase().indexOf(searchText) >= 0;
    }

    function matchesFilter(entry:AssetFileInfo):Bool {
        var isEngine = entry.kind == AssetTypeRegistry.KIND_ENGINE;
        // The Engine Asset filter is the explicit way to reveal built-ins.
        if (typeFilter == AssetTypeRegistry.KIND_ENGINE) return isEngine;
        // Otherwise engine assets are hidden until the settings toggle opts in.
        if (isEngine && !showEngineAssets) return false;
        return switch (typeFilter) {
            case "all": true;
            case "favorites": store.isFavorite(entry.source);
            case "recent": store.recent.indexOf(entry.source) >= 0;
            case other: entry.kind == other;
        };
    }

    function visibleEntries():Array<AssetFileInfo> {
        // Direct child folders are first-class items in the Asset Panel, so
        // folders can be opened and dragged just like the tiles in the grid.
        var items:Array<BrowserItem> = [];
        var prefix = selectedFolder == "" ? "" : selectedFolder + "/";
        for (folder in folders) {
            // The Engine root is a hierarchy-only grouping; its type children
            // (Meshes/Materials) do get tiles when browsing inside Engine.
            if (folder == EngineAssetCatalog.FOLDER) continue;
            if (selectedFolder == "") {
                if (folder.indexOf("/") >= 0) continue;
            } else {
                if (!StringTools.startsWith(folder, prefix)) continue;
                var rest = folder.substring(prefix.length);
                if (rest.indexOf("/") >= 0) continue;
            }
            var parts = folder.split("/");
            items.push({
                isFolder: true, path: folder,
                name: parts[parts.length - 1], entry: null
            });
        }

        var result:Array<AssetFileInfo> = [];
        for (entry in entries) {
            if (selectedFolder != "" && entry.folder != selectedFolder) continue;
            // Engine assets only appear while browsing an Engine folder, never
            // mixed into project folders at the Content root.
            if (entry.kind == AssetTypeRegistry.KIND_ENGINE
                    && !isEngineFolder(selectedFolder)) continue;
            if (!matchesSearch(entry) || !matchesFilter(entry)) continue;
            result.push(entry);
        }
        var key = sortKey;
        var direction = sortAsc ? 1 : -1;
        result.sort(function(a, b) {
            var comparison = 0;
            switch (key) {
                case 1:
                    comparison = a.kindLabel == b.kindLabel ? 0
                        : (a.kindLabel < b.kindLabel ? -1 : 1);
                case 2:
                    comparison = compareFloat(detailSize(a), detailSize(b));
                case 3:
                    comparison = compareFloat(detailModified(a), detailModified(b));
                default:
                    comparison = a.name == b.name ? 0 : (a.name < b.name ? -1 : 1);
            }
            if (comparison == 0) comparison = a.source == b.source ? 0 : (a.source < b.source ? -1 : 1);
            return comparison * direction;
        });
        for (entry in result) {
            items.push({
                isFolder: false, path: entry.source,
                name: entry.name, entry: entry
            });
        }
        shownItems = items;
        shownEntries = result;
        return result;
    }

    static inline var FOLDER_KEY_PREFIX:String = "__folder__:";

    static inline function folderSelectionKey(path:String):String {
        return FOLDER_KEY_PREFIX + path;
    }

    static inline function folderFromSelectionKey(key:String):Null<String> {
        return StringTools.startsWith(key, FOLDER_KEY_PREFIX)
            ? key.substring(FOLDER_KEY_PREFIX.length) : null;
    }

    /** Engine folders are virtual: browsable but never moved/renamed/deleted. */
    static inline function isEngineFolder(path:String):Bool {
        return path == EngineAssetCatalog.FOLDER
            || StringTools.startsWith(path, EngineAssetCatalog.FOLDER + "/");
    }

    static function compareFloat(a:Float, b:Float):Int {
        return a == b ? 0 : (a < b ? -1 : 1);
    }

    function detailsFor(entry:AssetFileInfo):Null<AssetDetails> {
        if (!detailCache.exists(entry.source) && onQueryAssetDetails != null) {
            detailCache.set(entry.source, onQueryAssetDetails(entry.source));
        }
        return detailCache.get(entry.source);
    }

    function detailSize(entry:AssetFileInfo):Float {
        var details = detailsFor(entry);
        return details == null ? -1 : details.size;
    }

    function detailModified(entry:AssetFileInfo):Float {
        var details = detailsFor(entry);
        return details == null ? -1 : details.modified;
    }

    // ------------------------------------------------------------------
    // Folder tree
    // ------------------------------------------------------------------

    /** Build the full project tree: folders plus the assets inside them. */
    function buildAssetTree():Array<AssetTreeNode> {
        var roots:Array<AssetTreeNode> = [];
        var byPath = new Map<String, AssetTreeNode>();

        function folderNode(path:String):AssetTreeNode {
            var existing = byPath.get(path);
            if (existing != null) return existing;
            var parts = path.split("/");
            var node:AssetTreeNode = {
                name: parts[parts.length - 1], path: path, isFolder: true,
                entry: null, children: []
            };
            byPath.set(path, node);
            if (parts.length == 1) {
                roots.push(node);
            } else {
                folderNode(parts.slice(0, parts.length - 1).join("/")).children.push(node);
            }
            return node;
        }

        for (path in folders) if (path != "") folderNode(path);
        for (entry in entries) {
            var leaf:AssetTreeNode = {
                name: entry.name, path: entry.source, isFolder: false,
                entry: entry, children: []
            };
            if (entry.folder == "") roots.push(leaf);
            else folderNode(entry.folder).children.push(leaf);
        }
        sortTreeNodes(roots);
        return roots;
    }

    static function sortTreeNodes(nodes:Array<AssetTreeNode>):Void {
        nodes.sort(function(a, b) {
            if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
            // Real project folders come first; the virtual Engine branch stays
            // at the bottom so its rows never shift the project tree layout.
            var aEngine = isEngineFolder(a.path);
            var bEngine = isEngineFolder(b.path);
            if (aEngine != bEngine) return aEngine ? 1 : -1;
            return a.name < b.name ? -1 : (a.name == b.name ? 0 : 1);
        });
        for (node in nodes) sortTreeNodes(node.children);
    }

    function isExpanded(path:String):Bool {
        return expandedFolders.exists(path) ? expandedFolders.get(path) : true;
    }

    function treeScrollOffset():Float {
        return Math.max(0, treeContentHeight - treeMask.height) * treeScrollValue;
    }

    function countVisibleNodes(node:AssetTreeNode):Int {
        var count = 1;
        if (node.isFolder && isExpanded(node.path)) {
            for (child in node.children) count += countVisibleNodes(child);
        }
        return count;
    }

    function buildFolders():Void {
        clearRows(folderRows);
        folderRowPaths.resize(0);
        folderRowIsFolder.resize(0);
        folderRowStyleUpdaters.resize(0);

        treeAssetSelected = false;
        for (source in selectedSources) {
            if (!StringTools.startsWith(source, FOLDER_KEY_PREFIX)) {
                treeAssetSelected = true;
                break;
            }
        }
        var nodes = buildAssetTree();
        var visible = 1; // "All" root row
        for (node in nodes) visible += countVisibleNodes(node);
        var content = visible * ROW_HEIGHT;
        var over = Math.max(0, content - treeMask.height);
        treeContentHeight = content;
        treeScrollValue = Math.max(0, Math.min(1, treeScrollValue));
        treeScroll.setMetrics(over <= 0 ? 1 : treeMask.height / Math.max(1, content),
            treeScrollValue);
        // folderRowPaths is cleared above; use the measured content height so
        // the rebuilt rows actually shift when the tree is scrolled.
        var offset = over * treeScrollValue;

        var index = 0;
        var all = makeTreeRow("All", "", !treeAssetSelected && selectedFolder == "",
            0, false, true, null);
        // treeMask already starts below the folder header; no extra 22px here.
        all.y = index * ROW_HEIGHT - offset;
        folderRows.push(all);
        folderRowPaths.push("");
        folderRowIsFolder.push(true);
        index++;
        for (node in nodes) index = renderAssetTreeNode(node, 0, index, offset);
    }

    function renderAssetTreeNode(node:AssetTreeNode, depth:Int, index:Int,
            offset:Float):Int {
        var hasChildren = node.isFolder && node.children.length > 0;
        // The tree mirrors selection in both panes: folders follow the current
        // folder, assets follow their selected source.
        var selected = node.isFolder
            ? (!treeAssetSelected && (selectedFolder == node.path
                || isSelected(folderSelectionKey(node.path))))
            : isSelected(node.path);
        var row = makeTreeRow(node.name, node.path, selected, depth,
            hasChildren, node.isFolder, node.entry);
        row.y = index * ROW_HEIGHT - offset;
        folderRows.push(row);
        folderRowPaths.push(node.path);
        folderRowIsFolder.push(node.isFolder);
        index++;
        if (hasChildren && isExpanded(node.path)) {
            for (child in node.children) {
                index = renderAssetTreeNode(child, depth + 1, index, offset);
            }
        }
        return index;
    }

    function makeTreeRow(display:String, path:String, selected:Bool, depth:Int,
            hasChildren:Bool, isFolder:Bool, entry:Null<AssetFileInfo>):h2d.Object {
        var row = new h2d.Object(treeMask);
        row.x = 2;
        var rowWidth = Math.max(20, folderWidth - 16);
        // Reuse the Asset Browser's hover language (lighter surface, green
        // frame) and reserve the teal fill + green frame for click selection.
        var card = new UiSurface(ctx, row);
        card.setSize(rowWidth, ROW_HEIGHT - 2);
        var hovering = false;
        function applyStyle():Void {
            var selectedNow = isFolder
                ? (!treeAssetSelected && (selectedFolder == path
                    || isSelected(folderSelectionKey(path))))
                : isSelected(path);
            card.visible = selectedNow || hovering;
            card.setStyle(selectedNow
                ? (hovering ? 0x356B5C : Theme.ACCENT_MUTED) : Theme.SURFACE_3,
                Theme.ACCENT, 0, 0);
        }
        applyStyle();
        folderRowStyleUpdaters.push(applyStyle);
        var hit = new h2d.Interactive(rowWidth, ROW_HEIGHT - 2, row);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        var captured = path;
        hit.onPush = function(event) {
            if (tooltip != null) tooltip.cancel();
            event.propagate = false;
            if (event.button == 1) {
                if (isFolder) openFolderContextMenu(captured);
                else {
                    if (!isSelected(captured)) setSelected([captured]);
                    openContextMenu();
                }
                buildFolders();
                buildAssets();
                return;
            }
            var now = haxe.Timer.stamp();
            var isDouble = captured == lastClickSource && now - lastClickAt <= 0.35;
            lastClickAt = now;
            lastClickSource = captured;
            if (isFolder) {
                // A single click navigates and keeps folder drag/collapse working.
                setFolderState(captured, true);
                // Selecting the folder row makes Delete act on that folder, just
                // like clicking a folder tile in the main panel.
                if (captured != "") setSelected([folderSelectionKey(captured)]);
                if (isDouble && captured != "") expandedFolders.set(captured, true);
                if (captured != "" && !isEngineFolder(captured)) {
                    beginFolderDrag(captured, hit, event);
                } else {
                    buildFolders();
                    buildAssets();
                }
                return;
            }
            if (hxd.Key.isDown(hxd.Key.CTRL)) toggleSelection(captured);
            else if (hxd.Key.isDown(hxd.Key.SHIFT)) selectRange(captured);
            else setSelected([captured]);
            if (isDouble) {
                buildAssets();
                openSelected();
                return;
            }
            beginAssetDrag(captured, hit, event);
        };
        hit.onWheel = handleTreeWheel;
        hit.onOver = function(_) {
            hovering = true;
            applyStyle();
            if (tooltip != null) {
                tooltip.schedule(isFolder ? (path == "" ? "All" : path) : path,
                    ctx.mouseX, ctx.mouseY);
            }
        };
        hit.onOut = function(_) {
            hovering = false;
            applyStyle();
            if (tooltip != null) tooltip.cancel();
        };

        var compactRow = folderWidth < 90;
        var iconX = 20 + depth * 14;
        if (!compactRow) {
            var icon = new h2d.Graphics(row);
            var iconSize = 14;
            var iconColor = selected ? Theme.ACCENT : isFolder ? Theme.MUTED
                : (entry != null && entry.loadable ? Theme.TEXT_SECONDARY : Theme.MUTED);
            if (isFolder) UiIcons.draw(icon, Folder, iconX,
                Math.round((ROW_HEIGHT - iconSize) * 0.5), iconSize, iconColor);
            else drawAssetIcon(icon, entry, iconX,
                Math.round((ROW_HEIGHT - iconSize) * 0.5), iconSize, iconColor);
        }
        var labelX = compactRow ? 6 : iconX + 18;
        var label = new UiText(ctx.font, row);
        fitText(label, display, Math.max(0, rowWidth - labelX - 6));
        label.textColor = selected ? 0xF3F7FF : Theme.TEXT_SECONDARY;
        label.lineBreak = false;
        label.x = labelX;
        // Center on the icon's vertical middle instead of pinning to the top.
        label.y = Math.round((ROW_HEIGHT - label.textHeight) * 0.5);

        if (isFolder) {
            var pathParts = path.split("/");
            var probeName = path == "" ? "All" : pathParts[pathParts.length - 1];
            Sys.println('[probe] asset browser folder row=${probeName} depth=${depth}');
        } else {
            Sys.println('[probe] asset browser asset row=${display} depth=${depth}');
        }

        if (hasChildren && path != "" && !compactRow) {
            var chevron = new h2d.Graphics(row);
            // Keep the chevron in the same indent column as this row's icon.
            var chevronX = 4 + depth * 14;
            UiIcons.draw(chevron, isExpanded(path) ? ChevronDown : ChevronRight,
                chevronX, Math.round((ROW_HEIGHT - 9) * 0.5), 9, Theme.MUTED);
            var chevronHit = new h2d.Interactive(14, ROW_HEIGHT - 2, row);
            chevronHit.x = chevronX - 2;
            chevronHit.backgroundColor = 0;
            chevronHit.cursor = hxd.Cursor.Default;
            chevronHit.onPush = function(event) {
                expandedFolders.set(path, !isExpanded(path));
                buildFolders();
                event.propagate = false;
            };
        }
        return row;
    }

    function handleTreeWheel(event:hxd.Event):Void {
        handleTreeWheelDelta(event.wheelDelta);
        event.propagate = false;
    }

    function handleTreeWheelDelta(delta:Float):Void {
        var over = Math.max(0, treeContentHeight - treeMask.height);
        if (over <= 0) return;
        treeScrollValue = Math.max(0, Math.min(1,
            treeScrollValue + delta * WHEEL_STEP / over));
        buildFolders();
    }

    /**
     * Map a window-client point (as delivered by `hxd.DropFileEvent`) to a
     * browser folder. Internal drags already pass local coordinates; OS drops
     * arrive in window space and must be transformed through the dock layout.
     */
    public function folderAtWindowPoint(x:Float, y:Float):Null<String> {
        var local = globalToLocal(new h2d.col.Point(x, y));
        return folderAt(local.x, local.y);
    }

    /** Folder drop target in either the hierarchy pane or the main panel. */
    function folderAt(x:Float, y:Float):Null<String> {
        for (rect in assetFolderRects) {
            if (x >= rect.x && x <= rect.x + rect.width
                    && y >= rect.y && y <= rect.y + rect.height) return rect.path;
        }
        if (x < 0 || x > folderWidth) return null;
        var treeTop = TOOLBAR_HEIGHT + 22;
        if (y < treeTop || y > treeTop + treeMask.height) return null;
        var offset = treeScrollOffset();
        for (index in 0...folderRowPaths.length) {
            if (!folderRowIsFolder[index]) continue;
            var rowY = treeTop + index * ROW_HEIGHT - offset;
            if (y >= rowY && y <= rowY + ROW_HEIGHT - 2) return folderRowPaths[index];
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Asset views
    // ------------------------------------------------------------------

    function tileWidth():Int return thumbnailSize;
    function tileHeight():Int return Std.int(Math.max(40, thumbnailSize - 8));

    function centerWidth():Float {
        return Math.max(0, widthValue - folderWidth);
    }

    function gridColumns():Int {
        var available = Math.max(0, centerWidth() - 16);
        var columns:Int = Std.int((available + TILE_GAP) / (tileWidth() + TILE_GAP));
        return columns < 1 ? 1 : columns;
    }

    function gridViewportHeight():Float {
        return Math.max(0, heightValue - TOOLBAR_HEIGHT - 8);
    }

    function rowHeight():Float {
        return viewMode == 0 ? tileHeight() + TILE_GAP : LIST_ROW_HEIGHT + 2;
    }

    function contentHeight(count:Int):Float {
        if (viewMode == 0) {
            var rows = Math.ceil(count / Math.max(1, gridColumns()));
            return rows * rowHeight();
        }
        return count * rowHeight();
    }

    function scrollOffset(count:Int):Float {
        return Math.max(0, contentHeight(count) - gridViewportHeight()) * scrollValue;
    }

    function tilePosition(index:Int, count:Int):{ x:Float, y:Float } {
        var columns = gridColumns();
        return {
            x: viewMode == 0
                ? 8 + (index % columns) * (tileWidth() + TILE_GAP) : 8,
            y: viewMode == 0
                ? 4 + Std.int(index / columns) * rowHeight() - scrollOffset(count)
                : 4 + index * rowHeight() - scrollOffset(count)
        };
    }

    function buildAssets():Void {
        clearRows(assetRows);
        assetFolderRects.resize(0);
        visibleEntries();
        var items = shownItems;
        var content = contentHeight(items.length);
        var view = gridViewportHeight();
        var ratio = content <= 0 ? 1.0 : Math.min(1.0, view / content);
        if (ratio < 1 && Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset browser scrollable=true tiles=${items.length}');
        }
        gridScroll.setMetrics(ratio, scrollValue);
        gridScroll.setBounds(Math.max(0, folderWidth + centerWidth() - 10),
            TOOLBAR_HEIGHT + 2, 6, Math.max(0, view - 4));

        switch (viewMode) {
            case 1: buildCompactList(items);
            case 2: buildDetailsList(items);
            default: buildGrid(items);
        }

        // No persistent status sentence under the grid: selection is visible on
        // the tiles themselves, and transient messages use showStatus().
    }

    function buildGrid(shown:Array<BrowserItem>):Void {
        var width = tileWidth();
        var height = tileHeight();
        var previewHeight = Math.max(30, height - TILE_LABEL_HEIGHT - 10);
        for (index in 0...shown.length) {
            var item = shown[index];
            var position = tilePosition(index, shown.length);
            if (position.y + height < 0 || position.y > gridViewportHeight()) continue;
            var tile = new h2d.Object(listMask);
            tile.x = position.x;
            tile.y = position.y;
            assetRows.push(tile);

            var selected = isSelected(item.isFolder
                ? folderSelectionKey(item.path) : item.path);
            // The whole tile is one card: icon, left-aligned name, and a small
            // type caption share the same surface and selection highlight.
            var card = new UiSurface(ctx, tile);
            card.setSize(width, height);
            card.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT,
                selected ? Theme.ACCENT : Theme.BORDER, 0, 0);
            var preview = new h2d.Graphics(tile);
            if (item.isFolder) {
                drawFolderPreview(preview, 4, 2, width - 8, previewHeight, selected);
                assetFolderRects.push({
                    x: listMask.x + tile.x, y: listMask.y + tile.y,
                    width: width, height: height, path: item.path
                });
            } else if (item.entry != null) {
                drawPreview(preview, item.entry, 4, 2, width - 8, previewHeight, selected);
            }

            var name = new UiText(ctx.labelFont, tile);
            fitText(name, item.name, Math.max(0, width - 16));
            name.textColor = selected ? 0xF3F7FF : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = 8;
            name.y = height - TILE_LABEL_HEIGHT + 2;

            var type = new UiText(ctx.captionFont, tile);
            type.text = item.isFolder ? "Folder"
                : (item.entry == null ? "" : item.entry.kindLabel);
            type.textColor = selected ? Theme.TEXT_SECONDARY : Theme.MUTED;
            type.lineBreak = false;
            type.x = 8;
            type.y = height - 14;

            if (!item.isFolder && item.entry != null && store.isFavorite(item.entry.source)) {
                var star = new h2d.Graphics(tile);
                UiIcons.draw(star, Star, width - 19, 3, 12, Theme.WARNING);
            }
            var hit = if (item.isFolder) attachFolderHit(tile, item.path, width, height)
                else if (item.entry != null) attachItemHit(tile, item.entry, width, height)
                else null;
            if (hit != null) {
                hit.onOver = function(_) {
                                        card.setStyle(selected ? 0x356B5C : Theme.SURFACE_3,
                        Theme.ACCENT, 0, 0);
                    if (tooltip != null) {
                        tooltip.schedule(assetTooltipText(item),
                            ctx.mouseX, ctx.mouseY);
                    }
                };
                hit.onOut = function(_) {
                                        card.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT,
                        selected ? Theme.ACCENT : Theme.BORDER, 0, 0);
                    if (tooltip != null) tooltip.cancel();
                };
            }
        }
    }

    /** Folder tile preview: the pinned Tabler folder glyph on a square card. */
    function drawFolderPreview(g:h2d.Graphics, x:Float, y:Float,
            w:Float, h:Float, selected:Bool):Void {
        // No inner frame: the icon sits directly on the card surface so the
        // name and type caption get the full tile width and more breathing room.
        var size = Math.min(w, h) * 0.86;
        UiIcons.drawFolderThumb(g, x + (w - size) * 0.5, y + (h - size) * 0.5,
            size, selected ? Theme.ACCENT : Theme.TEXT_SECONDARY);
    }

    /** Folder tile interaction: double-click enters, drag moves, right-click
     *  opens the folder menu, and the tile is a drop target for assets. */
    function attachFolderHit(target:h2d.Object, path:String,
            width:Float, height:Float):h2d.Interactive {
        var hit = new h2d.Interactive(width, height, target);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        var captured = path;
        hit.onPush = function(event) {
            if (tooltip != null) tooltip.cancel();
            event.propagate = false;
            if (event.button == 1) {
                openFolderContextMenu(captured);
                return;
            }
            var now = haxe.Timer.stamp();
            var isDouble = captured == lastClickSource && now - lastClickAt <= 0.35;
            lastClickAt = now;
            lastClickSource = captured;
            setSelected([folderSelectionKey(captured)]);
            if (isDouble) {
                navigateTo(captured);
                return;
            }
            if (isEngineFolder(captured)) return;
            beginFolderDrag(captured, hit, event);
        };
        hit.onWheel = handleGridWheel;
        return hit;
    }

    /**
     * Draw a decoded texture tile fitted inside `size`. Returns false when no
     * tile is available so callers can fall back to their normal glyph.
     */
    function drawTextureThumb(g:h2d.Graphics, source:String,
            x:Float, y:Float, size:Float):Bool {
        if (onQueryTextureTile == null) return false;
        var tile = onQueryTextureTile(source);
        if (tile == null || tile.width <= 0 || tile.height <= 0) return false;
        var scale = Math.min(size / tile.width, size / tile.height);
        var width = Math.max(1, Std.int(tile.width * scale));
        var height = Math.max(1, Std.int(tile.height * scale));
        g.beginFill(0x000000, 0.22);
        g.drawRect(x, y, size, size);
        g.endFill();
        // scaleToSize mutates its tile; clone so the cached tile keeps its
        // original dimensions for every other card in the grid.
        var fitted = tile.clone();
        fitted.scaleToSize(width, height);
        g.drawTile(x + (size - width) * 0.5, y + (size - height) * 0.5, fitted);
        return true;
    }

    /** Large preview tile. Scenes use Tabler's `outline/photo` glyph - a framed
     *  landscape is the familiar shorthand for a level/scene thumbnail - and
     *  generic files keep a neutral document glyph. Both scale with the
     *  thumbnail-size slider. */
    function drawPreview(g:h2d.Graphics, entry:AssetFileInfo,
            x:Float, y:Float, w:Float, h:Float, selected:Bool):Void {
        // The outer card owns the surface and selection frame. The icon is
        // drawn straight onto it so the name/type captions get the full width.
        var cardSize = Math.min(w, h);
        var cardX = x + (w - cardSize) * 0.5;
        var cardY = y + (h - cardSize) * 0.5;
        var cx = cardX + cardSize * 0.5;
        var cy = cardY + cardSize * 0.5;
        if (entry.kind == AssetTypeRegistry.KIND_ENGINE) {
            var payload = EngineAssetCatalog.dragPayload(entry);
            PrimitiveThumbnails.draw(g, payload == null ? "" : payload.assetId,
                cardX, cardY, cardSize, cardSize,
                selected ? Theme.ACCENT : Theme.CUBE_ORANGE);
        } else if (entry.kind == AssetTypeRegistry.KIND_TEXTURE
                && drawTextureThumb(g, entry.source, cardX, cardY, cardSize)) {
            // Real decoded image, capped to a small GPU tile by TextureCache.
        } else if (entry.loadable && entry.kind == AssetTypeRegistry.KIND_SCENE) {
            var iconSize = cardSize * 0.86;
            UiIcons.drawSceneThumb(g, cx - iconSize * 0.5, cy - iconSize * 0.5,
                iconSize, selected ? Theme.ACCENT : Theme.TEXT_SECONDARY);
        } else {
            var base = 0x7A8794;
            var pw = cardSize * 0.42;
            var ph = pw * 1.3;
            var px = cx - pw * 0.5;
            var py = cardY + (cardSize - ph) * 0.5;
            g.beginFill(0x000000, 0.28);
            g.drawRect(px + 2, py + 3, pw, ph);
            g.endFill();
            g.beginFill(shade(base, 0.85));
            g.drawRect(px, py, pw, ph);
            g.endFill();
            g.beginFill(Theme.FIELD_BG);
            g.drawRect(px + pw * 0.6, py, pw * 0.4, ph * 0.24);
            g.endFill();
            g.beginFill(shade(base, 1.2));
            g.drawRect(px + pw * 0.6, py, pw * 0.4, ph * 0.22);
            g.endFill();
            for (line in 0...4) {
                g.beginFill(0x000000, 0.18);
                g.drawRect(px + pw * 0.12, py + ph * (0.38 + line * 0.13),
                    pw * 0.7, Math.max(1, ph * 0.035));
                g.endFill();
            }
        }
        if (entry.active) {
            g.beginFill(Theme.ACCENT);
            g.drawCircle(cardX + 9, cardY + 9, 3);
            g.endFill();
        }
    }

    function buildCompactList(shown:Array<BrowserItem>):Void {
        var width = Math.max(100, centerWidth() - 16);
        for (index in 0...shown.length) {
            var item = shown[index];
            var position = tilePosition(index, shown.length);
            if (position.y + LIST_ROW_HEIGHT < 0 || position.y > gridViewportHeight()) continue;
            var row = new h2d.Object(listMask);
            row.x = position.x;
            row.y = position.y;
            assetRows.push(row);
            var selected = isSelected(item.isFolder
                ? folderSelectionKey(item.path) : item.path);
            var surface = new UiSurface(ctx, row);
            surface.setSize(width, LIST_ROW_HEIGHT);
            surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL,
                selected ? Theme.ACCENT : Theme.BORDER, 0);
            var icon = new h2d.Graphics(row);
            var iconColor = selected ? Theme.ACCENT : item.isFolder ? Theme.TEXT_SECONDARY
                : (item.entry != null && item.entry.loadable ? Theme.TEXT_SECONDARY : Theme.MUTED);
            if (item.isFolder) UiIcons.draw(icon, Folder, 5, 3, 14, iconColor);
            else drawAssetIcon(icon, item.entry, 5, 3, 14, iconColor);
            var type = new UiText(ctx.captionFont, row);
            type.text = item.isFolder ? "Folder" : (item.entry == null ? "" : item.entry.kindLabel);
            type.textColor = Theme.MUTED;
            type.lineBreak = false;
            type.x = Math.max(0, width - type.textWidth - 8);
            type.y = 3;
            var name = new UiText(ctx.font, row);
            fitText(name, item.name, Math.max(0, type.x - 24 - 4));
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = 24;
            name.y = 2;
            if (item.isFolder) {
                assetFolderRects.push({
                    x: listMask.x + row.x, y: listMask.y + row.y,
                    width: width, height: LIST_ROW_HEIGHT, path: item.path
                });
                applyListHover(attachFolderHit(row, item.path, width, LIST_ROW_HEIGHT),
                    surface, selected, item);
            } else if (item.entry != null) {
                applyListHover(attachItemHit(row, item.entry, width, LIST_ROW_HEIGHT),
                    surface, selected, item);
            }
        }
    }

    function buildDetailsList(shown:Array<BrowserItem>):Void {
        var width = Math.max(100, centerWidth() - 16);
        var columnsX = [DETAILS_NAME_WIDTH, DETAILS_NAME_WIDTH + DETAILS_COL_WIDTH,
            DETAILS_NAME_WIDTH + DETAILS_COL_WIDTH * 2];
        var header = new h2d.Object(listMask);
        header.x = 8;
        header.y = 0;
        assetRows.push(header);
        var headerSurface = new UiSurface(ctx, header);
        headerSurface.setSize(width, LIST_ROW_HEIGHT);
        headerSurface.setStyle(Theme.PANEL_HEADER, Theme.BORDER, 0);
        addHeaderText(header, "Name", 8);
        addHeaderText(header, "Type", columnsX[0]);
        addHeaderText(header, "Size", columnsX[1]);
        addHeaderText(header, "Modified", columnsX[2]);

        for (index in 0...shown.length) {
            var item = shown[index];
            var position = tilePosition(index, shown.length);
            var y = position.y + LIST_ROW_HEIGHT + 2;
            if (y + LIST_ROW_HEIGHT < 0 || y > gridViewportHeight()) continue;
            var row = new h2d.Object(listMask);
            row.x = 8;
            row.y = y;
            assetRows.push(row);
            var selected = isSelected(item.isFolder
                ? folderSelectionKey(item.path) : item.path);
            var surface = new UiSurface(ctx, row);
            surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL,
                selected ? Theme.ACCENT : Theme.BORDER, 0);
            surface.setSize(width, LIST_ROW_HEIGHT);
            var icon = new h2d.Graphics(row);
            var iconColor = selected ? Theme.ACCENT : item.isFolder ? Theme.TEXT_SECONDARY
                : (item.entry != null && item.entry.loadable ? Theme.TEXT_SECONDARY : Theme.MUTED);
            if (item.isFolder) UiIcons.draw(icon, Folder, 4, 3, 14, iconColor);
            else drawAssetIcon(icon, item.entry, 4, 3, 14, iconColor);
            var name = new UiText(ctx.font, row);
            fitText(name, item.name, Math.max(0, columnsX[0] - 22 - 4));
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = 22;
            name.y = 2;
            if (item.isFolder) {
                addCell(row, "Folder", columnsX[0], selected);
                addCell(row, "\u2014", columnsX[1], selected);
                addCell(row, "\u2014", columnsX[2], selected);
                assetFolderRects.push({
                    x: listMask.x + row.x, y: listMask.y + row.y,
                    width: width, height: LIST_ROW_HEIGHT, path: item.path
                });
                applyListHover(attachFolderHit(row, item.path, width, LIST_ROW_HEIGHT),
                    surface, selected, item);
            } else if (item.entry != null) {
                var entry = item.entry;
                addCell(row, entry.kindLabel, columnsX[0], selected);
                var details = detailsFor(entry);
                addCell(row, details == null ? "\u2014" : formatSize(details.size), columnsX[1], selected);
                addCell(row, details == null ? "\u2014" : formatDate(details.modified), columnsX[2], selected);
                applyListHover(attachItemHit(row, entry, width, LIST_ROW_HEIGHT),
                    surface, selected, item);
            }
        }
    }

    function addHeaderText(parent:h2d.Object, text:String, x:Float):Void {
        var label = new UiText(ctx.captionFont, parent);
        label.text = text;
        label.textColor = Theme.MUTED;
        label.lineBreak = false;
        label.x = x;
        label.y = 3;
    }

    function addCell(parent:h2d.Object, text:String, x:Float, selected:Bool):Void {
        var label = new UiText(ctx.captionFont, parent);
        label.text = text;
        label.textColor = selected ? Theme.TEXT_SECONDARY : Theme.MUTED;
        label.lineBreak = false;
        label.x = x;
        label.y = 3;
    }

    function iconFor(entry:AssetFileInfo):UiIconKind {
        if (entry.kind == AssetTypeRegistry.KIND_SCENE) return Scene;
        return Document;
    }

    /** Engine assets get a real per-primitive thumbnail; files use atlas glyphs. */
    function drawAssetIcon(g:h2d.Graphics, entry:Null<AssetFileInfo>,
            x:Float, y:Float, size:Float, color:Int):Void {
        if (entry != null && entry.kind == AssetTypeRegistry.KIND_ENGINE) {
            var payload = EngineAssetCatalog.dragPayload(entry);
            PrimitiveThumbnails.draw(g, payload == null ? "" : payload.assetId,
                x, y, size, size, color);
        } else if (entry != null && entry.kind == AssetTypeRegistry.KIND_TEXTURE
                && drawTextureThumb(g, entry.source, x, y, size)) {
            // Grid/list miniature from the same decoded thumbnail cache.
        } else {
            UiIcons.draw(g, entry == null ? Document : iconFor(entry),
                x, y, size, color);
        }
    }

    function attachItemHit(target:h2d.Object, entry:AssetFileInfo,
            width:Float, height:Float):h2d.Interactive {
        var hit = new h2d.Interactive(width, height, target);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        var captured = entry.source;
        hit.onPush = function(event) {
            if (tooltip != null) tooltip.cancel();
            if (event.button == 1) {
                if (!isSelected(captured)) setSelected([captured]);
                buildAssets();
                openContextMenu();
                event.propagate = false;
                return;
            }
            var now = haxe.Timer.stamp();
            var isDouble = captured == lastClickSource && now - lastClickAt <= 0.35;
            lastClickAt = now;
            lastClickSource = captured;
            if (hxd.Key.isDown(hxd.Key.CTRL)) {
                toggleSelection(captured);
            } else if (hxd.Key.isDown(hxd.Key.SHIFT)) {
                selectRange(captured);
            } else {
                setSelected([captured]);
            }
            if (isDouble) {
                buildAssets();
                openSelected();
                event.propagate = false;
                return;
            }
            // Start capture while `hit` is still live. The grid is rebuilt in
            // the release handler; rebuilding here would destroy the capture
            // owner and swallow the release (and every following click).
            beginAssetDrag(captured, hit, event);
            event.propagate = false;
        };
        hit.onWheel = handleGridWheel;
        return hit;
    }

    static function assetTooltipText(item:BrowserItem):String {
        if (item.isFolder) return item.path;
        return item.entry == null ? "" : item.name + "  ·  " + item.entry.source;
    }

    function applyListHover(hit:Null<h2d.Interactive>, surface:UiSurface,
            selected:Bool, item:BrowserItem):Void {
        if (hit == null) return;
        hit.onOver = function(_) {
            if (!selected) surface.setStyle(Theme.SURFACE_3, Theme.ACCENT, 0);
            if (tooltip != null) {
                tooltip.schedule(assetTooltipText(item),
                    ctx.mouseX, ctx.mouseY);
            }
        };
        hit.onOut = function(_) {
            if (!selected) surface.setStyle(Theme.PANEL, Theme.BORDER, 0);
            if (tooltip != null) tooltip.cancel();
        };
    }

    function isSelected(source:String):Bool {
        return selectedSources.indexOf(source) >= 0;
    }

    function setSelected(sources:Array<String>):Void {
        selectedSources.resize(0);
        for (source in sources) if (selectedSources.indexOf(source) < 0) selectedSources.push(source);
        selectedSource = selectedSources.length > 0 ? selectedSources[selectedSources.length - 1] : "";
        // Inspector panel removed; metadata stays in the detail list only.
        refreshTreeSelection();
    }

    /**
     * Restyle existing tree rows in place. Rebuilding the tree here would
     * destroy the Interactive that owns the current drag capture.
     */
    function refreshTreeSelection():Void {
        treeAssetSelected = false;
        for (source in selectedSources) {
            if (!StringTools.startsWith(source, FOLDER_KEY_PREFIX)) {
                treeAssetSelected = true;
                break;
            }
        }
        for (apply in folderRowStyleUpdaters) apply();
    }

    function toggleSelection(source:String):Void {
        if (isSelected(source)) {
            selectedSources.remove(source);
            if (selectedSource == source) {
                selectedSource = selectedSources.length > 0 ? selectedSources[selectedSources.length - 1] : "";
            }
        } else {
            selectedSources.push(source);
            selectedSource = source;
        }
        refreshTreeSelection();
    }

    function selectRange(source:String):Void {
        var end = -1;
        for (index in 0...shownEntries.length) {
            if (shownEntries[index].source == source) end = index;
        }
        if (end < 0) { setSelected([source]); return; }
        var start = 0;
        if (selectedSource != "") {
            for (index in 0...shownEntries.length) {
                if (shownEntries[index].source == selectedSource) { start = index; break; }
            }
        }
        var from = start < end ? start : end;
        var to = start < end ? end : start;
        var range:Array<String> = [];
        for (index in from...to + 1) range.push(shownEntries[index].source);
        setSelected(range);
    }

    function handleGridWheel(event:hxd.Event):Void {
        handleWheelDelta(event.wheelDelta);
        event.propagate = false;
    }

    function handleWheelDelta(delta:Float):Void {
        var over = Math.max(0, contentHeight(shownItems.length) - gridViewportHeight());
        if (over <= 0) {
            if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
                Sys.println('[probe] asset browser grid wheel no-overflow'
                    + ' items=${shownItems.length} viewport=${gridViewportHeight()}');
            }
            return;
        }
        // Windows WM_MOUSEWHEEL: wheel-down is a negative WPARAM. hldx divides
        // by 120 and hxd.Window negates again, so wheel-down arrives here as a
        // positive delta. Adding it moves the viewport toward the end.
        // Use a fixed pixel step: the old 0.12/rows fraction made a notch move
        // less and less as the item count grew, which felt sluggish.
        scrollValue = Math.max(0, Math.min(1,
            scrollValue + delta * WHEEL_STEP / over));
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset browser grid scroll=${scrollValue}'
                + ' delta=${delta}');
        }
        buildAssets();
    }

    /**
     * Move the custom settings popover to the overlay owned by the window that
     * currently hosts this browser. MenuDropdown handles this dynamically via
     * its global overlay layer, but this non-menu popover consists of sibling
     * objects and must be reparented explicitly.
     */
    public function setOverlayParent(parent:h2d.Object):Void {
        if (parent == null || settingsPanel.parent == parent) return;
        closeSettings();
        // Preserve paint/hit order: dismiss catch behind the opaque panel,
        // controls and text above it.
        for (object in [settingsCatch, settingsPanel, settingsViewTitle,
                settingsTitle, settingsSlider, viewGridButton, viewListButton,
                viewDetailsButton, showEngineAssetsCheckbox]) {
            parent.addChild(object);
        }
    }

    public function restoreOverlayParent():Void {
        setOverlayParent(defaultOverlayParent);
    }

    // ------------------------------------------------------------------
    // Drag and drop: direct move on release, Ctrl+drop copies. Folder rows
    // use the same gesture to reparent, matching the scene hierarchy.
    // ------------------------------------------------------------------

    function updateDropTarget():Void {
        var target = folderAt(ctx.mouseX - this.x, ctx.mouseY - this.y);
        if (folderDragSource != "" && target != null
                && (target == folderDragSource
                    || StringTools.startsWith(target, folderDragSource + "/"))) {
            target = null;
        }
        if (target == dropTargetFolder) return;
        dropTargetFolder = target;
        if (target == null) {
            dropHighlight.visible = false;
            return;
        }
        for (rect in assetFolderRects) {
            if (rect.path != target) continue;
            dropHighlight.x = rect.x;
            dropHighlight.y = rect.y;
            dropHighlight.setSize(rect.width, rect.height);
            addChild(dropHighlight);
            dropHighlight.visible = true;
            return;
        }
        var offset = treeScrollOffset();
        for (index in 0...folderRowPaths.length) {
            if (!folderRowIsFolder[index] || folderRowPaths[index] != target) continue;
            dropHighlight.x = 2;
            dropHighlight.y = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT - offset;
            dropHighlight.setSize(folderWidth - 16, ROW_HEIGHT - 2);
            addChild(dropHighlight);
            dropHighlight.visible = true;
            return;
        }
        dropHighlight.visible = false;
    }

    function prepareDragGhost(label:String):Void {
        dragGhost.text = label;
        dragGhostSurface.setSize(Math.max(96,
            Math.round(dragGhost.textWidth + 20)), 22);
        dragGhostSurface.visible = false;
        addChild(dragGhostSurface);
    }

    function moveDragGhost():Void {
        // The shared DragLabelOverlay draws one label in an always-on-top HWND.
        // Keeping this per-browser ghost would duplicate it and disappear under
        // the float's own header, so it stays hidden.
        dragGhostSurface.visible = false;
    }

    function resetDragState():Void {
        UiContext.dragLabel = null;
        dragGhostSurface.visible = false;
        dropHighlight.visible = false;
        dropTargetFolder = null;
        folderDragSource = "";
        dragging = false;
    }

    /**
     * Stop capture through the browser's stable scene, never through the tile
     * that began the gesture. Asset refreshes remove tile Interactives and set
     * their `scene` field to null while SceneEvents can still own the closure.
     */
    function stopDragCapture():Void {
        if (!dragCaptureActive) return;
        // Clear the guard first because SceneEvents.stopCapture() invokes the
        // capture's onCancel callback synchronously.
        dragCaptureActive = false;
        var owner = getScene();
        if (owner != null) owner.stopCapture();
    }

    /** Cosmetic fallback if another widget replaces this capture. */
    function onDragCaptureCancelled():Void {
        if (!dragCaptureActive) return;
        dragCaptureActive = false;
        resetDragState();
        AssetDragSession.cancel();
    }

    function clearDrag():Void {
        stopDragCapture();
        resetDragState();
        buildFolders();
        buildAssets();
        positionRenameOverlay();
    }

    /**
     * Abort the current gesture the same way the docked browser does when the
     * editor window loses focus. Called by the native float host on focus loss;
     * it must not dispatch synthetic H2D events, which re-enters event handling
     * and can leave the panel unresponsive.
     */
    public function abortDrag():Bool {
        var hadDrag = dragCaptureActive || dragging
            || UiContext.dragLabel != null || AssetDragSession.current() != null;
        stopDragCapture();
        resetDragState();
        AssetDragSession.cancel();
        if (hadDrag) {
            buildFolders();
            buildAssets();
            positionRenameOverlay();
        }
        return hadDrag;
    }

    public inline function hasActiveDrag():Bool {
        return dragCaptureActive || dragging;
    }

    function beginAssetDrag(source:String, hit:h2d.Interactive, event:hxd.Event):Void {
        var draggedEntry = findEntry(source);
        var enginePayload = EngineAssetCatalog.dragPayload(draggedEntry);
        if (enginePayload != null) {
            beginEngineAssetDrag(enginePayload, source, hit, event);
            return;
        }
        dragSources = selectedSources.length > 1 ? selectedSources.copy() : [source];
        var labels = dragSources;
        prepareDragGhost(ProjectSession.sceneDisplayName(labels[0])
            + (labels.length > 1 ? ' (+${labels.length - 1})' : ""));
        dragging = false;
        dragStartX = ctx.mouseX;
        dragStartY = ctx.mouseY;
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.mouseX - dragStartX)
                            + Math.abs(ctx.mouseY - dragStartY) > 6) {
                        if (!dragging) UiContext.dragLabel = dragGhost.text;
                        dragging = true;
                    }
                    moveDragGhost();
                    updateDropTarget();
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside:
                    var target = dropTargetFolder;
                    var wasDragging = dragging;
                    var copy = hxd.Key.isDown(hxd.Key.CTRL);
                    UiContext.dragLabel = null;
                    clearDrag();
                    if (wasDragging && target != null) {
                        var mode = copy ? "copy" : "move";
                        Sys.println('[probe] asset browser drop source=${labels[0]}'
                            + ' folder=${target} mode=${mode}');
                        for (item in labels) {
                            if (copy) {
                                if (onCopyAsset != null) onCopyAsset(item, target);
                            } else if (onMoveAsset != null) {
                                onMoveAsset(item, target);
                            }
                        }
                    }
                    capturedEvent.propagate = false;
                case EFocusLost:
                    abortDrag();
                    capturedEvent.propagate = false;
                case _:
                    capturedEvent.propagate = false;
            }
        }, onDragCaptureCancelled);
        dragCaptureActive = true;
    }

    /**
     * Drag an engine asset out of the browser and onto a type-aware Inspector
     * slot. The browser still owns the gesture; AssetDragSession only carries
     * the payload and resolves the drop target under the cursor.
     */
    function beginEngineAssetDrag(payload:AssetDragPayload, source:String,
            hit:h2d.Interactive, event:hxd.Event):Void {
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset drag begin source=${source}'
                + ' at=${Std.int(event.relX)},${Std.int(event.relY)}');
        }
        dragSources = [source];
        prepareDragGhost(payload.label);
        dragging = false;
        dragStartX = ctx.mouseX;
        dragStartY = ctx.mouseY;
        // Don't begin the drag session on press: a plain click must not light
        // up the Inspector slots. The session (and its highlights) starts only
        // once the pointer actually moves far enough to be a drag.
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.mouseX - dragStartX)
                            + Math.abs(ctx.mouseY - dragStartY) > 6) {
                        if (!dragging) {
                            UiContext.dragLabel = payload.label;
                            AssetDragSession.begin(payload);
                        }
                        dragging = true;
                    }
                    // The scene-level capture already delivers moves/releases
                    // everywhere inside the editor. Native SetCapture would
                    // add latency to every move, so it is intentionally unused
                    // for these in-window asset drags.
                    moveDragGhost();
                    if (dragging) {
                        AssetDragSession.update(ctx.mouseX, ctx.mouseY);
                    }
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside:
                    var wasDragging = dragging;
                    var mouseX = ctx.mouseX;
                    var mouseY = ctx.mouseY;
                    // Stop capture FIRST. The drop rebuilds the inspector and
                    // refreshes this browser, which destroys `hit`; calling
                    // stopCapture() afterwards would dereference a dead
                    // Interactive. The payload survives until drop() because
                    // stopDragCapture clears its guard before onCancel runs.
                    stopDragCapture();
                    UiContext.dragLabel = null;
                    if (wasDragging) AssetDragSession.drop(mouseX, mouseY);
                    else AssetDragSession.cancel();
                    dragging = false;
                    capturedEvent.propagate = false;
                case EFocusLost:
                    abortDrag();
                    capturedEvent.propagate = false;
                case _:
                    capturedEvent.propagate = false;
            }
        }, onDragCaptureCancelled);
        dragCaptureActive = true;
    }

    function beginFolderDrag(source:String, hit:h2d.Interactive, event:hxd.Event):Void {
        folderDragSource = source;
        dragSources = [];
        prepareDragGhost(ProjectSession.folderDisplayName(source));
        dragging = false;
        dragStartX = ctx.mouseX;
        dragStartY = ctx.mouseY;
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.mouseX - dragStartX)
                            + Math.abs(ctx.mouseY - dragStartY) > 6) {
                        if (!dragging) UiContext.dragLabel = dragGhost.text;
                        dragging = true;
                    }
                    moveDragGhost();
                    updateDropTarget();
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside:
                    var target = dropTargetFolder;
                    var wasDragging = dragging;
                    UiContext.dragLabel = null;
                    clearDrag();
                    if (wasDragging && target != null) {
                        Sys.println('[probe] asset browser folder drop source=${source}'
                            + ' folder=${target}');
                        if (onMoveFolder != null) onMoveFolder(source, target);
                    }
                    capturedEvent.propagate = false;
                case EFocusLost:
                    abortDrag();
                    capturedEvent.propagate = false;
                case _:
                    capturedEvent.propagate = false;
            }
        }, onDragCaptureCancelled);
        dragCaptureActive = true;
    }

    // ------------------------------------------------------------------
    // Context menus and commands
    // ------------------------------------------------------------------

    function destinationItems(action:String->String->Void):Array<MenuItem> {
        var items:Array<MenuItem> = [];
        var allFolders = onQueryFolders != null ? onQueryFolders() : [];
        for (folder in allFolders) {
            var target = folder;
            items.push({
                label: ProjectSession.folderDisplayName(target),
                onClick: function() action(selectedSource, target)
            });
        }
        if (items.length == 0) items.push({label: "No folders"});
        return items;
    }

    function openContextMenu():Void {
        Sys.println('[probe] asset browser context source=${selectedSource}');
        var entry = findEntry(selectedSource);
        if (entry != null && entry.kind == AssetTypeRegistry.KIND_ENGINE) {
            contextMenu.open(ctx.mouseX, ctx.mouseY, [{
                label: store.isFavorite(selectedSource) ? "Remove Favorite" : "Add to Favorites",
                onClick: function() {
                    store.toggleFavorite(selectedSource);
                    rebuildAll();
                }
            }]);
            return;
        }
        var loadable = entry != null && entry.loadable;
        var moreItems:Array<MenuItem> = [{
            label: "Duplicate",
            onClick: duplicateSelected
        }, {
            label: "Copy",
            onClick: copyToClipboard
        }, {
            label: "Cut",
            onClick: cutToClipboard
        }, {
            label: "Copy Path",
            onClick: function() { if (onCopyAssetPath != null) onCopyAssetPath(selectedSource); }
        }, {
            label: "Reveal in Explorer",
            onClick: function() { if (onRevealAsset != null) onRevealAsset(selectedSource); }
        }, {
            label: store.isFavorite(selectedSource) ? "Remove Favorite" : "Add to Favorites",
            onClick: function() { store.toggleFavorite(selectedSource); rebuildAll(); }
        }];
        contextMenu.open(ctx.mouseX, ctx.mouseY, [{
            label: "Open",
            onClick: openSelected
        }, {
            label: "Rename",
            onClick: beginRenameSelected
        }, {
            label: "More Actions",
            submenu: moreItems
        }, {
            label: "Move To",
            submenu: destinationItems(function(source, folder) {
                if (onMoveAsset != null) onMoveAsset(source, folder);
            })
        }, {
            label: loadable ? "Delete" : "Delete File",
            onClick: deleteSelected
        }]);
    }

    /** Right-click over empty space anywhere in the browser. */
    /** Request an external import; the destination follows browser navigation. */
    function importAssets():Void {
        var folder = isEngineFolder(selectedFolder) ? "" : selectedFolder;
        Sys.println('[probe] asset browser import request folder=${folder}');
        if (onImportAssets != null) onImportAssets(folder);
    }

    /** Shared New... submenu; Folder is first and more kinds can be appended. */
    function newMenuItems(parent:String):Array<MenuItem> {
        return [{
            label: "Folder",
            onClick: function() {
                var created = onNewFolder != null ? onNewFolder(parent) : null;
                if (created != null) {
                    selectedFolder = created;
                    setSelected([]);
                    beginRenameFolder(created);
                }
            }
        }, {
            label: "Scene",
            onClick: function() {
                var target = parent == "" ? "Scenes" : parent;
                if (onNewScene != null) onNewScene(target, "New Scene");
            }
        }, {
            // Last row, matching the toolbar Add menu.
            label: "Import Asset...",
            onClick: function() {
                var folder = isEngineFolder(parent) ? "" : parent;
                Sys.println('[probe] asset browser import request folder=${folder}');
                if (onImportAssets != null) onImportAssets(folder);
            }
        }];
    }

    function openEmptyAreaMenu():Void {
        Sys.println('[probe] asset browser empty menu folder=${selectedFolder}');
        var items:Array<MenuItem> = [{
            label: "New...",
            submenu: newMenuItems(selectedFolder)
        }];
        if (hasClipboard()) {
            items.push({
                label: "Paste",
                onClick: pasteClipboard
            });
        }
        items.push({
            label: "Select All",
            onClick: selectAll
        });
        items.push({
            label: "Refresh",
            onClick: refresh
        });
        // The settings gear is elided on narrow docks; keep view modes and
        // thumbnail size reachable from the context menu in that layout.
        if (toolbarSettingsHidden) {
            items.push({ label: "", separator: true });
            items.push({
                label: "Settings...",
                onClick: openSettings
            });
        }
        contextMenu.open(ctx.mouseX, ctx.mouseY, items);
    }

    function openFolderContextMenu(path:String):Void {
        if (isEngineFolder(path)) {
            contextMenu.open(ctx.mouseX, ctx.mouseY, [{
                label: "Open Engine Assets",
                onClick: function() navigateTo(path)
            }]);
            return;
        }
        var isFavorite = store.isFavorite("__folder__:" + path);
        var isRoot = path == "";
        var items:Array<MenuItem> = [{
            label: "New...",
            submenu: newMenuItems(path)
        }];
        // The content root has no relative path: it cannot be renamed, moved,
        // or deleted, so those actions must not be offered for it.
        if (!isRoot) {
            items.push({
                label: "Rename Folder",
                onClick: function() beginRenameFolder(path)
            });
            items.push({
                label: "Delete Folder",
                onClick: function() {
                    if (onDeleteFolder != null) onDeleteFolder(path, true);
                    Sys.println('[probe] asset browser delete folder request=${path}');
                }
            });
            items.push({
                label: "Move To",
                submenu: destinationItems(function(_, folder) {
                    if (onMoveFolder != null) onMoveFolder(path, folder);
                })
            });
        }
        items.push({
            label: isFavorite ? "Remove Favorite" : "Add to Favorites",
            onClick: function() {
                store.toggleFavorite("__folder__:" + path);
                rebuildAll();
            }
        });
        items.push({
            label: "Copy Path",
            onClick: function() {
                if (onCopyAssetPath != null) onCopyAssetPath(path);
            }
        });
        items.push({
            label: "Reveal in Explorer",
            onClick: function() {
                if (onRevealAsset != null) onRevealAsset(path);
            }
        });
        contextMenu.open(ctx.mouseX, ctx.mouseY, items);
    }

    function openSelected():Void {
        if (selectedSource == "") return;
        Sys.println('[probe] asset browser open source=${selectedSource}');
        var entry = findEntry(selectedSource);
        if (entry != null && entry.kind == AssetTypeRegistry.KIND_ENGINE) {
            showStatus("Engine asset — drag it onto a matching MeshRenderer slot");
            return;
        }
        if (entry == null || !entry.loadable) {
            showStatus("No engine preview for this file type");
            return;
        }
        store.markRecent(selectedSource);
        if (onOpenAsset != null) onOpenAsset(selectedSource);
    }

    function duplicateSelected():Void {
        if (selectedSource == "") return;
        var entry = findEntry(selectedSource);
        if (entry != null && entry.kind == AssetTypeRegistry.KIND_ENGINE) {
            showStatus("Engine assets cannot be duplicated on disk");
            return;
        }
        if (onDuplicateAsset != null) onDuplicateAsset(selectedSource);
    }

    /**
     * True only when a folder tile is explicitly selected in the browser.
     * `selectedFolder` is navigation state (the folder currently being viewed)
     * and must not be treated as a delete target just because the user browsed
     * into it.
     */
    public function hasFolderSelection():Bool {
        return folderFromSelectionKey(selectedSource) != null;
    }

    /** Returns true only when an actual filesystem asset/folder delete was issued. */
    public function deleteSelection():Bool {
        return deleteSelected();
    }

    public function deleteSelectedFolder():Void {
        if (selectedFolder == "" || isEngineFolder(selectedFolder)) return;
        var folder = selectedFolder;
        if (onDeleteFolder != null) onDeleteFolder(folder, true);
        Sys.println('[probe] asset browser delete folder request=${folder}');
    }

    function deleteSelected():Bool {
        if (selectedSources.length == 0) return false;
        var assets:Array<String> = [];
        var folders:Array<String> = [];
        for (key in selectedSources) {
            var entry = findEntry(key);
            if (entry != null && entry.kind == AssetTypeRegistry.KIND_ENGINE) continue;
            var folder = folderFromSelectionKey(key);
            if (folder == null) assets.push(key);
            else if (!isEngineFolder(folder)) folders.push(folder);
        }
        if (assets.length == 0 && folders.length == 0) return false;
        var handled = false;
        // Folder keys are UI-only markers: route them to the folder command so
        // the user never sees "__folder__:" in a confirmation dialog.
        for (folder in folders) {
            if (onDeleteFolder != null) onDeleteFolder(folder, true);
            handled = true;
        }
        if (assets.length > 0) {
            if (onDeleteAssets != null) onDeleteAssets(assets);
            else for (source in assets) if (onDeleteAsset != null) onDeleteAsset(source);
            handled = true;
        }
        return handled;
    }

    // ------------------------------------------------------------------
    // Inline rename
    // ------------------------------------------------------------------

    /** F2 entry point: rename the primary asset, or the selected folder. */
    public function beginRename():Bool {
        if (renaming) return false;
        var selectedFolderKey = folderFromSelectionKey(selectedSource);
        if (selectedFolderKey != null) {
            beginRenameFolder(selectedFolderKey);
            return true;
        }
        if (selectedSource != "") {
            beginRenameSelected();
            return true;
        }
        if (selectedFolder != "") {
            beginRenameFolder(selectedFolder);
            return true;
        }
        return false;
    }

    function selectedName():String {
        var entry = findEntry(selectedSource);
        return entry == null ? "" : entry.name;
    }

    function selectedTile():{ x:Float, y:Float, width:Float, height:Float } {
        for (index in 0...shownEntries.length) {
            if (shownEntries[index].source == selectedSource) {
                var position = tilePosition(index, shownEntries.length);
                return {
                    x: listMask.x + position.x, y: listMask.y + position.y,
                    width: viewMode == 0 ? tileWidth() : centerWidth() - 16,
                    height: viewMode == 0 ? tileHeight() : LIST_ROW_HEIGHT
                };
            }
        }
        return {x: listMask.x + 8, y: listMask.y + 4,
            width: tileWidth(), height: tileHeight()};
    }

    function folderRowRect(folder:String):{ x:Float, y:Float, width:Float, height:Float } {
        var offset = treeScrollOffset();
        for (index in 0...folderRowPaths.length) {
            if (!folderRowIsFolder[index] || folderRowPaths[index] != folder) continue;
            return {
                x: 2, y: TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT - offset,
                width: folderWidth - 16, height: ROW_HEIGHT - 2
            };
        }
        // A folder tile in the main panel can also be renamed after selection.
        for (rect in assetFolderRects) {
            if (rect.path == folder) {
                return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
            }
        }
        return {x: 2, y: TOOLBAR_HEIGHT + 22,
            width: folderWidth - 14, height: ROW_HEIGHT - 2};
    }

    function positionRenameOverlay():Void {
        if (!renaming) return;
        var rect = renamingIsFolder ? folderRowRect(renamingSource) : selectedTile();
        renameSurface.x = rect.x;
        renameSurface.y = rect.y;
        renameSurface.setSize(rect.width, rect.height);
        renameInput.x = rect.x + 3;
        renameInput.y = rect.y + 1;
        renameInput.inputWidth = Std.int(Math.max(0, rect.width - 8));
    }

    function startRename(source:String, name:String, isFolder:Bool):Void {
        Sys.println('[probe] asset browser rename begin source=${source}');
        renaming = true;
        renamingIsFolder = isFolder;
        renamingSource = source;
        renamingOriginal = name;
        renameInput.text = name;
        positionRenameOverlay();
        addChild(renameSurface);
        addChild(renameInput);
        renameSurface.visible = true;
        renameInput.visible = true;
        haxe.Timer.delay(function() {
            if (renaming) renameInput.focus();
        }, 0);
    }

    function beginRenameSelected():Void {
        if (selectedSource == "") return;
        startRename(selectedSource, selectedName(), false);
    }

    function beginRenameFolder(folder:String):Void {
        startRename(folder, ProjectSession.folderDisplayName(folder), true);
    }

    function commitRename():Void {
        if (!renaming) return;
        var value = StringTools.trim(renameInput.text);
        var source = renamingSource;
        var original = renamingOriginal;
        var isFolder = renamingIsFolder;
        renaming = false;
        renameInput.visible = false;
        renameSurface.visible = false;
        clearRenameFocus();
        if (value.length == 0) value = original;
        if (value == original) return;
        if (isFolder) {
            if (onRenameFolder != null) onRenameFolder(source, value);
        } else if (onRenameAsset != null) {
            onRenameAsset(source, value);
        }
    }

    function cancelRename():Void {
        if (!renaming) return;
        var original = renamingOriginal;
        renaming = false;
        renameInput.text = original;
        renameInput.visible = false;
        renameSurface.visible = false;
        clearRenameFocus();
    }

    function clearRenameFocus():Void {
        var scene = getScene();
        if (scene == null) return;
        var focused = scene.getFocus();
        if (focused != null) focused.blur();
    }

    // ------------------------------------------------------------------
    // Shared helpers
    // ------------------------------------------------------------------

    function rebuildAll():Void {
        buildFolders();
        buildAssets();
        // Inspector panel removed; metadata stays in the detail list only.
        updateToolbarState();
    }

    function clearRows(rows:Array<h2d.Object>):Void {
        for (row in rows) row.remove();
        rows.resize(0);
    }

    /** Pixel-accurate elision: no label may cross its panel or cell edge. */
    static function fitText(target:UiText, value:String, available:Float):Void {
        if (available <= 0) {
            target.text = "";
            return;
        }
        target.text = value;
        if (target.calcTextWidth(value) <= available) return;
        target.text = "";
        for (i in 0...value.length) {
            var candidate = value.substr(0, i + 1) + "\u2026";
            if (target.calcTextWidth(candidate) > available) break;
            target.text = candidate;
        }
    }

    static function shade(color:Int, factor:Float):Int {
        var r = Std.int(Math.max(0, Math.min(255, Math.round(((color >> 16) & 0xFF) * factor))));
        var g = Std.int(Math.max(0, Math.min(255, Math.round(((color >> 8) & 0xFF) * factor))));
        var b = Std.int(Math.max(0, Math.min(255, Math.round((color & 0xFF) * factor))));
        return (r << 16) | (g << 8) | b;
    }

    /** Brief, self-hiding message for errors that have no other UI surface. */
    function showStatus(message:String):Void {
        statusMessage = message;
        fitStatusText();
        statusText.visible = true;
        haxe.Timer.delay(function() {
            if (statusMessage == message) statusText.visible = false;
        }, 2400);
    }

    function fitStatusText():Void {
        fitText(statusText, statusMessage,
            Math.max(0, widthValue - statusText.x - TOOLBAR_EDGE));
    }

    static function formatSize(bytes:Int):String {
        if (bytes < 0) return "\u2014";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB";
        return Math.round(bytes / (1024 * 1024)) + " MB";
    }

    static function formatDate(epoch:Float):String {
        if (epoch < 0) return "\u2014";
        var date = Date.fromTime(epoch * 1000);
        var month = date.getMonth() + 1;
        var day = date.getDate();
        return date.getFullYear() + "-"
            + (month < 10 ? "0" : "") + month + "-"
            + (day < 10 ? "0" : "") + day;
    }
}
