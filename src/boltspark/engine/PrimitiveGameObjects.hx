package boltspark.engine;

/** Convenience factories; primitives remain ordinary GameObjects. */
class PrimitiveGameObjects {
    public static function createCube(name:String = "Cube"):GameObject {
        var result = new GameObject(name);
        result.addComponent(createCubeRenderer());
        return result;
    }

    public static function createCubeRenderer():MeshRenderer {
        return new MeshRenderer(PrimitiveMeshes.cube(),
            Material.defaultMaterial());
    }

    /** Fresh component list suitable for EditorSession object creation. */
    public static function cubeComponents():Array<Component> {
        return [createCubeRenderer()];
    }
}
