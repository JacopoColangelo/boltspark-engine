package boltspark.editor;

import boltspark.project.StableId;

class SceneObject {
    public final id:Int;
    /** Durable serialization identity; runtime selection continues to use `id`. */
    public final persistentId:String;
    public final mesh:h3d.scene.Mesh;
    /** Authored culling before transform parity is applied. */
    public final baseCulling:h3d.mat.Data.Face;
    /** Continuous editor-Euler representation corresponding to mesh rotation. */
    public final rotationHint:h3d.Vector = new h3d.Vector();
    public var rotationHintValid:Bool = false;

    public function new(id:Int, mesh:h3d.scene.Mesh, ?persistentId:String) {
        this.id = id;
        this.persistentId = persistentId == null
            ? StableId.create("scene-object")
            : StableId.require(persistentId, "sceneObject.persistentId");
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

    /** Capture the exact renderer transform for an editor command preview. */
    public function captureTransform():EditorTransform {
        var rotation = mesh.getRotationQuat();
        return new EditorTransform(mesh.x, mesh.y, mesh.z,
            rotation.x, rotation.y, rotation.z, rotation.w,
            rotationHint.x, rotationHint.y, rotationHint.z,
            rotationHintValid, mesh.scaleX, mesh.scaleY, mesh.scaleZ);
    }

    /** Apply a renderer-independent session transform without Euler conversion. */
    public function applyTransform(transform:EditorTransform):Void {
        mesh.setPosition(transform.positionX, transform.positionY,
            transform.positionZ);
        mesh.setRotationQuat(new h3d.Quat(transform.rotationX,
            transform.rotationY, transform.rotationZ, transform.rotationW));
        mesh.scaleX = transform.scaleX;
        mesh.scaleY = transform.scaleY;
        mesh.scaleZ = transform.scaleZ;
        rotationHint.set(transform.rotationHintX, transform.rotationHintY,
            transform.rotationHintZ);
        rotationHintValid = transform.rotationHintValid;
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
