package boltspark.editor;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
 * Rebindable editor keybindings.
 *
 * Maps every keyboard-driven editor action (tool shortcuts, delete,
 * snap-to-grid, hold-to-disable snapping) to a key code plus an optional Ctrl
 * modifier. Defaults live in code; user rebinds persist to
 * %LOCALAPPDATA%\Boltspark Engine\keybindings.json using the same store
 * conventions as DockLayoutStore.
 *
 * Capture flow for the settings window: beginCapture(action) arms the
 * registry; the window-level InputAdapter forwards the next key event to
 * handleCaptureKey, which either stores the new binding or cancels on
 * Escape. `capturePending` lets the adapter consume capture keystrokes
 * before they can trigger the shortcuts they are meant to rebind.
 */
class Keybindings {
    static inline var FILE_NAME:String = "keybindings.json";
    static inline var SCHEMA_VERSION:Int = 1;

    final directory:Null<String>;
    final filePath:Null<String>;

    /** Fired after any rebind, capture end, or defaults reset. */
    public var onChanged:Null<Void->Void>;
    /** Last validation or persistence error, for settings window display. */
    public var lastError:String = "";

    /** A binding: key code plus optional Ctrl modifier. */
    public var capturePending(default, null):Bool = false;
    var captureAction:Int = -1;
    final bindings:Array<{keyCode:Int, ctrl:Bool}> = [];

    public function new() {
        var localAppData = Sys.getEnv("LOCALAPPDATA");
        if (localAppData == null || localAppData == "") {
            directory = null;
            filePath = null;
        } else {
            directory = Path.join([localAppData, "Boltspark Engine"]);
            filePath = Path.join([directory, FILE_NAME]);
        }
        // Always establish a complete usable map before touching disk. A
        // malformed or partially written settings file must never leave null
        // slots that later crash shortcut matching.
        for (_ in 0...EditorAction.ACTION_COUNT) {
            bindings.push({keyCode: 0, ctrl: false});
        }
        resetDefaults(true);
        load();
    }

    // ------------------------------------------------------------------
    // Binding access
    // ------------------------------------------------------------------

    public function keyCode(action:EditorAction):Int {
        return bindings[action].keyCode;
    }

    public function requiresCtrl(action:EditorAction):Bool {
        return bindings[action].ctrl;
    }

    /** Does this key event match the action's binding? */
    public function matches(action:EditorAction, keyCode:Int, ctrlDown:Bool):Bool {
        var binding = bindings[action];
        return binding.keyCode == keyCode && binding.ctrl == ctrlDown;
    }

    /** Human-readable label for the settings window, e.g. "Ctrl+End". */
    public function bindingLabel(action:EditorAction):String {
        var binding = bindings[action];
        if (binding == null) return "—";
        var name = hxd.Key.getKeyName(binding.keyCode);
        return (binding.ctrl ? "Ctrl+" : "") + name;
    }

    public static function actionName(action:EditorAction):String {
        return switch (action) {
            case EditorAction.ToolMove: "Move Tool";
            case EditorAction.ToolRotate: "Rotate Tool";
            case EditorAction.ToolScale: "Scale Tool";
            case EditorAction.DeleteSelection: "Delete Selection";
            case EditorAction.SnapToGrid: "Snap Selection to Grid";
            case EditorAction.HoldSnapOff: "Hold to Disable Move Snap";
            default: "Unknown Action";
        };
    }

    /**
     * Rebind an action. Rejects bindings already used by a different action;
     * returns a human-readable error or null on success.
     */
    public function rebind(action:EditorAction, keyCode:Int, ctrl:Bool):Null<String> {
        if (keyCode == hxd.Key.ESCAPE) {
            return "Escape is reserved for cancelling menus and captures.";
        }
        if (!isBindableKey(keyCode)) {
            return "Press a non-modifier keyboard key; Ctrl may be used as a modifier.";
        }
        var requested = (ctrl ? "Ctrl+" : "") + hxd.Key.getKeyName(keyCode);
        for (other in 0...EditorAction.ACTION_COUNT) {
            var binding = bindings[other];
            if (other != action && binding != null
                    && binding.keyCode == keyCode && binding.ctrl == ctrl) {
                return '$requested is already bound to ' + actionName(other);
            }
        }
        bindings[action] = {keyCode: keyCode, ctrl: ctrl};
        lastError = "";
        var saveError = save();
        if (saveError != null) lastError = saveError;
        if (onChanged != null) onChanged();
        return null;
    }

    public function resetDefaults(quiet:Bool = false):Void {
        bindings[EditorAction.ToolMove] = {keyCode: hxd.Key.NUMBER_1, ctrl: false};
        // Requested tool mapping: 1 Move, E Rotate, R Scale.
        bindings[EditorAction.ToolRotate] = {keyCode: hxd.Key.E, ctrl: false};
        bindings[EditorAction.ToolScale] = {keyCode: hxd.Key.R, ctrl: false};
        bindings[EditorAction.DeleteSelection] = {keyCode: hxd.Key.DELETE, ctrl: false};
        bindings[EditorAction.SnapToGrid] = {keyCode: hxd.Key.END, ctrl: true};
        bindings[EditorAction.HoldSnapOff] = {keyCode: hxd.Key.V, ctrl: false};
        lastError = "";
        if (!quiet) {
            var saveError = save();
            if (saveError != null) lastError = saveError;
            if (onChanged != null) onChanged();
        }
    }

    // ------------------------------------------------------------------
    // Capture
    // ------------------------------------------------------------------

