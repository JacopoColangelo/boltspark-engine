import boltspark.editor.EditorAction;
import boltspark.editor.Keybindings;
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Historical keybinding maps retain user chords and gain newer actions. */
class KeybindingsMigrationRepro {
    static function main():Void {
        var root = Path.join(["bin", "test-results",
            "keybindings-migration-" + Std.string(Math.floor(haxe.Timer.stamp() * 1000000))]);
        var directory = Path.join([root, "Boltspark Engine"]);
        FileSystem.createDirectory(root);
        FileSystem.createDirectory(directory);
        Sys.putEnv("LOCALAPPDATA", Path.normalize(root));

        var path = Path.join([directory, "keybindings.json"]);
        File.saveContent(path, Json.stringify({
            version: 1,
            bindings: [
                {action: 0, key: hxd.Key.NUMBER_1, ctrl: false},
                // Deliberately claim Copy's future default to exercise a
                // collision-free migration without losing this user chord.
                {action: 1, key: hxd.Key.C, ctrl: true},
                {action: 2, key: hxd.Key.R, ctrl: false},
                {action: 3, key: hxd.Key.DELETE, ctrl: false},
                {action: 4, key: hxd.Key.END, ctrl: true},
                {action: 5, key: hxd.Key.V, ctrl: false}
            ]
        }));

        var keybindings = new Keybindings();
        assertTrue(keybindings.keyCode(EditorAction.ToolRotate) == hxd.Key.C
                && keybindings.requiresCtrl(EditorAction.ToolRotate),
            "version-1 tool binding was not retained");
        assertTrue(keybindings.keyCode(EditorAction.Undo) == hxd.Key.Z
            && keybindings.requiresCtrl(EditorAction.Undo),
            "Undo default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.Redo) == hxd.Key.Y
            && keybindings.requiresCtrl(EditorAction.Redo),
            "Redo default was not appended");

        var migrated:Dynamic = Json.parse(File.getContent(path));
        var bindings:Array<Dynamic> = Reflect.field(migrated, "bindings");
        assertTrue(Reflect.field(migrated, "version") == 7
            && bindings.length == EditorAction.ACTION_COUNT,
            "migrated keybinding payload was not rewritten as version 7");
        assertTrue(keybindings.keyCode(EditorAction.DuplicateSelection) == hxd.Key.D
            && keybindings.requiresCtrl(EditorAction.DuplicateSelection),
            "hierarchy shortcut defaults were not appended");
        assertTrue(!(keybindings.keyCode(EditorAction.CopySelection) == hxd.Key.C
                && keybindings.requiresCtrl(EditorAction.CopySelection)),
            "new Copy action collided with a retained user chord");
        assertTrue(keybindings.keyCode(EditorAction.FocusSelection) == hxd.Key.F
                && !keybindings.requiresCtrl(EditorAction.FocusSelection),
            "Focus Selection default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.SaveCurrentScene) == hxd.Key.S
                && keybindings.requiresCtrl(EditorAction.SaveCurrentScene)
                && !keybindings.requiresShift(EditorAction.SaveCurrentScene),
            "Ctrl+S default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.SaveAll) == hxd.Key.S
                && keybindings.requiresCtrl(EditorAction.SaveAll)
                && keybindings.requiresShift(EditorAction.SaveAll),
            "Ctrl+Shift+S default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.CutAsset) == hxd.Key.X
                && keybindings.requiresCtrl(EditorAction.CutAsset),
            "Ctrl+X default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.Play) == hxd.Key.F5
                && !keybindings.requiresCtrl(EditorAction.Play),
            "F5 Play default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.Pause) == hxd.Key.F6,
            "F6 Pause default was not appended");
        assertTrue(keybindings.keyCode(EditorAction.Stop) == hxd.Key.F7,
            "F7 Stop default was not appended");
        Sys.println("[keybindings] version-1 map migrated with history, hierarchy,"
            + " focus, save, and transport actions preserved");
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
