package boltspark.ui.core;

/**
 * Backend-independent input snapshot shared by retained and immediate widgets.
 * Event adapters write it; a frame boundary clears only transient values.
 */
class UiInputState {
    public var pointerX(default, null):Float = 0;
    public var pointerY(default, null):Float = 0;
    public var pointerDown(default, null):Bool = false;
    public var pointerPressed(default, null):Bool = false;
    public var pointerReleased(default, null):Bool = false;
    public var wheelDelta(default, null):Float = 0;
    public var focused(default, null):Bool = true;
    public var orphanKeyUps(default, null):Int = 0;

    final keysDown:Map<Int, Bool> = [];

    public function new() {}

    public function movePointer(x:Float, y:Float):Void {
        pointerX = x;
        pointerY = y;
    }

    public function pressPointer(x:Float, y:Float):Void {
        movePointer(x, y);
        if (!pointerDown) pointerPressed = true;
        pointerDown = true;
    }

    public function releasePointer(x:Float, y:Float):Void {
        movePointer(x, y);
        if (pointerDown) pointerReleased = true;
        pointerDown = false;
    }

    public function addWheel(delta:Float):Void wheelDelta += delta;

    /** Returns true only for the first down event for this physical key. */
    public function keyDown(keyCode:Int):Bool {
        if (keysDown.exists(keyCode)) return false;
        keysDown.set(keyCode, true);
        return true;
    }

    /** Returns false for an unmatched key-up and records it for diagnostics. */
    public function keyUp(keyCode:Int):Bool {
        if (!keysDown.exists(keyCode)) {
            orphanKeyUps++;
            return false;
        }
        keysDown.remove(keyCode);
        return true;
    }

    public inline function isKeyDown(keyCode:Int):Bool return keysDown.exists(keyCode);

    public function focusLost():Void {
        focused = false;
        keysDown.clear();
        pointerDown = false;
    }

    public function focusGained():Void focused = true;

    /** Clear one-frame edges after widgets have consumed the snapshot. */
    public function advanceFrame():Void {
        pointerPressed = false;
        pointerReleased = false;
        wheelDelta = 0;
    }
}
