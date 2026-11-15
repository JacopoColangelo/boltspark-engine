package boltspark.project;

class ProjectCodec {
    static final PROJECT_FIELDS = ["version", "id", "name", "defaultSceneId", "assets"];
    static final ASSET_FIELDS = ["id", "type", "source", "importSettings"];

    public static function encode(project:ProjectDocument, pretty:Bool = true):String {
        ProjectValidator.validateProject(project);
        var root = JsonFields.withExtras(project.extraFields);
        Reflect.setField(root, "version", ProjectDocument.SCHEMA_VERSION);
        Reflect.setField(root, "id", project.id);
        Reflect.setField(root, "name", project.name);
        Reflect.setField(root, "defaultSceneId", project.defaultSceneId);
        var assets:Array<Dynamic> = [];
        for (asset in project.assets) {
            var value = JsonFields.withExtras(asset.extraFields);
            Reflect.setField(value, "id", asset.id);
            Reflect.setField(value, "type", asset.type);
            Reflect.setField(value, "source", asset.source);
            Reflect.setField(value, "importSettings", asset.importSettings);
            assets.push(value);
        }
        Reflect.setField(root, "assets", assets);
        return haxe.Json.stringify(root, null, pretty ? "  " : null);
    }

    public static function decode(contents:String):ProjectDocument {
        var root:Dynamic;
        try {
            root = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            throw 'Project JSON could not be parsed: ${Std.string(error)}';
        }
        JsonFields.object(root, "project");
        var version = JsonFields.intField(root, "version", "project");
        if (version != ProjectDocument.SCHEMA_VERSION) {
            throw 'Unsupported project schema version ${version}';
        }
        var project = new ProjectDocument(
            JsonFields.stringField(root, "id", "project"),
            JsonFields.stringField(root, "name", "project"),
            JsonFields.nullableStringField(root, "defaultSceneId", "project"),
            [], JsonFields.extras(root, PROJECT_FIELDS));
        for (raw in JsonFields.array(Reflect.field(root, "assets"), "project.assets")) {
            var data = JsonFields.object(raw, "project.assets[]");
            project.assets.push(new AssetRecord(
                JsonFields.stringField(data, "id", "asset"),
                JsonFields.stringField(data, "type", "asset"),
                JsonFields.stringField(data, "source", "asset"),
                Reflect.field(data, "importSettings"),
                JsonFields.extras(data, ASSET_FIELDS)));
        }
        ProjectValidator.validateProject(project);
        return project;
    }
}
