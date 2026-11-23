package boltspark.platform;

/** Opaque handle to a floating-panel HWND owned by tools/native/winfloat.c. */
typedef WinFloatHandle = hl.Abstract<"winfloat_panel">;
/** Opaque handle to the always-on-top drag-label overlay HWND. */
typedef WinFloatLabelHandle = hl.Abstract<"winfloat_label">;
/** Explorer drop latched by winfloat.c and drained on the next pump(). */
typedef WinFloatDrop = { paths:Array<String>, x:Int, y:Int };

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

    // Explorer file drops, latched by WM_DROPFILES in WndProc and delivered
    // only when Haxe calls takeDrops() after pump() has returned.
    @:hlNative("winfloat", "drop_count")
    static function dropCount(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "drop_path")
    static function dropPath(handle:WinFloatHandle, index:Int):hl.Bytes return null;

    @:hlNative("winfloat", "drop_x")
    static function dropX(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "drop_y")
    static function dropY(handle:WinFloatHandle):Int return 0;

    @:hlNative("winfloat", "clear_drops")
    static function clearDrops(handle:WinFloatHandle):Void {}

    /** Drain one latched drop, or null when nothing arrived. */
    public static function takeDrops(handle:WinFloatHandle):Null<WinFloatDrop> {
        var count = dropCount(handle);
        if (count <= 0) return null;
        var paths:Array<String> = [];
        for (index in 0...count) {
            var bytes = dropPath(handle, index);
            if (bytes == null) continue;
            paths.push(@:privateAccess String.fromUCS2(bytes));
        }
        var x = dropX(handle);
        var y = dropY(handle);
        clearDrops(handle);
        return { paths: paths, x: x, y: y };
    }

    /** Deterministic probe hook: fills the same latch a real drop would. */
    @:hlNative("winfloat", "inject_drop")
    public static function injectDrops(handle:WinFloatHandle,
            paths:hl.NativeArray<hl.Bytes>, x:Int, y:Int):Void {}

    /** Convert a Haxe string to the NUL-terminated UCS-2 bytes winfloat latches. */
    public static function toUcs2(text:String):hl.Bytes {
        var out = haxe.io.Bytes.alloc((text.length + 1) * 2);
        for (index in 0...text.length) {
            var code = text.charCodeAt(index);
            out.set(index * 2, code & 0xFF);
            out.set(index * 2 + 1, (code >> 8) & 0xFF);
        }
        return @:privateAccess out.b;
    }
}
