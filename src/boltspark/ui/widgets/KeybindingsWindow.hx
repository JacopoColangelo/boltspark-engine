package boltspark.ui.widgets;

import boltspark.editor.EditorAction;
import boltspark.editor.Keybindings;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

/**
 * Floating editor settings window: File > Editor Settings > Editor
 * Keybindings. Lists every keyboard action with its current binding; clicking
 * a binding button arms the Keybindings registry's capture mode, and the next
 * key press (Escape cancels) rebinds the action. Mouse interactions are
 * listed read-only since viewport bindings are structural. Non-modal: the
 * editor stays live while the window floats, and the title bar drags.
 */
class KeybindingsWindow extends h2d.Object {
    static inline var WIDTH:Int = 372;
    static inline var ROW_HEIGHT:Int = 26;
    static inline var PADDING:Int = 6;
    /** Space under the binding rows for the mouse reference + footer. */
    static inline var FOOTER_SPACE:Int = 74;

    final context:UiContext;
    final keybindings:Keybindings;
    final background:UiSurface;
    final windowCatch:h2d.Interactive;
    final titleBar:h2d.Interactive;
    final titleText:h2d.Text;
    final closeButton:UiButton;
    final resetButton:UiButton;
    final statusText:h2d.Text;
    final bindingButtons:Array<UiButton> = [];
    final rows:h2d.Object;
    /** Window-local drag offset while the title bar is captured. */
    var dragOffsetX:Float = 0;
    var dragOffsetY:Float = 0;

    public var isOpen(default, null):Bool = false;

    public function new(context:UiContext, keybindings:Keybindings, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        this.keybindings = keybindings;
        visible = false;

        background = new UiSurface(context, this);
        background.setSize(WIDTH, contentHeight());
        background.setStyle(Theme.PANEL, Theme.BORDER_STRONG, 0.36);
        // Consume blank-window presses/wheel events so this non-modal window
        // does not accidentally pick or edit content directly underneath it.
        windowCatch = new h2d.Interactive(WIDTH, contentHeight(), this);
        windowCatch.backgroundColor = 0;
        windowCatch.onPush = function(event) event.propagate = false;
        windowCatch.onWheel = function(event) event.propagate = false;

        // Title bar doubles as the drag surface.
        titleBar = new h2d.Interactive(WIDTH - 26, 24, this);
        titleBar.x = 0;
        titleBar.y = 0;
        titleBar.backgroundColor = 0;
        titleBar.cursor = hxd.Cursor.Move;
        titleText = new UiText(context.semiboldFont, this);
        titleText.text = "Editor Keybindings";
        titleText.textColor = Theme.TEXT;
        titleText.lineBreak = false;
        titleText.x = 10;
        titleText.y = 4;
        closeButton = new UiButton(context, "", 20, 20, this);
        closeButton.setIcon(Close).setQuiet();
        closeButton.x = WIDTH - 23;
        closeButton.y = 2;
        closeButton.onClick = close;

        rows = new h2d.Object(this);
        for (actionIndex in 0...EditorAction.ACTION_COUNT) {
            var action:EditorAction = actionIndex;
            var rowY = PADDING + 26 + actionIndex * ROW_HEIGHT;
            var label = new UiText(context.labelFont, rows);
            label.text = Keybindings.actionName(action);
            label.textColor = Theme.TEXT_SECONDARY;
            label.lineBreak = false;
            label.x = PADDING + 4;
            label.y = rowY + Math.round((ROW_HEIGHT - label.textHeight) * 0.5 - 1);
            var bindingButton = new UiButton(context, "", 108, 22, rows);
            bindingButton.x = WIDTH - 108 - PADDING - 4;
            bindingButton.y = rowY;
            bindingButton.onClick = function() {
                // Clicking a row arms capture for it; the next key press
                // (Escape cancels) rebinds the action via the registry.
                captureTarget = action;
                keybindings.beginCapture(action);
                refresh();
            };
            bindingButtons.push(bindingButton);
        }

        // Mouse interactions are structural: listed for reference, not bound.
        var mouseHeader = new UiText(context.captionFont, rows);
        mouseHeader.text = "Mouse (fixed)";
        mouseHeader.textColor = Theme.MUTED;
        mouseHeader.lineBreak = false;
        mouseHeader.x = PADDING + 4;
        mouseHeader.y = PADDING + 26 + EditorAction.ACTION_COUNT * ROW_HEIGHT + 6;
        var mouseInfo = new UiText(context.captionFont, rows);
        mouseInfo.text = "Select / Drag Object: Left Button   ·   Scroll Panels: Wheel";
        mouseInfo.textColor = Theme.MUTED;
        mouseInfo.lineBreak = false;
        mouseInfo.x = PADDING + 4;
        mouseInfo.y = mouseHeader.y + 15;

        resetButton = new UiButton(context, "Reset to Defaults", 132, 24, this);
        resetButton.x = PADDING;
        resetButton.y = contentHeight() - 30;
        resetButton.onClick = function() {
            keybindings.cancelCapture();
            captureTarget = cast -1;
            keybindings.resetDefaults();
            refresh();
        };

        statusText = new UiText(context.captionFont, this);
        statusText.lineBreak = false;
        statusText.x = PADDING + 142;
        statusText.y = contentHeight() - 25;

        titleBar.onPush = function(event) {
            if (event.button != 0) return;
            event.propagate = false;
            var startX = x;
            var startY = y;
            titleBar.startCapture(function(captured) {
                switch (captured.kind) {
                    case EMove:
                        x = Math.max(4, Math.min(Math.max(4, context.width - WIDTH - 4),
                            startX + (context.window.mouseX - dragOffsetX)));
                        y = Math.max(4, Math.min(
                            Math.max(4, context.height - contentHeight() - 4),
                            startY + (context.window.mouseY - dragOffsetY)));
                        captured.propagate = false;
                    case ERelease, EReleaseOutside, EFocusLost:
                        titleBar.stopCapture();
                        captured.propagate = false;
                    case _:
                        captured.propagate = true;
                }
            });
            dragOffsetX = context.window.mouseX;
            dragOffsetY = context.window.mouseY;
        };

        keybindings.onChanged = refresh;
        refresh();
    }

