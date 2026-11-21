package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockOrientation;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Everything needed to persist one docking session. Contains no live objects. */
typedef DockLayoutSnapshot = {
    var root:Null<DockNode>;
    var floating:Array<FloatingDockWindow>;
    var closed:Array<String>;
    var bottomTab:Int;
}

typedef DockDeserializeResult = {
    var ok:Bool;
    var version:Int;
    var root:Null<DockNode>;
    var floating:Array<FloatingDockWindow>;
    var warnings:Array<String>;
}

/**
 * Versioned JSON persistence for the complete docking layout. Serializes only
 * panel ids, instance keys, panel-specific state blobs and numeric geometry —
 * never native object references. Corrupt or outdated data is rejected with
 * warnings so the host can fall back to the default layout.
 */
class DockLayoutSerializer {
    public static inline var VERSION:Int = 3;
    static inline var FILE_NAME:String = "dock-layout.json";
    static inline var MAX_DEPTH:Int = 32;
    static inline var MAX_NODES:Int = 256;

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

    public function path():Null<String> return filePath;

    public function exists():Bool {
        return filePath != null && FileSystem.exists(filePath);
    }

    public function save(snapshot:DockLayoutSnapshot):Null<String> {
        if (filePath == null || directory == null) {
            return "LOCALAPPDATA is not available; docking layout could not be saved.";
        }
        try {
            if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
            File.saveContent(filePath, toJson(snapshot));
        } catch (error:Dynamic) {
            return 'Could not save docking layout at ${filePath}: ${Std.string(error)}';
        }
        return null;
    }

    /** Serialize a snapshot to JSON without touching disk (also used by tests). */
    public function toJson(snapshot:DockLayoutSnapshot):String {
        var rootData = snapshot.root == null ? null : nodeToData(snapshot.root);
        var floats:Array<Dynamic> = [];
        for (window in snapshot.floating) {
            floats.push({
                id: window.id,
                title: window.title,
                x: window.x,
                y: window.y,
                width: window.width,
                height: window.height,
                minimized: window.minimized,
                root: window.root == null ? null : nodeToData(window.root)
            });
        }
        return haxe.Json.stringify({
            version: VERSION,
            bottomTab: snapshot.bottomTab,
            root: rootData,
            floating: floats,
            closed: snapshot.closed
        });
    }

    public function delete():Null<String> {
        if (filePath == null) return "LOCALAPPDATA is not available.";
        try {
            if (FileSystem.exists(filePath)) FileSystem.deleteFile(filePath);
        } catch (error:Dynamic) {
            return 'Could not delete docking layout at ${filePath}: ${Std.string(error)}';
        }
        return null;
    }

    /** Read and validate a saved layout from disk. Missing file is not an error. */
    public function load(registry:PanelRegistry):DockDeserializeResult {
        var empty:DockDeserializeResult = {
            ok: false, version: -1, root: null, floating: [], warnings: []
        };
        if (filePath == null) {
            empty.warnings.push("LOCALAPPDATA is not available; docking layout will not persist.");
            return empty;
        }
        if (!FileSystem.exists(filePath)) {
            empty.warnings.push("no saved docking layout; using the default layout.");
            return empty;
        }
        var contents:String;
        try {
            contents = File.getContent(filePath);
        } catch (error:Dynamic) {
            empty.warnings.push('Could not read docking layout: ${Std.string(error)}');
            return empty;
        }
        return parse(contents, registry);
    }

    /** Parse a layout string. Public so tests can exercise migration/recovery. */
    public function parse(contents:String, registry:PanelRegistry):DockDeserializeResult {
        var result:DockDeserializeResult = {
            ok: false, version: -1, root: null, floating: [], warnings: []
        };
        var data:Dynamic;
        try {
            data = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            result.warnings.push('Could not parse docking layout: ${Std.string(error)}');
            return result;
        }
        if (!Reflect.isObject(data)) {
            result.warnings.push("Docking layout root is not an object.");
            return result;
        }
        var version = numberField(data, "version", -1);
        result.version = Std.int(version);
        // v1/v2 predate floating windows; accepted because their root/tab shape
        // is identical and missing fields fall back to empty/default values.
        if (version < 1 || version > VERSION) {
            result.warnings.push('Unsupported docking layout version ${Std.int(version)}.');
            return result;
        }

        var counter = {nodes: 0};
        var root = parseNode(Reflect.field(data, "root"), registry,
            result.warnings, 0, counter);
        if (root == null) {
            result.warnings.push("Saved docking layout contains no usable tab group.");
            return result;
        }
        result.root = root;

        var floats:Array<Dynamic> = Reflect.field(data, "floating");
        if (floats != null && Std.isOfType(floats, Array)) {
            for (entry in floats) {
                if (!Reflect.isObject(entry)) continue;
                var floatRoot = parseNode(Reflect.field(entry, "root"), registry,
                    result.warnings, 0, counter);
                if (floatRoot == null) continue;
                var x = finiteField(entry, "x", 60, -4000, 4000);
                var y = finiteField(entry, "y", 60, -4000, 4000);
                var w = finiteField(entry, "width", 480, 160, 4000);
                var h = finiteField(entry, "height", 320, 100, 4000);
                var id = Std.int(finiteField(entry, "id", -1, 0, 1000000));
                var titleValue = Reflect.field(entry, "title");
                var title = Std.isOfType(titleValue, String) ? titleValue : "Floating Panel";
                var window = new FloatingDockWindow(id >= 0 ? id : 0, floatRoot, x, y, w, h,
                    title);
                window.minimized = boolField(entry, "minimized", false);
                result.floating.push(window);
            }
        }
        result.ok = true;
        return result;
    }

