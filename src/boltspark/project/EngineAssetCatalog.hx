package boltspark.project;

import boltspark.engine.Material;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.inspector.AssetType;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.AssetDragPayload;

/**
 * Engine-provided assets surfaced by the Asset Browser. Primitives and built-in
 * materials have no on-disk files, so they are synthesized as AssetFileInfo
 * records with a reserved `engine://` source scheme. They stay out of every
 * filesystem command and can only be consumed through a type-aware asset slot.
 */
class EngineAssetCatalog {
    public static inline var SOURCE_PREFIX:String = "engine://";
    /** Virtual root folder that groups engine assets in the browser. */
    public static inline var FOLDER:String = "Engine";
    /** Engine meshes and materials get their own virtual subfolders. */
    public static inline var MESH_FOLDER:String = FOLDER + "/Meshes";
    public static inline var MATERIAL_FOLDER:String = FOLDER + "/Materials";
    public static inline var MESH_LABEL:String = "Mesh";
    public static inline var MATERIAL_LABEL:String = "Material";

    public static function all():Array<AssetFileInfo> {
        var result:Array<AssetFileInfo> = [];
        for (mesh in PrimitiveMeshes.all()) {
            result.push(make(sourceFor(AssetType.MeshAsset, mesh.id), mesh.name,
                AssetType.MeshAsset));
        }
        for (material in Material.all()) {
            result.push(make(sourceFor(AssetType.MaterialAsset, material.id),
                material.name, AssetType.MaterialAsset));
        }
        return result;
    }

    /** Virtual folder for one engine asset family. */
    public static function folderFor(assetType:AssetType):String {
        return switch (assetType) {
            case AssetType.MeshAsset: MESH_FOLDER;
            case AssetType.MaterialAsset: MATERIAL_FOLDER;
            default: FOLDER;
        };
    }

    /** Caption shown under an engine asset's name in the browser. */
    public static function labelFor(assetType:AssetType):String {
        return switch (assetType) {
            case AssetType.MeshAsset: MESH_LABEL;
            case AssetType.MaterialAsset: MATERIAL_LABEL;
            default: AssetTypeRegistry.ENGINE_INFO_LABEL;
        };
    }

    public static function sourceFor(assetType:AssetType, id:String):String {
        return SOURCE_PREFIX + assetType + "/" + id;
    }

    /** Build the Inspector drag payload for an engine asset entry, if any. */
    public static function dragPayload(entry:Null<AssetFileInfo>):Null<AssetDragPayload> {
        if (entry == null || entry.kind != AssetTypeRegistry.KIND_ENGINE) return null;
        if (!StringTools.startsWith(entry.source, SOURCE_PREFIX)) return null;
        var rest = entry.source.substr(SOURCE_PREFIX.length);
        var slash = rest.indexOf("/");
        if (slash < 0) return null;
        var family = rest.substr(0, slash);
        var id = rest.substr(slash + 1);
        if (id.length == 0) return null;
        var assetType:Null<AssetType> = switch (family) {
            case "mesh": AssetType.MeshAsset;
            case "material": AssetType.MaterialAsset;
            default: null;
        };
        if (assetType == null) return null;
        // Only hand out ids the engine can actually resolve to an asset.
        var valid = assetType == AssetType.MeshAsset
            ? PrimitiveMeshes.find(id) != null
            : Material.find(id) != null;
        if (!valid) return null;
        return {
            assetId: id,
            label: entry.name,
            assetType: assetType,
            source: entry.source
        };
    }

    static function make(source:String, name:String,
            assetType:AssetType):AssetFileInfo {
        return {
            source: source,
            name: name,
            folder: folderFor(assetType),
            kind: AssetTypeRegistry.KIND_ENGINE,
            active: false,
            registered: false,
            extension: "",
            kindLabel: labelFor(assetType),
            loadable: true
        };
    }
}
