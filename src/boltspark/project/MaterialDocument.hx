package boltspark.project;

import boltspark.engine.Material;

/**
 * Versioned, project-authored material asset using the metallic/smoothness
 * PBR workflow. Mirrors SceneDocument's field contract.
 *
 * Schema 2 replaced the legacy Blinn-Phong `specularAmount`/`specularPower`
 * pair with metallic/smoothness values and dedicated PBR texture slots.
 * Schema 1 documents still decode (their specular values are dropped).
 */
class MaterialDocument {
    public static inline var SCHEMA_VERSION:Int = 2;

    public var version:Int;
    public var id:String;
    public var name:String;
    public var baseColor:Int;
    /** Project-relative source of an imported texture, or "" for none. */
    public var albedoTexture:String;
    public var culling:String;
    public var shadows:Bool;

    public var metallic:Float;
    public var smoothness:Float;
    /** "metallicAlpha" or "albedoAlpha"; see Material.SMOOTHNESS_*. */
    public var smoothnessSource:String;
    public var metallicTexture:String;
    public var normalTexture:String;
    public var normalStrength:Float;
    /** Optional roughness map (G channel). "" for none. */
    public var roughnessTexture:String;
    public var occlusionTexture:String;
    public var occlusionStrength:Float;
    public var emissionColor:Int;
    public var emissionIntensity:Float;
    public var tilingX:Float;
    public var tilingY:Float;
    public var offsetX:Float;
    public var offsetY:Float;

    public var extraFields:Dynamic;

    public function new(id:String, name:String, ?baseColor:Int,
            ?albedoTexture:String, ?culling:String, ?shadows:Bool,
            ?extraFields:Dynamic) {
        version = SCHEMA_VERSION;
        this.id = id;
        this.name = name;
        this.baseColor = baseColor == null ? 0xFFFFFF : baseColor;
        this.albedoTexture = albedoTexture == null ? "" : albedoTexture;
        this.culling = culling == null ? "back" : culling;
        this.shadows = shadows == null ? false : shadows;
        metallic = 0;
        smoothness = 0.5;
        smoothnessSource = Material.SMOOTHNESS_METALLIC_ALPHA;
        metallicTexture = "";
        normalTexture = "";
        normalStrength = 1;
        roughnessTexture = "";
        occlusionTexture = "";
        occlusionStrength = 1;
        emissionColor = 0x000000;
        emissionIntensity = 1;
        tilingX = 1;
        tilingY = 1;
        offsetX = 0;
        offsetY = 0;
        this.extraFields = extraFields == null ? {} : extraFields;
    }

    /** Build the runtime engine definition for this document. */
    public function toMaterial(source:String):Material {
        var material = new Material(id, name, baseColor, shadows,
            cast culling, albedoTexture, source);
        applyTo(material);
        return material;
    }

    /** Copy every authored PBR value onto an existing runtime definition. */
    public function applyTo(material:Material):Void {
        material.color = baseColor;
        material.shadows = shadows;
        material.culling = cast culling;
        material.albedoTexture = albedoTexture;
        material.metallic = metallic;
        material.smoothness = smoothness;
        material.smoothnessSource = smoothnessSource;
        material.metallicTexture = metallicTexture;
        material.normalTexture = normalTexture;
        material.normalStrength = normalStrength;
        material.roughnessTexture = roughnessTexture;
        material.occlusionTexture = occlusionTexture;
        material.occlusionStrength = occlusionStrength;
        material.emissionColor = emissionColor;
        material.emissionIntensity = emissionIntensity;
        material.tilingX = tilingX;
        material.tilingY = tilingY;
        material.offsetX = offsetX;
        material.offsetY = offsetY;
    }
}
