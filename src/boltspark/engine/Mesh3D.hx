package boltspark.engine;

/**
 * The engine's renderable 3D object type.
 *
 * A Mesh3D is a ordinary GameObject whose defining behavior is a MeshRenderer.
 * It exists so the engine can answer "is this a 3D mesh object?" without the
 * caller having to know about components, while type determination stays
 * component-based under the hood. Primitive factory objects and editor scene
 * objects that carry a MeshRenderer both report this type through `objectType`.
 */
class Mesh3D extends GameObject {
    public static inline var TYPE:String = "Mesh3D";

    public var meshRenderer(default, null):MeshRenderer;

    public function new(name:String = "Mesh3D", ?mesh:Mesh, ?material:Material) {
        super(name);
        meshRenderer = new MeshRenderer(mesh, material);
        addComponent(meshRenderer);
    }

    override function get_objectType():String return TYPE;

    /** True for an engine Mesh3D or any editor projection that reports its type. */
    public static function is(object:Dynamic):Bool {
        if (object == null) return false;
        if (Std.isOfType(object, Mesh3D)) return true;
        return Std.isOfType(object, GameObject)
            && cast(object, GameObject).objectType == TYPE;
    }
}
