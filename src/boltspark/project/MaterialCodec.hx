package boltspark.project;

/** JSON codec for MaterialDocument, following SceneCodec's field contract. */
class MaterialCodec {
    static final MATERIAL_FIELDS = [
        "version", "id", "name", "baseColor", "albedoTexture",
        "specularAmount", "specularPower", "culling", "shadows"
    ];

    public static function encode(material:MaterialDocument,
            pretty:Bool = true):String {
        ProjectValidator.validateMaterial(material);
        var root = JsonFields.withExtras(material.extraFields);
        Reflect.setField(root, "version", MaterialDocument.SCHEMA_VERSION);
        Reflect.setField(root, "id", material.id);
        Reflect.setField(root, "name", material.name);
        Reflect.setField(root, "baseColor", material.baseColor);
        Reflect.setField(root, "albedoTexture", material.albedoTexture);
        Reflect.setField(root, "specularAmount", material.specularAmount);
        Reflect.setField(root, "specularPower", material.specularPower);
        Reflect.setField(root, "culling", material.culling);
        Reflect.setField(root, "shadows", material.shadows);
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
        if (version != MaterialDocument.SCHEMA_VERSION) {
            throw 'Unsupported material schema version ${version}';
        }
        var material = new MaterialDocument(
            JsonFields.stringField(root, "id", "material"),
            JsonFields.stringField(root, "name", "material"),
            JsonFields.intField(root, "baseColor", "material"),
            JsonFields.stringField(root, "albedoTexture", "material"),
            JsonFields.numberField(root, "specularAmount", "material"),
            JsonFields.numberField(root, "specularPower", "material"),
            JsonFields.stringField(root, "culling", "material"),
            Reflect.field(root, "shadows") == true,
            JsonFields.extras(root, MATERIAL_FIELDS));
        ProjectValidator.validateMaterial(material);
        return material;
    }
}
