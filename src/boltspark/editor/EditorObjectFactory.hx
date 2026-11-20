package boltspark.editor;

import boltspark.engine.Component;
import boltspark.engine.MeshRenderer;

/**
 * Single construction path for editor scene objects. Anything carrying a
 * MeshRenderer becomes an EditorMesh3D so the engine's object type stays
 * consistent across creation, undo/redo, duplication, and scene loading.
 */
class EditorObjectFactory {
    public static function create(id:Int, persistentId:String, name:String,
            transform:EditorTransform, ?components:Array<Component>,
            ?scene:EditorSession, visible:Bool = true,
            enabled:Bool = true):EditorObject {
        var list = components == null ? [] : components;
        var rendersMesh = false;
        for (component in list) {
            if (Std.isOfType(component, MeshRenderer)) {
                rendersMesh = true;
                break;
            }
        }
        if (rendersMesh) {
            return new EditorMesh3D(id, persistentId, name, transform, list,
                scene, visible, enabled);
        }
        return new EditorObject(id, persistentId, name, transform, list,
            scene, visible, enabled);
    }
}
