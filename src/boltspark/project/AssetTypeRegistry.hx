package boltspark.project;

import haxe.io.Path;

/**
 * The single source of truth for which on-disk asset kinds Boltspark actually
 * understands. The engine loads scene documents (`.boltscene`) and imported
 * textures (PNG/JPG/TGA); it also shows engine-provided assets (primitives and
 * built-in materials) under the "Engine Asset" kind. Those have no on-disk
 * files and are built by `EngineAssetCatalog`; everything else under the
 * project root is surfaced as a generic file so users can still see, organize,
 * and reveal it without the browser pretending the engine can import it.
 *
 * The registry deliberately contains no UI or rendering code. It is shared by
 * the filesystem scan, the import command, and the Asset Browser so extension
 * checks never drift between them.
 */
typedef AssetTypeInfo = {
    /** Stable machine kind: "scene", "texture", "engine", or "file". */
    var kind:String;
    /** Human-readable label shown in filters and the inspector. */
    var label:String;
    /** Lower-case extension without the dot ("" for generic/engine assets). */
    var extension:String;
    /** True only when the engine has a real loader for this kind. */
    var loadable:Bool;
};

class AssetTypeRegistry {
    public static inline var SCENE_EXT:String = "boltscene";
    public static inline var KIND_SCENE:String = "scene";
    public static inline var KIND_TEXTURE:String = "texture";
    public static inline var KIND_MATERIAL:String = "material";
    public static inline var KIND_ENGINE:String = "engine";
    public static inline var KIND_FILE:String = "file";
    public static inline var SCENE_INFO_LABEL:String = "Scene";
    public static inline var TEXTURE_INFO_LABEL:String = "Texture";
    public static inline var MATERIAL_INFO_LABEL:String = "Material";
    public static inline var ENGINE_INFO_LABEL:String = "Engine Asset";
    public static inline var FILE_INFO_LABEL:String = "File";
    /** Canonical filter extension; the other accepted texture formats are in TEXTURE_EXTENSIONS. */
    public static inline var TEXTURE_EXT:String = "png";
    /** Extensions accepted by the external import command and Explorer drop path. */
    public static final TEXTURE_EXTENSIONS:Array<String> = ["png", "jpg", "jpeg", "tga"];
    /** File-dialog filter shown for texture imports. */
    public static inline var TEXTURE_FILTER_LABEL:String = "Image files (PNG/JPG/TGA)";
    /** Project-authored material documents. */
    public static inline var MATERIAL_EXT:String = "boltmaterial";

    static final SCENE_INFO:AssetTypeInfo = {
        kind: KIND_SCENE,
        label: "Scene",
        extension: SCENE_EXT,
        loadable: true
    };
    static final TEXTURE_INFO:AssetTypeInfo = {
        kind: KIND_TEXTURE,
        label: TEXTURE_INFO_LABEL,
        extension: TEXTURE_EXT,
        loadable: true
    };
    static final MATERIAL_INFO:AssetTypeInfo = {
        kind: KIND_MATERIAL,
        label: MATERIAL_INFO_LABEL,
        extension: MATERIAL_EXT,
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
        var extension = extensionOf(fileName);
        if (extension == SCENE_EXT) return SCENE_INFO;
        if (isTextureExtension(extension)) return TEXTURE_INFO;
        if (extension == MATERIAL_EXT) return MATERIAL_INFO;
        return FILE_INFO;
    }

    /** True for any extension accepted by the texture importer. */
    public static function isTextureExtension(extension:String):Bool {
        if (extension == null) return false;
        var lower = extension.toLowerCase();
        if (StringTools.startsWith(lower, ".")) lower = lower.substr(1);
        return TEXTURE_EXTENSIONS.indexOf(lower) >= 0;
    }

    /** Classify a full path or bare file name as an importable texture. */
    public static function isTextureFile(fileName:String):Bool {
        return fileName != null && isTextureExtension(extensionOf(fileName));
    }

    /** Kind string for an asset scan record. */
    public static function kindFor(fileName:String):String {
        return infoFor(fileName).kind;
    }

    /** Metadata for engine-provided assets such as primitives. */
    public static function engineInfo():AssetTypeInfo return ENGINE_INFO;

    /** Metadata for imported textures (dialog/filter extension is PNG). */
    public static function textureInfo():AssetTypeInfo return TEXTURE_INFO;

    /** Kinds offered by the browser's type filter. Generic files are last. */
    public static function filterKinds():Array<AssetTypeInfo> {
        return [SCENE_INFO, TEXTURE_INFO, MATERIAL_INFO, ENGINE_INFO, FILE_INFO];
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
    public static function extensionOf(fileName:String):String {
        var ext = new Path(fileName).ext;
        return ext == null ? "" : ext.toLowerCase();
    }
}
