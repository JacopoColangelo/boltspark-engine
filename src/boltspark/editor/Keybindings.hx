package boltspark.editor;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

typedef Binding = {
    var keyCode:Int;
    var ctrl:Bool;
    var shift:Bool;
};

/**
 * Rebindable editor keybindings.
 *
 * Maps every keyboard-driven editor action (tool shortcuts, delete,
 * snap-to-grid, save, hold-to-disable snapping) to a key code plus optional Ctrl
 * and Shift modifiers. Defaults live in code; user rebinds persist to
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
    static inline var SCHEMA_VERSION:Int = 7;
    static inline var VERSION_ONE_ACTION_COUNT:Int = 6;
    static inline var VERSION_TWO_ACTION_COUNT:Int = 8;
    static inline var VERSION_THREE_ACTION_COUNT:Int = 13;
    static inline var VERSION_FOUR_ACTION_COUNT:Int = 14;
    static inline var VERSION_FIVE_ACTION_COUNT:Int = 16;
    static inline var VERSION_SIX_ACTION_COUNT:Int = 17;

    final directory:Null<String>;
    final filePath:Null<String>;

    /** Fired after any rebind, capture end, or defaults reset. */
    public var onChanged:Null<Void->Void>;
    /** Last validation or persistence error, for settings window display. */
    public var lastError:String = "";

    /** A binding: key code plus optional Ctrl and Shift modifiers. */
    public var capturePending(default, null):Bool = false;
    var captureAction:Int = -1;
    final bindings:Array<Binding> = [];
    /** Exact last successfully loaded/saved payload for cross-window sync. */
    var persistedContents:Null<String>;
    var nextExternalPollAt:Float = 0;

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
            bindings.push({keyCode: 0, ctrl: false, shift: false});
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

    public function requiresShift(action:EditorAction):Bool {
        return bindings[action].shift;
    }

    /** Does this key event match the action's binding? */
    public function matches(action:EditorAction, keyCode:Int, ctrlDown:Bool,
            shiftDown:Bool = false):Bool {
        var binding = bindings[action];
        return binding.keyCode == keyCode && binding.ctrl == ctrlDown
            && binding.shift == shiftDown;
    }

    /** Human-readable label for the settings window, e.g. "Ctrl+Shift+S". */
    public function bindingLabel(action:EditorAction):String {
        var binding = bindings[action];
        if (binding == null) return "—";
        var name = hxd.Key.getKeyName(binding.keyCode);
        return (binding.ctrl ? "Ctrl+" : "")
            + (binding.shift ? "Shift+" : "") + name;
    }

    public static function actionName(action:EditorAction):String {
        return switch (action) {
            case EditorAction.ToolMove: "Move Tool";
            case EditorAction.ToolRotate: "Rotate Tool";
            case EditorAction.ToolScale: "Scale Tool";
            case EditorAction.DeleteSelection: "Delete Selection";
            case EditorAction.SnapToGrid: "Snap Selection to Grid";
            case EditorAction.HoldSnapOff: "Hold to Disable Move Snap";
            case EditorAction.Undo: "Undo";
            case EditorAction.Redo: "Redo";
            case EditorAction.CopySelection: "Copy Selection";
            case EditorAction.Paste: "Paste";
            case EditorAction.DuplicateSelection: "Duplicate Selection";
            case EditorAction.RenameSelection: "Rename Selection";
            case EditorAction.ToggleGrid: "Toggle Editor Grid";
            case EditorAction.FocusSelection: "Focus Selection";
            case EditorAction.SaveCurrentScene: "Save Current Scene";
            case EditorAction.SaveAll: "Save All";
            case EditorAction.CutAsset: "Cut Asset";
            case EditorAction.Play: "Play Scene";
            case EditorAction.Pause: "Pause Scene";
            case EditorAction.Stop: "Stop Scene";
            default: "Unknown Action";
        };
    }

    /**
     * Rebind an action. Rejects bindings already used by a different action;
     * returns a human-readable error or null on success.
     */
    public function rebind(action:EditorAction, keyCode:Int, ctrl:Bool,
            shift:Bool = false):Null<String> {
        if (keyCode == hxd.Key.ESCAPE) {
            return "Escape is reserved for cancelling menus and captures.";
        }
        if (!isBindableKey(keyCode)) {
            return "Press a non-modifier keyboard key; Ctrl/Shift may be modifiers.";
        }
        var requested = (ctrl ? "Ctrl+" : "") + (shift ? "Shift+" : "")
            + hxd.Key.getKeyName(keyCode);
        for (other in 0...EditorAction.ACTION_COUNT) {
            var binding = bindings[other];
            if (other != action && binding != null
                    && binding.keyCode == keyCode && binding.ctrl == ctrl
                    && binding.shift == shift) {
                return '$requested is already bound to ' + actionName(other);
            }
        }
        bindings[action] = {keyCode: keyCode, ctrl: ctrl, shift: shift};
        lastError = "";
        var saveError = save();
        if (saveError != null) lastError = saveError;
        if (onChanged != null) onChanged();
        return null;
    }

    public function resetDefaults(quiet:Bool = false):Void {
        bindings[EditorAction.ToolMove] = {keyCode: hxd.Key.NUMBER_1, ctrl: false, shift: false};
        // Requested tool mapping: 1 Move, E Rotate, R Scale.
        bindings[EditorAction.ToolRotate] = {keyCode: hxd.Key.E, ctrl: false, shift: false};
        bindings[EditorAction.ToolScale] = {keyCode: hxd.Key.R, ctrl: false, shift: false};
        bindings[EditorAction.DeleteSelection] = {keyCode: hxd.Key.DELETE, ctrl: false, shift: false};
        bindings[EditorAction.SnapToGrid] = {keyCode: hxd.Key.END, ctrl: true, shift: false};
        bindings[EditorAction.HoldSnapOff] = {keyCode: hxd.Key.V, ctrl: false, shift: false};
        bindings[EditorAction.Undo] = {keyCode: hxd.Key.Z, ctrl: true, shift: false};
        bindings[EditorAction.Redo] = {keyCode: hxd.Key.Y, ctrl: true, shift: false};
        bindings[EditorAction.CopySelection] = {keyCode: hxd.Key.C, ctrl: true, shift: false};
        bindings[EditorAction.Paste] = {keyCode: hxd.Key.V, ctrl: true, shift: false};
        bindings[EditorAction.DuplicateSelection] = {keyCode: hxd.Key.D, ctrl: true, shift: false};
        bindings[EditorAction.RenameSelection] = {keyCode: hxd.Key.F2, ctrl: false, shift: false};
        // G toggles the independent editor grid (Game View); registered like
        // every other action so it is rebindable and persisted.
        bindings[EditorAction.ToggleGrid] = {keyCode: hxd.Key.G, ctrl: false, shift: false};
        bindings[EditorAction.FocusSelection] = {keyCode: hxd.Key.F, ctrl: false, shift: false};
        bindings[EditorAction.SaveCurrentScene] = {keyCode: hxd.Key.S, ctrl: true, shift: false};
        bindings[EditorAction.SaveAll] = {keyCode: hxd.Key.S, ctrl: true, shift: true};
        bindings[EditorAction.CutAsset] = {keyCode: hxd.Key.X, ctrl: true, shift: false};
        // Play mode transport; function keys avoid the editing/save chords.
        bindings[EditorAction.Play] = {keyCode: hxd.Key.F5, ctrl: false, shift: false};
        bindings[EditorAction.Pause] = {keyCode: hxd.Key.F6, ctrl: false, shift: false};
        bindings[EditorAction.Stop] = {keyCode: hxd.Key.F7, ctrl: false, shift: false};
        lastError = "";
        if (!quiet) {
            var saveError = save();
            if (saveError != null) lastError = saveError;
            if (onChanged != null) onChanged();
        }
    }

    /**
     * Pick up a valid map written by a separate application window.
     * Polling is internally throttled; malformed/in-progress writes never
     * replace the complete live map.
     */
    public function pollExternalChanges():Bool {
        if (capturePending) return false;
        var now = haxe.Timer.stamp();
        if (now < nextExternalPollAt) return false;
        nextExternalPollAt = now + 0.25;
        return load(true);
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
    public function handleCaptureKey(keyCode:Int, ctrlDown:Bool,
            shiftDown:Bool = false):Bool {
        if (!capturePending) return false;
        // Ctrl/Shift are modifiers in the persisted binding, not the action
        // key. Ignore modifier-only down events so Ctrl+End or Ctrl+Shift+S is
        // captured only when the real key arrives.
        if (isModifierKey(keyCode)) return true;
        capturePending = false;
        var action:Int = captureAction;
        captureAction = -1;
        if (keyCode == hxd.Key.ESCAPE) {
            lastError = "";
            if (onChanged != null) onChanged();
            return true;
        }
        var error = rebind(action, keyCode, ctrlDown, shiftDown);
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

    function load(notify:Bool = false):Bool {
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
        if (contents == persistedContents) return false;

        var data:Dynamic;
        try {
            data = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            lastError = 'Could not parse keybindings at ${filePath}; using defaults.';
            return false;
        }

        if (!Reflect.isObject(data)) {
            lastError = 'Keybindings at ${filePath} have an unsupported format; using defaults.';
            return false;
        }
        var storedVersion = Reflect.field(data, "version");
        if ((storedVersion != 1 && storedVersion != 2 && storedVersion != 3
                && storedVersion != 4 && storedVersion != 5 && storedVersion != 6
                && storedVersion != SCHEMA_VERSION)
                || !Std.isOfType(Reflect.field(data, "bindings"), Array)) {
            lastError = 'Keybindings at ${filePath} have an unsupported format; using defaults.';
            return false;
        }

        var stored:Array<Dynamic> = Reflect.field(data, "bindings");
        // Parse atomically into a temporary map. Only replace the live,
        // complete defaults if every action appears exactly once and no two
        // actions claim the same chord.
        var loaded:Array<Null<Binding>> = [];
        for (_ in 0...EditorAction.ACTION_COUNT) loaded.push(null);
        var chords:Map<String, Bool> = [];
        var expectedActions = expectedActionCount(storedVersion);
        for (entry in stored) {
            if (!Reflect.isObject(entry)) return invalidStoredBindings();
            var action = Reflect.field(entry, "action");
            var keyCode = Reflect.field(entry, "key");
            var ctrl = Reflect.field(entry, "ctrl") == true;
            var shift = Reflect.field(entry, "shift") == true;
            if (!isActionIndex(action) || !isBindableKey(keyCode)
                    || action >= expectedActions || keyCode == hxd.Key.ESCAPE
                    || loaded[action] != null) {
                return invalidStoredBindings();
            }
            var chord = (ctrl ? "1:" : "0:") + (shift ? "1:" : "0:") + keyCode;
            if (chords.exists(chord)) return invalidStoredBindings();
            chords.set(chord, true);
            loaded[action] = {keyCode: keyCode, ctrl: ctrl, shift: shift};
        }
        for (action in 0...expectedActions) {
            if (loaded[action] == null) return invalidStoredBindings();
        }
        // Older versions predate Undo/Redo, hierarchy clipboard actions,
        // and/or viewport focus. Preserve every user binding and append
        // collision-free defaults. If an older user already claimed a new
        // action's default chord, give the new action a deterministic spare
        // binding instead of rejecting the complete historical map.
        for (action in expectedActions...(EditorAction.ACTION_COUNT : Int)) {
            var fallback = bindings[action];
            var chord = (fallback.ctrl ? "1:" : "0:")
                + (fallback.shift ? "1:" : "0:") + fallback.keyCode;
            if (chords.exists(chord)) {
                fallback = spareMigrationBinding(chords);
                chord = (fallback.ctrl ? "1:" : "0:")
                    + (fallback.shift ? "1:" : "0:") + fallback.keyCode;
            }
            chords.set(chord, true);
            loaded[action] = {
                keyCode: fallback.keyCode, ctrl: fallback.ctrl, shift: fallback.shift
            };
        }
        for (action in 0...EditorAction.ACTION_COUNT) {
            bindings[action] = loaded[action];
        }
        lastError = "";
        if (storedVersion == SCHEMA_VERSION) {
            persistedContents = contents;
        } else {
            // Rewrite the complete migrated map once so both editor windows
            // subsequently observe the same current-schema payload.
            persistedContents = null;
            var migrationError = save();
            if (migrationError != null) lastError = migrationError;
        }
        if (notify && onChanged != null) onChanged();
        return true;
    }

    /** Number of actions a stored schema version is expected to contain. */
    static function expectedActionCount(version:Int):Int {
        return switch (version) {
            case 1: VERSION_ONE_ACTION_COUNT;
            case 2: VERSION_TWO_ACTION_COUNT;
            case 3: VERSION_THREE_ACTION_COUNT;
            case 4: VERSION_FOUR_ACTION_COUNT;
            case 5: VERSION_FIVE_ACTION_COUNT;
            case 6: VERSION_SIX_ACTION_COUNT;
            default: EditorAction.ACTION_COUNT;
        };
    }

    function invalidStoredBindings():Bool {
        lastError = 'Keybindings at ${filePath} are incomplete or invalid; using defaults.';
        return false;
    }

    function spareMigrationBinding(chords:Map<String, Bool>):Binding {
        // F13-F24 are valid Windows virtual keys and remain reachable from the
        // keybindings UI, while being unlikely to displace a common shortcut.
        for (keyCode in hxd.Key.F13...(hxd.Key.F24 + 1)) {
            var chord = "1:0:" + keyCode;
            if (!chords.exists(chord)) {
                return {keyCode: keyCode, ctrl: true, shift: false};
            }
        }
        throw "No collision-free keybinding remained during migration";
    }

    function save():Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; keybindings could not be saved.";
        var stored:Array<Dynamic> = [];
        for (action in 0...EditorAction.ACTION_COUNT) {
            var binding = bindings[action];
            if (binding == null) continue;
            stored.push({
                action: action, key: binding.keyCode,
                ctrl: binding.ctrl, shift: binding.shift
            });
        }
        var contents = haxe.Json.stringify({
            version: SCHEMA_VERSION,
            bindings: stored
        });
        try {
            if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
            File.saveContent(filePath, contents);
        } catch (error:Dynamic) {
            return 'Could not save keybindings at ${filePath}: ${Std.string(error)}';
        }
        persistedContents = contents;
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
