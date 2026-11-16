package boltspark.ui.widgets;

import boltspark.project.ProjectSession;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.Theme;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;
import boltspark.ui.widgets.MenuDropdown.MenuItem;

typedef FolderNode = {
    var name:String;
    var path:String;
    var children:Array<FolderNode>;
};

/**
 * Docked project Asset Browser. It reads real files under the project root,
 * groups them by folder, and exposes Unreal-style asset actions: double-click
 * or Open to load, Add to create, Rename, and Delete. All actions are routed
 * upward; this widget never edits documents or the filesystem.
 */
class AssetBrowser extends h2d.Object {
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

    static inline var TOOLBAR_HEIGHT:Float = 26;
    static inline var FOLDER_WIDTH:Float = 118;
    static inline var ROW_HEIGHT:Float = 22;
    static inline var TILE_WIDTH:Float = 88;
    static inline var TILE_HEIGHT:Float = 80;
    static inline var GRID_GAP:Float = 8;

    final ctx:UiContext;
    final background:UiSurface;
    final toolbar:UiSurface;
    final titleText:UiText;
    final folderText:UiText;
    final statusText:UiText;
    final addButton:UiButton;
    final addMenu:MenuDropdown;
    final folderSurface:UiSurface;
    final folderTitle:UiText;
    final listSurface:UiSurface;
    final listMask:h2d.Mask;
    final gridScroll:ScrollBar;
    final contextMenu:MenuDropdown;
    final renameSurface:UiSurface;
    final renameInput:UiTextInput;
    final dragGhost:UiText;

    var entries:Array<AssetFileInfo> = [];
    var folders:Array<String> = [];
    var folderRows:Array<h2d.Object> = [];
    var folderRowPaths:Array<String> = [];
    final expandedFolders:Map<String, Bool> = [];
    var assetRows:Array<h2d.Object> = [];
    var selectedFolder:String = "";
    var selectedSource:String = "";
    var renamingSource:String = "";
    var renamingOriginal:String = "";
    var renamingIsFolder:Bool = false;
    var renaming:Bool = false;
    var lastClickSource:String = "";
    var lastClickAt:Float = 0;
    var scrollValue:Float = 0;
    var clipboardSource:String = "";
    var clipboardIsCut:Bool = false;
    var dragSource:String = "";
    var dragging:Bool = false;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;
    var widthValue:Float = 0;
    var heightValue:Float = 0;

