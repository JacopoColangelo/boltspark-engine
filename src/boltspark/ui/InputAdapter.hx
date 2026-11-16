package boltspark.ui;

import boltspark.editor.EditorAction;
import boltspark.editor.Keybindings;
import boltspark.ui.core.UiInputState;

/**
 * Central input adapter (Gate 3).
 *
 * One scene-level listener records keyboard, focus, and pointer state so the
 * editor shell can surface input diagnostics in the status bar. Widgets stay
 * responsible for their own behavior; this adapter only *reports*.
 *
 * Keyboard actions are matched through the rebindable Keybindings registry —
 * no action key is hardcoded here. While the settings window is capturing a
 * new binding, key events are consumed by the registry first so the key
 * being bound cannot simultaneously trigger the shortcut it replaces.
 */
class InputAdapter {
    public var lastKey(default, null):String = "-";
    public var keyDownCount(default, null):Int = 0;
    public var keyUpCount(default, null):Int = 0;
    public var pointerMoves(default, null):Int = 0;
    public var focusLostCount(default, null):Int = 0;
    public var focusGotCount(default, null):Int = 0;
    public var pointerInsideWindow(default, null):Bool = true;
    public var onDeletePressed:Null<Void->Void>;
    /** Keyboard shortcut reported as an editor tool index (Move/Rotate/Scale). */
    public var onShortcutPressed:Null<Int->Void>;
    /** Ctrl+End (rebindable): snap the primary selection onto the grid. */
    public var onSnapToGridPressed:Null<Void->Void>;
    /** Hold key (rebindable): true while held to suspend translation snapping. */
    public var onSnapHoldChanged:Null<Bool->Void>;
    /** Escape (outside text fields and captures): closes menus and windows. */
    public var onEscapePressed:Null<Void->Void>;
    public var onUndoPressed:Null<Void->Void>;
    public var onRedoPressed:Null<Void->Void>;
    public var onCopyPressed:Null<Void->Void>;
    public var onPastePressed:Null<Void->Void>;
    public var onDuplicatePressed:Null<Void->Void>;
    public var onRenamePressed:Null<Void->Void>;
    /** G (rebindable): toggle the independent editor grid. */
    public var onToggleGridPressed:Null<Void->Void>;
    /** F (rebindable): frame the primary selection in the viewport. */
    public var onFocusSelectionPressed:Null<Void->Void>;
    /** The native window lost keyboard focus; release held navigation state. */
    public var onWindowFocusLost:Null<Void->Void>;
    /** Returns true only while RMB fly navigation owns the viewport. */
    public var viewportNavigationQuery:Null<Void->Bool>;

    final scene:h2d.Scene;
    final keybindings:Keybindings;
    final state:UiInputState;
    var report:h2d.Text;
    // Store the physical key that activated each action. Key-up must release
    // the action even if Ctrl was pressed/released in the meantime; matching
    // the full chord again on key-up can otherwise leave hold actions stuck.
    var deleteKeyDown:Int = -1;
    var shortcutKeyDown:Int = -1;
    var snapToGridKeyDown:Int = -1;
    var snapHoldKeyDown:Int = -1;
    var undoKeyDown:Int = -1;
    var redoKeyDown:Int = -1;
    var copyKeyDown:Int = -1;
    var pasteKeyDown:Int = -1;
    var duplicateKeyDown:Int = -1;
    var renameKeyDown:Int = -1;
    var toggleGridKeyDown:Int = -1;
    var focusSelectionKeyDown:Int = -1;

    public function new(scene:h2d.Scene, keybindings:Keybindings,
            ?state:UiInputState) {
        this.scene = scene;
        this.keybindings = keybindings;
        this.state = state == null ? new UiInputState() : state;
        // Listen at the window level so full-window editor interactives (which
        // consume events before scene listeners run) cannot starve the adapter.
        hxd.Window.getInstance().addEventTarget(onSceneEvent);
    }

    /** Optional status text updated as events arrive. */
    public function bindReport(target:h2d.Text):Void {
        report = target;
        refresh();
    }

