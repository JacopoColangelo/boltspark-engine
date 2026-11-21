package boltspark.ui.windows;

import boltspark.editor.EditorAction;
import boltspark.editor.Keybindings;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.widgets.ScrollBar;
import boltspark.ui.widgets.UiButton;

/** Retained-H2D content rendered inside the native Editor Keybindings HWND. */
class KeybindingsWindowContent extends h2d.Object {
    public static inline var DEFAULT_WIDTH:Int = 460;
    public static inline var DEFAULT_HEIGHT:Int = 640;
    public static inline var MIN_WIDTH:Int = 420;
    public static inline var MIN_HEIGHT:Int = 360;

    static inline var PADDING:Int = 16;
    static inline var LIST_TOP:Int = 48;
    static inline var FOOTER_HEIGHT:Int = 52;
    static inline var ROW_HEIGHT:Int = 30;
    static inline var HEADER_HEIGHT:Int = 24;
    static inline var SEPARATOR_HEIGHT:Int = 10;
    static inline var BINDING_WIDTH:Int = 136;
    static inline var SCROLL_GUTTER:Int = 12;

    /**
     * Display order is deliberately independent of `EditorAction` indices:
     * those indices are persisted in keybindings.json and must stay stable.
     * Group by what the shortcuts do, not by when the action was added.
     */
    static final CATEGORIES:Array<{ name:String, actions:Array<EditorAction> }> = [
        { name: "TOOLS", actions: [
            EditorAction.ToolMove, EditorAction.ToolRotate, EditorAction.ToolScale
        ] },
        { name: "VIEWPORT", actions: [
            EditorAction.FocusSelection, EditorAction.ToggleGrid
        ] },
        { name: "EDITING", actions: [
            EditorAction.Undo, EditorAction.Redo,
            EditorAction.DeleteSelection, EditorAction.RenameSelection
        ] },
        { name: "SNAPPING", actions: [
            EditorAction.SnapToGrid, EditorAction.HoldSnapOff
        ] },
        { name: "CLIPBOARD", actions: [
            EditorAction.CopySelection, EditorAction.CutAsset,
            EditorAction.Paste, EditorAction.DuplicateSelection
        ] },
        { name: "FILES", actions: [
            EditorAction.SaveCurrentScene, EditorAction.SaveAll
        ] }
    ];

    final context:UiContext;
    final keybindings:Keybindings;
    final background:UiSurface;
    final windowCatch:h2d.Interactive;
    final listMask:h2d.Mask;
    final listScrollBar:ScrollBar;
    final divider:h2d.Graphics;
    final categoryDividers:h2d.Graphics;
    final bindingButtons:Array<UiButton> = [];
    final resetButton:UiButton;
    final statusText:h2d.Text;
    var captureTarget:EditorAction = cast -1;
    var lastWidth:Int = -1;
    var lastHeight:Int = -1;
    var maxListScroll:Float = 0;
    var listScrollValue:Float = 0;
    var contentHeightValue:Float = 0;
    var lastProbeState:String = "";
    // Status text is the only label whose content changes with width. Cache
    // its glyph measurements so a resize drag never re-runs text layout.
    var statusSource:String = "";
    var statusPrefixWidths:Array<Float> = [];
    var statusEllipsisWidth:Float = -1;

