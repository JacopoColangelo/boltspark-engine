package boltspark.editor;

class SceneObject {
    public final id:Int;
    public final mesh:h3d.scene.Mesh;
    /** Authored culling before transform parity is applied. */
    public final baseCulling:h3d.mat.Data.Face;
    /** Continuous editor-Euler representation corresponding to mesh rotation. */
    public final rotationHint:h3d.Vector = new h3d.Vector();
    public var rotationHintValid:Bool = false;

    public function new(id:Int, mesh:h3d.scene.Mesh) {
        this.id = id;
        this.mesh = mesh;
        baseCulling = mesh.material.mainPass.culling;
    }

    public function cullingForScale(mirrored:Bool):h3d.mat.Data.Face {
        if (!mirrored) return baseCulling;
        return switch (baseCulling) {
            case Back: Front;
            case Front: Back;
            case None: None;
            case Both: Both;
        };
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
