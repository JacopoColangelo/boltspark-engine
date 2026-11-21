import boltspark.editor.EditorSession;
import boltspark.engine.Component;
import boltspark.engine.ComponentRegistry;
import boltspark.engine.GameObject;
import boltspark.engine.Mesh3D;
import boltspark.engine.MeshRenderer;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.engine.inspector.ComponentPropertyKind;
import boltspark.engine.Transform;
import boltspark.project.ComponentData;
import boltspark.project.SceneSerializer;
import boltspark.project.StableId;

/** Headless GameObject/component ownership, lifecycle, history, and data test. */
class ComponentSystemRepro {
    static function main():Void {
        testGenericGameObjectApi();
        testPrimitiveComposition();
        testEditorHistoryAndSerialization();
        testRemoveComponentHistory();
        Sys.println("[component-system] ownership, lifecycle, primitives, history, and serialization passed");
    }

    static function testGenericGameObjectApi():Void {
        var object = new GameObject();
        assertTrue(object.name == "GameObject", "default GameObject name changed");
        assertTrue(object.components.length == 1
                && object.components[0] == object.transform
                && object.getComponent(Transform) == object.transform,
            "mandatory Transform was not installed first");
        assertTrue(object.transform.positionX == 0
                && object.transform.positionY == 0
                && object.transform.positionZ == 0,
            "empty GameObject Transform is not at the true origin");

        var first = object.addComponent(new LifecycleProbe());
        var second = object.addComponentType(LifecycleProbe);
        assertTrue(first.gameObject == object && first.transform == object.transform,
            "component ownership/Transform access was not assigned");
        assertTrue(object.getComponent(LifecycleProbe) == first
                && object.getComponents(LifecycleProbe).length == 2,
            "typed component lookup failed");

        object.update(0.25);
        assertTrue(first.starts == 1 && first.updates == 1,
            "component start/update lifecycle did not run");
        var late = object.addComponent(new LifecycleProbe());
        assertTrue(late.starts == 1,
            "component added to a started GameObject did not start immediately");
        object.update(0.25);
        assertTrue(first.updates == 2 && late.updates == 1,
            "component update lifecycle count changed");

        assertTrue(object.removeComponentInstance(first)
                && first.destroyed && first.destroys == 1
                && first.gameObject == null,
            "component removal did not clean up ownership exactly once");
        assertTrue(object.removeComponent(LifecycleProbe)
                && second.destroyed,
            "removeComponent(type) did not remove the first matching component");

        assertThrows(function() object.removeComponent(Transform),
            "mandatory Transform could be removed");
        var transform = object.transform;
        object.destroy();
        assertTrue(object.destroyed && late.destroyed && transform.destroyed,
            "GameObject destruction did not destroy every attached component");
    }

    static function testPrimitiveComposition():Void {
        var cube = PrimitiveGameObjects.createCube();
        var renderer = cube.getComponent(MeshRenderer);
        assertTrue(Std.isOfType(cube, Mesh3D) && Mesh3D.is(cube)
                && cube.objectType == Mesh3D.TYPE,
            "cube factory did not return a Mesh3D");
        assertTrue(cube.components.length == 2
                && cube.components[0] == cube.transform
                && renderer != null,
            "cube is not composed from Transform + MeshRenderer");
        assertTrue(renderer.mesh != null
                && renderer.mesh.name == "Cube"
                && renderer.material.name == "White Material",
            "cube primitive mesh/default material assignment changed");
        var transformInspector = cube.transform.inspectorData(0);
        var rendererInspector = renderer.inspectorData(1);
        assertTrue(transformInspector.title == "Transform"
                && transformInspector.properties.length == 3
                && rendererInspector.title == "MeshRenderer"
                && rendererInspector.properties.length == 5
                && rendererInspector.properties[0].textValue == "Cube"
                && rendererInspector.properties[1].textValue == "White Material",
            "component-owned Inspector property definitions changed");
        // Cube geometry parameters follow the two asset rows.
        for (index in 2...5) {
            var geometry = rendererInspector.properties[index];
            assertTrue(geometry.kind == ComponentPropertyKind.Number,
                "cube geometry rows must be number properties");
        }
    }

