package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
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
    ?mixed:Bool
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

    final context:UiContext;
    /** Full-window catch behind the rows: any outside left-click dismisses. */
    final dismissCatch:h2d.Interactive;
    final levels:Array<MenuLevel> = [];

    public var isOpen(default, null):Bool = false;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        dismissCatch = new h2d.Interactive(1, 1, this);
        dismissCatch.backgroundColor = 0;
        dismissCatch.cursor = hxd.Cursor.Default;
        dismissCatch.onPush = function(event) {
            event.propagate = false;
            close();
        };
        dismissCatch.visible = false;
    }

    /** Open the dropdown at window coordinates (x, y) with these items. */
    public function open(x:Float, y:Float, items:Array<MenuItem>):Void {
        closeLevelsFrom(0);
        var width = measureItems(items);
        var height = measureHeight(items);
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

        buildLevel(items, null, 0);
        visible = true;
        isOpen = true;
        Sys.println('[probe] menu open');
    }

    public function close():Void {
        if (!isOpen) return;
        closeLevelsFrom(0);
        dismissCatch.visible = false;
        visible = false;
        isOpen = false;
        Sys.println('[probe] menu close');
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
            rowY:Float):MenuLevel {
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

        var hasStates = hasSelectionState(items);
        level.width = measureItems(items);
        level.height = measureHeight(items);
        level.surface.setSize(level.width, level.height);
        level.hitCatch.width = level.width;
        level.hitCatch.height = level.height;

        var cursor = PADDING;
        for (index in 0...items.length) {
            var item = items[index];
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
        levels.push(level);
        return level;
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
            activate();
        };
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