    /** Release keyboard focus from the currently active native UI control. */
    public function clearFocus():Void {
        var focused = scene.getFocus();
        if (focused != null) focused.blur();
    }

    /** Compact status line for the editor status bar. */
    public function statusLine():String {
        return 'key ${lastKey} | d${keyDownCount} u${keyUpCount} mv${pointerMoves} '
            + 'focus ${focusGotCount}/${focusLostCount}'
            + (state.orphanKeyUps == 0 ? "" : ' orphanUp ${state.orphanKeyUps}');
    }

    function onSceneEvent(event:hxd.Event):Void {
        switch (event.kind) {
            case EKeyDown:
                keyDownCount++;
                state.keyDown(event.keyCode);
                lastKey = hxd.Key.getKeyName(event.keyCode);
                // Rebind capture takes priority: the key being bound must not
                // also fire the shortcut it is replacing.
                if (keybindings.capturePending) {
                    keybindings.handleCaptureKey(event.keyCode,
                        hxd.Key.isDown(hxd.Key.CTRL));
                    // SceneEvents queues this same event object. Mark it
                    // cancelled so a text field that happened to own focus
                    // in this application window cannot also consume the key.
                    event.cancel = true;
                    event.propagate = false;
                    refresh();
                    return;
                }
                var ctrlDown = hxd.Key.isDown(hxd.Key.CTRL);
                if (keybindings.matches(EditorAction.DeleteSelection,
                        event.keyCode, ctrlDown)) {
                    if (deleteKeyDown < 0) {
                        if (onDeletePressed != null) onDeletePressed();
                        deleteKeyDown = event.keyCode;
                    }
                }
                // Tool shortcuts (1 = Move, E = Rotate, R = Scale by
                // default); repeat while held is suppressed like Delete.
                // Single-key shortcuts bound to camera navigation keys (E by
                // default) stay silent while the viewport owns navigation.
                var shortcut = -1;
                if (!(viewportNavigationActive()
                        && isCameraNavigationKey(event.keyCode))) {
                    if (keybindings.matches(EditorAction.ToolMove, event.keyCode, ctrlDown)) {
                        shortcut = 0;
                    } else if (keybindings.matches(EditorAction.ToolRotate, event.keyCode, ctrlDown)) {
                        shortcut = 1;
                    } else if (keybindings.matches(EditorAction.ToolScale, event.keyCode, ctrlDown)) {
                        shortcut = 2;
                    }
                }
                if (shortcut >= 0) {
                    if (shortcutKeyDown < 0) {
                        if (onShortcutPressed != null) onShortcutPressed(shortcut);
                        shortcutKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.SnapToGrid, event.keyCode, ctrlDown)) {
                    if (snapToGridKeyDown < 0) {
                        if (onSnapToGridPressed != null) onSnapToGridPressed();
                        snapToGridKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.HoldSnapOff, event.keyCode, ctrlDown)) {
                    if (snapHoldKeyDown < 0) {
                        if (onSnapHoldChanged != null) onSnapHoldChanged(true);
                        snapHoldKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.Undo, event.keyCode, ctrlDown)) {
                    if (undoKeyDown < 0) {
                        if (onUndoPressed != null) onUndoPressed();
                        undoKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.Redo, event.keyCode, ctrlDown)) {
                    if (redoKeyDown < 0) {
                        if (onRedoPressed != null) onRedoPressed();
                        redoKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.CopySelection, event.keyCode, ctrlDown)) {
                    if (copyKeyDown < 0) {
                        if (onCopyPressed != null) onCopyPressed();
                        copyKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.Paste, event.keyCode, ctrlDown)) {
                    if (pasteKeyDown < 0) {
                        if (onPastePressed != null) onPastePressed();
                        pasteKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.DuplicateSelection,
                        event.keyCode, ctrlDown)) {
                    if (duplicateKeyDown < 0) {
                        if (onDuplicatePressed != null) onDuplicatePressed();
                        duplicateKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.RenameSelection,
                        event.keyCode, ctrlDown)) {
                    if (renameKeyDown < 0) {
                        if (onRenamePressed != null) onRenamePressed();
                        renameKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.ToggleGrid,
                        event.keyCode, ctrlDown)) {
                    if (toggleGridKeyDown < 0) {
                        if (onToggleGridPressed != null) onToggleGridPressed();
                        toggleGridKeyDown = event.keyCode;
                    }
                }
                if (keybindings.matches(EditorAction.FocusSelection,
                        event.keyCode, ctrlDown)) {
                    if (focusSelectionKeyDown < 0) {
                        if (onFocusSelectionPressed != null) {
                            onFocusSelectionPressed();
                        }
                        focusSelectionKeyDown = event.keyCode;
                    }
                }
                if (event.keyCode == hxd.Key.ESCAPE && onEscapePressed != null) {
                    onEscapePressed();
                }
                refresh();
            case EKeyUp:
                keyUpCount++;
                state.keyUp(event.keyCode);
                if (event.keyCode == deleteKeyDown) deleteKeyDown = -1;
                if (event.keyCode == shortcutKeyDown) shortcutKeyDown = -1;
                if (event.keyCode == snapToGridKeyDown) snapToGridKeyDown = -1;
                if (event.keyCode == undoKeyDown) undoKeyDown = -1;
                if (event.keyCode == redoKeyDown) redoKeyDown = -1;
                if (event.keyCode == copyKeyDown) copyKeyDown = -1;
                if (event.keyCode == pasteKeyDown) pasteKeyDown = -1;
                if (event.keyCode == duplicateKeyDown) duplicateKeyDown = -1;
                if (event.keyCode == renameKeyDown) renameKeyDown = -1;
                if (event.keyCode == toggleGridKeyDown) toggleGridKeyDown = -1;
                if (event.keyCode == focusSelectionKeyDown) {
                    focusSelectionKeyDown = -1;
                }
                if (event.keyCode == snapHoldKeyDown) {
                    if (onSnapHoldChanged != null) onSnapHoldChanged(false);
                    snapHoldKeyDown = -1;
                }
                refresh();
            case EMove:
                pointerMoves++;
                pointerInsideWindow = true;
                state.movePointer(event.relX, event.relY);
            case EPush:
                state.pressPointer(event.relX, event.relY);
            case ERelease, EReleaseOutside:
                state.releasePointer(event.relX, event.relY);
            case EWheel:
                state.addWheel(event.wheelDelta);
            case EFocusLost:
                focusLostCount++;
                state.focusLost();
                deleteKeyDown = -1;
                shortcutKeyDown = -1;
                snapToGridKeyDown = -1;
                undoKeyDown = -1;
                redoKeyDown = -1;
                copyKeyDown = -1;
                pasteKeyDown = -1;
                duplicateKeyDown = -1;
                renameKeyDown = -1;
                toggleGridKeyDown = -1;
                focusSelectionKeyDown = -1;
                if (snapHoldKeyDown >= 0) {
                    if (onSnapHoldChanged != null) onSnapHoldChanged(false);
                    snapHoldKeyDown = -1;
                }
                if (onWindowFocusLost != null) onWindowFocusLost();
                refresh();
            case EFocus:
                focusGotCount++;
                state.focusGained();
                refresh();
            case EOut:
                pointerInsideWindow = false;
            case _:
        }
    }

    function refresh():Void {
        if (report != null) report.text = statusLine();
    }

    /** WASD/QE fly the editor camera only while RMB look is held; a single-key
        shortcut bound to one of them (Rotate on E by default) must not fire
        during that flight gesture. */
    public static function isCameraNavigationKey(keyCode:Int):Bool {
        return keyCode == hxd.Key.W || keyCode == hxd.Key.A
            || keyCode == hxd.Key.S || keyCode == hxd.Key.D
            || keyCode == hxd.Key.Q || keyCode == hxd.Key.E;
    }

    function viewportNavigationActive():Bool {
        return viewportNavigationQuery != null && viewportNavigationQuery();
    }
}