    static function testEditorHistoryAndSerialization():Void {
        var session = new EditorSession(32);
        var object = session.addInitialObject("Empty");
        assertTrue(object.getComponent(MeshRenderer) == null,
            "empty editor GameObject unexpectedly has renderer behavior");
        assertTrue(session.addComponent(object.id,
            PrimitiveGameObjects.createCubeRenderer()),
            "Add Component command was rejected");
        assertTrue(object.getComponent(MeshRenderer) != null
                && session.history.undoLabel == "Add MeshRenderer",
            "Add Component did not enter history");
        assertTrue(session.undo() && object.getComponent(MeshRenderer) == null,
            "Add Component undo failed");
        assertTrue(session.redo() && object.getComponent(MeshRenderer) != null,
            "Add Component redo failed");

        var duplicate = session.duplicateObjects([object.id])[0];
        assertTrue(duplicate.getComponent(MeshRenderer) != null
                && duplicate.getComponent(MeshRenderer)
                    != object.getComponent(MeshRenderer),
            "duplicate did not clone attached components");

        var unknownData = new ComponentData("futureGameplay", 7,
            {answer: 42}, {futureEnvelope: "preserve"});
        var unknown = ComponentRegistry.deserialize(unknownData);
        var unknownObject = session.addInitialObject("Forward Compatible",
            null, null, [unknown]);
        var document = SceneSerializer.fromSession(session,
            StableId.create("component-scene"), "Component Test");
        var loaded = SceneSerializer.toSession(document);
        var loadedObject = loaded.findObjectByPersistentId(object.persistentId);
        var loadedUnknown = loaded.findObjectByPersistentId(
            unknownObject.persistentId);
        assertTrue(loadedObject != null
                && loadedObject.getComponent(MeshRenderer) != null,
            "MeshRenderer did not survive scene serialization");
        assertTrue(loadedUnknown != null && loadedUnknown.components.length == 2,
            "unknown component was not retained on load");
        var serializedAgain = SceneSerializer.fromSession(loaded,
            StableId.create("component-scene-copy"), "Component Test Copy");
        var foundUnknown = false;
        for (entity in serializedAgain.entities) {
            if (entity.id != unknownObject.persistentId) continue;
            for (component in entity.components) {
                if (component.type == "futureGameplay"
                        && Reflect.field(component.data, "answer") == 42
                        && Reflect.field(component.extraFields,
                            "futureEnvelope") == "preserve") {
                    foundUnknown = true;
                }
            }
        }
        assertTrue(foundUnknown,
            "unknown component payload/envelope fields were not preserved");
    }

    static function testRemoveComponentHistory():Void {
        var session = new EditorSession(33);
        var object = session.addInitialObject("Removable");
        var renderer = PrimitiveGameObjects.createCubeRenderer();
        assertTrue(session.addComponent(object.id, renderer),
            "Add Component command was rejected");
        var attached = object.getComponent(MeshRenderer);
        var index = object.components.indexOf(attached);
        assertTrue(index == 1, "added component was not placed after Transform");

        assertTrue(!session.removeComponentAt(object.id, 0),
            "mandatory Transform was removed through EditorSession");
        assertTrue(session.removeComponentAt(object.id, index)
                && object.getComponent(MeshRenderer) == null
                && attached.destroyed
                && session.history.undoLabel == "Remove MeshRenderer",
            "Remove Component did not enter history or destroy the component");
        assertTrue(session.undo() && object.getComponent(MeshRenderer) != null,
            "Remove Component undo failed");
        assertTrue(session.redo() && object.getComponent(MeshRenderer) == null,
            "Remove Component redo failed");
        assertTrue(!session.removeComponentAt(object.id, 99),
            "out-of-range component index was accepted");
    }

    static function assertThrows(action:Void->Void, message:String):Void {
        try action() catch (_:Dynamic) return;
        throw message;
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}

private class LifecycleProbe extends Component {
    public var starts:Int = 0;
    public var updates:Int = 0;
    public var destroys:Int = 0;

    public function new() super();
    override function get_typeId():String return "lifecycleProbe";
    override function get_displayName():String return "Lifecycle Probe";
    override public function onStart():Void starts++;
    override public function onUpdate(dt:Float):Void updates++;
    override public function onDestroy():Void destroys++;
    override public function cloneComponent():Component return new LifecycleProbe();
}
