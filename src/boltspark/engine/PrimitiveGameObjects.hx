package boltspark.engine;

/** Convenience factories for Mesh3D objects backed by primitive assets. */
class PrimitiveGameObjects {
    public static function createCube(name:String = "Cube"):Mesh3D {
        return new Mesh3D(name, PrimitiveMeshes.cube(), Material.defaultMaterial());
    }

    public static function createCubeRenderer():MeshRenderer {
        return new MeshRenderer(PrimitiveMeshes.cube(),
            Material.defaultMaterial());
    }

    /** Fresh component list suitable for EditorSession object creation. */
    public static function cubeComponents():Array<Component> {
        return [createCubeRenderer()];
    }

    /** Renderer referencing a primitive asset with its default settings. */
    public static function createPrimitiveRenderer(mesh:Mesh):MeshRenderer {
        if (mesh == null) throw "Cannot create a renderer for a null mesh";
        return new MeshRenderer(mesh, Material.defaultMaterial(),
            null, null, PrimitiveMeshes.defaultSettings(mesh.primitiveId));
    }

    /** Fresh component list for any primitive asset id or alias. */
    public static function primitiveComponents(meshId:String):Array<Component> {
        var mesh = PrimitiveMeshes.find(meshId);
        if (mesh == null) throw 'Unknown primitive mesh ${meshId}';
        return [createPrimitiveRenderer(mesh)];
    }

    /** Display name used by the Add Object palette and context menus. */
    public static function displayName(meshId:String):String {
        var mesh = PrimitiveMeshes.find(meshId);
        return mesh == null ? "Primitive" : mesh.name;
    }
}
