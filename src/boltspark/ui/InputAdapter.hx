package boltspark.ui;

/**
 * Central input adapter (Gate 3).
 *
 * One scene-level listener records keyboard, focus, and pointer state so the
 * editor shell can surface input diagnostics in the status bar. Widgets stay
 * responsible for their own behavior; this adapter only *reports*.
 */
class InputAdapter {
    public var lastKey(default, null):String = "-";
    public var keyDownCount(default, null):Int = 0;
    public var keyUpCount(default, null):Int = 0;
    public var pointerMoves(default, null):Int = 0;
    public var focusLostCount(default, null):Int = 0;
    public var focusGotCount(default, null):Int = 0;
    public var pointerInsideWindow(default, null):Bool = true;

    final scene:h2d.Scene;
    var report:h2d.Text;

    public function new(scene:h2d.Scene) {
        this.scene = scene;
        scene.addEventListener(onSceneEvent);
    }

    /** Optional status text updated as events arrive. */
    public function bindReport(target:h2d.Text):Void {
        report = target;
        refresh();
    }

    /** Compact status line for the editor status bar. */
    public function statusLine():String {
        return 'key ${lastKey} | d${keyDownCount} u${keyUpCount} mv${pointerMoves} '
            + 'focus ${focusGotCount}/${focusLostCount}';
    }

    function onSceneEvent(event:hxd.Event):Void {
        switch (event.kind) {
            case EKeyDown:
                keyDownCount++;
                lastKey = hxd.Key.getKeyName(event.keyCode);
                refresh();
            case EKeyUp:
                keyUpCount++;
                refresh();
            case EMove:
                pointerMoves++;
                pointerInsideWindow = true;
            case EFocusLost:
                focusLostCount++;
                refresh();
            case EFocus:
                focusGotCount++;
                refresh();
            case EOut:
                pointerInsideWindow = false;
            case _:
        }
    }

    function refresh():Void {
        if (report != null) report.text = statusLine();
    }
}
