package boltspark.editor;

import boltspark.engine.Material;
import boltspark.engine.MaterialCulling;
import boltspark.engine.MaterialTextureBindings;
import boltspark.engine.MeshRenderer;
import boltspark.editor.shaders.PbrNormalMap;
import boltspark.editor.shaders.PbrSurfaceProps;
import boltspark.editor.shaders.PbrUv;
import h3d.mat.PbrMaterial.PbrCullingMode;
import h3d.mat.PbrMaterial.PbrProps;

/** Heaps projection of one renderer-independent MeshRenderer component. */
class SceneRendererView {
    static final PBR_SETUP = new h3d.mat.PbrMaterialSetup();

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
            synchronizePbr(material, definition);
        }
    }

    static function synchronizePbr(material:h3d.mat.Material,
            definition:Material):Void {
        var pbr = Std.downcast(material, h3d.mat.PbrMaterial);
        if (pbr == null) return;

        var props:PbrProps = pbr.props;
        props.shadows = definition.shadows;
        props.culling = toPbrCulling(definition.culling);
        props.textureWrap = false; // tiling is handled by PbrUv
        pbr.refreshProps();

        var pass = pbr.mainPass;
        // refreshProps() installs a default PropsValues when it sees neither
        // stock props shader. Our shader replaces both stock variants.
        var stockValues = pass.getShader(h3d.shader.pbr.PropsValues);
        if (stockValues != null) pass.removeShader(stockValues);
        var stockTexture = pass.getShader(h3d.shader.pbr.PropsTexture);
        if (stockTexture != null) pass.removeShader(stockTexture);

        var uv = pass.getShader(PbrUv);
        if (uv == null) {
            uv = new PbrUv();
            pass.addShader(uv);
        }
        uv.tiling.set(definition.tilingX, definition.tilingY);
        uv.offset.set(definition.offsetX, definition.offsetY);

        var surface = pass.getShader(PbrSurfaceProps);
        if (surface == null) {
            surface = new PbrSurfaceProps();
            pass.addShader(surface);
        }
        surface.metalnessValue = definition.metallic;
        surface.roughnessValue = clamp(Math.max(0.045,
            1 - definition.smoothness), 0.045, 1);
        surface.occlusionStrength = definition.occlusionStrength;
        surface.smoothnessFromAlbedoAlpha =
            definition.smoothnessSource == Material.SMOOTHNESS_ALBEDO_ALPHA;

        var roughnessTexture = MaterialTextureBindings.get(definition.roughnessTexture);
        surface.hasRoughnessMap = roughnessTexture != null;
        surface.roughnessMap = roughnessTexture;

        var metallicTexture = MaterialTextureBindings.get(definition.metallicTexture);
        surface.hasMetallicMap = metallicTexture != null;
        surface.metallicMap = metallicTexture;

        var occlusionTexture = MaterialTextureBindings.get(definition.occlusionTexture);
        surface.hasOcclusionMap = occlusionTexture != null;
        surface.occlusionMap = occlusionTexture;

        var emission = definition.emissionColor;
        var intensity = definition.emissionIntensity;
        surface.emissiveColor.set(
            ((emission >> 16) & 0xFF) / 255 * intensity,
            ((emission >> 8) & 0xFF) / 255 * intensity,
            (emission & 0xFF) / 255 * intensity);
        surface.emissiveIntensity = 1;

        // Albedo uses Heaps' Texture shader so alpha/alpha-cutout keeps working.
        material.texture = MaterialTextureBindings.get(definition.albedoTexture);

        var normal = pass.getShader(PbrNormalMap);
        var normalTexture = MaterialTextureBindings.get(definition.normalTexture);
        if (normalTexture != null) {
            if (normal == null) {
                normal = new PbrNormalMap(normalTexture, definition.normalStrength);
                pass.addShader(normal);
            }
            normal.texture = normalTexture;
            normal.strength = definition.normalStrength;
        } else if (normal != null) {
            pass.removeShader(normal);
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
        var material = PBR_SETUP.createMaterial();
        material.props = material.getDefaultProps();
        return material;
    }

    static function toPbrCulling(value:MaterialCulling):PbrCullingMode {
        return switch (value) {
            case Back: PbrCullingMode.Back;
            case Front: PbrCullingMode.Front;
            case None: PbrCullingMode.None;
            case Both: PbrCullingMode.Both;
        };
    }

    static function toHeapsCulling(value:MaterialCulling):h3d.mat.Data.Face {
        return switch (value) {
            case Back: h3d.mat.Data.Face.Back;
            case Front: h3d.mat.Data.Face.Front;
            case None: h3d.mat.Data.Face.None;
            case Both: h3d.mat.Data.Face.Both;
        };
    }

    static inline function clamp(value:Float, min:Float, max:Float):Float {
        return value < min ? min : (value > max ? max : value);
    }
}
