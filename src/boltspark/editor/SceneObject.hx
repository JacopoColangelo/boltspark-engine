package boltspark.editor;

class SceneObject {
    public final id:Int;
    public final mesh:h3d.scene.Mesh;
    public var spinSpeed:Float;
    public var color:Int;

    public function new(id:Int, mesh:h3d.scene.Mesh, color:Int, spinSpeed:Float = 0.35) {
        this.id = id;
        this.mesh = mesh;
        this.color = color;
        this.spinSpeed = spinSpeed;
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
