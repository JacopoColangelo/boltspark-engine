package boltspark.editor;

import boltspark.engine.Component;
import boltspark.engine.Mesh3D;
import boltspark.engine.MeshRenderer;

/**
 * Editor-side projection of the engine's Mesh3D object type. It is created for
 * any scene object that owns a MeshRenderer, so primitives created from the
 * Add palette, the asset browser, or scene loading all share one type identity.
 */
class EditorMesh3D extends EditorObject {
    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform, ?components:Array<Component>,
            ?scene:EditorSession, visible:Bool = true, enabled:Bool = true) {
        super(id, persistentId, name, transform, components, scene, visible, enabled);
    }

    override function get_objectType():String return Mesh3D.TYPE;

    public inline function renderer():Null<MeshRenderer> {
        return getComponent(MeshRenderer);
    }
}
