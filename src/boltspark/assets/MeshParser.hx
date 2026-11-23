package boltspark.assets;

import boltspark.project.AssetTypeRegistry;

/**
 * Extension dispatcher for the supported mesh import formats. FBX decoding uses
 * pinned Heaps code, so it is injected at runtime to keep headless tests free of
 * h3d dependencies.
 */
class MeshParser {
    public static var fbxResolver:Null<String->String->MeshGeometry> = null;

    public static function parse(path:String, name:String = ""):MeshGeometry {
        var extension = AssetTypeRegistry.extensionOf(path);
        return switch (extension) {
            case "obj":
                ObjParser.parse(sys.io.File.getContent(path), name);
            case "gltf" | "glb":
                GltfParser.parse(path, name);
            case "fbx":
                if (fbxResolver == null) throw 'FBX parser is not available: ${path}';
                fbxResolver(path, name);
            default:
                throw 'Unsupported mesh format: ${extension}';
        };
    }
}
