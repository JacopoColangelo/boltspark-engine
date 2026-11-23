package boltspark.project;

/** JSON codec for MaterialDocument, following SceneCodec's field contract. */
class MaterialCodec {
    static final MATERIAL_FIELDS = [
        "version", "id", "name", "baseColor", "albedoTexture",
        "culling", "shadows",
        "metallic", "smoothness", "smoothnessSource",
        "metallicTexture", "normalTexture", "normalStrength", "roughnessTexture",
        "occlusionTexture", "occlusionStrength",
        "emissionColor", "emissionIntensity",
        "tilingX", "tilingY", "offsetX", "offsetY"
    ];

    /** Schema-1 fields dropped by the PBR migration; never treated as extras. */
    static final LEGACY_FIELDS = ["specularAmount", "specularPower"];

    public static function encode(material:MaterialDocument,
            pretty:Bool = true):String {
        ProjectValidator.validateMaterial(material);
        var root = JsonFields.withExtras(material.extraFields);
        Reflect.setField(root, "version", MaterialDocument.SCHEMA_VERSION);
        Reflect.setField(root, "id", material.id);
        Reflect.setField(root, "name", material.name);
        Reflect.setField(root, "baseColor", material.baseColor);
        Reflect.setField(root, "albedoTexture", material.albedoTexture);
        Reflect.setField(root, "culling", material.culling);
        Reflect.setField(root, "shadows", material.shadows);
        Reflect.setField(root, "metallic", material.metallic);
        Reflect.setField(root, "smoothness", material.smoothness);
        Reflect.setField(root, "smoothnessSource", material.smoothnessSource);
        Reflect.setField(root, "metallicTexture", material.metallicTexture);
        Reflect.setField(root, "normalTexture", material.normalTexture);
        Reflect.setField(root, "normalStrength", material.normalStrength);
        Reflect.setField(root, "roughnessTexture", material.roughnessTexture);
        Reflect.setField(root, "occlusionTexture", material.occlusionTexture);
        Reflect.setField(root, "occlusionStrength", material.occlusionStrength);
        Reflect.setField(root, "emissionColor", material.emissionColor);
        Reflect.setField(root, "emissionIntensity", material.emissionIntensity);
        Reflect.setField(root, "tilingX", material.tilingX);
        Reflect.setField(root, "tilingY", material.tilingY);
        Reflect.setField(root, "offsetX", material.offsetX);
        Reflect.setField(root, "offsetY", material.offsetY);
        return haxe.Json.stringify(root, null, pretty ? "  " : null);
    }

    public static function decode(contents:String):MaterialDocument {
        var root:Dynamic;
        try {
            root = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            throw 'Material JSON could not be parsed: ${Std.string(error)}';
        }
        JsonFields.object(root, "material");
        var version = JsonFields.intField(root, "version", "material");
        if (version != 1 && version != MaterialDocument.SCHEMA_VERSION) {
            throw 'Unsupported material schema version ${version}';
        }
        var known = version == 1 ? MATERIAL_FIELDS.concat(LEGACY_FIELDS) : MATERIAL_FIELDS;
        var material = new MaterialDocument(
            JsonFields.stringField(root, "id", "material"),
            JsonFields.stringField(root, "name", "material"),
            JsonFields.intField(root, "baseColor", "material"),
            JsonFields.stringField(root, "albedoTexture", "material"),
            JsonFields.stringField(root, "culling", "material"),
            Reflect.field(root, "shadows") == true,
            JsonFields.extras(root, known));
        if (version == MaterialDocument.SCHEMA_VERSION) {
            material.metallic = JsonFields.numberField(root, "metallic", "material");
            material.smoothness = JsonFields.numberField(root, "smoothness", "material");
            material.smoothnessSource = JsonFields.stringField(root, "smoothnessSource", "material");
            material.metallicTexture = JsonFields.stringField(root, "metallicTexture", "material");
            material.normalTexture = JsonFields.stringField(root, "normalTexture", "material");
            material.normalStrength = JsonFields.numberField(root, "normalStrength", "material");
            // Additive field: older v2 documents omit it.
            material.roughnessTexture = Reflect.field(root, "roughnessTexture") == null
                ? "" : JsonFields.stringField(root, "roughnessTexture", "material");
            material.occlusionTexture = JsonFields.stringField(root, "occlusionTexture", "material");
            material.occlusionStrength = JsonFields.numberField(root, "occlusionStrength", "material");
            material.emissionColor = JsonFields.intField(root, "emissionColor", "material");
            material.emissionIntensity = JsonFields.numberField(root, "emissionIntensity", "material");
            material.tilingX = JsonFields.numberField(root, "tilingX", "material");
            material.tilingY = JsonFields.numberField(root, "tilingY", "material");
            material.offsetX = JsonFields.numberField(root, "offsetX", "material");
            material.offsetY = JsonFields.numberField(root, "offsetY", "material");
        }
        // Schema 1 migrates with neutral PBR defaults; its Blinn-Phong
        // specular pair has no physical equivalent and is intentionally dropped.
        ProjectValidator.validateMaterial(material);
        return material;
    }
}
