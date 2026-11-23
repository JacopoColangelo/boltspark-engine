package boltspark.runtime;

import boltspark.editor.EditorObject;
import boltspark.editor.EditorSession;
import boltspark.project.SceneDocument;
import boltspark.project.SceneSerializer;

/**
 * Detached, renderer-independent scene copy used by Play mode.
 *
 * Play captures the authored editor graph as a `SceneDocument`, then rebuilds a
 * *separate* session instance from that snapshot. Component `onStart/onUpdate`
 * and any component-driven transform changes therefore happen only on the
 * copy: the editor session, its selection, and its undo history are never
 * touched. Stop destroys the copy, so every Play starts from the authored
 * state again.
 *
 * The session type is deliberately shared with the editor because it already
 * owns the authoritative hierarchy and component container. Runtime code uses
 * none of its editor-only history or selection APIs.
 */
class PlayModeSession {
    /** Fresh session rebuilt from the snapshot; never the editor session. */
    public var session(default, null):EditorSession;
    /** Authored scene state captured when Play was pressed. */
    public var snapshot(default, null):SceneDocument;
    /** True once the first running frame has dispatched component start. */
    public var started(default, null):Bool = false;
    public var paused(default, null):Bool = false;
    public var stopped(default, null):Bool = false;
    /** Accumulated running time; paused frames do not advance it. */
    public var elapsed(default, null):Float = 0;

    public function new(snapshot:SceneDocument) {
        if (snapshot == null) throw "Play mode requires a scene snapshot";
        this.snapshot = snapshot;
        session = SceneSerializer.toSession(snapshot);
    }

    public inline function objects():Array<EditorObject> return session.objects;

    public inline function findObject(id:Int):Null<EditorObject> {
        return session.findObject(id);
    }

    /** Tick component lifecycle once per running frame. */
    public function update(dt:Float):Void {
        if (stopped || paused) return;
        started = true;
        elapsed += dt;
        session.update(dt);
    }

    public function setPaused(value:Bool):Void {
        if (stopped) return;
        paused = value;
    }

    public function togglePaused():Bool {
        setPaused(!paused);
        return paused;
    }

    /** Destroy the detached copy. The editor session is never modified. */
    public function destroy():Void {
        if (stopped) return;
        stopped = true;
        session.destroy();
    }
}
