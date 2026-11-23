import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.engine.Component;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.project.SceneSerializer;
import boltspark.project.StableId;
import boltspark.runtime.PlayModeSession;

/**
 * Play mode runs a serialized, detached scene copy. Runtime lifecycle and
 * transform changes must never reach the authored editor session or its
 * history, and Stop must be able to discard the copy cleanly.
 */
class PlayModeRepro {
    static function main():Void {
        isolationAndLifecycle();
        pauseAndReplay();
        Sys.println("[play-mode] snapshot isolation, lifecycle, pause, and replay passed");
    }

    static function isolationAndLifecycle():Void {
        var editor = new EditorSession();
        var parent = editor.addInitialObject("Parent", new EditorTransform(1, 2, 3),
            StableId.create("scene-object"), []);
        var child = editor.addInitialObject("Child", new EditorTransform(4, 5, 6),
            StableId.create("scene-object"),
            PrimitiveGameObjects.cubeComponents(), parent.id);
        editor.selectObject(child.id);
        var editorRevision = editor.history.revision;
        var editorSelection = editor.selectedObjectId;

        var snapshot = SceneSerializer.fromSession(editor,
            StableId.create("scene"), "Test Scene");
        var runtime = new PlayModeSession(snapshot);
        assertTrue(runtime.objects().length == 2, "runtime object count");
        assertTrue(runtime.findObject(parent.id) != parent,
            "runtime must own fresh object instances");
        var runtimeParent = runtime.findObject(parent.id);
        var runtimeChild = runtime.findObject(child.id);
        assertTrue(runtimeParent != null && runtimeChild != null,
            "runtime mirrors authored runtime ids");
        assertTrue(runtimeParent.persistentId == parent.persistentId
                && runtimeChild.persistentId == child.persistentId,
            "durable ids are preserved");
        assertTrue(runtimeChild.parent == runtimeParent, "hierarchy is preserved");
        assertTrue(runtimeParent.transform.value.sameAs(parent.transform.value)
                && runtimeChild.transform.value.sameAs(child.transform.value),
            "authored transforms are preserved");

        var probe = new TickCounter();
        runtimeChild.addComponent(probe);
        runtime.update(0.016);
        runtime.update(0.016);
        assertTrue(probe.starts == 1 && probe.updates == 2,
            "component start and update ran on the runtime copy");
        assertTrue(editor.history.revision == editorRevision
                && editor.selectedObjectId == editorSelection,
            "runtime must not touch editor history or selection");

        runtimeChild.transform.positionX = 99;
        assertTrue(child.transform.positionX != 99,
            "runtime transform mutation leaked into editor state");

        runtime.destroy();
        assertTrue(probe.destroys == 1, "component destroy ran on stop");
        assertTrue(runtime.stopped, "runtime is marked stopped");
        assertTrue(editor.findObject(child.id).transform.positionX != 99,
            "editor scene still holds the authored transform after stop");
        editor.destroy();
    }

    static function pauseAndReplay():Void {
        var editor = new EditorSession();
        var object = editor.addInitialObject("Cube", new EditorTransform(),
            StableId.create("scene-object"), PrimitiveGameObjects.cubeComponents());
        var snapshot = SceneSerializer.fromSession(editor,
            StableId.create("scene"), "Test Scene");

        var first = new PlayModeSession(snapshot);
        var probe = new TickCounter();
        first.findObject(object.id).addComponent(probe);
        first.update(0.5);
        assertTrue(probe.updates == 1, "first runtime tick");
        first.setPaused(true);
        first.update(0.5);
        assertTrue(probe.updates == 1 && first.elapsed == 0.5,
            "paused runtime must not tick or advance time");
        first.togglePaused();
        first.update(0.25);
        assertTrue(!first.paused && probe.updates == 2, "resume ticks again");
        first.destroy();

        // A fresh session is rebuilt from the same authored snapshot, so no
        // runtime state from the previous run can leak into the next Play.
        var second = new PlayModeSession(snapshot);
        var replayProbe = new TickCounter();
        second.findObject(object.id).addComponent(replayProbe);
        second.update(0.1);
        assertTrue(replayProbe.starts == 1 && replayProbe.updates == 1,
            "replay starts fresh components");
        assertTrue(second.findObject(object.id).transform.positionX == 0,
            "replay restores the authored transform");
        second.destroy();
        editor.destroy();
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}

private class TickCounter extends Component {
    public var starts:Int = 0;
    public var updates:Int = 0;
    public var destroys:Int = 0;

    public function new() super();
    override public function onStart():Void starts++;
    override public function onUpdate(dt:Float):Void updates++;
    override public function onDestroy():Void destroys++;
    override public function cloneComponent():Component return new TickCounter();
}
