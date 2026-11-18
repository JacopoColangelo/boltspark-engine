package boltspark.ui.widgets;

import boltspark.project.AssetTypeRegistry;
import boltspark.project.ProjectSession;
import boltspark.project.ProjectSession.AssetDetails;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.Theme;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;
import boltspark.ui.widgets.MenuDropdown.MenuItem;
import boltspark.ui.widgets.UiSlider;
import hxd.Key;

typedef FolderNode = {
    var name:String;
    var path:String;
    var children:Array<FolderNode>;
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
    public var onDuplicateAsset:Null<String->Void>;
    public var onDeleteFolder:Null<String->Bool->Void>;
    public var onMoveFolder:Null<String->String->Void>;
    public var onRevealAsset:Null<String->Void>;
    public var onCopyAssetPath:Null<String->Void>;

    static inline var TOOLBAR_HEIGHT:Float = 26;
    /** The three navigation hits occupy x=4..74 inside the toolbar. */
    static inline var NAV_CLUSTER_END:Float = 76;
    static inline var TOOLBAR_EDGE:Float = 4;
    static inline var TOOLBAR_GAP:Float = 4;
    /** Icon-only toolbar control width (UiButton elides its label below 39 px). */
    static inline var ICON_CONTROL_WIDTH:Float = 26;
    static inline var SEARCH_MIN_WIDTH:Float = 64;
    static inline var SEARCH_MAX_WIDTH:Float = 240;

    static inline var ROW_HEIGHT:Float = 22;
    static inline var LIST_ROW_HEIGHT:Float = 20;
    static inline var TILE_GAP:Float = 8;
    /** Space reserved under a grid preview for its name. */
    static inline var TILE_LABEL_HEIGHT:Float = 20;
    static inline var DETAILS_NAME_WIDTH:Float = 168;
    static inline var DETAILS_COL_WIDTH:Float = 72;

    final ctx:UiContext;
    final store:AssetBrowserStore;
    final background:UiSurface;
    final emptyAreaHit:h2d.Interactive;
    final toolbar:UiSurface;
    final titleText:UiText;
    final folderText:UiText;
    final statusText:UiText;
    final addButton:UiButton;
    final addMenu:MenuDropdown;
    final folderSurface:UiSurface;
    final folderTitle:UiText;
    final folderSplitter:h2d.Interactive;
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
    final settingsHeader:UiSurface;
    final settingsDivider:UiSurface;
    final settingsCatch:h2d.Interactive;
    final settingsViewTitle:UiText;
    final settingsTitle:UiText;
    final settingsSlider:UiSlider;
    var settingsOpen:Bool = false;
    final favoriteHeaderStar:h2d.Graphics;
    final favoriteHeaderHit:h2d.Interactive;
    final filterMenu:MenuDropdown;
    final sortMenu:MenuDropdown;
    final favoriteMenu:MenuDropdown;
    final contextMenu:MenuDropdown;

    final renameSurface:UiSurface;
    final renameInput:UiTextInput;
    final dragGhost:UiText;
    final dropHighlight:UiSurface;
    final breadcrumbObjects:Array<h2d.Object> = [];

    var entries:Array<AssetFileInfo> = [];
    var folders:Array<String> = [];
    var folderRows:Array<h2d.Object> = [];
    var folderRowPaths:Array<String> = [];
    final expandedFolders:Map<String, Bool> = [];
    var assetRows:Array<h2d.Object> = [];
    var shownEntries:Array<AssetFileInfo> = [];

    var selectedSources:Array<String> = [];
    var selectedSource:String = "";
    var selectedFolder:String = "";
    var folderHistory:Array<String> = [""];
    var folderHistoryIndex:Int = 0;

    var searchText:String = "";
    var statusMessage:String = "";
    var typeFilter:String = "all";
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
        store = new AssetBrowserStore();
        var loadError = store.load();
        if (loadError != null) Sys.println('[probe] asset browser store load=${loadError}');
        viewMode = store.viewMode;
        thumbnailSize = store.thumbnailSize;
        sortKey = store.sortKey;
        sortAsc = store.sortAsc;
        typeFilter = store.typeFilter;
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
        filterButton = new UiButton(ctx, "All", 90, 20, this);
        filterButton.setIcon(Filter);
        filterButton.setIconSize(14);
        filterButton.onClick = openFilterMenu;
        sortButton = new UiButton(ctx, "Name \u2191", 96, 20, this);
        sortButton.setIcon(Sort);
        sortButton.setIconSize(14);
        sortButton.onClick = openSortMenu;

        // View modes live in the settings popover, not the toolbar. Framed
        // buttons read as one aligned segmented control (quiet buttons would
        // leave bare icons next to a bordered selected one).
        viewGridButton = makeIconButton(menus, function() setViewMode(0), Grid).setQuiet(false);
        viewListButton = makeIconButton(menus, function() setViewMode(1), List).setQuiet(false);
        viewDetailsButton = makeIconButton(menus, function() setViewMode(2), Table).setQuiet(false);
        settingsButton = makeIconButton(this, openSettings, Settings);

        settingsCatch = new h2d.Interactive(1, 1, menus);
        settingsCatch.backgroundColor = 0;
        // The full-window dismiss catch must not show the pointing-hand cursor
        // through transparent parts of the settings popover.
        settingsCatch.cursor = hxd.Cursor.Default;
        settingsCatch.onPush = function(event) {
            event.propagate = false;
            closeSettings();
        };
        settingsPanel = new UiSurface(ctx, menus);
        settingsPanel.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        settingsHeader = new UiSurface(ctx, menus);
        settingsHeader.setStyle(Theme.PANEL_HEADER, Theme.BORDER, 0);
        settingsDivider = new UiSurface(ctx, menus);
        settingsDivider.setStyle(Theme.BORDER, Theme.BORDER, 0, 0);
        settingsViewTitle = new UiText(ctx.semiboldFont, menus);
        settingsViewTitle.text = "Asset Browser Settings";
        settingsViewTitle.textColor = Theme.TEXT;
        settingsViewTitle.lineBreak = false;
        settingsTitle = new UiText(ctx.semiboldFont, menus);
        settingsTitle.text = "Thumbnail size";
        settingsTitle.textColor = Theme.TEXT;
        settingsTitle.lineBreak = false;
        settingsSlider = new UiSlider(ctx, SETTINGS_WIDTH - 24,
            THUMB_MIN, THUMB_MAX, thumbnailSize, " px", menus);
        settingsSlider.onChange = function(value) {
            thumbnailSize = Std.int(value);
            store.thumbnailSize = thumbnailSize;
            refreshLayout();
        };
        // The popover surface was created after the buttons; lift them above it.
        menus.addChild(viewGridButton);
        menus.addChild(viewListButton);
        menus.addChild(viewDetailsButton);
        settingsCatch.visible = false;
        settingsPanel.visible = false;
        settingsHeader.visible = false;
        settingsDivider.visible = false;
        settingsViewTitle.visible = false;
        settingsTitle.visible = false;
        settingsSlider.visible = false;
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
            }]);
        };
        addMenu = new MenuDropdown(ctx, menus);

        filterMenu = new MenuDropdown(ctx, menus);
        sortMenu = new MenuDropdown(ctx, menus);
        favoriteMenu = new MenuDropdown(ctx, menus);
        contextMenu = new MenuDropdown(ctx, menus);

        folderSurface = new UiSurface(ctx, this);
        folderSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER, 0);
        folderSplitter = new h2d.Interactive(5, 1, this);
        folderSplitter.backgroundColor = 0;
        folderSplitter.cursor = ctx.resizeHorizontal;
        folderSplitter.onOut = function(_) ctx.restoreArrowCursor();
        folderSplitter.onPush = function(_) beginFolderSplitterDrag();

        folderTitle = new UiText(ctx.captionFont, this);
        folderTitle.text = "FOLDERS";
        folderTitle.textColor = Theme.MUTED;
        folderTitle.lineBreak = false;

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

        dragGhost = new UiText(ctx.captionFont, this);
        dragGhost.textColor = Theme.ACCENT;
        dragGhost.lineBreak = false;
        dragGhost.visible = false;

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
    }

    /** Ctrl+C: remember the selection for a later paste. */
    public function copyToClipboard():Void {
        if (selectedSource == "") return;
        clipboardSource = selectedSource;
        clipboardIsCut = false;
        Sys.println('[probe] asset browser clipboard copy=${selectedSource}');
    }

    /** Ctrl+X: remember the selection for a move-on-paste. */
    public function cutToClipboard():Void {
        if (selectedSource == "") return;
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
        Sys.println('[probe] asset browser paste source=${source} folder=${target} cut=${isCut}');
        if (isCut) {
            clipboardSource = "";
            for (item in selectedSources) if (onMoveAsset != null) onMoveAsset(item, target);
            if (selectedSources.length == 0 && onMoveAsset != null) onMoveAsset(source, target);
        } else if (onCopyAsset != null) {
            for (item in selectedSources) onCopyAsset(item, target);
            if (selectedSources.length == 0) onCopyAsset(source, target);
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
        entries = onQueryAssets != null ? onQueryAssets() : [];
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
        fitText(folderTitle, "FOLDERS", Math.max(0, folderWidth - 12));

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
        folderSplitter.x = folderWidth - 2;
        folderSplitter.y = TOOLBAR_HEIGHT;
        folderSplitter.width = 5;
        folderSplitter.height = Math.max(0, heightValue - TOOLBAR_HEIGHT);
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

    function beginFolderSplitterDrag():Void {
        var startX = ctx.window.mouseX;
        var startWidth = preferredFolderWidth;
        var maxWidth = maxFolderWidth();
        var minWidth = Math.min(MIN_FOLDER_WIDTH, maxWidth);
        folderSplitter.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    preferredFolderWidth = Math.max(minWidth,
                        Math.min(maxWidth,
                            startWidth + (ctx.window.mouseX - startX)));
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
        var filterWidth = 90.0;
        var sortWidth = 96.0;
        var searchWidth = Math.min(SEARCH_MAX_WIDTH,
            Math.max(130, widthValue * 0.26));

        function clusterWidth():Float {
            var result = searchWidth;
            if (showAdd) result += addWidth + TOOLBAR_GAP;
            if (showSettings) result += settingsWidth + TOOLBAR_GAP;
            if (showFilters) result += filterWidth + sortWidth + TOOLBAR_GAP * 2;
            return result;
        }

        // Full labels, then icon-only filter/sort, then a compact Add with the
        // minimum search field, then drop nav, and finally the filter/sort icons.
        if (clusterWidth() > available) {
            filterWidth = ICON_CONTROL_WIDTH;
            sortWidth = ICON_CONTROL_WIDTH;
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
        searchField.x = place(searchWidth);
        searchField.y = 3;
        searchField.setWidth(searchWidth);

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
        var items:Array<MenuItem> = [];
        var options = [
            {key: "all", label: "All assets"},
            {key: AssetTypeRegistry.KIND_SCENE, label: AssetTypeRegistry.SCENE_INFO_LABEL},
            {key: AssetTypeRegistry.KIND_FILE, label: AssetTypeRegistry.FILE_INFO_LABEL},
            {key: "favorites", label: "Favorites"},
            {key: "recent", label: "Recent"}
        ];
        for (option in options) {
            var captured = option.key;
            items.push({
                label: option.label,
                selected: typeFilter == captured,
                onClick: function() {
                    typeFilter = captured;
                    store.typeFilter = typeFilter;
                    store.save();
                    scrollValue = 0;
                    rebuildAll();
                }
            });
        }
        filterMenu.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    function openSortMenu():Void {
        var names = ["Name", "Type", "Size", "Modified"];
        var items:Array<MenuItem> = [];
        for (index in 0...names.length) {
            var capturedIndex = index;
            items.push({
                label: names[index] + (sortKey == index
                    ? (sortAsc ? "  \u2191" : "  \u2193") : ""),
                selected: sortKey == index,
                onClick: function() {
                    if (sortKey == capturedIndex) sortAsc = !sortAsc;
                    else { sortKey = capturedIndex; sortAsc = true; }
                    saveViewState();
                    rebuildAll();
                }
            });
        }
        sortMenu.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    static inline var THUMB_MIN:Int = 64;
    static inline var THUMB_MAX:Int = 192;
    static inline var SETTINGS_WIDTH:Float = 242;
    static inline var SETTINGS_HEIGHT:Float = 150;

    function openSettings():Void {
        if (settingsOpen) {
            closeSettings();
            return;
        }
        settingsOpen = true;
        settingsCatch.width = ctx.width;
        settingsCatch.height = ctx.height;
        settingsCatch.visible = true;
        // The toolbar button is hidden on narrow docks; anchor the popover to
        // the invoking pointer instead of a stale offscreen button position.
        var px = toolbarSettingsHidden
            ? ctx.window.mouseX - SETTINGS_WIDTH * 0.5
            : this.x + settingsButton.x - 96;
        var py = this.y + TOOLBAR_HEIGHT;
        settingsPanel.x = Math.max(4, Math.min(px, ctx.width - SETTINGS_WIDTH - 4));
        settingsPanel.y = Math.max(4, Math.min(py, ctx.height - SETTINGS_HEIGHT - 4));
        settingsPanel.setSize(SETTINGS_WIDTH, SETTINGS_HEIGHT);
        settingsHeader.x = settingsPanel.x;
        settingsHeader.y = settingsPanel.y;
        settingsHeader.setSize(SETTINGS_WIDTH, 28);
        settingsDivider.x = settingsPanel.x + 12;
        settingsDivider.y = settingsPanel.y + 72;
        settingsDivider.setSize(SETTINGS_WIDTH - 24, 1);
        settingsViewTitle.x = settingsPanel.x + 12;
        settingsViewTitle.y = settingsPanel.y + 5;
        for (index in 0...3) {
            var button = [viewGridButton, viewListButton, viewDetailsButton][index];
            button.x = settingsPanel.x + 12 + index * 30;
            button.y = settingsPanel.y + 38;
            button.visible = true;
        }
        settingsTitle.x = settingsPanel.x + 12;
        settingsTitle.y = settingsPanel.y + 86;
        settingsSlider.setWidth(SETTINGS_WIDTH - 24);
        settingsSlider.x = settingsPanel.x + 12;
        settingsSlider.y = settingsPanel.y + 108;
        settingsPanel.visible = true;
        settingsHeader.visible = true;
        settingsDivider.visible = true;
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
        settingsHeader.visible = false;
        settingsDivider.visible = false;
        settingsViewTitle.visible = false;
        settingsTitle.visible = false;
        settingsSlider.visible = false;
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
        favoriteMenu.open(ctx.window.mouseX, ctx.window.mouseY, items);
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
        filterButton.setText(typeFilter == "all" ? "All"
            : typeFilter == "favorites" ? "Favorites"
            : typeFilter == "recent" ? "Recent"
            : typeFilter == AssetTypeRegistry.KIND_SCENE ? "Scenes" : "Files");
        var sortNames = ["Name", "Type", "Size", "Modified"];
        sortButton.setText(sortNames[sortKey] + (sortAsc ? " \u2191" : " \u2193"));
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
        var parts = selectedFolder == "" ? ["Content"] : ["Content"].concat(selectedFolder.split("/"));
        var prefix = "";
        var x = 82.0;
        for (index in 0...parts.length) {
            var slash:Null<UiText> = null;
            if (index > 0) {
                slash = new UiText(ctx.captionFont, this);
                slash.text = "/";
                slash.textColor = Theme.DISABLED;
                slash.lineBreak = false;
                slash.x = x;
                slash.y = 6;
                x += 8;
            }
            if (index > 0) prefix = prefix == "" ? parts[index] : prefix + "/" + parts[index];
            var target = index == 0 ? "" : prefix;
            var isLast = index == parts.length - 1;
            var label = new UiText(ctx.captionFont, this);
            label.text = parts[index];
            label.textColor = isLast ? Theme.TEXT : Theme.MUTED;
            label.lineBreak = false;
            label.x = x;
            label.y = 6;
            // A label that does not fit must be removed, not just skipped:
            // h2d objects are attached on construction and would otherwise
            // stay visible and leak on every narrow-layout rebuild.
            if (x + label.textWidth > availableWidth) {
                label.remove();
                if (slash != null) slash.remove();
                break;
            }
            if (slash != null) breadcrumbObjects.push(slash);
            var hit = new h2d.Interactive(label.textWidth + 2, 16, this);
            hit.x = x;
            hit.y = 3;
            hit.backgroundColor = 0;
            hit.cursor = hxd.Cursor.Default;
            var captured = target;
            hit.onPush = function(event) {
                event.propagate = false;
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
        return switch (typeFilter) {
            case "all": true;
            case "favorites": store.isFavorite(entry.source);
            case "recent": store.recent.indexOf(entry.source) >= 0;
            case other: entry.kind == other;
        };
    }

    function visibleEntries():Array<AssetFileInfo> {
        var result:Array<AssetFileInfo> = [];
        for (entry in entries) {
            if (selectedFolder != "" && entry.folder != selectedFolder) continue;
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
        shownEntries = result;
        return result;
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

    function buildFolderTree():Array<FolderNode> {
        var roots:Array<FolderNode> = [];
        for (path in folders) {
            var parts = path.split("/");
            var level = roots;
            var prefix = "";
            for (index in 0...parts.length) {
                var part = parts[index];
                prefix = index == 0 ? part : prefix + "/" + part;
                var node:Null<FolderNode> = null;
                for (candidate in level) {
                    if (candidate.name == part) { node = candidate; break; }
                }
                if (node == null) {
                    node = {name: part, path: prefix, children: []};
                    level.push(node);
                }
                level = node.children;
            }
        }
        sortFolderNodes(roots);
        return roots;
    }

    static function sortFolderNodes(nodes:Array<FolderNode>):Void {
        nodes.sort(function(a, b) return a.name < b.name ? -1 : (a.name == b.name ? 0 : 1));
        for (node in nodes) sortFolderNodes(node.children);
    }

    function isExpanded(path:String):Bool {
        return expandedFolders.exists(path) ? expandedFolders.get(path) : true;
    }

    function buildFolders():Void {
        clearRows(folderRows);
        folderRowPaths.resize(0);
        var all = makeFolderRow("All", "", selectedFolder == "", 0, false);
        all.y = TOOLBAR_HEIGHT + 22;
        folderRows.push(all);
        folderRowPaths.push("");
        var index = 1;
        for (node in buildFolderTree()) index = renderFolderNode(node, 0, index);
    }

    function renderFolderNode(node:FolderNode, depth:Int, index:Int):Int {
        var hasChildren = node.children.length > 0;
        var maxRows = Std.int(Math.max(1, (heightValue - TOOLBAR_HEIGHT - 26) / ROW_HEIGHT));
        if (index > maxRows) return index;
        var row = makeFolderRow(node.name,
            node.path, selectedFolder == node.path, depth, hasChildren);
        row.y = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT;
        folderRows.push(row);
        folderRowPaths.push(node.path);
        index++;
        if (hasChildren && isExpanded(node.path)) {
            for (child in node.children) index = renderFolderNode(child, depth + 1, index);
        }
        return index;
    }

    function makeFolderRow(display:String, path:String, selected:Bool,
            depth:Int, hasChildren:Bool):h2d.Object {
        var row = new h2d.Object(this);
        row.x = 2;
        var surface = new UiSurface(ctx, row);
        surface.setSize(folderWidth - 4, ROW_HEIGHT - 2);
        surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT,
            selected ? Theme.ACCENT : Theme.BORDER, 0);

        var hit = new h2d.Interactive(folderWidth - 4, ROW_HEIGHT - 2, row);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        hit.onPush = function(event) {
            event.propagate = false;
            // Record navigation (history + breadcrumb) without rebuilding the
            // rows: the hit that starts capture must stay alive for the drag.
            setFolderState(path, true);
            if (event.button != 1) {
                if (path != "") {
                    beginFolderDrag(path, hit, event);
                } else {
                    buildFolders();
                    buildAssets();
                }
                return;
            }
            buildFolders();
            buildAssets();
            openFolderContextMenu(path);
        };
        hit.onWheel = function(event) {
            handleGridWheel(event);
        };

        // The chevron lives in a fixed gutter, so every depth level shifts the
        // folder icon and label by the same amount. On a very narrow folder
        // column the icon gutter is dropped so the label still fits.
        var compactRow = folderWidth < 90;
        var iconX = 20 + depth * 14;
        if (!compactRow) {
            var icon = new h2d.Graphics(row);
            UiIcons.draw(icon, Folder, iconX, 3, 14,
                selected ? Theme.ACCENT : Theme.MUTED);
        }
        var probeName = path == "" ? "All" : path.split("/")[path.split("/").length - 1];
        Sys.println('[probe] asset browser folder row=${probeName} depth=${depth}');
        var labelX = compactRow ? 6 : iconX + 18;
        var label = new UiText(ctx.font, row);
        fitText(label, display, Math.max(0, folderWidth - labelX - 6));
        label.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
        label.lineBreak = false;
        label.x = labelX;
        label.y = 3;

        if (hasChildren && path != "" && !compactRow) {
            var chevron = new h2d.Graphics(row);
            UiIcons.draw(chevron, isExpanded(path) ? ChevronDown : ChevronRight,
                4, 6, 9, Theme.MUTED);
            var chevronHit = new h2d.Interactive(14, ROW_HEIGHT - 2, row);
            chevronHit.x = 2;
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

    function folderAt(x:Float, y:Float):Null<String> {
        if (x < 0 || x > folderWidth) return null;
        for (index in 0...folderRowPaths.length) {
            var rowY = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT;
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
        var shown = visibleEntries();
        var content = contentHeight(shown.length);
        var view = gridViewportHeight();
        var ratio = content <= 0 ? 1.0 : Math.min(1.0, view / content);
        if (ratio < 1) Sys.println('[probe] asset browser scrollable=true tiles=${shown.length}');
        gridScroll.setMetrics(ratio, scrollValue);
        gridScroll.setBounds(Math.max(0, folderWidth + centerWidth() - 10),
            TOOLBAR_HEIGHT + 2, 6, Math.max(0, view - 4));

        switch (viewMode) {
            case 1: buildCompactList(shown);
            case 2: buildDetailsList(shown);
            default: buildGrid(shown);
        }

        // No persistent status sentence under the grid: selection is visible on
        // the tiles themselves, and transient messages use showStatus().
    }

    function buildGrid(shown:Array<AssetFileInfo>):Void {
        var width = tileWidth();
        var height = tileHeight();
        var previewHeight = Math.max(30, height - TILE_LABEL_HEIGHT - 6);
        for (index in 0...shown.length) {
            var entry = shown[index];
            var position = tilePosition(index, shown.length);
            if (position.y + height < 0 || position.y > gridViewportHeight()) continue;
            var tile = new h2d.Object(listMask);
            tile.x = position.x;
            tile.y = position.y;
            assetRows.push(tile);

            var selected = isSelected(entry.source);
            var preview = new h2d.Graphics(tile);
            drawPreview(preview, entry, 4, 2, width - 8, previewHeight, selected);

            var name = new UiText(ctx.captionFont, tile);
            fitText(name, entry.name, Math.max(0, width - 8));
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = Math.max(2, Math.round((width - name.textWidth) * 0.5));
            name.y = height - 17;

            if (store.isFavorite(entry.source)) {
                var star = new h2d.Graphics(tile);
                UiIcons.draw(star, Star, width - 19, 3, 12, Theme.WARNING);
            }
            attachItemHit(tile, entry, width, height);
        }
    }

    /** Large preview tile. Scenes use Tabler's `outline/photo` glyph - a framed
     *  landscape is the familiar shorthand for a level/scene thumbnail - and
     *  generic files keep a neutral document glyph. Both scale with the
     *  thumbnail-size slider. */
    function drawPreview(g:h2d.Graphics, entry:AssetFileInfo,
            x:Float, y:Float, w:Float, h:Float, selected:Bool):Void {
        g.beginFill(selected ? 0x245045 : Theme.SURFACE_1);
        g.drawRect(x, y, w, h);
        g.endFill();
        g.lineStyle(1, selected ? Theme.ACCENT : Theme.SURFACE_3);
        g.drawRect(x + 0.5, y + 0.5, w - 1, h - 1);
        g.lineStyle(0);

        var cx = x + w * 0.5;
        var cy = y + h * 0.5;
        if (entry.loadable) {
            var iconSize = Math.min(w, h) * 0.68;
            UiIcons.drawSceneThumb(g, cx - iconSize * 0.5, cy - iconSize * 0.5,
                iconSize, selected ? Theme.ACCENT : Theme.TEXT_SECONDARY);
        } else {
            var base = 0x7A8794;
            var pw = Math.min(w * 0.42, h * 0.58);
            var ph = pw * 1.3;
            var px = cx - pw * 0.5;
            var py = y + (h - ph) * 0.5;
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
            g.drawCircle(x + 9, y + 9, 3);
            g.endFill();
        }
    }

    function buildCompactList(shown:Array<AssetFileInfo>):Void {
        var width = Math.max(100, centerWidth() - 16);
        for (index in 0...shown.length) {
            var entry = shown[index];
            var position = tilePosition(index, shown.length);
            if (position.y + LIST_ROW_HEIGHT < 0 || position.y > gridViewportHeight()) continue;
            var row = new h2d.Object(listMask);
            row.x = position.x;
            row.y = position.y;
            assetRows.push(row);
            var selected = isSelected(entry.source);
            var surface = new UiSurface(ctx, row);
            surface.setSize(width, LIST_ROW_HEIGHT);
            surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL,
                selected ? Theme.ACCENT : Theme.BORDER, 0);
            var icon = new h2d.Graphics(row);
            UiIcons.draw(icon, iconFor(entry), 5, 3, 14,
                selected ? Theme.ACCENT : entry.loadable ? Theme.TEXT_SECONDARY : Theme.MUTED);
            var type = new UiText(ctx.captionFont, row);
            type.text = entry.kindLabel;
            type.textColor = Theme.MUTED;
            type.lineBreak = false;
            type.x = Math.max(0, width - type.textWidth - 8);
            type.y = 3;
            var name = new UiText(ctx.font, row);
            fitText(name, entry.name, Math.max(0, type.x - 24 - 4));
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = 24;
            name.y = 2;
            attachItemHit(row, entry, width, LIST_ROW_HEIGHT);
        }
    }

    function buildDetailsList(shown:Array<AssetFileInfo>):Void {
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
            var entry = shown[index];
            var position = tilePosition(index, shown.length);
            var y = position.y + LIST_ROW_HEIGHT + 2;
            if (y + LIST_ROW_HEIGHT < 0 || y > gridViewportHeight()) continue;
            var row = new h2d.Object(listMask);
            row.x = 8;
            row.y = y;
            assetRows.push(row);
            var selected = isSelected(entry.source);
            var surface = new UiSurface(ctx, row);
            surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL,
                selected ? Theme.ACCENT : Theme.BORDER, 0);
            surface.setSize(width, LIST_ROW_HEIGHT);
            var icon = new h2d.Graphics(row);
            UiIcons.draw(icon, iconFor(entry), 4, 3, 14,
                selected ? Theme.ACCENT : entry.loadable ? Theme.TEXT_SECONDARY : Theme.MUTED);
            var name = new UiText(ctx.font, row);
            fitText(name, entry.name, Math.max(0, columnsX[0] - 22 - 4));
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = 22;
            name.y = 2;
            addCell(row, entry.kindLabel, columnsX[0], selected);
            var details = detailsFor(entry);
            addCell(row, details == null ? "\u2014" : formatSize(details.size), columnsX[1], selected);
            addCell(row, details == null ? "\u2014" : formatDate(details.modified), columnsX[2], selected);
            attachItemHit(row, entry, width, LIST_ROW_HEIGHT);
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

    function attachItemHit(target:h2d.Object, entry:AssetFileInfo,
            width:Float, height:Float):Void {
        var hit = new h2d.Interactive(width, height, target);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        var captured = entry.source;
        hit.onPush = function(event) {
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
    }

    function isSelected(source:String):Bool {
        return selectedSources.indexOf(source) >= 0;
    }

    function setSelected(sources:Array<String>):Void {
        selectedSources.resize(0);
        for (source in sources) if (selectedSources.indexOf(source) < 0) selectedSources.push(source);
        selectedSource = selectedSources.length > 0 ? selectedSources[selectedSources.length - 1] : "";
        // Inspector panel removed; metadata stays in the detail list only.
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
        var over = Math.max(0, contentHeight(shownEntries.length) - gridViewportHeight());
        if (over <= 0) return;
        var rows = viewMode == 0
            ? Math.max(1, Math.ceil(shownEntries.length / Math.max(1, gridColumns())))
            : Math.max(1, shownEntries.length);
        // Windows WM_MOUSEWHEEL: wheel-down is a negative WPARAM. hldx divides
        // by 120 and hxd.Window negates again, so wheel-down arrives here as a
        // positive delta. Adding it moves the viewport toward the end.
        scrollValue = Math.max(0, Math.min(1, scrollValue + delta * 0.12 / rows));
        Sys.println('[probe] asset browser scroll=${scrollValue} delta=${delta}');
        buildAssets();
    }

    // ------------------------------------------------------------------
    // Drag and drop: direct move on release, Ctrl+drop copies. Folder rows
    // use the same gesture to reparent, matching the scene hierarchy.
    // ------------------------------------------------------------------

    function updateDropTarget():Void {
        var target = folderAt(ctx.window.mouseX - this.x, ctx.window.mouseY - this.y);
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
        for (index in 0...folderRowPaths.length) {
            if (folderRowPaths[index] != target) continue;
            dropHighlight.x = 2;
            dropHighlight.y = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT;
            dropHighlight.setSize(folderWidth - 4, ROW_HEIGHT - 2);
            addChild(dropHighlight);
            dropHighlight.visible = true;
            return;
        }
        dropHighlight.visible = false;
    }

    function clearDrag(hit:h2d.Interactive):Void {
        dragGhost.visible = false;
        dropHighlight.visible = false;
        dropTargetFolder = null;
        folderDragSource = "";
        dragging = false;
        hit.stopCapture();
        buildFolders();
        buildAssets();
        positionRenameOverlay();
    }

    function beginAssetDrag(source:String, hit:h2d.Interactive, event:hxd.Event):Void {
        dragSources = selectedSources.length > 1 ? selectedSources.copy() : [source];
        var labels = dragSources;
        dragGhost.text = ProjectSession.sceneDisplayName(labels[0])
            + (labels.length > 1 ? ' (+${labels.length - 1})' : "");
        addChild(dragGhost);
        // A plain click must never show the floating drag label.
        dragGhost.visible = false;
        dragGhost.x = event.relX + 10;
        dragGhost.y = event.relY + 8;
        dragging = false;
        dragStartX = ctx.window.mouseX;
        dragStartY = ctx.window.mouseY;
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.window.mouseX - dragStartX)
                            + Math.abs(ctx.window.mouseY - dragStartY) > 6) {
                        if (!dragging) dragGhost.visible = true;
                        dragging = true;
                    }
                    dragGhost.x = ctx.window.mouseX - this.x + 10;
                    dragGhost.y = ctx.window.mouseY - this.y + 8;
                    updateDropTarget();
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    var target = dropTargetFolder;
                    var wasDragging = dragging;
                    var copy = hxd.Key.isDown(hxd.Key.CTRL);
                    clearDrag(hit);
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
                case _:
                    capturedEvent.propagate = false;
            }
        });
    }

    function beginFolderDrag(source:String, hit:h2d.Interactive, event:hxd.Event):Void {
        folderDragSource = source;
        dragSources = [];
        dragGhost.text = ProjectSession.folderDisplayName(source);
        addChild(dragGhost);
        // A plain click must never show the floating drag label.
        dragGhost.visible = false;
        dragGhost.x = event.relX + 10;
        dragGhost.y = event.relY + 8;
        dragging = false;
        dragStartX = ctx.window.mouseX;
        dragStartY = ctx.window.mouseY;
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.window.mouseX - dragStartX)
                            + Math.abs(ctx.window.mouseY - dragStartY) > 6) {
                        if (!dragging) dragGhost.visible = true;
                        dragging = true;
                    }
                    dragGhost.x = ctx.window.mouseX - this.x + 10;
                    dragGhost.y = ctx.window.mouseY - this.y + 8;
                    updateDropTarget();
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    var target = dropTargetFolder;
                    var wasDragging = dragging;
                    clearDrag(hit);
                    if (wasDragging && target != null) {
                        Sys.println('[probe] asset browser folder drop source=${source}'
                            + ' folder=${target}');
                        if (onMoveFolder != null) onMoveFolder(source, target);
                    }
                    capturedEvent.propagate = false;
                case _:
                    capturedEvent.propagate = false;
            }
        });
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
        contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, [{
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
        contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    function openFolderContextMenu(path:String):Void {
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
        contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, items);
    }

    function openSelected():Void {
        if (selectedSource == "") return;
        Sys.println('[probe] asset browser open source=${selectedSource}');
        var entry = findEntry(selectedSource);
        if (entry == null || !entry.loadable) {
            showStatus("No engine preview for this file type");
            return;
        }
        store.markRecent(selectedSource);
        if (onOpenAsset != null) onOpenAsset(selectedSource);
    }

    function duplicateSelected():Void {
        if (selectedSource == "") return;
        if (onDuplicateAsset != null) onDuplicateAsset(selectedSource);
    }

    /** Delete entry points used by the Delete keyboard shortcut. */
    public function hasFolderSelection():Bool return selectedFolder != "";

    public function deleteSelection():Void {
        deleteSelected();
    }

    public function deleteSelectedFolder():Void {
        if (selectedFolder == "") return;
        var folder = selectedFolder;
        if (onDeleteFolder != null) onDeleteFolder(folder, true);
        Sys.println('[probe] asset browser delete folder request=${folder}');
    }

    function deleteSelected():Void {
        if (selectedSources.length == 0) return;
        var sources = selectedSources.copy();
        if (onDeleteAssets != null) {
            onDeleteAssets(sources);
            return;
        }
        for (source in sources) if (onDeleteAsset != null) onDeleteAsset(source);
    }

    // ------------------------------------------------------------------
    // Inline rename
    // ------------------------------------------------------------------

    /** F2 entry point: rename the primary asset, or the selected folder. */
    public function beginRename():Bool {
        if (renaming) return false;
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
        for (index in 0...folderRowPaths.length) {
            if (folderRowPaths[index] == folder) {
                return {
                    x: 2, y: TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT,
                    width: folderWidth - 4, height: ROW_HEIGHT - 2
                };
            }
        }
        return {x: 2, y: TOOLBAR_HEIGHT + 22,
            width: folderWidth - 4, height: ROW_HEIGHT - 2};
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
