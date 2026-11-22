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
    /** Muted uppercase heading for a group of mutually exclusive choices. */
    ?section:Bool,
    /** Draws an accent checkmark and tints the row as the active choice. */
    ?selected:Bool,
    /** Draws a radio dot instead of a checkmark for the active choice. */
    ?radio:Bool,
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
    /** Visible height; `items` may be taller and scroll inside `rowMask`. */
    public var height:Float = 0;
    public var viewHeightLimit:Float = 0;
    public var rowMask:h2d.Mask;
    public var scrollBar:ScrollBar;
    public var scrollY:Float = 0;
    public var rowsHeight:Float = 0;
    public var viewportHeight:Float = 0;
    public var maxScroll:Float = 0;
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
    /**
     * Topmost layer for editor popups. Hosts set this so menus opened by
     * docked panels are not covered by dock tab bars and split handles.
     */
    public static var overlayLayer:Null<h2d.Object> = null;
    /** True while any dropdown is open (used to keep float overlays alive). */
    public static var hasOpenMenu:Bool = false;

    static inline var ROW_HEIGHT:Int = 22;
    static inline var SECTION_HEIGHT:Int = 21;
    static inline var SEPARATOR_HEIGHT:Int = 9;
    static inline var PADDING:Int = 3;
    static inline var MIN_WIDTH:Int = 168;
    /** Left gutter reserved for the state mark of a selection-style menu. */
    static inline var STATE_GUTTER:Float = 20;
    static inline var SEARCH_HEIGHT:Float = 24;
    /** Menus taller than this scroll instead of overflowing the window. */
    static inline var MAX_MENU_HEIGHT:Float = 360;
    static inline var SCROLLBAR_WIDTH:Float = 3;
    static inline var WHEEL_STEP:Float = 36;

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
        // Any outside mouse button dismisses the menu. Heaps only routes
        // onPush to the primary button by default, so middle/right clicks
        // would otherwise leave the popup open while focus was already lost.
        dismissCatch.enableRightButton = true;
        dismissCatch.onPush = function(event) {
            // Keep the catch alive through ERelease for left clicks: buttons
            // fire their action on release, so closing on push would let that
            // release fall through to a control underneath the menu.
            event.propagate = false;
            // Right-click menus open during push, so their own release arrives
            // after the catch became visible. Dismiss right clicks on push
            // instead, otherwise the opening release would close the menu
            // immediately (or after dragging the pointer elsewhere).
            if (event.button == 1) close();
        };
        dismissCatch.onRelease = function(event) {
            event.propagate = false;
            // Ignore the release of a right-click: that press either opened
            // this menu or already dismissed it above.
            if (event.button != 1) close();
        };
        // While open, swallow wheel events that reach the catch so masked
        // inspector content cannot scroll underneath the popup.
        dismissCatch.onWheel = function(event) event.propagate = false;
        dismissCatch.visible = false;
    }

    /** Open the dropdown at window coordinates (x, y) with these items.
     *  Passing a placeholder adds a search field that filters menu entries;
     *  `fixedWidth` makes the menu match an anchor control instead of sizing
     *  it from its labels (cascades still size themselves naturally). */
    public function open(x:Float, y:Float, items:Array<MenuItem>,
            ?searchPlaceholder:String, ?fixedWidth:Float, ?preferAboveY:Float):Void {
        if (overlayLayer != null && parent != overlayLayer) overlayLayer.addChild(this);
        closeLevelsFrom(0);
        activeQuery = "";
        rootSearchPlaceholder = searchPlaceholder == null ? "" : searchPlaceholder;
        var withSearch = rootSearchPlaceholder != "";
        var width = fixedWidth != null && fixedWidth > 0
            ? fixedWidth
            : Math.max(measureItems(items),
                withSearch ? Math.max(MIN_WIDTH, measureLabel(rootSearchPlaceholder) + 60) : 0);
        var maxMenuHeight = maxViewHeight();
        var height = Math.min(
            measureHeight(items) + (withSearch ? SEARCH_HEIGHT + PADDING : 0),
            maxMenuHeight);
        // An anchored menu (e.g. Add Component) flips above its control when
        // there is not enough room below, like an editor drop-down.
        if (preferAboveY != null && y + height > context.height - 4) {
            var above = preferAboveY - height;
            if (above >= 4) y = above;
        }
        // Clamp inside the window frame and snap to whole pixels. Anchored
        // menus inherit fractional layout/scroll coordinates, and subpixel
        // origins make the FreeType atlas glyphs (including search fields)
        // sample between texels and look blurry.
        this.x = Math.round(Math.max(4, Math.min(x, context.width - width - 4)));
        this.y = Math.round(Math.max(4, Math.min(y, context.height - height - 4)));
        // The menu object itself is offset to the popup position; pull the
        // catch back so it covers the whole window in screen coordinates.
        dismissCatch.x = -this.x;
        dismissCatch.y = -this.y;
        dismissCatch.width = context.width;
        dismissCatch.height = context.height;
        dismissCatch.visible = true;

        buildLevel(items, null, 0, withSearch, width, maxMenuHeight);
        visible = true;
        isOpen = true;
        hasOpenMenu = true;
        Sys.println('[probe] menu open');
    }

    public function close():Void {
        if (!isOpen) return;
        // Release focus before tearing down the search field. Otherwise Heaps
        // keeps a focused TextInput (with its white cursor/selection tiles)
        // whose parent was removed, which can render as a white or oversized
        // overlay when the inspector mask scrolls underneath it.
        if (isSearchFocused()) {
            var scene = getScene();
            var focused = scene == null ? null : scene.getFocus();
            if (focused != null) focused.blur();
        }
        closeLevelsFrom(0);
        dismissCatch.visible = false;
        hideDragGhost();
        visible = false;
        isOpen = false;
        hasOpenMenu = false;
        Sys.println('[probe] menu close');
    }

    /** True while the root menu's search field owns keyboard focus, so
     *  editor shortcuts can be suppressed while the user is typing a query. */
    public function isSearchFocused():Bool {
        if (levels.length == 0) return false;
        var field = levels[0].searchField;
        return field != null && field.isFocused();
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
        var startX = context.mouseX;
        var startY = context.mouseY;
        hideDragGhost();
        hit.startCapture(function(event) {
            switch (event.kind) {
                case EMove:
                    var mouseX = context.mouseX;
                    var mouseY = context.mouseY;
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
                    var mouseX = context.mouseX;
                    var mouseY = context.mouseY;
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
            if (item.separator || item.section) continue;
            width = Math.max(width, measureLabel(item.label) + 44
                + (hasStates ? STATE_GUTTER : 0));
        }
        return width;
    }

    function measureHeight(items:Array<MenuItem>):Float {
        var height = PADDING * 2;
        for (item in items) height += menuRowHeight(item);
        return height;
    }

    static inline function menuRowHeight(item:MenuItem):Int {
        if (item.separator) return SEPARATOR_HEIGHT;
        if (item.section) return SECTION_HEIGHT;
        return ROW_HEIGHT;
    }

    function maxViewHeight():Float {
        return Math.min(MAX_MENU_HEIGHT, Math.max(80, context.height - 16));
    }

    function buildLevel(items:Array<MenuItem>, parent:Null<MenuLevel>,
            rowY:Float, withSearch:Bool = false, ?fixedWidth:Float,
            ?viewHeightLimit:Float):MenuLevel {
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
        level.viewHeightLimit = viewHeightLimit == null
            ? maxViewHeight() : viewHeightLimit;
        level.rowMask = new h2d.Mask(1, 1, level.object);
        level.scrollBar = new ScrollBar(context, level.object);
        level.scrollBar.onChange = function(value) {
            setLevelScroll(level, value * level.maxScroll);
        };
        level.scrollBar.onWheel = function(delta) {
            if (level.maxScroll <= 0) return false;
            setLevelScroll(level, level.scrollY + delta * WHEEL_STEP);
            return true;
        };
        level.hitCatch.onWheel = function(event) {
            if (level.maxScroll <= 0) return;
            setLevelScroll(level, level.scrollY + event.wheelDelta * WHEEL_STEP);
            event.propagate = false;
        };

        level.items = items;
        level.hasSearch = withSearch;
        level.width = fixedWidth != null && fixedWidth > 0
            ? fixedWidth
            : withSearch
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
        level.scrollY = 0;
        level.rowMask.scrollY = 0;

        var shown = filteredItems(level.items,
            level.hasSearch ? level.searchQuery : activeQuery);
        var searchArea = level.hasSearch ? SEARCH_HEIGHT + PADDING : PADDING;
        var rowsSum = 0.0;
        for (item in shown) rowsSum += menuRowHeight(item);
        level.rowsHeight = PADDING * 2 + rowsSum;
        level.viewportHeight = Math.min(level.rowsHeight,
            Math.max(ROW_HEIGHT, level.viewHeightLimit - searchArea - PADDING));
        level.height = searchArea + level.viewportHeight + PADDING;
        level.maxScroll = Math.max(0, level.rowsHeight - level.viewportHeight);
        var hasScroll = level.maxScroll > 0;
        var innerWidth = Math.max(1,
            level.width - PADDING * 2 - (hasScroll ? SCROLLBAR_WIDTH : 0));

        level.surface.setSize(level.width, level.height);
        level.hitCatch.width = level.width;
        level.hitCatch.height = level.height;
        level.rowMask.x = PADDING;
        level.rowMask.y = searchArea;
        level.rowMask.width = Std.int(Math.ceil(innerWidth));
        level.rowMask.height = Std.int(Math.ceil(level.viewportHeight));
        level.scrollBar.setBounds(level.width - PADDING - SCROLLBAR_WIDTH,
            searchArea, SCROLLBAR_WIDTH, level.viewportHeight);
        level.scrollBar.setMetrics(level.viewportHeight
            / Math.max(1, level.rowsHeight), 0);

        var cursor = PADDING;
        var hasStates = hasSelectionState(shown);
        for (index in 0...shown.length) {
            var item = shown[index];
            var itemRowY = cursor;
            cursor += menuRowHeight(item);
            var row = new h2d.Object(level.rowMask);
            level.rows.push(row);
            row.y = itemRowY;
            if (item.separator) {
                var line = new UiSurface(context, row);
                line.x = 0;
                line.setStyle(Theme.BORDER, Theme.BORDER, 0, 0);
                line.setSize(innerWidth, 1);
                line.y = Math.floor(SEPARATOR_HEIGHT * 0.5);
                continue;
            }
            if (item.section) {
                var heading = new UiText(context.captionFont, row);
                heading.text = item.label.toUpperCase();
                heading.textColor = Theme.MUTED;
                heading.lineBreak = false;
                heading.x = 10 + (hasStates ? STATE_GUTTER : 0);
                heading.y = Math.round((SECTION_HEIGHT - heading.textHeight) * 0.5);
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
            addRowContent(row, item, itemRowY, innerWidth, activate,
                item.submenu != null, level, hasStates, item.radio == true);
        }
        positionLevel(level);
    }

    function setLevelScroll(level:MenuLevel, value:Float):Void {
        level.scrollY = Math.max(0, Math.min(level.maxScroll, value));
        level.rowMask.scrollY = level.scrollY;
        level.scrollBar.setMetrics(level.viewportHeight
            / Math.max(1, level.rowsHeight),
            level.maxScroll > 0 ? level.scrollY / level.maxScroll : 0);
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
        if (item.separator || item.section) return;
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
        // Both offsets are in this object's coordinate space; keep a small gap
        // from the parent edge so the two panels never overlap.
        var rightX = parent.object.x + parent.width + 2;
        var leftX = parent.object.x - level.width - 2;
        level.object.x = Math.round(this.x + rightX + level.width <= context.width - 4
            ? rightX : leftX);
        // Rows live inside the parent's rowMask, which is inset by the search
        // area / padding. Include that offset or the cascade sits slightly
        // above the row that opened it.
        var desiredY = parent.object.y + parent.rowMask.y + level.rowY - parent.scrollY;
        var minY = 4 - this.y;
        var maxY = context.height - this.y - level.height - 4;
        level.object.y = Math.round(Math.max(minY, Math.min(desiredY, maxY)));
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
            showStates:Bool, radio:Bool):Void {
        // The wrapper is positioned at the row's Y; all content is relative.
        row.y = rowY;
        var selected = item.selected == true;
        // The active choice gets the same restrained teal the hierarchy uses
        // for selected objects; plain rows stay on the panel surface.
        var normalFill = selected ? Theme.ACCENT_MUTED : Theme.PANEL_ALT;
        // Rows start after the panel padding. Painting them at x=0 covered the
        // panel's left border and made every menu look clipped on that side.
        var rowSurface = new UiSurface(context, row);
        rowSurface.x = 0;
        rowSurface.setSize(width, ROW_HEIGHT - 1);
        rowSurface.setStyle(normalFill, normalFill, 0);
        var rowHit = new h2d.Interactive(width, ROW_HEIGHT - 1, row);
        rowHit.x = 0;
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
        };
        rowHit.onRelease = function(event) {
            // Activate on release, while this row is still subscribed to input.
            // Otherwise close() detaches it and the release event reaches the
            // UI control underneath the submenu.
            event.propagate = false;
            if (item.dragMeshId == null) activate();
        };
        if (item.dragMeshId != null && dropViewport != null && onDropPrimitive != null) {
            rowHit.cursor = hxd.Cursor.Move;
        }
        if (showStates) drawStateMark(row, selected, item.mixed == true, radio);
        var label = new UiText(context.font, row);
        label.text = item.label;
        label.lineBreak = false;
        label.textColor = Theme.TEXT;
        label.x = 10 + (showStates ? STATE_GUTTER : 0);
        label.y = Math.round((ROW_HEIGHT - label.textHeight) * 0.5 - 1);
        if (hasSubmenu) {
            var chevron = new h2d.Graphics(row);
            UiIcons.draw(chevron, ChevronRight, 0, 0, 9, Theme.MUTED);
            chevron.x = width - 14;
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
     * whether or not its row is active. The pinned Tabler `check` glyph marks
     * the current choice; `minus` marks a mixed multi-selection instead of a
     * bullet glued to one label.
     */
    static function drawStateMark(row:h2d.Object, selected:Bool, mixed:Bool,
            radio:Bool):Void {
        if (!selected && !mixed) return;
        var mark = new h2d.Graphics(row);
        var size = 12;
        mark.x = 7;
        mark.y = Math.round((ROW_HEIGHT - size) * 0.5);
        if (radio && !mixed) {
            mark.beginFill(Theme.ACCENT_HOVER, 1);
            mark.drawCircle(size * 0.5, size * 0.5, 3.5);
            mark.endFill();
        } else if (mixed) {
            UiIcons.draw(mark, Minus, 0, 0, size, Theme.MUTED);
        } else {
            UiIcons.draw(mark, Check, 0, 0, size, Theme.ACCENT_HOVER);
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
