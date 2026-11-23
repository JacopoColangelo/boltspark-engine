package boltspark.platform;

/** Opaque handle to a floating-panel HWND owned by tools/native/winfloat.c. */
typedef WinFloatHandle = hl.Abstract<"winfloat_panel">;
/** Opaque handle to the always-on-top drag-label overlay HWND. */
typedef WinFloatLabelHandle = hl.Abstract<"winfloat_label">;

/**
 * Thin Haxe binding for the raw-Win32 floating panel module. The module is
 * loaded by HashLink from `bin/winfloat.hdll` in bytecode builds and linked in
 * statically for the HLC release (the generated import library is installed by
 * tools/build.ps1 next to the other HashLink native libraries).
 */
class NativeFloatWindow {
    /** Event kinds delivered to the callback registered by `create`. */
    public static inline var EVENT_CLOSE:Int = 0;
    public static inline var EVENT_DESTROY:Int = 1;
    public static inline var EVENT_RESIZE:Int = 2;
    public static inline var EVENT_MOUSEMOVE:Int = 3;
    public static inline var EVENT_LBUTTONDOWN:Int = 4;
    public static inline var EVENT_LBUTTONUP:Int = 5;
    public static inline var EVENT_WHEEL:Int = 6;
    public static inline var EVENT_PAINT:Int = 7;
    public static inline var EVENT_KEYDOWN:Int = 8;
    public static inline var EVENT_KEYUP:Int = 9;
    public static inline var EVENT_CHAR:Int = 10;
    public static inline var EVENT_RBUTTONDOWN:Int = 11;
    public static inline var EVENT_RBUTTONUP:Int = 12;
    /** OS stole focus/capture (Alt+Tab, Windows key, screenshot overlay). */
    public static inline var EVENT_FOCUS_LOST:Int = 13;
    /** Focus returned after any interrupted gesture has been cancelled. */
    public static inline var EVENT_FOCUS_GAINED:Int = 14;

    @:hlNative("winfloat", "create")
    public static function create(title:hl.Bytes, x:Int, y:Int, width:Int,
            height:Int, cb:Int->Int->Int->Int->Void):WinFloatHandle return null;

    /** Pump only this HWND's queue; never steals the editor's messages. */
    @:hlNative("winfloat", "pump")
    public static function pump(handle:WinFloatHandle):Void {}

    /** Blit a top-down 32-bit BGRA buffer into the client area. */
    @:hlNative("winfloat", "paint")
    public static function paint(handle:WinFloatHandle, pixels:hl.Bytes,
            width:Int, height:Int):Void {}

    @:hlNative("winfloat", "set_geometry")
    public static function setGeometry(handle:WinFloatHandle, x:Int, y:Int,
            width:Int, height:Int):Void {}

    @:hlNative("winfloat", "client_width")
    public static function clientWidth(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "client_height")
    public static function clientHeight(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "get_dpi")
    public static function getDpi(handle:WinFloatHandle):Int return 96;

    @:hlNative("winfloat", "set_title")
    public static function setTitle(handle:WinFloatHandle, title:hl.Bytes):Void {}

    /** Destroy the HWND and release the native panel. Call after pump() drains. */
    /** Client header height and the x where its buttons start (for HTCAPTION). */
    @:hlNative("winfloat", "set_header_height")
    public static function setHeaderHeight(handle:WinFloatHandle, height:Int,
            buttonsX:Int):Void {}

    @:hlNative("winfloat", "minimize")
    public static function minimize(handle:WinFloatHandle):Void {}

    @:hlNative("winfloat", "cursor_x")
    public static function cursorX():Int return 0;

    @:hlNative("winfloat", "cursor_y")
    public static function cursorY():Int return 0;

    @:hlNative("winfloat", "window_x")
    public static function windowX(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "window_y")
    public static function windowY(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "move_window")
    public static function moveWindow(handle:WinFloatHandle, x:Int, y:Int):Void {}

    @:hlNative("winfloat", "set_capture")
    public static function setCapture(handle:WinFloatHandle):Void {}

    @:hlNative("winfloat", "release_capture")
    public static function releaseCapture():Void {}

    /** Preserve the cursor chosen by the float's H2D scene across native
     *  resize-edge hit tests. */
    @:hlNative("winfloat", "remember_client_cursor")
    public static function rememberClientCursor(handle:WinFloatHandle):Void {}

    @:hlNative("winfloat", "destroy")
    public static function destroy(handle:WinFloatHandle):Void {}
}
