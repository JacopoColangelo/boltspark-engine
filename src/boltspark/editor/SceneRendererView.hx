package boltspark.editor;

import boltspark.engine.MaterialCulling;
import boltspark.engine.MaterialTextureBindings;
import boltspark.engine.MeshRenderer;

/** Heaps projection of one renderer-independent MeshRenderer component. */
class SceneRendererView {
    public final component:MeshRenderer;
    /** MultiMaterial keeps one Heaps material per renderer material slot. */
    public final mesh:h3d.scene.MultiMaterial;

    public function new(component:MeshRenderer, parent:h3d.scene.Object) {
        if (component == null || component.mesh == null) {
            throw "SceneRendererView requires an assigned MeshRenderer";
        }
        this.component = component;
        var primitive = HeapsMeshFactory.resolve(component.mesh, component.primitiveSettings);
        var materials = buildMaterials(component.materialCount);
        mesh = new h3d.scene.MultiMaterial(primitive, materials, parent);
        synchronize();
    }

    public function synchronize():Void {
        if (component.mesh == null) return;
        mesh.primitive = HeapsMeshFactory.resolve(
            component.mesh, component.primitiveSettings);
        mesh.name = component.gameObject == null
            ? component.displayName
            : component.gameObject.name + " · " + component.displayName;
        ensureMaterialCount(component.materialCount);
        for (index in 0...mesh.materials.length) {
            var definition = component.getMaterial(index);
            var material = mesh.materials[index];
            if (definition == null || material == null) continue;
            material.name = definition.name;
            material.color.setColor(definition.color);
            material.shadows = definition.shadows;
            material.specularAmount = definition.specularAmount;
            material.specularPower = definition.specularPower;
            // Material assets own their albedo map; MeshRenderer only stores a
            // reference to the material, so the renderer reads it from there.
            material.texture = MaterialTextureBindings.get(definition.albedoTexture);
            var culling = toHeapsCulling(definition.culling);
            material.mainPass.culling = culling;
            var shadowPass = material.getPass("shadow");
            if (shadowPass != null) shadowPass.culling = culling;
        }
    }

    public function cullingForScale(mirrored:Bool,
            ?materialIndex:Int):h3d.mat.Data.Face {
        return toHeapsCulling(component.cullingForScale(mirrored, materialIndex));
    }

    public function remove():Void mesh.remove();

    function ensureMaterialCount(count:Int):Void {
        while (mesh.materials.length > count) mesh.materials.pop();
        while (mesh.materials.length < count) mesh.materials.push(buildMaterial());
    }

    static function buildMaterials(count:Int):Array<h3d.mat.Material> {
        var result:Array<h3d.mat.Material> = [];
        for (index in 0...count) result.push(buildMaterial());
        return result;
    }

    static function buildMaterial():h3d.mat.Material {
        var material = h3d.mat.MaterialSetup.current.createMaterial();
        material.props = material.getDefaultProps();
        return material;
    }

    static function toHeapsCulling(value:MaterialCulling):h3d.mat.Data.Face {
        return switch (value) {
            case Back: h3d.mat.Data.Face.Back;
            case Front: h3d.mat.Data.Face.Front;
            case None: h3d.mat.Data.Face.None;
            case Both: h3d.mat.Data.Face.Both;
        };
    }
}
