package boltspark.project;

import boltspark.editor.EditorObject;
import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.engine.ComponentRegistry;
import boltspark.engine.Transform;

/** Maps the authoritative editor scene graph to/from durable scene documents. */
class SceneSerializer {
    public static function fromSession(session:EditorSession, sceneId:String,
            name:String):SceneDocument {
        if (session == null) throw "Cannot serialize a null editor session";
        var document = new SceneDocument(
            StableId.require(sceneId, "scene.id"), name);
        for (object in session.hierarchy.flatten()) {
            var transform = object.transform.value;
            var data = new TransformData(
                transform.positionX, transform.positionY, transform.positionZ,
                transform.rotationHintValid ? transform.rotationHintX : 0,
                transform.rotationHintValid ? transform.rotationHintY : 0,
                transform.rotationHintValid ? transform.rotationHintZ : 0,
                transform.scaleX, transform.scaleY, transform.scaleZ,
                 transform.rotationX, transform.rotationY,
                 transform.rotationZ, transform.rotationW, true,
                 transform.shearXY, transform.shearXZ, transform.shearYZ,
                 transform.rotationHintValid);
            var components:Array<ComponentData> = [];
            for (component in object.components) {
                if (Std.isOfType(component, Transform)) continue;
                var serialized = ComponentRegistry.serialize(component);
                if (serialized != null) components.push(serialized);
            }
            var extras:Dynamic = {};
            if (!object.visible) Reflect.setField(extras, "visible", false);
            if (!object.enabled) Reflect.setField(extras, "enabled", false);
            document.entities.push(new SceneEntityData(object.persistentId,
                object.name,
                object.parent == null ? null : object.parent.persistentId,
                data, components, extras));
        }
        ProjectValidator.validateScene(document);
        return document;
    }

    /** Validate and reconstruct objects first, then parent them in a safe pass. */
    public static function toSession(document:SceneDocument,
            historyCapacity:Int = 256):EditorSession {
        ProjectValidator.validateScene(document);
        var session = new EditorSession(historyCapacity);
        var entityToObject:Map<String, EditorObject> = [];
        for (entity in document.entities) {
            var components = [for (component in entity.components)
                ComponentRegistry.deserialize(component)];
            var storedVisible = Reflect.field(entity.extraFields, "visible");
            var storedEnabled = Reflect.field(entity.extraFields, "enabled");
            var object = session.addInitialObject(entity.name,
                toEditorTransform(entity.transform), entity.id,
                components, -1, -1,
                storedVisible == null ? true : storedVisible,
                storedEnabled == null ? true : storedEnabled);
            entityToObject.set(entity.id, object);
        }

        var siblingCounts:Map<String, Int> = [];
        for (entity in document.entities) {
            var object = entityToObject.get(entity.id);
            var parent = entity.parentId == null
                ? null : entityToObject.get(entity.parentId);
            var key = entity.parentId == null ? "<root>" : entity.parentId;
            var siblingIndex = siblingCounts.exists(key)
                ? siblingCounts.get(key) : 0;
            siblingCounts.set(key, siblingIndex + 1);
            session.hierarchy.attach(object, parent, siblingIndex);
        }
        session.hierarchy.validate();
        session.clearHistory();
        return session;
    }

    /** Duplicate a complete scene while remapping every hierarchy identity. */
    public static function duplicate(document:SceneDocument,
            ?name:String):SceneDocument {
        ProjectValidator.validateScene(document);
        // Codec round-trip provides a safe deep copy of components/extras.
        var copy = SceneCodec.decode(SceneCodec.encode(document, false));
        copy.id = StableId.create("scene");
        copy.name = name == null ? document.name + " Copy" : name;
        var remap:Map<String, String> = [];
        for (entity in copy.entities) {
            remap.set(entity.id, StableId.create("scene-object"));
        }
        for (entity in copy.entities) {
            var previousId = entity.id;
            entity.id = remap.get(previousId);
            if (entity.parentId != null) entity.parentId = remap.get(entity.parentId);
        }
        ProjectValidator.validateScene(copy);
        return copy;
    }

    static function toEditorTransform(data:TransformData):EditorTransform {
        var result = data.quaternionValid
            ? new EditorTransform(0, 0, 0,
                data.quaternionX, data.quaternionY,
                 data.quaternionZ, data.quaternionW,
                 data.rotationX, data.rotationY, data.rotationZ,
                 data.rotationHintValid)
             : EditorTransform.fromEditorEulerDegrees(
                 data.rotationX, data.rotationY, data.rotationZ);
        if (!data.rotationHintValid) result.rotationHintValid = false;
        result.positionX = data.positionX;
        result.positionY = data.positionY;
        result.positionZ = data.positionZ;
        result.scaleX = data.scaleX;
        result.scaleY = data.scaleY;
        result.scaleZ = data.scaleZ;
        result.shearXY = data.shearXY;
        result.shearXZ = data.shearXZ;
        result.shearYZ = data.shearYZ;
        return result;
    }
}