    public function new(context:UiContext, keybindings:Keybindings, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        this.keybindings = keybindings;

        background = new UiSurface(context, this);
        background.setStyle(Theme.PANEL, Theme.PANEL, 0);
        // Consume otherwise empty client-area presses so this top-level window
        // never routes pointer input into another application window. Keep the
        // arrow cursor here: h2d.Interactive defaults to Cursor.Button, whose
        // native mapping is the pointing-hand cursor.
        windowCatch = new h2d.Interactive(1, 1, this);
        windowCatch.backgroundColor = 0;
        windowCatch.cursor = hxd.Cursor.Default;
        windowCatch.onPush = function(event) event.propagate = false;
        windowCatch.onWheel = function(event) {
            var inList = event.relY >= LIST_TOP && event.relY <= listMask.y + listMask.height;
            if (inList) scrollList(event.wheelDelta);
            event.propagate = false;
        };

        var heading = new UiText(context.titleFont, this);
        heading.text = "Keyboard Shortcuts";
        heading.textColor = Theme.TEXT;
        heading.lineBreak = false;
        heading.x = PADDING;
        heading.y = 12;

        // The binding rows live inside a clip mask so the window can shrink
        // below the full list height and still expose every action by scrolling.
        listMask = new h2d.Mask(1, 1, this);
        listScrollBar = new ScrollBar(context, this);
        listScrollBar.onChange = function(value) {
            listScrollValue = value;
            applyListScroll();
        };

        categoryDividers = new h2d.Graphics(listMask);
        var cursorY:Float = 0;
        for (categoryIndex in 0...CATEGORIES.length) {
            var category = CATEGORIES[categoryIndex];
            if (categoryIndex > 0) cursorY += SEPARATOR_HEIGHT;

            var header = new UiText(context.semiboldFont, listMask);
            header.text = category.name;
            header.textColor = Theme.ACCENT;
            header.lineBreak = false;
            header.x = PADDING + 4;
            header.y = cursorY
                + Math.round((HEADER_HEIGHT - header.textHeight) * 0.5 - 1);
            cursorY += HEADER_HEIGHT;

            for (action in category.actions) {
                var label = new UiText(context.labelFont, listMask);
                label.text = Keybindings.actionName(action);
                label.textColor = Theme.TEXT_SECONDARY;
                label.lineBreak = false;
                label.x = PADDING + 12;
                label.y = cursorY + Math.round((24 - label.textHeight) * 0.5 - 1);

                var bindingButton = new UiButton(context, "", BINDING_WIDTH, 24, listMask);
                bindingButton.y = cursorY + 3;
                bindingButton.onClick = function() {
                    captureTarget = action;
                    keybindings.beginCapture(action);
                    refresh();
                };
                // Index by the persisted action id, not display order, so
                // refresh and layout always target the correct binding.
                bindingButtons[action] = bindingButton;
                cursorY += ROW_HEIGHT;
            }
        }
        contentHeightValue = cursorY;
        categoryDividers.clear();
        categoryDividers.lineStyle(1, Theme.BORDER, 1);
        cursorY = 0;
        for (categoryIndex in 0...CATEGORIES.length) {
            if (categoryIndex > 0) {
                var lineY = cursorY + SEPARATOR_HEIGHT * 0.5;
                categoryDividers.moveTo(PADDING + 4, lineY);
                categoryDividers.lineTo(
                    BINDING_WIDTH + PADDING + 12, lineY);
                cursorY += SEPARATOR_HEIGHT;
            }
            cursorY += HEADER_HEIGHT + CATEGORIES[categoryIndex].actions.length * ROW_HEIGHT;
        }
        categoryDividers.lineStyle();

        divider = new h2d.Graphics(this);

        resetButton = new UiButton(context, "Reset to Defaults", 132, 24, this);
        resetButton.x = PADDING;
        resetButton.onClick = function() {
            keybindings.cancelCapture();
            captureTarget = cast -1;
            keybindings.resetDefaults();
            refresh();
        };

        statusText = new UiText(context.captionFont, this);
        statusText.lineBreak = false;

        keybindings.onChanged = refresh;
        resize();
        refresh();
    }

    public function update():Void {
        if (lastWidth != context.width || lastHeight != context.height) resize();
    }

    public function resize():Void {
        var width = context.width;
        var height = context.height;
        // onResize() and update() can both request a layout in the same frame.
        // Doing it twice re-assigns every text object and makes labels shimmer
        // while the window is being dragged, so only real size changes apply.
        if (width == lastWidth && height == lastHeight) return;
        var widthChanged = width != lastWidth;
        lastWidth = width;
        lastHeight = height;
        background.setSize(width, height);
        windowCatch.width = width;
        windowCatch.height = height;

        var listHeight = Math.max(0, height - LIST_TOP - FOOTER_HEIGHT);
        listMask.width = Std.int(Math.max(0, width));
        listMask.height = Std.int(listHeight);
        listMask.y = LIST_TOP;

        var contentHeight = contentHeightValue;
        // Preserve the absolute pixel offset, not the normalized fraction.
        // Otherwise a vertical resize maps the same fraction to a different
        // pixel offset and the whole list jumps while dragging the border.
        var previousOffset = Math.round(maxListScroll * listScrollValue);
        maxListScroll = Math.max(0, contentHeight - listHeight);
        var ratio = contentHeight <= 0 ? 1 : Math.min(1, listHeight / contentHeight);
        listScrollValue = maxListScroll <= 0
            ? 0 : Math.max(0, Math.min(1, previousOffset / maxListScroll));
        listScrollBar.setBounds(width - SCROLL_GUTTER, LIST_TOP + 2,
            4, Math.max(0, listHeight - 4));
        listScrollBar.setMetrics(ratio, listScrollValue);
        applyListScroll();

        var buttonX = width - PADDING - BINDING_WIDTH - SCROLL_GUTTER;
        for (actionIndex in 0...EditorAction.ACTION_COUNT) {
            var button = bindingButtons[actionIndex];
            if (button != null) button.x = buttonX;
        }

        var footerY = height - 39;
        divider.clear();
        divider.lineStyle(1, Theme.BORDER, 1);
        divider.moveTo(PADDING, footerY - 8.5);
        divider.lineTo(width - PADDING, footerY - 8.5);
        divider.lineStyle();
        resetButton.y = footerY;
        statusText.x = PADDING + 144;
        statusText.y = footerY + 5;
        // The footer's available width only depends on window width, so a
        // height-only drag needs no status refit at all.
        if (widthChanged) refreshStatus();
        reportProbeState();
    }