    function contentHeight():Float {
        return PADDING + 26 + EditorAction.ACTION_COUNT * ROW_HEIGHT + FOOTER_SPACE;
    }

    /** Open centered in the editor window. */
    public function open():Void {
        x = Math.max(4, Math.round((context.width - WIDTH) * 0.5));
        y = Math.max(Theme.TOP_BAR_HEIGHT + 6,
            Math.round((context.height - contentHeight()) * 0.5));
        visible = true;
        isOpen = true;
        clampToWindow();
        refresh();
    }

    public function close():Void {
        if (!isOpen) return;
        keybindings.cancelCapture();
        captureTarget = cast -1;
        visible = false;
        isOpen = false;
    }

    /** Keep the complete settings window reachable after a native resize. */
    public function clampToWindow():Void {
        if (!isOpen) return;
        x = Math.max(4, Math.min(x, Math.max(4, context.width - WIDTH - 4)));
        y = Math.max(4, Math.min(y,
            Math.max(4, context.height - contentHeight() - 4)));
    }

    /** Re-sync every binding button and the status line with the registry. */
    function refresh():Void {
        for (actionIndex in 0...bindingButtons.length) {
            var action:EditorAction = actionIndex;
            if (isCapturing(action)) {
                bindingButtons[actionIndex].setText("press a key...");
            } else {
                bindingButtons[actionIndex].setText(keybindings.bindingLabel(action));
            }
        }
        var status = keybindings.lastError == ""
            ? "Changes save automatically"
            : keybindings.lastError;
        statusText.text = fitStatus(status,
            WIDTH - statusText.x - PADDING - 4);
        statusText.textColor = keybindings.lastError == "" ? Theme.MUTED : Theme.DANGER;
    }

    function fitStatus(value:String, maxWidth:Float):String {
        if (statusText.calcTextWidth(value) <= maxWidth) return value;
        var fitted = "";
        for (index in 0...value.length) {
            var candidate = value.substr(0, index + 1) + "…";
            if (statusText.calcTextWidth(candidate) > maxWidth) break;
            fitted = candidate;
        }
        return fitted;
    }

    /** True while THIS action's row is the one armed for capture. */
    function isCapturing(action:EditorAction):Bool {
        return keybindings.capturePending && captureTarget == action;
    }

    var captureTarget:EditorAction = cast -1;
}
