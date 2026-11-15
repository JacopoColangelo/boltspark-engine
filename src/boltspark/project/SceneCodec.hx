package boltspark.project;

class SceneCodec {
    static final SCENE_FIELDS = ["version", "id", "name", "entities"];
    static final ENTITY_FIELDS = ["id", "name", "parentId", "transform", "components"];
    static final COMPONENT_FIELDS = ["type", "version", "data"];

    public static function encode(scene:SceneDocument, pretty:Bool = true):String {
        ProjectValidator.validateScene(scene);
        var root = JsonFields.withExtras(scene.extraFields);
        Reflect.setField(root, "version", SceneDocument.SCHEMA_VERSION);
        Reflect.setField(root, "id", scene.id);
        Reflect.setField(root, "name", scene.name);
        var entities:Array<Dynamic> = [];
        for (entity in scene.entities) {
            var raw = JsonFields.withExtras(entity.extraFields);
            Reflect.setField(raw, "id", entity.id);
            Reflect.setField(raw, "name", entity.name);
            Reflect.setField(raw, "parentId", entity.parentId);
            Reflect.setField(raw, "transform", encodeTransform(entity.transform));
            var components:Array<Dynamic> = [];
            for (component in entity.components) {
                var componentRaw = JsonFields.withExtras(component.extraFields);
                Reflect.setField(componentRaw, "type", component.type);
                Reflect.setField(componentRaw, "version", component.version);
                Reflect.setField(componentRaw, "data", component.data);
                components.push(componentRaw);
            }
            Reflect.setField(raw, "components", components);
            entities.push(raw);
        }
        Reflect.setField(root, "entities", entities);
        return haxe.Json.stringify(root, null, pretty ? "  " : null);
    }

    public static function decode(contents:String):SceneDocument {
        var root:Dynamic;
        try {
            root = haxe.Json.parse(contents);
        } catch (error:Dynamic) {
            throw 'Scene JSON could not be parsed: ${Std.string(error)}';
        }
        JsonFields.object(root, "scene");
        var version = JsonFields.intField(root, "version", "scene");
        if (version != SceneDocument.SCHEMA_VERSION) {
            throw 'Unsupported scene schema version ${version}';
        }
        var scene = new SceneDocument(
            JsonFields.stringField(root, "id", "scene"),
            JsonFields.stringField(root, "name", "scene"), [],
            JsonFields.extras(root, SCENE_FIELDS));
        for (raw in JsonFields.array(Reflect.field(root, "entities"), "scene.entities")) {
            var data = JsonFields.object(raw, "scene.entities[]");
            var transform = decodeTransform(
                JsonFields.object(Reflect.field(data, "transform"), "entity.transform"));
            var entity = new SceneEntityData(
                JsonFields.stringField(data, "id", "entity"),
                JsonFields.stringField(data, "name", "entity"),
                JsonFields.nullableStringField(data, "parentId", "entity"),
                transform, [], JsonFields.extras(data, ENTITY_FIELDS));
            for (rawComponent in JsonFields.array(
                    Reflect.field(data, "components"), "entity.components")) {
                var component = JsonFields.object(rawComponent, "entity.components[]");
                entity.components.push(new ComponentData(
                    JsonFields.stringField(component, "type", "component"),
                    JsonFields.intField(component, "version", "component"),
                    Reflect.field(component, "data"),
                    JsonFields.extras(component, COMPONENT_FIELDS)));
            }
            scene.entities.push(entity);
        }
        ProjectValidator.validateScene(scene);
        return scene;
    }

    static function encodeTransform(value:TransformData):Dynamic {
        return {
            position: [value.positionX, value.positionY, value.positionZ],
            rotation: [value.rotationX, value.rotationY, value.rotationZ],
            scale: [value.scaleX, value.scaleY, value.scaleZ]
        };
    }

    static function decodeTransform(data:Dynamic):TransformData {
        var position = vector(Reflect.field(data, "position"), "transform.position");
        var rotation = vector(Reflect.field(data, "rotation"), "transform.rotation");
        var scale = vector(Reflect.field(data, "scale"), "transform.scale");
        return new TransformData(position[0], position[1], position[2],
            rotation[0], rotation[1], rotation[2], scale[0], scale[1], scale[2]);
    }

    static function vector(value:Dynamic, context:String):Array<Float> {
        var raw = JsonFields.array(value, context);
        if (raw.length != 3) throw '${context} must contain exactly three numbers';
        var result:Array<Float> = [];
        for (index in 0...3) {
            var holder:Dynamic = {value: raw[index]};
            result.push(JsonFields.numberField(holder, "value", '${context}[${index}]'));
        }
        return result;
    }
}