    /**
     * The keybindings window is a grandchild process whose stdout is not
     * inherited by a redirected parent probe. Probe runs therefore direct
     * this one line to an env-specified file; normal runs emit nothing.
     */
    function reportProbeState():Void {
        var line = '[keybindings] actions=${EditorAction.ACTION_COUNT} '
            + 'categories=${CATEGORIES.length} '
            + 'listHeight=${Std.int(listMask.height)} '
            + 'scrollable=${maxListScroll > 0}';
        if (line == lastProbeState) return;
        lastProbeState = line;
        var probeLog = Sys.getEnv("BOLTSPARK_PROBE_LOG");
        if (probeLog != null && probeLog != "") {
            try {
                sys.io.File.saveContent(probeLog, line);
            } catch (_:Dynamic) {}
        } else if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println(line);
        }
    }

    function scrollList(delta:Float):Void {
        if (maxListScroll <= 0) return;
        // HashLink/Windows normalizes a downward wheel step to a positive delta.
        listScrollValue = Math.max(0, Math.min(1,
            listScrollValue + delta * ROW_HEIGHT / maxListScroll));
        applyListScroll();
        listScrollBar.setMetrics(
            listMask.height / Math.max(1, contentHeightValue),
            listScrollValue);
    }

    function applyListScroll():Void {
        // Integer scroll keeps masked FreeType glyphs on whole pixels; a
        // fractional offset shimmers as the window is resized.
        var next = Math.round(maxListScroll * listScrollValue);
        if (listMask.scrollY == next) return;
        listMask.scrollY = next;
    }

    /** Re-sync every binding button and the status line with the registry. */
    function refresh():Void {
        for (actionIndex in 0...EditorAction.ACTION_COUNT) {
            var button = bindingButtons[actionIndex];
            if (button == null) continue;
            var action:EditorAction = actionIndex;
            button.setText(isCapturing(action)
                ? "press a key..."
                : keybindings.bindingLabel(action));
        }
        refreshStatus();
    }

    function refreshStatus():Void {
        var status = keybindings.lastError == ""
            ? "Changes save automatically"
            : keybindings.lastError;
        if (status != statusSource) {
            statusSource = status;
            statusPrefixWidths.resize(0);
            var prefix = "";
            for (index in 0...status.length) {
                prefix += status.charAt(index);
                statusPrefixWidths.push(statusText.calcTextWidth(prefix));
            }
            if (statusEllipsisWidth < 0) {
                statusEllipsisWidth = statusText.calcTextWidth("…");
            }
        }
        var fitted = fitStatus(context.width - statusText.x - PADDING);
        // Assigning h2d.Text.text re-tessellates the glyph run. Skip it when
        // unchanged so resize frames do not re-rasterize the footer label.
        if (statusText.text != fitted) statusText.text = fitted;
        var color = keybindings.lastError == "" ? Theme.MUTED : Theme.DANGER;
        if (statusText.textColor != color) statusText.textColor = color;
    }

    /** Elide from cached prefix widths; no glyph layout during resize. */
    function fitStatus(maxWidth:Float):String {
        var count = statusPrefixWidths.length;
        if (count == 0) return "";
        if (statusPrefixWidths[count - 1] <= maxWidth) return statusSource;
        var limit = maxWidth - statusEllipsisWidth;
        var keep = 0;
        for (width in statusPrefixWidths) {
            if (width > limit) break;
            keep++;
        }
        return statusSource.substr(0, keep) + "…";
    }

    inline function isCapturing(action:EditorAction):Bool {
        return keybindings.capturePending && captureTarget == action;
    }
}
