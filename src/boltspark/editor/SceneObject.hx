package boltspark.editor;

import boltspark.project.StableId;

class SceneObject {
    public final id:Int;
    /** Durable serialization identity; runtime selection continues to use `id`. */
    public final persistentId:String;
    /** Render node; empty hierarchy objects use a plain h3d.scene.Object. */
    public final mesh:h3d.scene.Object;
    public final renderMesh:Null<h3d.scene.Mesh>;
    /** Authored culling before transform parity is applied. */
    public final baseCulling:h3d.mat.Data.Face;
    /** Continuous editor-Euler representation corresponding to mesh rotation. */
    public final rotationHint:h3d.Vector = new h3d.Vector();
    public var rotationHintValid:Bool = false;

    var appliedTransform:EditorTransform = new EditorTransform();

    public function new(id:Int, mesh:h3d.scene.Object, ?persistentId:String) {
        this.id = id;
        this.persistentId = persistentId == null
            ? StableId.create("scene-object")
            : StableId.require(persistentId, "sceneObject.persistentId");
        this.mesh = mesh;
        renderMesh = Std.downcast(mesh, h3d.scene.Mesh);
        baseCulling = renderMesh == null
            ? h3d.mat.Data.Face.None
            : renderMesh.material.mainPass.culling;
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
            rotationHintValid, mesh.scaleX, mesh.scaleY, mesh.scaleZ,
            appliedTransform.shearXY, appliedTransform.shearXZ,
            appliedTransform.shearYZ);
    }

    /** Apply a renderer-independent session transform without Euler conversion. */
    public function applyTransform(transform:EditorTransform):Void {
        mesh.defaultTransform = null;
        mesh.setPosition(transform.positionX, transform.positionY,
            transform.positionZ);
        mesh.setRotationQuat(normalizedQuaternion(transform));
        mesh.scaleX = transform.scaleX;
        mesh.scaleY = transform.scaleY;
        mesh.scaleZ = transform.scaleZ;
        rotationHint.set(transform.rotationHintX, transform.rotationHintY,
            transform.rotationHintZ);
        rotationHintValid = transform.rotationHintValid;
        appliedTransform = transform.clone();

        // Heaps' editable channels represent TRS. Apply an additional local
        // correction only when exact affine shear is present. This keeps the
        // common path fully editable while preserving world-space appearance
        // after non-uniform, rotated reparenting.
        if (transform.shearXY != 0 || transform.shearXZ != 0
                || transform.shearYZ != 0) {
            var desired = toHeapsMatrix(transform.toMatrix());
            var base = mesh.getTransform();
            var inverseBase = new h3d.Matrix();
            inverseBase.inverse3x4(base);
            var correction = new h3d.Matrix();
            correction.multiply3x4(desired, inverseBase);
            mesh.defaultTransform = correction;
        }
    }

    static function toHeapsMatrix(value:TransformMatrix):h3d.Matrix {
        var result = new h3d.Matrix();
        // Heaps uses row vectors, so this is the transpose of the editor's
        // column-vector affine matrix.
        result._11 = value.m00; result._12 = value.m10; result._13 = value.m20; result._14 = 0;
        result._21 = value.m01; result._22 = value.m11; result._23 = value.m21; result._24 = 0;
        result._31 = value.m02; result._32 = value.m12; result._33 = value.m22; result._34 = 0;
        result._41 = value.m03; result._42 = value.m13; result._43 = value.m23; result._44 = 1;
        return result;
    }

    /** Keep Heaps' non-normalizing quaternion path aligned with EditorTransform. */
    static function normalizedQuaternion(transform:EditorTransform):h3d.Quat {
        var maximum = Math.max(Math.max(Math.abs(transform.rotationX),
            Math.abs(transform.rotationY)), Math.max(Math.abs(transform.rotationZ),
            Math.abs(transform.rotationW)));
        if (!Math.isFinite(maximum) || maximum <= 0.000000000001) {
            throw "Cannot render a non-finite or zero-length quaternion";
        }
        var x = transform.rotationX / maximum;
        var y = transform.rotationY / maximum;
        var z = transform.rotationZ / maximum;
        var w = transform.rotationW / maximum;
        var length = Math.sqrt(x * x + y * y + z * z + w * w);
        return new h3d.Quat(x / length, y / length, z / length, w / length);
    }

    public var name(get, set):String;

    function get_name():String {
        return mesh.name == null ? "GameObject" : mesh.name;
    }

    function set_name(value:String):String {
        mesh.name = value;
        return value;
    }
}
