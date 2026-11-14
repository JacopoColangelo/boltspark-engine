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

    /** Show, raise, and request foreground focus for a user-opened window. */
    public static function activate(window:hxd.Window):Bool {
        #if hldx
        return activateHandle(handle(window));
        #else
        return false;
        #end
    }
}