    public function new(ctx:UiContext, ?parent:h2d.Object, ?menuParent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        var menus = menuParent == null ? this : menuParent;

        background = new UiSurface(ctx, this);
        background.setStyle(Theme.PANEL, Theme.BORDER, 0);

        toolbar = new UiSurface(ctx, this);
        toolbar.setStyle(Theme.PANEL_HEADER, Theme.BORDER, 0);

        titleText = new UiText(ctx.semiboldFont, this);
        titleText.text = "Asset Browser";
        titleText.textColor = Theme.TEXT_SECONDARY;
        titleText.lineBreak = false;

        folderText = new UiText(ctx.captionFont, this);
        folderText.textColor = Theme.MUTED;
        folderText.lineBreak = false;

        statusText = new UiText(ctx.captionFont, this);
        statusText.textColor = Theme.MUTED;
        statusText.lineBreak = false;

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
                    var created = onNewFolder != null
                        ? onNewFolder(selectedFolder) : null;
                    if (created != null) {
                        selectedFolder = created;
                        selectedSource = "";
                        beginRenameFolder(created);
                    }
                }
            }]);
        };
        addMenu = new MenuDropdown(ctx, menus);

        folderSurface = new UiSurface(ctx, this);
        folderSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER, 0);
        folderTitle = new UiText(ctx.captionFont, this);
        folderTitle.text = "Folders";
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

        contextMenu = new MenuDropdown(ctx, menus);

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
    }

    public inline function isRenaming():Bool return renaming;

    /** Ctrl+C: remember the selected asset for a later paste. */
    public function copyToClipboard():Void {
        if (selectedSource == "") return;
        clipboardSource = selectedSource;
        clipboardIsCut = false;
        Sys.println('[probe] asset browser clipboard copy=${selectedSource}');
    }

    /** Ctrl+X: remember the selected asset for a move-on-paste. */
    public function cutToClipboard():Void {
        if (selectedSource == "") return;
        clipboardSource = selectedSource;
        clipboardIsCut = true;
        Sys.println('[probe] asset browser clipboard cut=${selectedSource}');
    }

    public inline function hasClipboard():Bool return clipboardSource != "";
    public inline function hasSelection():Bool return selectedSource != "";

    public function pasteClipboard():Void {
        pasteInto(selectedFolder);
    }

    /** Ctrl+V: paste the clipboard asset into the selected folder. */
    public function pasteInto(folder:String):Void {
        if (clipboardSource == "") return;
        var target = folder == "" ? "Scenes" : folder;
        var source = clipboardSource;
        var isCut = clipboardIsCut;
        Sys.println('[probe] asset browser paste source=${source} folder=${target} cut=${isCut}');
        if (isCut) {
            clipboardSource = "";
            if (onMoveAsset != null) onMoveAsset(source, target);
        } else if (onCopyAsset != null) {
            onCopyAsset(source, target);
        }
    }

    /** Dismiss transient menus when the editor closes other popups. */
    public function closeMenus():Void {
        addMenu.close();
        contextMenu.close();
    }

    /** Re-read assets from the project root and rebuild the listing. */
    public function refresh():Void {
        entries = onQueryAssets != null ? onQueryAssets() : [];
        printEntries();
        collectFolders();
        Sys.println('[probe] asset browser folders=${folders.length}');
        if (selectedFolder != "" && folders.indexOf(selectedFolder) < 0) {
            selectedFolder = "";
        }
        if (findEntry(selectedSource) == null) {
            selectedSource = "";
            for (entry in entries) if (entry.active) selectedSource = entry.source;
        }
        buildFolders();
        buildAssets();
    }

    public function layout(x:Float, y:Float, width:Float, height:Float):Void {
        this.x = x;
        this.y = y;
        widthValue = Math.max(0, width);
        heightValue = Math.max(0, height);
        background.setSize(widthValue, heightValue);
        toolbar.setSize(widthValue, TOOLBAR_HEIGHT);
        titleText.x = 10;
        titleText.y = 5;
        addButton.x = widthValue - 64;
        addButton.y = 3;
        folderText.x = addButton.x - Math.min(380, Math.max(120, widthValue * 0.45));
        folderText.y = 6;
        statusText.x = 118;
        statusText.y = 5;

        folderSurface.setSize(FOLDER_WIDTH, Math.max(0, heightValue - TOOLBAR_HEIGHT));
        folderTitle.x = 8;
        folderTitle.y = TOOLBAR_HEIGHT + 6;
        listSurface.x = FOLDER_WIDTH;
        listSurface.y = TOOLBAR_HEIGHT;
        listSurface.setSize(Math.max(0, widthValue - FOLDER_WIDTH),
            Math.max(0, heightValue - TOOLBAR_HEIGHT));
        listMask.x = FOLDER_WIDTH;
        listMask.y = TOOLBAR_HEIGHT;
        listMask.width = Std.int(Math.max(0, widthValue - FOLDER_WIDTH - 12));
        listMask.height = Std.int(gridViewportHeight());
        gridScroll.setBounds(Math.max(0, widthValue - 10), TOOLBAR_HEIGHT + 2,
            6, Math.max(0, gridViewportHeight() - 4));
        buildFolders();
        buildAssets();
        positionRenameOverlay();
    }

    function printEntries():Void {
        Sys.println('[probe] asset browser entries=${entries.length}');
    }

    function collectFolders():Void {
        folders.resize(0);
        // Registered/discovered directories come first so empty folders appear.
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

    function visibleEntries():Array<AssetFileInfo> {
        if (selectedFolder == "") return entries;
        return [for (entry in entries) if (entry.folder == selectedFolder) entry];
    }

    function clearRows(rows:Array<h2d.Object>):Void {
        for (row in rows) row.remove();
        rows.resize(0);
    }

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
                    if (candidate.name == part) {
                        node = candidate;
                        break;
                    }
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
        nodes.sort(function(a, b) {
            return a.name < b.name ? -1 : (a.name == b.name ? 0 : 1);
        });
        for (node in nodes) sortFolderNodes(node.children);
    }

    function isExpanded(path:String):Bool {
        return expandedFolders.exists(path) ? expandedFolders.get(path) : true;
    }

    function folderLabelChars(depth:Int):Int {
        var chars:Int = Std.int((FOLDER_WIDTH - 32 - depth * 12) / 7);
        return chars < 5 ? 5 : chars;
    }

    function buildFolders():Void {
        clearRows(folderRows);
        folderRowPaths.resize(0);
        var all = makeFolderRow("All", "", selectedFolder == "", 0, false);
        all.y = TOOLBAR_HEIGHT + 22;
        folderRows.push(all);
        folderRowPaths.push("");
        var index = 1;
        for (node in buildFolderTree()) {
            index = renderFolderNode(node, 0, index);
        }
    }

    function renderFolderNode(node:FolderNode, depth:Int, index:Int):Int {
        var hasChildren = node.children.length > 0;
        var row = makeFolderRow(shorten(node.name, folderLabelChars(depth)),
            node.path, selectedFolder == node.path, depth, hasChildren);
        row.y = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT;
        folderRows.push(row);
        folderRowPaths.push(node.path);
        index++;
        if (hasChildren && isExpanded(node.path)) {
            for (child in node.children) {
                index = renderFolderNode(child, depth + 1, index);
            }
        }
        return index;
    }

    function makeFolderRow(display:String, path:String, selected:Bool,
            depth:Int, hasChildren:Bool):h2d.Object {
        var row = new h2d.Object(this);
        row.x = 2;
        var surface = new UiSurface(ctx, row);
        surface.setSize(FOLDER_WIDTH - 4, ROW_HEIGHT - 2);
        surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT,
            selected ? Theme.ACCENT : Theme.BORDER, 0);

        var hit = new h2d.Interactive(FOLDER_WIDTH - 4, ROW_HEIGHT - 2, row);
        hit.backgroundColor = 0;
        hit.cursor = hxd.Cursor.Default;
        hit.enableRightButton = true;
        hit.onPush = function(event) {
            event.propagate = false;
            selectedFolder = path;
            selectedSource = "";
            buildFolders();
            buildAssets();
            if (event.button != 1) return;
            contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, [{
                label: "New Scene Here",
                onClick: function() {
                    var target = path == "" ? "Scenes" : path;
                    if (onNewScene != null) onNewScene(target, "New Scene");
                }
            }, {
                label: "New Subfolder",
                onClick: function() {
                    if (onNewFolder != null) {
                        var _ = onNewFolder(path);
                    }
                }
            }, {
                label: "Rename Folder",
                onClick: function() beginRenameFolder(path)
            }]);
        };

        var iconX = 4 + depth * 12 + (hasChildren ? 12 : 0);
        var icon = new h2d.Graphics(row);
        UiIcons.draw(icon, Folder, iconX, 3, 14,
            selected ? Theme.ACCENT : Theme.MUTED);
        Sys.println('[probe] asset browser folder row=${display} depth=${depth}');
        var label = new UiText(ctx.font, row);
        label.text = display;
        label.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
        label.lineBreak = false;
        label.x = iconX + 18;
        label.y = 3;

        if (hasChildren && path != "") {
            var chevron = new h2d.Graphics(row);
            UiIcons.draw(chevron, isExpanded(path) ? ChevronDown : ChevronRight,
                4 + depth * 12, 6, 9, Theme.MUTED);
            var chevronHit = new h2d.Interactive(12, ROW_HEIGHT - 2, row);
            chevronHit.x = 2 + depth * 12;
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

    function gridColumns():Int {
        var listWidth = Math.max(0, widthValue - FOLDER_WIDTH - 16);
        var columns:Int = Std.int((listWidth + GRID_GAP) / (TILE_WIDTH + GRID_GAP));
        return columns < 1 ? 1 : columns;
    }

    function gridViewportHeight():Float {
        return Math.max(0, heightValue - TOOLBAR_HEIGHT - 8);
    }

    function gridContentHeight(count:Int):Float {
        var rows = Math.ceil(count / Math.max(1, gridColumns()));
        return rows * (TILE_HEIGHT + GRID_GAP);
    }

    function gridScrollOffset(count:Int):Float {
        return Math.max(0, gridContentHeight(count) - gridViewportHeight())
            * scrollValue;
    }

    /** Local position inside the clipped grid, including scroll offset. */
    function tilePosition(index:Int, count:Int):{ x:Float, y:Float } {
        var columns = gridColumns();
        return {
            x: 8 + (index % columns) * (TILE_WIDTH + GRID_GAP),
            y: 4 + Std.int(index / columns) * (TILE_HEIGHT + GRID_GAP)
                - gridScrollOffset(count)
        };
    }

    function buildAssets():Void {
        clearRows(assetRows);
        var shown = visibleEntries();
        var content = gridContentHeight(shown.length);
        var view = gridViewportHeight();
        var ratio = content <= 0 ? 1.0 : Math.min(1.0, view / content);
        if (ratio < 1) {
            Sys.println('[probe] asset browser scrollable=true tiles=${shown.length}');
        }
        gridScroll.setMetrics(ratio, scrollValue);
        gridScroll.setBounds(Math.max(0, widthValue - 10), TOOLBAR_HEIGHT + 2,
            6, Math.max(0, view - 4));
        for (index in 0...shown.length) {
            var entry = shown[index];
            var position = tilePosition(index, shown.length);
            var tile = new h2d.Object(listMask);
            tile.x = position.x;
            tile.y = position.y;
            assetRows.push(tile);
            var selected = entry.source == selectedSource;
            var surface = new UiSurface(ctx, tile);
            surface.setSize(TILE_WIDTH, TILE_HEIGHT);
            surface.setStyle(selected ? Theme.ACCENT_MUTED : Theme.SURFACE_1,
                selected ? Theme.ACCENT : Theme.BORDER, 0);

            var icon = new h2d.Graphics(tile);
            UiIcons.draw(icon, entry.kind == "scene" ? Scene : Hierarchy,
                Math.round((TILE_WIDTH - 16) * 0.5), 12, 16,
                selected ? Theme.ACCENT : Theme.TEXT_SECONDARY);

            var name = new UiText(ctx.captionFont, tile);
            name.text = shorten(entry.name, 14);
            name.textColor = selected ? Theme.TEXT : Theme.TEXT_SECONDARY;
            name.lineBreak = false;
            name.x = Math.max(2, Math.round((TILE_WIDTH - name.textWidth) * 0.5));
            name.y = 48;

            if (entry.active) {
                var badge = new UiText(ctx.captionFont, tile);
                badge.text = "ACTIVE";
                badge.textColor = Theme.ACCENT;
                badge.lineBreak = false;
                badge.x = Math.max(2, Math.round((TILE_WIDTH - badge.textWidth) * 0.5));
                badge.y = 64;
            }

            var hit = new h2d.Interactive(TILE_WIDTH, TILE_HEIGHT, tile);
            hit.backgroundColor = 0;
            hit.cursor = hxd.Cursor.Default;
            hit.enableRightButton = true;
            var captured = entry.source;
            hit.onPush = function(event) {
                if (event.button == 1) {
                    selectedSource = captured;
                    buildAssets();
                    openContextMenu();
                    event.propagate = false;
                    return;
                }
                var now = haxe.Timer.stamp();
                var isDouble = captured == lastClickSource
                    && now - lastClickAt <= 0.35;
                lastClickAt = now;
                lastClickSource = captured;
                selectedSource = captured;
                if (isDouble) {
                    buildAssets();
                    openSelected();
                    event.propagate = false;
                    return;
                }
                beginAssetDrag(captured, hit, event);
                event.propagate = false;
            };
            hit.onWheel = handleGridWheel;
        }
        statusText.text = '${shown.length} asset(s) · double-click to open';
    }

    function folderAt(x:Float, y:Float):Null<String> {
        if (x < 0 || x > FOLDER_WIDTH) return null;
        for (index in 0...folderRowPaths.length) {
            var rowY = TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT;
            if (y >= rowY && y <= rowY + ROW_HEIGHT - 2) {
                return folderRowPaths[index];
            }
        }
        return null;
    }

    function openDropMenu(source:String, folder:String):Void {
        Sys.println('[probe] asset browser drop source=${source} folder=${folder}'
            + ' menu=${ctx.window.mouseX},${ctx.window.mouseY}');
        contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, [{
            label: "Move Here",
            onClick: function() {
                Sys.println('[probe] drop move chosen');
                if (onMoveAsset != null) onMoveAsset(source, folder);
            }
        }, {
            label: "Copy Here",
            onClick: function() {
                if (onCopyAsset != null) onCopyAsset(source, folder);
            }
        }]);
    }

    function beginAssetDrag(source:String, hit:h2d.Interactive,
            event:hxd.Event):Void {
        dragSource = source;
        dragging = false;
        dragStartX = ctx.window.mouseX;
        dragStartY = ctx.window.mouseY;
        dragGhost.text = ProjectSession.sceneDisplayName(source);
        addChild(dragGhost);
        dragGhost.visible = true;
        dragGhost.x = event.relX + 10;
        dragGhost.y = event.relY + 8;
        hit.startCapture(function(capturedEvent) {
            switch (capturedEvent.kind) {
                case EMove:
                    if (Math.abs(ctx.window.mouseX - dragStartX)
                            + Math.abs(ctx.window.mouseY - dragStartY) > 6) {
                        dragging = true;
                    }
                    dragGhost.x = ctx.window.mouseX - this.x + 10;
                    dragGhost.y = ctx.window.mouseY - this.y + 8;
                    capturedEvent.propagate = false;
                case ERelease, EReleaseOutside, EFocusLost:
                    dragGhost.visible = false;
                    var folder = folderAt(ctx.window.mouseX - this.x,
                        ctx.window.mouseY - this.y);
                    var wasDragging = dragging;
                    dragging = false;
                    hit.stopCapture();
                    buildAssets();
                    positionRenameOverlay();
                    if (wasDragging && folder != null && folder != "") {
                        openDropMenu(source, folder);
                    }
                    capturedEvent.propagate = false;
                case _:
                    capturedEvent.propagate = false;
            }
        });
    }

    function handleGridWheel(event:hxd.Event):Void {
        var shown = visibleEntries();
        var over = Math.max(0, gridContentHeight(shown.length) - gridViewportHeight());
        if (over <= 0) return;
        var rows = Math.max(1, Math.ceil(shown.length / Math.max(1, gridColumns())));
        scrollValue = Math.max(0, Math.min(1,
            scrollValue - event.wheelDelta * 0.12 / rows));
        buildAssets();
        event.propagate = false;
    }

    static function shorten(value:String, max:Int):String {
        return value.length <= max ? value : value.substr(0, max - 1) + "…";
    }

    function destinationItems(action:String->String->Void):Array<MenuItem> {
        var items:Array<MenuItem> = [];
        var folders = onQueryFolders != null ? onQueryFolders() : [];
        for (folder in folders) {
            var target = folder;
            items.push({
                label: ProjectSession.folderDisplayName(target),
                onClick: function() action(selectedSource, target)
            });
        }
        if (items.length == 0) items.push({ label: "No folders" });
        return items;
    }

    function openContextMenu():Void {
        Sys.println('[probe] asset browser context source=${selectedSource}');
        contextMenu.open(ctx.window.mouseX, ctx.window.mouseY, [{
            label: "Open",
            onClick: openSelected
        }, {
            label: "Rename",
            onClick: beginRenameSelected
        }, {
            label: "Move To",
            submenu: destinationItems(function(source, folder) {
                if (onMoveAsset != null) onMoveAsset(source, folder);
            })
        }, {
            label: "Copy To",
            submenu: destinationItems(function(source, folder) {
                if (onCopyAsset != null) onCopyAsset(source, folder);
            })
        }, {
            label: "Delete",
            onClick: deleteSelected
        }]);
    }

    function openSelected():Void {
        if (selectedSource == "") return;
        Sys.println('[probe] asset browser open source=${selectedSource}');
        if (onOpenAsset != null) onOpenAsset(selectedSource);
    }

    function deleteSelected():Void {
        if (selectedSource == "") return;
        if (onDeleteAsset != null) onDeleteAsset(selectedSource);
    }

    function selectedName():String {
        var entry = findEntry(selectedSource);
        return entry == null ? "" : entry.name;
    }

    function selectedTile():{ x:Float, y:Float, width:Float, height:Float } {
        var shown = visibleEntries();
        for (index in 0...shown.length) {
            if (shown[index].source == selectedSource) {
                var position = tilePosition(index, shown.length);
                return {
                    x: listMask.x + position.x, y: listMask.y + position.y,
                    width: TILE_WIDTH, height: TILE_HEIGHT
                };
            }
        }
        return {
            x: listMask.x + 8, y: listMask.y + 4,
            width: TILE_WIDTH, height: TILE_HEIGHT
        };
    }

    /** F2 entry point: rename the selected asset, or the selected folder. */
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

    function folderRowRect(folder:String):{ x:Float, y:Float, width:Float, height:Float } {
        for (index in 0...folderRowPaths.length) {
            if (folderRowPaths[index] == folder) {
                return {
                    x: 2, y: TOOLBAR_HEIGHT + 22 + index * ROW_HEIGHT,
                    width: FOLDER_WIDTH - 4, height: ROW_HEIGHT - 2
                };
            }
        }
        return {
            x: 2, y: TOOLBAR_HEIGHT + 22,
            width: FOLDER_WIDTH - 4, height: ROW_HEIGHT - 2
        };
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
        // Rows are rebuilt on top of the widget; lift the editor above them.
        addChild(renameSurface);
        addChild(renameInput);
        renameSurface.visible = true;
        renameInput.visible = true;
        // The click that started rename is still dispatching; grab focus on
        // the next frame so its release cannot immediately blur us.
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
}
