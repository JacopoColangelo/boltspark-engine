package boltspark.editor;

import boltspark.engine.MaterialCulling;
import boltspark.engine.MeshRenderer;

/** Heaps projection of one renderer-independent MeshRenderer component. */
class SceneRendererView {
    public final component:MeshRenderer;
    public final mesh:h3d.scene.Mesh;

    public function new(component:MeshRenderer, parent:h3d.scene.Object) {
        if (component == null || component.mesh == null) {
            throw "SceneRendererView requires an assigned MeshRenderer";
        }
        this.component = component;
        mesh = new h3d.scene.Mesh(
            HeapsMeshFactory.resolve(component.mesh, component.primitiveSettings), parent);
        synchronize();
    }

    public function synchronize():Void {
        if (component.mesh == null) return;
        mesh.primitive = HeapsMeshFactory.resolve(
            component.mesh, component.primitiveSettings);
        mesh.name = component.gameObject == null
            ? component.displayName
            : component.gameObject.name + " · " + component.displayName;
        var material = component.material;
        mesh.material.name = material.name;
        mesh.material.color.setColor(material.color);
        mesh.material.shadows = material.shadows;
        mesh.material.specularAmount = material.specularAmount;
        mesh.material.specularPower = material.specularPower;
        var culling = toHeapsCulling(material.culling);
        mesh.material.mainPass.culling = culling;
        var shadowPass = mesh.material.getPass("shadow");
        if (shadowPass != null) shadowPass.culling = culling;
    }

    public function cullingForScale(mirrored:Bool):h3d.mat.Data.Face {
        return toHeapsCulling(component.cullingForScale(mirrored));
    }

    public function remove():Void mesh.remove();

    static function toHeapsCulling(value:MaterialCulling):h3d.mat.Data.Face {
        return switch (value) {
            case Back: h3d.mat.Data.Face.Back;
            case Front: h3d.mat.Data.Face.Front;
            case None: h3d.mat.Data.Face.None;
            case Both: h3d.mat.Data.Face.Both;
        };
    }
}
