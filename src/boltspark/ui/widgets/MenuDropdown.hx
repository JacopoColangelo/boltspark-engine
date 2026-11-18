package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.widgets.SearchField;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/** One dropdown menu entry; `submenu` turns the row into a cascade parent. */
typedef MenuItem = {
    label:String,
    ?onClick:Void->Void,
    ?submenu:Array<MenuItem>,
    /** Non-interactive divider used to group actions. */
    ?separator:Bool,
    /** Draws an accent checkmark and tints the row as the active choice. */
    ?selected:Bool,
    /** Draws a muted dash when the choice differs across a multi-selection. */
    ?mixed:Bool,
    /** Makes the row draggable into the viewport as this primitive asset. */
    ?dragMeshId:String
};

/** One open cascade level. Level 0 is the menu opened at the cursor position. */
private class MenuLevel {
    public var object:h2d.Object;
    public var surface:UiSurface;
    public var hitCatch:h2d.Interactive;
    public var rows:Array<h2d.Object> = [];
    public var parent:Null<MenuLevel> = null;
    public var index:Int = 0;
    public var rowY:Float = 0;
    public var width:Float = 0;
    public var height:Float = 0;
    public var items:Array<MenuItem> = [];
    public var hasSearch:Bool = false;
    public var searchQuery:String = "";
    public var searchField:Null<SearchField> = null;

    public function new() {}
}

/**
 * Native dropdown menu for the editor. Built from the same retained-H2D popup
 * patterns as the object palette: UiSurface chrome, per-row interactives, and
 * manual row layout. Cascades may nest to any depth (Scene Hierarchy > Create
 * New... > Primitives); rows are rebuilt on every open so the menu reflects
 * live state.
 */
class MenuDropdown extends h2d.Object {
    static inline var ROW_HEIGHT:Int = 22;
    static inline var SEPARATOR_HEIGHT:Int = 9;
    static inline var PADDING:Int = 3;
    static inline var MIN_WIDTH:Int = 168;
    /** Left gutter reserved for the state mark of a selection-style menu. */
    static inline var STATE_GUTTER:Float = 20;
    static inline var SEARCH_HEIGHT:Float = 24;

    final context:UiContext;
    /** Full-window catch behind the rows: any outside left-click dismisses. */
    final dismissCatch:h2d.Interactive;
    final levels:Array<MenuLevel> = [];
    var activeQuery:String = "";
    var rootSearchPlaceholder:String = "";

    public var isOpen(default, null):Bool = false;
    /** Viewport in window coordinates; draggable rows can drop into it. */
    public var dropViewport:Null<LayoutRect> = null;
    public var onDropPrimitive:Null<String->Float->Float->Void>;

