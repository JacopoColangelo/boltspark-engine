package boltspark.ui.widgets;

import boltspark.editor.GridSnapping;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiIcons.UiIconKind;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/**
 * Unreal Engine-style snap toolbar for the editor viewport HUD.
 *
 * One compact row rendered next to the view-mode control with three
 * toggle/value pairs:
 *
 *   [move toggle][value v]  [rotate toggle][value v]  [scale toggle][value v]
 *
 * A toggle button flips the matching GridSnapping enable flag; the value
 * button beside it opens a preset dropdown showing the active step (marked
 * with an accent dot) and lets the user switch steps at any time. The row is
 * built from h2d.Flow cell layout over native H2D widgets — no DOM, no
 * foreign UI layer.
 */
class ViewportSnapBar extends h2d.Object {
    static inline var CELL_HEIGHT:Int = 22;
    static inline var TOGGLE_WIDTH:Int = 24;
    static inline var VALUE_WIDTH:Int = 48;
    static inline var PAIR_SPACING:Int = 4;

    static inline var POPUP_ROW_HEIGHT:Int = 19;
    static inline var POPUP_WIDTH:Int = 58;
    static inline var POPUP_PADDING:Int = 3;

    /** Fired after a toggle flip or a preset change; argument is the mode. */
    public var onSnapChanged:Null<Int->Void>;

    final context:UiContext;
    final snapping:GridSnapping;

    // Cell layout: no strip background — the toggle/value cells float
    // directly over the viewport for a cleaner look.
    final flow:h2d.Flow;
    final toggleCells:Array<h2d.Object> = [];
    final toggleSurfaces:Array<UiSurface> = [];
    final toggleHits:Array<h2d.Interactive> = [];
    final toggleIcons:Array<h2d.Graphics> = [];
    final valueCells:Array<h2d.Object> = [];
    final valueSurfaces:Array<UiSurface> = [];
    final valueHits:Array<h2d.Interactive> = [];
    final valueTexts:Array<h2d.Text> = [];
    final valueChevrons:Array<h2d.Graphics> = [];

    // Preset dropdown popup. Background and event catcher are built once;
    // the row list is rebuilt into a clip mask on every open so it always
    // mirrors the manager state.
    final popupRoot:h2d.Object;
    final popupBackground:UiSurface;
    final popupCatch:h2d.Interactive;
    var popupRows:h2d.Mask;
    var popupMode:Int = -1;
    /** Usable height of the HUD container in bar-local coordinates. */
    var containerHeight:Float = 0;
    var popupHeight:Float = 0;

    public function new(context:UiContext, snapping:GridSnapping, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        this.snapping = snapping;

        flow = new h2d.Flow(this);
        flow.layout = h2d.Flow.FlowLayout.Horizontal;
        flow.horizontalSpacing = PAIR_SPACING;
        flow.verticalAlign = h2d.Flow.FlowAlign.Middle;

        var icons:Array<UiIconKind> = [Move, Rotate, Scale];
        for (mode in 0...3) {
            var capturedMode = mode;

            // Toggle cell: flips the snapping enable flag for this mode.
            var toggleCell = new h2d.Object(flow);
            var toggleSurface = new UiSurface(context, toggleCell);
            toggleSurface.setSize(TOGGLE_WIDTH, CELL_HEIGHT);
            var toggleHit = new h2d.Interactive(TOGGLE_WIDTH, CELL_HEIGHT, toggleCell);
            toggleHit.backgroundColor = 0;
            toggleHit.cursor = hxd.Cursor.Default;
            toggleHit.onOver = function(_) redrawCell(capturedMode, true);
            toggleHit.onOut = function(_) redrawCell(capturedMode, false);
            toggleHit.onPush = function(event) {
                event.propagate = false;
                toggleMode(capturedMode);
            };
            var toggleIcon = new h2d.Graphics(toggleCell);
            UiIcons.draw(toggleIcon, icons[mode], 0, 0, 12, Theme.TEXT_SECONDARY);

            // Value cell: opens the preset dropdown for this mode.
            var valueCell = new h2d.Object(flow);
            var valueSurface = new UiSurface(context, valueCell);
            valueSurface.setSize(VALUE_WIDTH, CELL_HEIGHT);
            var valueHit = new h2d.Interactive(VALUE_WIDTH, CELL_HEIGHT, valueCell);
            valueHit.backgroundColor = 0;
            valueHit.cursor = hxd.Cursor.Default;
            valueHit.onOver = function(_) redrawCell(capturedMode, true);
            valueHit.onOut = function(_) redrawCell(capturedMode, false);
            valueHit.onPush = function(event) {
                event.propagate = false;
                togglePopup(capturedMode);
            };
            var valueText = new UiText(context.captionFont, valueCell);
            valueText.lineBreak = false;
            // Inset from the cell border; the chevron owns the right side.
            valueText.x = 6;
            var chevron = new h2d.Graphics(valueCell);
            UiIcons.draw(chevron, ChevronDown, 0, 0, 8, Theme.MUTED);

            toggleCells.push(toggleCell);
            toggleSurfaces.push(toggleSurface);
            toggleHits.push(toggleHit);
            toggleIcons.push(toggleIcon);
            valueCells.push(valueCell);
            valueSurfaces.push(valueSurface);
            valueHits.push(valueHit);
            valueTexts.push(valueText);
            valueChevrons.push(chevron);
        }

        // Shared preset popup chrome. The row list is clipped and scrolled
        // inside a mask so the menu can never render outside its container.
        popupRoot = new h2d.Object(this);
        popupRoot.visible = false;
        popupBackground = new UiSurface(context, popupRoot);
        popupBackground.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        popupCatch = new h2d.Interactive(1, 1, popupRoot);
        popupCatch.backgroundColor = 0;
        popupCatch.cursor = hxd.Cursor.Default;
        // Swallow presses on the popup body so they cannot fall through to the
        // viewport (which would run object picking underneath the menu), and
        // scroll the clipped row list with the wheel.
        popupCatch.onPush = function(event) event.propagate = false;
        popupCatch.onWheel = function(event) {
            if (popupRows == null) return;
            var contentHeight = GridSnapping.presetCount(popupMode) * POPUP_ROW_HEIGHT;
            if (popupRows.height >= contentHeight) return;
            popupRows.scrollBy(0, -event.wheelDelta * POPUP_ROW_HEIGHT * 2);
            event.propagate = false;
        };

        flow.reflow();
        refresh();
    }

