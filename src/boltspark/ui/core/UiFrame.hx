package boltspark.ui.core;

import boltspark.ui.layout.LayoutRect;

/** Stable IDs, persistent state, and validation for one BoltUI frame. */
class UiFrame {
    public final input:UiInputState = new UiInputState();
    public final diagnostics:UiDiagnostics = new UiDiagnostics();

    final ids:UiIdStack = new UiIdStack();
    final seen:Map<String, Bool> = [];
    final persistent:Map<String, Dynamic> = [];
    var active:Bool = false;

    public var frameIndex(default, null):Int = 0;
    public var width(default, null):Float = 0;
    public var height(default, null):Float = 0;

    public function new() {}

    public function begin(width:Float, height:Float, root:String = "boltspark"):Void {
        var previousStillActive = active;
        diagnostics.reset();
        if (previousStillActive) diagnostics.report("begin() called before the previous frame ended");
        active = true;
        frameIndex++;
        this.width = width;
        this.height = height;
        ids.reset(root);
        seen.clear();
        if (!finite(width) || !finite(height) || width < 0 || height < 0) {
            diagnostics.report('invalid frame bounds ${width}x${height}');
        }
    }

    public function pushScope(name:String):Void {
        ensureActive("pushScope");
        ids.push(name);
    }

    public function popScope():Void {
        ensureActive("popScope");
        if (!ids.pop()) diagnostics.report("attempted to pop the root ID scope");
    }

    public function register(name:String, rect:LayoutRect):UiId {
        ensureActive("register");
        var id = ids.resolve(name);
        if (seen.exists(id.path)) diagnostics.report('duplicate widget ID: ${id.path}');
        seen.set(id.path, true);
        if (rect == null || !rect.isValid()) {
            diagnostics.report('invalid layout for widget ${id.path}');
        }
        return id;
    }

    public function state<T>(id:UiId, create:Void->T):T {
        if (!persistent.exists(id.path)) persistent.set(id.path, create());
        return cast persistent.get(id.path);
    }

    public function setState<T>(id:UiId, value:T):Void persistent.set(id.path, value);

    public function end():Array<String> {
        ensureActive("end");
        if (ids.depth != 0) diagnostics.report('unbalanced ID scopes: ${ids.depth} still open');
        active = false;
        input.advanceFrame();
        return diagnostics.all();
    }

    function ensureActive(operation:String):Void {
        if (!active) diagnostics.report('${operation}() called outside begin()/end()');
    }

    static inline function finite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY
            && value != Math.NEGATIVE_INFINITY;
    }
}
