package boltspark.ui.widgets;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
 * Lightweight persisted state for the Asset Browser: favorites, recently opened
 * assets, and view preferences. It follows the same `%LOCALAPPDATA%` JSON
 * convention as DockLayoutStore and Keybindings; when LOCALAPPDATA is missing
 * (headless tests) everything stays in memory and load/save report a reason.
 */
class AssetBrowserStore {
    static inline var FILE_NAME:String = "asset-browser.json";
    static inline var SCHEMA_VERSION:Int = 1;
    static inline var MAX_RECENT:Int = 24;

    public var favorites:Array<String> = [];
    public var recent:Array<String> = [];
    public var viewMode:Int = 0;
    public var thumbnailSize:Int = 104;
    public var sortKey:Int = 0;
    public var sortAsc:Bool = true;
    public var typeFilter:String = "all";
    public var foldersFirst:Bool = true;
    public var folderWidth:Float = 118;
    public var inspectorWidth:Float = 220;
    public var inspectorCollapsed:Bool = false;

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

    public function isFavorite(source:String):Bool {
        return favorites.indexOf(source) >= 0;
    }

    /** Add or remove a favorite and persist the result. */
    public function toggleFavorite(source:String):Bool {
        if (source == "") return false;
        var index = favorites.indexOf(source);
        if (index >= 0) favorites.splice(index, 1);
        else favorites.push(source);
        save();
        return index < 0;
    }

    /** Record an opened asset; most recent first, bounded and de-duplicated. */
    public function markRecent(source:String):Void {
        if (source == "") return;
        var index = recent.indexOf(source);
        if (index >= 0) recent.splice(index, 1);
        recent.unshift(source);
        if (recent.length > MAX_RECENT) recent.resize(MAX_RECENT);
        save();
    }

    public function load():Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; Asset Browser state will not persist.";
        if (!FileSystem.exists(filePath)) return null;

        var contents:String;
        try {
            contents = File.getContent(filePath);
        } catch (error:Dynamic) {
            return 'Could not read Asset Browser state at ${filePath}: ${Std.string(error)}';
        }
        var data:Dynamic;
        try {
            data = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            return 'Could not parse Asset Browser state at ${filePath}: ${Std.string(error)}';
        }
        if (!Reflect.isObject(data) || !isNumber(Reflect.field(data, "version"))
                || Reflect.field(data, "version") != SCHEMA_VERSION) {
            return 'Asset Browser state at ${filePath} has an unsupported format; using defaults.';
        }

        favorites = stringArray(Reflect.field(data, "favorites"));
        recent = stringArray(Reflect.field(data, "recent"));
        viewMode = clampInt(Reflect.field(data, "viewMode"), 0, 2, 0);
        thumbnailSize = clampInt(Reflect.field(data, "thumbnailSize"), 64, 192, 104);
        sortKey = clampInt(Reflect.field(data, "sortKey"), 0, 3, 0);
        sortAsc = boolValue(Reflect.field(data, "sortAsc"), true);
        typeFilter = Reflect.field(data, "typeFilter") is String
            ? Reflect.field(data, "typeFilter") : "all";
        foldersFirst = boolValue(Reflect.field(data, "foldersFirst"), true);
        folderWidth = clampFloat(Reflect.field(data, "folderWidth"), 90, 280, 118);
        inspectorWidth = clampFloat(Reflect.field(data, "inspectorWidth"), 160, 420, 220);
        inspectorCollapsed = boolValue(Reflect.field(data, "inspectorCollapsed"), false);
        return null;
    }

    public function save():Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available; Asset Browser state could not be saved.";
        try {
            if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
            File.saveContent(filePath, haxe.Json.stringify({
                version: SCHEMA_VERSION,
                favorites: favorites,
                recent: recent,
                viewMode: viewMode,
                thumbnailSize: thumbnailSize,
                sortKey: sortKey,
                sortAsc: sortAsc,
                typeFilter: typeFilter,
                foldersFirst: foldersFirst,
                folderWidth: folderWidth,
                inspectorWidth: inspectorWidth,
                inspectorCollapsed: inspectorCollapsed
            }));
        } catch (error:Dynamic) {
            return 'Could not save Asset Browser state at ${filePath}: ${Std.string(error)}';
        }
        return null;
    }

    static function stringArray(value:Dynamic):Array<String> {
        var result:Array<String> = [];
        if (!Std.isOfType(value, Array)) return result;
        for (item in cast(value, Array<Dynamic>)) {
            if (item is String && result.indexOf(item) < 0) result.push(item);
        }
        return result;
    }

    static function boolValue(value:Dynamic, fallback:Bool):Bool {
        return Std.isOfType(value, Bool) ? value : fallback;
    }

    static function isNumber(value:Dynamic):Bool {
        return Std.isOfType(value, Int) || Std.isOfType(value, Float);
    }

    static function clampInt(value:Dynamic, min:Int, max:Int, fallback:Int):Int {
        if (!isNumber(value)) return fallback;
        var number = Std.int(value);
        return number < min ? min : (number > max ? max : number);
    }

    static function clampFloat(value:Dynamic, min:Float, max:Float, fallback:Float):Float {
        if (!isNumber(value)) return fallback;
        var number:Float = value;
        if (number != number) return fallback;
        return number < min ? min : (number > max ? max : number);
    }
}