    public var popupOpen(get, never):Bool;
    inline function get_popupOpen():Bool return popupMode >= 0;

    /**
     * Report the usable height of the HUD container in bar-local coordinates
     * (viewport height minus its top and bottom margins). Called on resize;
     * an open dropdown is closed so its clamped geometry is never stale.
     */
    public function setContainerHeight(value:Float):Void {
        containerHeight = Math.max(0, value);
        if (popupMode >= 0) closePopup();
    }

    /** Close the preset dropdown if it is open (background-click plumbing). */
    public function closePopup():Void {
        if (popupMode < 0) return;
        popupMode = -1;
        popupRoot.visible = false;
        refresh();
    }

    /** Re-sync every cell with the GridSnapping manager state. */
    public function refresh():Void {
        for (mode in 0...3) {
            valueTexts[mode].text = formatPreset(mode, snapStep(mode));
            context.centerY(valueTexts[mode], 0, CELL_HEIGHT);
            redrawCell(mode, false);
        }
    }

    /** `true` while the pointer hovers a cell of this mode. */
    function hoveredCell(mode:Int):Bool {
        return toggleHits[mode].isOver() || valueHits[mode].isOver();
    }

    function snapStep(mode:Int):Float {
        return GridSnapping.presetAt(mode, snapping.presetIndex(mode));
    }

    function toggleMode(mode:Int):Void {
        var enabled = !snapping.isEnabled(mode);
        snapping.setEnabled(mode, enabled);
        refresh();
        if (onSnapChanged != null) onSnapChanged(mode);
    }

    function togglePopup(mode:Int):Void {
        if (popupMode == mode) {
            closePopup();
            return;
        }
        closePopup();
        openPopup(mode);
    }

    function openPopup(mode:Int):Void {
        popupMode = mode;
        var rows = GridSnapping.presetCount(mode);
        var fullHeight = rows * POPUP_ROW_HEIGHT + POPUP_PADDING * 2;

        // Open below the value cell. The bar is a child of the viewport HUD,
        // so containerHeight is measured in the same bar-local coordinates.
        var cell = valueCells[mode];
        popupRoot.x = flow.x + cell.x;
        var popupTop = flow.y + flow.outerHeight + 1;
        popupRoot.y = popupTop;
        var available = containerHeight - popupTop - 2;
        popupHeight = available >= fullHeight ? fullHeight
            : Math.max(POPUP_PADDING * 2 + POPUP_ROW_HEIGHT, available);

        popupBackground.setSize(POPUP_WIDTH, popupHeight);
        popupBackground.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);
        popupCatch.width = POPUP_WIDTH;
        popupCatch.height = popupHeight;

        // Rebuild the row list inside a clip mask sized to the available
        // height, so long lists scroll instead of overflowing the container.
        if (popupRows != null) popupRows.remove();
        popupRows = new h2d.Mask(
            Std.int(POPUP_WIDTH - POPUP_PADDING * 2),
            Std.int(popupHeight - POPUP_PADDING * 2), popupRoot);
        popupRows.x = POPUP_PADDING;
        popupRows.y = POPUP_PADDING;
        popupRows.scrollBounds = new h2d.col.Bounds();
        popupRows.scrollBounds.xMin = 0;
        popupRows.scrollBounds.xMax = popupRows.width;
        popupRows.scrollBounds.yMin = 0;
        popupRows.scrollBounds.yMax = rows * POPUP_ROW_HEIGHT;

