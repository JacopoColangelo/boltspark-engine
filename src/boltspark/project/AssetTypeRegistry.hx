package boltspark.project;

import haxe.io.Path;

/**
 * The single source of truth for which on-disk asset kinds Boltspark actually
 * understands. The engine has one loadable file format (`.boltscene`) plus a
 * catalog of engine-provided assets (primitives and built-in materials) shown
 * by the Asset Browser under the "Engine Asset" kind. Those have no on-disk
 * files and are built by `EngineAssetCatalog`; everything else under the
 * project root is surfaced as a generic file so users can still see, organize,
 * and reveal it without the browser pretending the engine can import it.
 *
 * The registry deliberately contains no UI or rendering code. It is shared by
 * the filesystem scan and by the Asset Browser so extension checks never drift
 * between the two.
 */
typedef AssetTypeInfo = {
    /** Stable machine kind: "scene", "engine", or "file". */
    var kind:String;
    /** Human-readable label shown in filters and the inspector. */
    var label:String;
    /** Lower-case extension without the dot ("" for generic files). */
    var extension:String;
    /** True only when the engine has a real loader for this kind. */
    var loadable:Bool;
};

class AssetTypeRegistry {
    public static inline var SCENE_EXT:String = "boltscene";
    public static inline var KIND_SCENE:String = "scene";
    public static inline var KIND_ENGINE:String = "engine";
    public static inline var KIND_FILE:String = "file";
    public static inline var SCENE_INFO_LABEL:String = "Scene";
    public static inline var ENGINE_INFO_LABEL:String = "Engine Asset";
    public static inline var FILE_INFO_LABEL:String = "File";

    static final SCENE_INFO:AssetTypeInfo = {
        kind: KIND_SCENE,
        label: "Scene",
        extension: SCENE_EXT,
        loadable: true
    };
    static final ENGINE_INFO:AssetTypeInfo = {
        kind: KIND_ENGINE,
        label: ENGINE_INFO_LABEL,
        extension: "",
        loadable: true
    };
    static final FILE_INFO:AssetTypeInfo = {
        kind: KIND_FILE,
        label: "File",
        extension: "",
        loadable: false
    };

    /** Classify a file name using only extensions the engine recognizes. */
    public static function infoFor(fileName:String):AssetTypeInfo {
        return extensionOf(fileName) == SCENE_EXT ? SCENE_INFO : FILE_INFO;
    }

    /** Kind string for an asset scan record. */
    public static function kindFor(fileName:String):String {
        return infoFor(fileName).kind;
    }

    /** Metadata for engine-provided assets such as primitives. */
    public static function engineInfo():AssetTypeInfo return ENGINE_INFO;

    /** Kinds offered by the browser's type filter. Generic files are last. */
    public static function filterKinds():Array<AssetTypeInfo> {
        return [SCENE_INFO, ENGINE_INFO, FILE_INFO];
    }

    /**
     * Files hidden from the browser: dot files, the project manifest itself,
     * atomic-save backups, and engine temp files. These are internal documents,
     * not user assets, and exposing them would break asset counts and create
     * misleading "unsupported asset" entries.
     */
    public static function isInternal(fileName:String):Bool {
        if (fileName == null || fileName.length == 0 || fileName.charAt(0) == ".") return true;
        var extension = extensionOf(fileName);
        return extension == "boltproject"
            || extension == "bak"
            || extension == "tmp";
    }

    /** `haxe.io.Path.ext` is null for extensionless names and directories. */
    static function extensionOf(fileName:String):String {
        var ext = new Path(fileName).ext;
        return ext == null ? "" : ext.toLowerCase();
    }
}
