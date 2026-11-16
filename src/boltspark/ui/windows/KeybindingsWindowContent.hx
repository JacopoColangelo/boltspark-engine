package boltspark.ui.windows;

import boltspark.editor.EditorAction;
import boltspark.editor.Keybindings;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.widgets.UiButton;

/** Retained-H2D content rendered inside the native Editor Keybindings HWND. */
class KeybindingsWindowContent extends h2d.Object {
    public static inline var DEFAULT_WIDTH:Int = 460;
    public static inline var DEFAULT_HEIGHT:Int = 580;
    public static inline var MIN_WIDTH:Int = 420;
    public static inline var MIN_HEIGHT:Int = 580;

    static inline var PADDING:Int = 16;
    static inline var ROW_START:Int = 62;
    static inline var ROW_HEIGHT:Int = 30;
    static inline var BINDING_WIDTH:Int = 136;

    final context:UiContext;
    final keybindings:Keybindings;
    final background:UiSurface;
    final windowCatch:h2d.Interactive;
    final divider:h2d.Graphics;
    final bindingButtons:Array<UiButton> = [];
    final resetButton:UiButton;
    final statusText:h2d.Text;
    var captureTarget:EditorAction = cast -1;
    var lastWidth:Int = -1;
    var lastHeight:Int = -1;

    public function new(context:UiContext, keybindings:Keybindings, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        this.keybindings = keybindings;

        background = new UiSurface(context, this);
        background.setStyle(Theme.PANEL, Theme.PANEL, 0);
        // Consume otherwise empty client-area presses so this top-level window
        // never routes pointer input into another application window.
        windowCatch = new h2d.Interactive(1, 1, this);
        windowCatch.backgroundColor = 0;
        windowCatch.onPush = function(event) event.propagate = false;
        windowCatch.onWheel = function(event) event.propagate = false;

        var heading = new UiText(context.titleFont, this);
        heading.text = "Keyboard Shortcuts";
        heading.textColor = Theme.TEXT;
        heading.lineBreak = false;
        heading.x = PADDING;
        heading.y = 12;

        var help = new UiText(context.captionFont, this);
        help.text = "Click a shortcut, then press its replacement key.";
        help.textColor = Theme.MUTED;
        help.lineBreak = false;
        help.x = PADDING;
        help.y = 36;

        for (actionIndex in 0...EditorAction.ACTION_COUNT) {
            var action:EditorAction = actionIndex;
            var rowY = ROW_START + actionIndex * ROW_HEIGHT;
            var label = new UiText(context.labelFont, this);
            label.text = Keybindings.actionName(action);
            label.textColor = Theme.TEXT_SECONDARY;
            label.lineBreak = false;
            label.x = PADDING + 4;
            label.y = rowY + Math.round((24 - label.textHeight) * 0.5 - 1);

            var bindingButton = new UiButton(context, "", BINDING_WIDTH, 24, this);
            bindingButton.y = rowY;
            bindingButton.onClick = function() {
                captureTarget = action;
                keybindings.beginCapture(action);
                refresh();
            };
            bindingButtons.push(bindingButton);
        }

        var mouseY = ROW_START + EditorAction.ACTION_COUNT * ROW_HEIGHT + 6;
        var mouseHeader = new UiText(context.captionFont, this);
        mouseHeader.text = "Mouse (fixed)";
        mouseHeader.textColor = Theme.MUTED;
        mouseHeader.lineBreak = false;
        mouseHeader.x = PADDING + 4;
        mouseHeader.y = mouseY;

        var mouseInfo = new UiText(context.captionFont, this);
        mouseInfo.text = "Viewport: LMB Select · Wheel Dolly · RMB Fly · MMB Pan · Alt+LMB Orbit";
        mouseInfo.textColor = Theme.MUTED;
        mouseInfo.lineBreak = false;
        mouseInfo.x = PADDING + 4;
        mouseInfo.y = mouseY + 16;

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
        lastWidth = width;
        lastHeight = height;
        background.setSize(width, height);
        windowCatch.width = width;
        windowCatch.height = height;
        for (button in bindingButtons) {
            button.x = width - PADDING - BINDING_WIDTH;
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
        refreshStatus();
    }

    /** Re-sync every binding button and the status line with the registry. */
    function refresh():Void {
        for (actionIndex in 0...bindingButtons.length) {
            var action:EditorAction = actionIndex;
            bindingButtons[actionIndex].setText(isCapturing(action)
                ? "press a key..."
                : keybindings.bindingLabel(action));
        }
        refreshStatus();
    }

    function refreshStatus():Void {
        var status = keybindings.lastError == ""
            ? "Changes save automatically"
            : keybindings.lastError;
        statusText.text = fitStatus(status,
            context.width - statusText.x - PADDING);
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

    inline function isCapturing(action:EditorAction):Bool {
        return keybindings.capturePending && captureTarget == action;
    }
}
