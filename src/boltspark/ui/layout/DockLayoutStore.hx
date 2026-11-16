package boltspark.ui.layout;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class DockLayoutStore {
    static inline var FILE_NAME:String = "layout.json";
    static inline var SCHEMA_VERSION:Int = 2;

    final directory:Null<String>;
    final filePath:Null<String>;

    public function new() {
        var localAppData = Sys.getEnv("LOCALAPPDATA");
        if (localAppData == null || localAppData == "") {
            directory = null;
            filePath = null;
        } else {
            directory = Path.join([localAppData, "Boltspark Engine"]);
            filePath = Path.join([directory, FILE_NAME]);
        }
    }

    public function load(layout:DockLayout):Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; panel layout will not persist.";
        if (!FileSystem.exists(filePath)) return null;

        var contents:String;
        try {
            contents = File.getContent(filePath);
        } catch (error:Dynamic) {
            return 'Could not read panel layout at ${filePath}: ${Std.string(error)}';
        }

        var data:Dynamic;
        try {
            data = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            return 'Could not parse panel layout at ${filePath}: ${Std.string(error)}';
        }

        var version:Float = Reflect.isObject(data) && isNumber(Reflect.field(data, "version"))
            ? Reflect.field(data, "version") : -1;
        // Version 1 predates the bottom tab field; accept it with defaults.
        var supported = version == 1 || version == SCHEMA_VERSION;
        if (!Reflect.isObject(data)
            || !supported
            || !isNumber(Reflect.field(data, "leftPanelWidth"))
            || !isNumber(Reflect.field(data, "rightPanelWidth"))
            || !isNumber(Reflect.field(data, "consoleHeight"))) {
            return 'Panel layout at ${filePath} has an unsupported or invalid format; using defaults.';
        }

        var leftWidth:Float = Reflect.field(data, "leftPanelWidth");
        var rightWidth:Float = Reflect.field(data, "rightPanelWidth");
        var consoleHeight:Float = Reflect.field(data, "consoleHeight");
        if (!isFinitePositive(leftWidth) || !isFinitePositive(rightWidth) || !isFinitePositive(consoleHeight)) {
            return 'Panel layout at ${filePath} contains invalid dimensions; using defaults.';
        }

        layout.leftPanelWidth = leftWidth;
        layout.rightPanelWidth = rightWidth;
        layout.consoleHeight = consoleHeight;
        if (version == SCHEMA_VERSION && isNumber(Reflect.field(data, "bottomTab"))) {
            var tab:Int = Std.int(Reflect.field(data, "bottomTab"));
            layout.bottomTab = tab == 1 ? 1 : 0;
        }
        return null;
    }

    public function save(layout:DockLayout):Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; panel layout could not be saved.";

        try {
            if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
            File.saveContent(filePath, haxe.Json.stringify({
                version: SCHEMA_VERSION,
                leftPanelWidth: layout.leftPanelWidth,
                rightPanelWidth: layout.rightPanelWidth,
                consoleHeight: layout.consoleHeight,
                bottomTab: layout.bottomTab
            }));
        } catch (error:Dynamic) {
            return 'Could not save panel layout at ${filePath}: ${Std.string(error)}';
        }
        return null;
    }

    static function isNumber(value:Dynamic):Bool {
        return Std.isOfType(value, Int) || Std.isOfType(value, Float);
    }

    static function isFinitePositive(value:Float):Bool {
        return value > 0 && value < 1000000 && value == value;
    }
}
