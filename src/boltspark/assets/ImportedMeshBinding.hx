package boltspark.assets;

import boltspark.editor.HeapsMeshFactory;
import boltspark.engine.Mesh;
import boltspark.engine.PrimitiveMeshes;

/** Runtime-only bridge from parsed mesh files to assignable engine meshes. */
class ImportedMeshBinding {
    public static function install():Void {
        MeshParser.fbxResolver = function(path, name) return FbxParser.parse(path, name);
        ImportedMeshLibrary.onRegister = function(id, geometry) {
            var mesh = new Mesh(id, geometry.name, null, 1);
            PrimitiveMeshes.register(mesh);
            var factoryGeometry = geometry;
            HeapsMeshFactory.registerParametric(id,
                function(_) return HeapsMeshFactory.fromGeometry(factoryGeometry));
        };
        ImportedMeshLibrary.onClear = function() {
            PrimitiveMeshes.clearRegistered();
            HeapsMeshFactory.clearImported();
        };
    }

    public static function uninstall():Void {
        MeshParser.fbxResolver = null;
        ImportedMeshLibrary.onRegister = null;
        ImportedMeshLibrary.onClear = null;
    }
}
