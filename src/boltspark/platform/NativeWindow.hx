package boltspark.platform;

#if hldx
private typedef DxWindowHandle = hl.Abstract<"dx_window">;
#end

/** Small Win32 behaviors missing from the locked hldx window wrapper. */
class NativeWindow {
    #if hl
    @:hlNative("std", "sys_getpid")
    static function getProcessId():Int {
        return 0;
    }
    #end

    #if hldx
    @:hlNative("directx", "win_set_owner_process")
    static function setOwnerProcessHandle(window:DxWindowHandle, processId:Int):Bool {
        return false;
    }

    @:hlNative("directx", "win_activate")
    static function activateHandle(window:DxWindowHandle):Bool {
        return false;
    }

    static inline function handle(window:hxd.Window):DxWindowHandle {
        return @:privateAccess window.window.win;
    }
    #end

    /** Keep an auxiliary top-level HWND above the editor that launched it. */
    public static function setOwnerProcess(window:hxd.Window, processId:Int):Bool {
        #if hldx
        return processId > 0 && setOwnerProcessHandle(handle(window), processId);
        #else
        return false;
        #end
    }

    public static function currentProcessId():Int {
        #if hl
        return getProcessId();
        #else
        return 0;
        #end
    }

    /** Screen-space origin of a window, for converting client rects to HWND coords. */
    public static function screenOrigin(window:hxd.Window):{x:Float, y:Float} {
        #if hldx
        @:privateAccess return {x: window.window.x, y: window.window.y};
        #else
        return {x: 0, y: 0};
        #end
    }

    #if hldx
    @:hlNative("winfloat", "client_origin_x")
    static function clientOriginXHandle(window:DxWindowHandle):Int return 0;

    @:hlNative("winfloat", "client_origin_y")
    static function clientOriginYHandle(window:DxWindowHandle):Int return 0;
    #end

    /**
     * Screen-space origin of the window's *client area*. hldx's Window.x/y are
     * the HWND rect origin, which sits above/left of the client area by the
     * title bar and border. UI and drag coordinates are client-space, so this
     * is the origin that must be used when translating between windows.
     */
    public static function clientOrigin(window:hxd.Window):{x:Float, y:Float} {
        #if hldx
        return {x: clientOriginXHandle(handle(window)),
            y: clientOriginYHandle(handle(window))};
        #else
        return {x: 0, y: 0};
        #end
    }

    /** Per-monitor scale reported by the locked hldx Win32 window wrapper. */
    public static function displayScale(window:hxd.Window):Float {
        #if hldx
        var scale:Float = @:privateAccess window.window.displayScale;
        return scale > 0 && Math.isFinite(scale) ? scale : 1;
        #else
        return 1;
        #end
    }

    /** Show, raise, and request foreground focus for a user-opened window. */
    public static function activate(window:hxd.Window):Bool {
        #if hldx
        return activateHandle(handle(window));
        #else
        return false;
        #end
    }
}
