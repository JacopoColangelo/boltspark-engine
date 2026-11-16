package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/** One dropdown menu entry; `submenu` turns the row into a cascade parent. */
typedef MenuItem = {
    label:String,
    ?onClick:Void->Void,
    ?submenu:Array<MenuItem>
};

/**
 * Native dropdown menu for the editor title bar, with one level of cascade
 * submenus (File > Editor Settings > Editor Keybindings). Built from the
 * same retained-H2D popup patterns as the object palette: UiSurface chrome,
 * per-row interactives, and manual row layout. Rows are rebuilt into fresh
 * row containers on every open so the menu always reflects live state.
 */
class MenuDropdown extends h2d.Object {
    static inline var ROW_HEIGHT:Int = 22;
    static inline var PADDING:Int = 3;
    static inline var MIN_WIDTH:Int = 168;

    final context:UiContext;
    final panel:h2d.Object;
    final panelSurface:UiSurface;
    final panelCatch:h2d.Interactive;
    final submenu:h2d.Object;
    final submenuSurface:UiSurface;
    final submenuCatch:h2d.Interactive;
    /** Row containers rebuilt per open; only these are ever removed. */
    final panelRows:Array<h2d.Object> = [];
    final submenuRows:Array<h2d.Object> = [];
    var panelWidth:Float = MIN_WIDTH;
    var panelHeight:Float = 0;
    var submenuOpen:Bool = false;

    public var isOpen(default, null):Bool = false;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        panel = new h2d.Object(this);
        panelSurface = new UiSurface(context, panel);
        panelSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        panelCatch = new h2d.Interactive(1, 1, panel);
        panelCatch.backgroundColor = 0;
        panelCatch.cursor = hxd.Cursor.Default;
        // Swallow presses on the menu body so they cannot fall through to the
        // viewport or the chrome underneath.
        panelCatch.onPush = function(event) event.propagate = false;

        submenu = new h2d.Object(this);
        submenuSurface = new UiSurface(context, submenu);
        submenuSurface.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        submenuCatch = new h2d.Interactive(1, 1, submenu);
        submenuCatch.backgroundColor = 0;
        submenuCatch.cursor = hxd.Cursor.Default;
        submenuCatch.onPush = function(event) event.propagate = false;
        submenu.visible = false;
    }

    /** Open the dropdown at window coordinates (x, y) with these items. */
    public function open(x:Float, y:Float, items:Array<MenuItem>):Void {
        clearRows(panelRows);
        closeSubmenu();

        panelWidth = MIN_WIDTH;
        for (item in items) {
            panelWidth = Math.max(panelWidth, measureLabel(item.label) + 44);
        }
        panelHeight = items.length * ROW_HEIGHT + PADDING * 2;
        panelSurface.setSize(panelWidth, panelHeight);
        panelCatch.width = panelWidth;
        panelCatch.height = panelHeight;

        for (index in 0...items.length) {
            var item = items[index];
            var rowY = PADDING + index * ROW_HEIGHT;
            var row = new h2d.Object(panel);
            panelRows.push(row);
            addRowContent(row, item, rowY, panelWidth,
                item.submenu != null
                    ? function() openSubmenu(item, rowY)
                    : function() {
                        close();
                        if (item.onClick != null) item.onClick();
                    },
                item.submenu != null, true);
        }

        // Clamp inside the window frame.
        this.x = Math.max(4, Math.min(x, context.width - panelWidth - 4));
        this.y = Math.max(4, Math.min(y, context.height - panelHeight - 4));
        visible = true;
        isOpen = true;
    }

    public function close():Void {
        if (!isOpen) return;
        clearRows(panelRows);
        closeSubmenu();
        visible = false;
        isOpen = false;
    }

    function closeSubmenu():Void {
        clearRows(submenuRows);
        submenu.visible = false;
        submenuOpen = false;
    }

    function openSubmenu(item:MenuItem, rowY:Float):Void {
        closeSubmenu();
        var items = item.submenu;
        var width:Float = MIN_WIDTH;
        for (sub in items) {
            width = Math.max(width, measureLabel(sub.label) + 44);
        }
        var height = items.length * ROW_HEIGHT + PADDING * 2;
        submenuSurface.setSize(width, height);
        submenuCatch.width = width;
        submenuCatch.height = height;

        for (index in 0...items.length) {
            var sub = items[index];
            var subRowY = PADDING + index * ROW_HEIGHT;
            var row = new h2d.Object(submenu);
            submenuRows.push(row);
            addRowContent(row, sub, subRowY, width, function() {
                close();
                if (sub.onClick != null) sub.onClick();
            }, false, false);
        }
        // Prefer a right-opening cascade, but flip left and vertically clamp
        // when the parent menu is near a window edge.
        submenu.x = this.x + panelWidth + width <= context.width - 4
            ? panelWidth - 2
            : -width + 2;
        var minLocalY = 4 - this.y;
        var maxLocalY = context.height - this.y - height - 4;
        submenu.y = Math.max(minLocalY, Math.min(rowY, maxLocalY));
        submenu.visible = true;
        submenuOpen = true;
    }

    function clearRows(rows:Array<h2d.Object>):Void {
        for (row in rows) row.remove();
        rows.resize(0);
    }

    function addRowContent(row:h2d.Object, item:MenuItem, rowY:Float, width:Float,
            activate:Void->Void, hasSubmenu:Bool, panelRow:Bool):Void {
        // The wrapper is positioned at the row's Y; all content is relative.
        row.y = rowY;
        var rowSurface = new UiSurface(context, row);
        rowSurface.setSize(width - PADDING * 2, ROW_HEIGHT - 1);
        rowSurface.setStyle(Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
        var rowHit = new h2d.Interactive(width - PADDING * 2, ROW_HEIGHT - 1, row);
        rowHit.backgroundColor = 0;
        rowHit.cursor = hxd.Cursor.Default;
        rowHit.onOver = function(_) {
            rowSurface.setStyle(Theme.SURFACE_3, Theme.ACCENT, 0);
            // Cascade parents open their submenu on hover; plain rows close
            // an open cascade only when they belong to the parent panel. A
            // leaf inside the submenu must not close the submenu containing it.
            if (hasSubmenu) activate() else if (panelRow) closeSubmenu();
        };
        rowHit.onOut = function(_) rowSurface.setStyle(
            Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
        rowHit.onPush = function(event) {
            event.propagate = false;
            activate();
        };
        var label = new UiText(context.font, row);
        label.text = item.label;
        label.lineBreak = false;
        label.textColor = Theme.TEXT;
        label.x = 10;
        label.y = Math.round((ROW_HEIGHT - label.textHeight) * 0.5 - 1);
        if (hasSubmenu) {
            var chevron = new h2d.Graphics(row);
            UiIcons.draw(chevron, ChevronRight, 0, 0, 9, Theme.MUTED);
            chevron.x = width - PADDING - 16;
            chevron.y = Math.round((ROW_HEIGHT - 9) * 0.5);
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
