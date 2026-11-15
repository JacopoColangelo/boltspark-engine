package boltspark.engine;

/** Built-in geometry assets. Primitive identity is independent of GameObject. */
class PrimitiveMeshes {
    public static inline var CUBE_ID:String = "primitive:cube";

    static var cubeMesh:Null<Mesh>;

    public static function cube():Mesh {
        if (cubeMesh == null) {
            cubeMesh = new Mesh(CUBE_ID, "Primitive Cube", "cube");
        }
        return cubeMesh;
    }

    public static function find(id:String):Null<Mesh> {
        return switch (id) {
            case CUBE_ID, "cube", "Primitive Cube": cube();
            default: null;
        };
    }
}