        var activeIndex = snapping.presetIndex(mode);
        for (index in 0...rows) {
            var rowIndex = index;
            var rowY = rowIndex * POPUP_ROW_HEIGHT;
            var rowSurface = new UiSurface(context, popupRows);
            rowSurface.setSize(popupRows.width, POPUP_ROW_HEIGHT - 1);
            rowSurface.setStyle(Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
            var rowHit = new h2d.Interactive(popupRows.width, POPUP_ROW_HEIGHT - 1, popupRows);
            rowHit.backgroundColor = 0;
            rowHit.cursor = hxd.Cursor.Default;
            rowHit.onOver = function(_) rowSurface.setStyle(
                Theme.SURFACE_3, Theme.ACCENT, 0);
            rowHit.onOut = function(_) rowSurface.setStyle(
                Theme.PANEL_ALT, Theme.PANEL_ALT, 0);
            rowHit.onPush = function(event) {
                event.propagate = false;
                snapping.setPresetIndex(popupMode, rowIndex);
                var changedMode = popupMode;
                closePopup();
                refresh();
                if (onSnapChanged != null) onSnapChanged(changedMode);
            };

            var active = rowIndex == activeIndex;
            if (active) {
                var dot = new h2d.Graphics(popupRows);
                dot.y = rowY;
                dot.beginFill(Theme.ACCENT, 1);
                dot.drawCircle(7, POPUP_ROW_HEIGHT * 0.5 - 0.5, 2);
                dot.endFill();
            }
            var label = new UiText(context.captionFont, popupRows);
            label.text = formatPreset(mode, GridSnapping.presetAt(mode, rowIndex));
            label.lineBreak = false;
            label.textColor = active ? Theme.ACCENT : Theme.TEXT_SECONDARY;
            label.x = 15;
            label.y = rowY + Math.round(
                (POPUP_ROW_HEIGHT - label.textHeight) * 0.5 - 1);

            // Manual row layout: the mask clips and scrolls; it never reflows.
            rowSurface.y = rowHit.y = rowY + 1;
        }

        popupRoot.visible = true;
        refresh();
    }

    /** Repaint one toggle/value pair for its enabled/hover/popup state. */
    function redrawCell(mode:Int, _:Bool):Void {
        // Holding the temporary translation override should look disabled as
        // well as behave disabled, without changing the stored toggle state.
        var enabled = mode == GridSnapping.MODE_TRANSLATION
            ? snapping.translationSnapActive
            : snapping.isEnabled(mode);
        var hovered = hoveredCell(mode);
        var icon = mode == GridSnapping.MODE_TRANSLATION
            ? Move : (mode == GridSnapping.MODE_ROTATION ? Rotate : Scale);

        if (enabled) {
            toggleSurfaces[mode].setStyle(Theme.ACCENT_MUTED, Theme.ACCENT, 0);
            UiIcons.draw(toggleIcons[mode], icon, 0, 0, 12, Theme.TEXT);
        } else {
            toggleSurfaces[mode].setStyle(
                hovered ? Theme.SURFACE_2 : Theme.TITLE_BAR,
                hovered ? Theme.BORDER_STRONG : Theme.BORDER, 0);
            UiIcons.draw(toggleIcons[mode], icon, 0, 0, 12, Theme.TEXT_SECONDARY);
        }
        centerToggleIcon(mode);

        // Value cell: accent while snapping is on; accent border while its
        // dropdown is open.
        var valueBorder = popupMode == mode ? Theme.ACCENT : Theme.BORDER_STRONG;
        valueSurfaces[mode].setStyle(Theme.TITLE_BAR, valueBorder, 0);
        valueTexts[mode].textColor = enabled ? Theme.ACCENT : Theme.MUTED;
        UiIcons.draw(valueChevrons[mode], ChevronDown, 0, 0, 8,
            popupMode == mode ? Theme.ACCENT : Theme.MUTED);
        valueChevrons[mode].x = VALUE_WIDTH - 14;
        valueChevrons[mode].y = Math.round((CELL_HEIGHT - 8) * 0.5);
    }

    function centerToggleIcon(mode:Int):Void {
        toggleIcons[mode].x = Math.round((TOGGLE_WIDTH - 12) * 0.5);
        toggleIcons[mode].y = Math.round((CELL_HEIGHT - 12) * 0.5);
    }

    /** Compact preset label: "10" / "10°" / "0.25" style values. */
    function formatPreset(mode:Int, value:Float):String {
        if (mode == GridSnapping.MODE_ROTATION) {
            var number = value % 1 == 0
                ? Std.string(Std.int(value))
                : Std.string(value);
            return number + "°";
        }
        return Std.string(Math.round(value * 100) / 100);
    }
}
