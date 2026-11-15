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
        var result:Dynamic = {
            position: [value.positionX, value.positionY, value.positionZ],
            rotation: [value.rotationX, value.rotationY, value.rotationZ],
            scale: [value.scaleX, value.scaleY, value.scaleZ]
        };
        // These additive schema-1 fields keep exact affine state while old
        // readers can continue consuming Position/Rotator/Scale.
        if (value.quaternionValid) {
            Reflect.setField(result, "quaternion", [value.quaternionX,
                value.quaternionY, value.quaternionZ, value.quaternionW]);
        }
        if (value.shearXY != 0 || value.shearXZ != 0 || value.shearYZ != 0) {
            Reflect.setField(result, "shear",
                [value.shearXY, value.shearXZ, value.shearYZ]);
        }
        // Legacy transforms always treated Rotation as a valid hint. Only the
        // false case needs an additive marker to preserve exact editor state.
        if (!value.rotationHintValid) {
            Reflect.setField(result, "rotationHintValid", false);
        }
        return result;
    }

    static function decodeTransform(data:Dynamic):TransformData {
        var position = vector(Reflect.field(data, "position"), "transform.position");
        var rotation = vector(Reflect.field(data, "rotation"), "transform.rotation");
        var scale = vector(Reflect.field(data, "scale"), "transform.scale");
        var quaternion = Reflect.hasField(data, "quaternion")
            ? vectorLength(Reflect.field(data, "quaternion"),
                "transform.quaternion", 4)
            : [0.0, 0.0, 0.0, 1.0];
        var shear = Reflect.hasField(data, "shear")
            ? vectorLength(Reflect.field(data, "shear"), "transform.shear", 3)
            : [0.0, 0.0, 0.0];
        var rotationHintValid = true;
        if (Reflect.hasField(data, "rotationHintValid")) {
            var rawHintValid = Reflect.field(data, "rotationHintValid");
            if (!Std.isOfType(rawHintValid, Bool)) {
                throw "transform.rotationHintValid must be a boolean";
            }
            rotationHintValid = rawHintValid;
        }
        return new TransformData(position[0], position[1], position[2],
            rotation[0], rotation[1], rotation[2], scale[0], scale[1], scale[2],
            quaternion[0], quaternion[1], quaternion[2], quaternion[3],
            Reflect.hasField(data, "quaternion"),
            shear[0], shear[1], shear[2], rotationHintValid);
    }

    static function vector(value:Dynamic, context:String):Array<Float> {
        return vectorLength(value, context, 3);
    }

    static function vectorLength(value:Dynamic, context:String,
            length:Int):Array<Float> {
        var raw = JsonFields.array(value, context);
        if (raw.length != length) {
            throw '${context} must contain exactly ${length} numbers';
        }
        var result:Array<Float> = [];
        for (index in 0...length) {
            var holder:Dynamic = {value: raw[index]};
            result.push(JsonFields.numberField(holder, "value", '${context}[${index}]'));
        }
        return result;
    }
}