    final dragBackground:UiSurface;
    final dragIcon:h2d.Graphics;
    final dragLabel:UiText;
    var dragNativeCapture:Bool = false;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        // Drag ghost belongs to the same layer as the menu so it can follow the
        // cursor in window coordinates, outside the popup's own bounds.
        var ghostParent = parent == null ? this : parent;
        dragBackground = new UiSurface(context, ghostParent);
        dragBackground.setSize(78, 26);
        dragBackground.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT, 0.30);
        dragIcon = new h2d.Graphics(ghostParent);
        UiIcons.draw(dragIcon, Cube, 0, 0, 15, Theme.CUBE_ORANGE);
        dragLabel = new UiText(context.semiboldFont, ghostParent);
        dragLabel.textColor = Theme.TEXT;
        dragLabel.lineBreak = false;
        hideDragGhost();

        dismissCatch = new h2d.Interactive(1, 1, this);
        dismissCatch.backgroundColor = 0;
        dismissCatch.cursor = hxd.Cursor.Default;
        dismissCatch.onPush = function(event) {
            event.propagate = false;
            close();
        };
        dismissCatch.visible = false;
    }

    /** Open the dropdown at window coordinates (x, y) with these items.
     *  Passing a placeholder adds a search field that filters menu entries. */
    public function open(x:Float, y:Float, items:Array<MenuItem>,
            ?searchPlaceholder:String):Void {
        closeLevelsFrom(0);
        activeQuery = "";
        rootSearchPlaceholder = searchPlaceholder == null ? "" : searchPlaceholder;
        var withSearch = rootSearchPlaceholder != "";
        var width = Math.max(measureItems(items),
            withSearch ? Math.max(MIN_WIDTH, measureLabel(rootSearchPlaceholder) + 60) : 0);
        var height = measureHeight(items) + (withSearch ? SEARCH_HEIGHT + PADDING : 0);
        // Clamp inside the window frame.
        this.x = Math.max(4, Math.min(x, context.width - width - 4));
        this.y = Math.max(4, Math.min(y, context.height - height - 4));
        // The menu object itself is offset to the popup position; pull the
        // catch back so it covers the whole window in screen coordinates.
        dismissCatch.x = -this.x;
        dismissCatch.y = -this.y;
        dismissCatch.width = context.width;
        dismissCatch.height = context.height;
        dismissCatch.visible = true;

        buildLevel(items, null, 0, withSearch);
        visible = true;
        isOpen = true;
        Sys.println('[probe] menu open');
    }

    public function close():Void {
        if (!isOpen) return;
        closeLevelsFrom(0);
        dismissCatch.visible = false;
        hideDragGhost();
        visible = false;
        isOpen = false;
        Sys.println('[probe] menu close');
    }

    function hideDragGhost():Void {
        dragBackground.visible = false;
        dragIcon.visible = false;
        dragLabel.visible = false;
    }

    function releaseDragCapture():Void {
        if (!dragNativeCapture) return;
        dragNativeCapture = false;
        context.setMouseCapture(false);
    }

    /** Drag a primitive row into the viewport; a plain click just activates it. */
    function beginRowDrag(item:MenuItem, hit:h2d.Interactive,
            activate:Void->Void):Void {
        var meshId = item.dragMeshId;
        if (meshId == null || dropViewport == null || onDropPrimitive == null) {
            activate();
            return;
        }
        var startX = context.window.mouseX;
        var startY = context.window.mouseY;
        hideDragGhost();
        hit.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    var mouseX = context.window.mouseX;
                    var mouseY = context.window.mouseY;
                    if (!dragBackground.visible
                        && Math.abs(mouseX - startX) + Math.abs(mouseY - startY) > 5) {
                        dragBackground.visible = true;
                        dragIcon.visible = true;
                        dragLabel.visible = true;
                        // Keep the object-type label ("Primitive Plane"); the
                        // frame grows to enclose it instead of clipping it.
                        dragLabel.text = item.label;
                        // Frame the icon plus the whole label with a small pad.
                        dragBackground.setSize(
                            Math.max(78, dragLabel.textWidth + 42), 26);
                        context.setMouseCapture(true);
                        dragNativeCapture = true;
                    }
                    if (dragBackground.visible) {
                        dragBackground.x = mouseX + 8;
                        dragBackground.y = mouseY + 6;
                        dragIcon.x = mouseX + 15;
                        dragIcon.y = mouseY + 12;
                        dragLabel.x = mouseX + 34;
                        dragLabel.y = mouseY + 9;
                    }
                    event.propagate = false;
                case ERelease, EReleaseOutside:
                    var dragged = dragBackground.visible;
                    var mouseX = context.window.mouseX;
                    var mouseY = context.window.mouseY;
                    hit.stopCapture();
                    releaseDragCapture();
                    hideDragGhost();
                    close();
                    if (dragged) {
                        var viewport = dropViewport;
                        if (viewport != null
                            && mouseX >= viewport.x && mouseX < viewport.x + viewport.width
                            && mouseY >= viewport.y && mouseY < viewport.y + viewport.height
                            && onDropPrimitive != null) {
                            onDropPrimitive(meshId,
                                mouseX - viewport.x, mouseY - viewport.y);
                        }
                    } else {
                        activate();
                    }
                    event.propagate = false;
                case EFocusLost:
                    hit.stopCapture();
                    releaseDragCapture();
                    hideDragGhost();
                    close();
                    event.propagate = false;
                case _:
                    event.propagate = false;
            }
        }, function() {
            releaseDragCapture();
            hideDragGhost();
        });
    }

    function measureItems(items:Array<MenuItem>):Float {
        var hasStates = hasSelectionState(items);
        var width:Float = MIN_WIDTH;
        for (item in items) {
            if (item.separator) continue;
            width = Math.max(width, measureLabel(item.label) + 44
                + (hasStates ? STATE_GUTTER : 0));
        }
        return width;
    }

    function measureHeight(items:Array<MenuItem>):Float {
        var height = PADDING * 2;
        for (item in items) {
            height += item.separator ? SEPARATOR_HEIGHT : ROW_HEIGHT;
        }
        return height;
    }

    function buildLevel(items:Array<MenuItem>, parent:Null<MenuLevel>,
            rowY:Float, withSearch:Bool = false):MenuLevel {
        var level = new MenuLevel();
        level.parent = parent;
        level.rowY = rowY;
        level.index = levels.length;
        level.object = new h2d.Object(this);
        level.surface = new UiSurface(context, level.object);
        level.surface.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        level.hitCatch = new h2d.Interactive(1, 1, level.object);
        level.hitCatch.backgroundColor = 0;
        level.hitCatch.cursor = hxd.Cursor.Default;
        // Swallow presses on the menu body so they cannot fall through to the
        // viewport or the chrome underneath.
        level.hitCatch.onPush = function(event) event.propagate = false;

        level.items = items;
        level.hasSearch = withSearch;
        level.width = withSearch
            ? Math.max(measureItems(items),
                Math.max(MIN_WIDTH, measureLabel(rootSearchPlaceholder) + 60))
            : measureItems(items);
        if (withSearch) {
            level.searchField = new SearchField(context, rootSearchPlaceholder,
                level.width - PADDING * 2, 20, level.object);
            level.searchField.x = PADDING;
            level.searchField.y = PADDING;
            level.searchField.onChange = function(value) {
                activeQuery = StringTools.trim(value.toLowerCase());
                level.searchQuery = activeQuery;
                closeLevelsFrom(1);
                populateRows(level);
            };
            // Typing right after opening filters immediately.
            level.searchField.focusInput();
        }
        populateRows(level);
        levels.push(level);
        return level;
    }

    function populateRows(level:MenuLevel):Void {
        for (row in level.rows) row.remove();
        level.rows.resize(0);

        var shown = filteredItems(level.items,
            level.hasSearch ? level.searchQuery : activeQuery);
        level.height = measureHeight(shown) + PADDING * 2
            + (level.hasSearch ? SEARCH_HEIGHT + PADDING : 0);
        level.surface.setSize(level.width, level.height);
        level.hitCatch.width = level.width;
        level.hitCatch.height = level.height;

        var cursor = PADDING + (level.hasSearch ? SEARCH_HEIGHT + PADDING : 0);
        var hasStates = hasSelectionState(shown);
        for (index in 0...shown.length) {
            var item = shown[index];
            var itemRowY = cursor;
            cursor += item.separator ? SEPARATOR_HEIGHT : ROW_HEIGHT;
            var row = new h2d.Object(level.object);
            level.rows.push(row);
            row.y = itemRowY;
            if (item.separator) {
                var line = new UiSurface(context, row);
                line.x = PADDING;
                line.setStyle(Theme.BORDER, Theme.BORDER, 0, 0);
                line.setSize(level.width - PADDING * 2, 1);
                line.y = Math.floor(SEPARATOR_HEIGHT * 0.5);
                continue;
            }
            var captured = item;
            var activate = function() {
                if (captured.submenu != null) {
                    openSubmenuFrom(level, captured, itemRowY);
                } else {
                    close();
                    if (captured.onClick != null) captured.onClick();
                }
            };
            addRowContent(row, item, itemRowY, level.width, activate,
                item.submenu != null, level, hasStates);
        }
        positionLevel(level);
    }

    static function filteredItems(items:Array<MenuItem>, query:String):Array<MenuItem> {
        if (query == "") return items;
        // Search flattens cascades: matching actions appear directly so a
        // primitive can be created without walking into its submenu first.
        var shown:Array<MenuItem> = [];
        for (item in items) collectMatches(item, query, shown);
        return shown;
    }

    static function collectMatches(item:MenuItem, query:String,
            out:Array<MenuItem>):Void {
        if (item.separator) return;
        if (item.submenu != null) {
            for (child in item.submenu) collectMatches(child, query, out);
        } else if (item.label.toLowerCase().indexOf(query) >= 0) {
            out.push(item);
        }
    }

    function positionLevel(level:MenuLevel):Void {
        if (level.parent == null) {
            level.object.x = 0;
            level.object.y = 0;
            return;
        }
        var parent = level.parent;
        // Prefer a right-opening cascade, flipping left near the window edge.
        var parentScreenX = this.x + parent.object.x;
        var rightX = parent.object.x + parent.width - 2;
        var leftX = parent.object.x - level.width + 2;
        level.object.x = parentScreenX + rightX + level.width <= context.width - 4
            ? rightX : leftX;
        var desiredY = parent.object.y + level.rowY;
        var minY = 4 - this.y;
        var maxY = context.height - this.y - level.height - 4;
        level.object.y = Math.max(minY, Math.min(desiredY, maxY));
    }

    function openSubmenuFrom(parent:MenuLevel, item:MenuItem, rowY:Float):Void {
        closeLevelsFrom(parent.index + 1);
        buildLevel(item.submenu, parent, rowY);
    }

    function closeLevelsFrom(index:Int):Void {
        while (levels.length > index) {
            var level = levels.pop();
            for (row in level.rows) row.remove();
            level.rows.resize(0);
            level.object.remove();
        }
    }

    function addRowContent(row:h2d.Object, item:MenuItem, rowY:Float, width:Float,
            activate:Void->Void, hasSubmenu:Bool, level:MenuLevel,
            showStates:Bool):Void {
        // The wrapper is positioned at the row's Y; all content is relative.
        row.y = rowY;
        var selected = item.selected == true;
        // The active choice gets the same restrained teal the hierarchy uses
        // for selected objects; plain rows stay on the panel surface.
        var normalFill = selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT;
        // Rows start after the panel padding. Painting them at x=0 covered the
        // panel's left border and made every menu look clipped on that side.
        var rowSurface = new UiSurface(context, row);
        rowSurface.x = PADDING;
        rowSurface.setSize(width - PADDING * 2, ROW_HEIGHT - 1);
        rowSurface.setStyle(normalFill, normalFill, 0);
        var rowHit = new h2d.Interactive(width - PADDING * 2, ROW_HEIGHT - 1, row);
        rowHit.x = PADDING;
        rowHit.backgroundColor = 0;
        rowHit.cursor = hxd.Cursor.Default;
        rowHit.onOver = function(_) {
            rowSurface.setStyle(
                selected ? Theme.ACCENT_MUTED : Theme.SURFACE_3,
                Theme.ACCENT, 0);
            // Cascade parents open their submenu on hover; a plain row closes
            // only levels deeper than its own, leaving the containing cascade.
            if (hasSubmenu) activate() else closeLevelsFrom(level.index + 1);
        };
        rowHit.onOut = function(_) rowSurface.setStyle(normalFill, normalFill, 0);
        rowHit.onPush = function(event) {
            event.propagate = false;
            if (item.dragMeshId != null) beginRowDrag(item, rowHit, activate);
            else activate();
        };
        if (item.dragMeshId != null && dropViewport != null && onDropPrimitive != null) {
            rowHit.cursor = hxd.Cursor.Move;
        }
        if (showStates) drawStateMark(row, selected, item.mixed == true);
        var label = new UiText(context.font, row);
        label.text = item.label;
        label.lineBreak = false;
        label.textColor = Theme.TEXT;
        label.x = 10 + (showStates ? STATE_GUTTER : 0);
        label.y = Math.round((ROW_HEIGHT - label.textHeight) * 0.5 - 1);
        if (hasSubmenu) {
            var chevron = new h2d.Graphics(row);
            UiIcons.draw(chevron, ChevronRight, 0, 0, 9, Theme.MUTED);
            chevron.x = width - PADDING - 16;
            chevron.y = Math.round((ROW_HEIGHT - 9) * 0.5);
        }
    }

    static function hasSelectionState(items:Array<MenuItem>):Bool {
        for (item in items) {
            if (item.selected != null || item.mixed != null) return true;
        }
        return false;
    }

    /**
     * Selection-style menus reserve a left gutter so every label lines up,
     * whether or not its row is active. An accent check marks the current
     * choice; a muted dash marks a mixed multi-selection instead of a bullet
     * glued to one label.
     */
    static function drawStateMark(row:h2d.Object, selected:Bool, mixed:Bool):Void {
        if (!selected && !mixed) return;
        var mark = new h2d.Graphics(row);
        var x = 7.0;
        var y = Math.round((ROW_HEIGHT - 10) * 0.5);
        if (mixed) {
            mark.lineStyle(1.6, Theme.MUTED);
            mark.moveTo(x, y + 5);
            mark.lineTo(x + 8, y + 5);
        } else {
            mark.lineStyle(1.8, Theme.ACCENT_HOVER);
            mark.moveTo(x, y + 4);
            mark.lineTo(x + 3.2, y + 7.4);
            mark.lineTo(x + 9, y + 0.8);
        }
    }

    function measureLabel(labelText:String):Float {
        var probe = new UiText(context.font, null);
        probe.text = labelText;
        var width = probe.textWidth;
        probe.remove();
        return width;
    }
}
