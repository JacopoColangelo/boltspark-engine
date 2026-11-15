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
        assertTrue(Reflect.field(migrated, "version") == 3
            && bindings.length == EditorAction.ACTION_COUNT,
            "migrated keybinding payload was not rewritten as version 3");
        assertTrue(keybindings.keyCode(EditorAction.DuplicateSelection) == hxd.Key.D
            && keybindings.requiresCtrl(EditorAction.DuplicateSelection),
            "hierarchy shortcut defaults were not appended");
        assertTrue(!(keybindings.keyCode(EditorAction.CopySelection) == hxd.Key.C
                && keybindings.requiresCtrl(EditorAction.CopySelection)),
            "new Copy action collided with a retained user chord");
        Sys.println("[keybindings] version-1 map migrated with history and hierarchy actions preserved");
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
