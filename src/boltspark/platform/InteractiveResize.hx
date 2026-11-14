package boltspark.platform;

/** Keep hldx/DX12 application windows repainting during a Win32 resize loop. */
class InteractiveResize {
    @:hlNative("directx", "win_set_interactive_resize_callback")
    static function setCallback(callback:Void->Void):Void return;

    public static function install():Void {
        setCallback(renderFrame);
    }

    public static function uninstall():Void {
        setCallback(null);
    }

    static function renderFrame():Void {
        try {
            @:privateAccess hxd.System.mainLoop();
        } catch (error:Dynamic) {
            Sys.println('[resize] frame failed: ${Std.string(error)}');
            uninstall();
        }
    }
}