    // ------------------------------------------------------------------
    // Serialization
    // ------------------------------------------------------------------

    static function nodeToData(node:DockNode):Dynamic {
        if (Std.isOfType(node, TabNode)) {
            var tab = cast(node, TabNode);
            var panels:Array<Dynamic> = [];
            for (slot in tab.slots) {
                panels.push({
                    id: slot.view.panelId,
                    key: slot.instanceKey,
                    state: slot.view.serializeState()
                });
            }
            return {kind: "tab", panels: panels, active: tab.activeIndex};
        }
        if (Std.isOfType(node, SplitNode)) {
            var split = cast(node, SplitNode);
            return {
                kind: "split",
                orientation: split.orientation == Horizontal ? "h" : "v",
                ratio: split.ratio,
                minFirst: split.minFirst,
                minSecond: split.minSecond,
                first: nodeToData(split.first),
                second: nodeToData(split.second)
            };
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Deserialization + validation
    // ------------------------------------------------------------------

    static function parseNode(data:Dynamic, registry:PanelRegistry,
            warnings:Array<String>, depth:Int, counter:{nodes:Int}):Null<DockNode> {
        if (data == null || !Reflect.isObject(data) || depth > MAX_DEPTH
                || counter.nodes >= MAX_NODES) {
            if (depth > MAX_DEPTH) warnings.push("Docking tree exceeded maximum depth.");
            return null;
        }
        counter.nodes++;
        var kind = Reflect.field(data, "kind");
        if (!Std.isOfType(kind, String)) return null;

        if (kind == "tab") {
            var tab = new TabNode();
            var panels:Array<Dynamic> = Reflect.field(data, "panels");
            if (panels != null && Std.isOfType(panels, Array)) {
                for (entry in panels) {
                    if (!Reflect.isObject(entry)) continue;
                    var id = Reflect.field(entry, "id");
                    if (!Std.isOfType(id, String)) continue;
                    if (!registry.has(id)) {
                        warnings.push('Saved panel "${id}" no longer exists; skipped.');
                        continue;
                    }
                    var keyValue = Reflect.field(entry, "key");
                    var key = Std.isOfType(keyValue, String) ? keyValue : id;
                    var view:DockPanelView;
                    try {
                        view = registry.create(id, key);
                    } catch (error:Dynamic) {
                        warnings.push('Could not recreate panel "${id}": ${Std.string(error)}');
                        continue;
                    }
                    try {
                        view.restoreState(Reflect.field(entry, "state"));
                    } catch (error:Dynamic) {
                        warnings.push('Panel "${id}" had invalid saved state; ignored.');
                    }
                    tab.add({view: view, instanceKey: key,
                        locked: registry.flag(id, "fixed", false)});
                }
            }
            if (tab.slots.length == 0) return null;
            tab.activeIndex = Std.int(finiteField(data, "active", 0, 0, 1000000));
            if (tab.activeIndex >= tab.slots.length) tab.activeIndex = 0;
            return tab;
        }

        if (kind == "split") {
            var orientationValue = Reflect.field(data, "orientation");
            var orientation = Std.isOfType(orientationValue, String)
                    && orientationValue == "v"
                ? DockOrientation.Vertical : DockOrientation.Horizontal;
            var first = parseNode(Reflect.field(data, "first"), registry,
                warnings, depth + 1, counter);
            var second = parseNode(Reflect.field(data, "second"), registry,
                warnings, depth + 1, counter);
            if (first == null && second == null) return null;
            if (first == null) {
                second.parent = null;
                return second;
            }
            if (second == null) {
                first.parent = null;
                return first;
            }
            var split = new SplitNode(orientation, first, second,
                finiteField(data, "ratio", 0.5, 0.001, 0.999),
                finiteField(data, "minFirst", 120, 0, 100000),
                finiteField(data, "minSecond", 120, 0, 100000));
            return split;
        }

        warnings.push('Unknown docking node kind "${Std.string(kind)}"; skipped.');
        return null;
    }

    static function numberField(data:Dynamic, field:String, fallback:Float):Float {
        var value = Reflect.field(data, field);
        if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) return fallback;
        var number:Float = value;
        return number == number ? number : fallback;
    }

    static function finiteField(data:Dynamic, field:String, fallback:Float,
            min:Float, max:Float):Float {
        var value = numberField(data, field, fallback);
        if (value < min || value > max) return fallback;
        return value;
    }

    static function boolField(data:Dynamic, field:String, fallback:Bool):Bool {
        var value = Reflect.field(data, field);
        return Std.isOfType(value, Bool) ? value : fallback;
    }
}