    /** Arm capture for an action; the next key event rebinds it. */
    public function beginCapture(action:EditorAction):Void {
        captureAction = action;
        capturePending = true;
        lastError = "";
        if (onChanged != null) onChanged();
    }

    public function cancelCapture():Void {
        if (!capturePending) return;
        capturePending = false;
        captureAction = -1;
        if (onChanged != null) onChanged();
    }

    /**
     * Consume the next key event while a capture is armed. Escape cancels;
     * anything else becomes the new binding (with the Ctrl state held at the
     * time of the press). Returns true when the event is consumed.
     */
    public function handleCaptureKey(keyCode:Int, ctrlDown:Bool):Bool {
        if (!capturePending) return false;
        // Ctrl is represented as a modifier in the persisted binding rather
        // than as the action key. Ignore modifier-only down events so the
        // normal Ctrl-then-key gesture captures (for example) Ctrl+End instead
        // of prematurely binding the row to Ctrl itself. Shift/Alt are not yet
        // part of the schema and are ignored for the same reason.
        if (isModifierKey(keyCode)) return true;
        capturePending = false;
        var action:Int = captureAction;
        captureAction = -1;
        if (keyCode == hxd.Key.ESCAPE) {
            lastError = "";
            if (onChanged != null) onChanged();
            return true;
        }
        var error = rebind(action, keyCode, ctrlDown);
        if (error != null) {
            // Rejected rebinds skip rebind()'s own onChanged notification.
            lastError = error;
            if (onChanged != null) onChanged();
        }
        return true;
    }

    // ------------------------------------------------------------------
    // Persistence (same conventions as DockLayoutStore)
    // ------------------------------------------------------------------

    function load():Bool {
        if (filePath == null) {
            lastError = "LOCALAPPDATA is not available; keybindings will not persist.";
            return false;
        }
        if (!FileSystem.exists(filePath)) return false;

        var contents:String;
        try {
            contents = File.getContent(filePath);
        } catch (error:Dynamic) {
            lastError = 'Could not read keybindings at ${filePath}: ${Std.string(error)}';
            return false;
        }

        var data:Dynamic;
        try {
            data = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            lastError = 'Could not parse keybindings at ${filePath}; using defaults.';
            return false;
        }

        if (!Reflect.isObject(data)
                || Reflect.field(data, "version") != SCHEMA_VERSION
                || !Std.isOfType(Reflect.field(data, "bindings"), Array)) {
            lastError = 'Keybindings at ${filePath} have an unsupported format; using defaults.';
            return false;
        }

        var stored:Array<Dynamic> = Reflect.field(data, "bindings");
        // Parse atomically into a temporary map. Only replace the live,
        // complete defaults if every action appears exactly once and no two
        // actions claim the same chord.
        var loaded:Array<Null<{keyCode:Int, ctrl:Bool}>> = [];
        for (_ in 0...EditorAction.ACTION_COUNT) loaded.push(null);
        var chords:Map<String, Bool> = [];
        for (entry in stored) {
            if (!Reflect.isObject(entry)) return invalidStoredBindings();
            var action = Reflect.field(entry, "action");
            var keyCode = Reflect.field(entry, "key");
            var ctrl = Reflect.field(entry, "ctrl") == true;
            if (!isActionIndex(action) || !isBindableKey(keyCode)
                    || keyCode == hxd.Key.ESCAPE || loaded[action] != null) {
                return invalidStoredBindings();
            }
            var chord = (ctrl ? "1:" : "0:") + keyCode;
            if (chords.exists(chord)) return invalidStoredBindings();
            chords.set(chord, true);
            loaded[action] = {keyCode: keyCode, ctrl: ctrl};
        }
        for (action in 0...EditorAction.ACTION_COUNT) {
            if (loaded[action] == null) return invalidStoredBindings();
        }
        for (action in 0...EditorAction.ACTION_COUNT) {
            bindings[action] = loaded[action];
        }
        lastError = "";
        return true;
    }

    function invalidStoredBindings():Bool {
        lastError = 'Keybindings at ${filePath} are incomplete or invalid; using defaults.';
        return false;
    }

    function save():Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; keybindings could not be saved.";
        var stored:Array<Dynamic> = [];
        for (action in 0...EditorAction.ACTION_COUNT) {
            var binding = bindings[action];
            if (binding == null) continue;
            stored.push({action: action, key: binding.keyCode, ctrl: binding.ctrl});
        }
        try {
            if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
            File.saveContent(filePath, haxe.Json.stringify({
                version: SCHEMA_VERSION,
                bindings: stored
            }));
        } catch (error:Dynamic) {
            return 'Could not save keybindings at ${filePath}: ${Std.string(error)}';
        }
        return null;
    }

    static function isActionIndex(value:Dynamic):Bool {
        return Std.isOfType(value, Int) && value >= 0
            && value < (EditorAction.ACTION_COUNT : Int);
    }

    static function isKeyIndex(value:Dynamic):Bool {
        return Std.isOfType(value, Int) && value >= 0 && value < 256;
    }

    static function isBindableKey(value:Dynamic):Bool {
        return isKeyIndex(value) && value >= hxd.Key.BACKSPACE
            && !isModifierKey(value);
    }

    static function isModifierKey(keyCode:Int):Bool {
        // Location-specific modifier codes carry LOC_LEFT/LOC_RIGHT bits; the
        // low byte remains the generic Shift/Ctrl/Alt code.
        var base = keyCode & 0xFF;
        return base == hxd.Key.SHIFT || base == hxd.Key.CTRL || base == hxd.Key.ALT;
    }
}
