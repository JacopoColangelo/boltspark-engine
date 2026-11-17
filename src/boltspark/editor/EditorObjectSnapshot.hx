package boltspark.editor;

import boltspark.engine.Component;
import boltspark.engine.Transform;

/** Immutable-by-convention command snapshot of one component-based object. */
class EditorObjectSnapshot {
    public final id:Int;
    public final persistentId:String;
    public final name:String;
    public final transform:EditorTransform;
    public final components:Array<Component>;
    public final parentPersistentId:Null<String>;
    public final siblingIndex:Int;
    public final visible:Bool;
    public final enabled:Bool;

    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform, ?components:Array<Component>,
            ?parentPersistentId:String, siblingIndex:Int = 0,
            visible:Bool = true, enabled:Bool = true) {
        this.id = id;
        this.persistentId = persistentId;
        this.name = name;
        this.transform = transform.clone();
        this.components = cloneComponents(components);
        this.parentPersistentId = parentPersistentId;
        this.siblingIndex = siblingIndex;
        this.visible = visible;
        this.enabled = enabled;
    }

    public static function capture(object:EditorObject):EditorObjectSnapshot {
        return new EditorObjectSnapshot(object.id, object.persistentId,
            object.name, object.transform.value, nonTransformComponents(object),
            object.parent == null ? null : object.parent.persistentId,
            object.siblingIndex, object.visible, object.enabled);
    }

    public function restore(?scene:EditorSession):EditorObject {
        return new EditorObject(id, persistentId, name, transform,
            cloneComponents(components), scene, visible, enabled);
    }

    public static function nonTransformComponents(
            object:EditorObject):Array<Component> {
        return [for (component in object.components)
            if (!Std.isOfType(component, Transform)) component];
    }

    static function cloneComponents(source:Null<Array<Component>>):Array<Component> {
        if (source == null) return [];
        return [for (component in source) component.cloneComponent()];
    }
}
