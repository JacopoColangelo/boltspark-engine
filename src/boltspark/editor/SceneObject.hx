package boltspark.editor;

class SceneObject {
    public final id:Int;
    public final mesh:h3d.scene.Mesh;

    public function new(id:Int, mesh:h3d.scene.Mesh) {
        this.id = id;
        this.mesh = mesh;
    }

    public var name(get, set):String;

    function get_name():String {
        return mesh.name;
    }

    function set_name(value:String):String {
        mesh.name = value;
        return value;
    }
}
