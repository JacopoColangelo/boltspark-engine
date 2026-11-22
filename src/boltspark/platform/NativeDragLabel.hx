package boltspark.platform;

import boltspark.platform.NativeFloatWindow.WinFloatLabelHandle;

/** Native always-on-top, click-through window used for the shared drag label. */
class NativeDragLabel {
    @:hlNative("winfloat", "overlay_create")
    public static function create():WinFloatLabelHandle return null;

    @:hlNative("winfloat", "overlay_paint")
    public static function paint(handle:WinFloatLabelHandle,
            pixels:hl.Bytes, width:Int, height:Int, x:Int, y:Int):Void {}

    @:hlNative("winfloat", "overlay_hide")
    public static function hide(handle:WinFloatLabelHandle):Void {}

    @:hlNative("winfloat", "overlay_destroy")
    public static function destroy(handle:WinFloatLabelHandle):Void {}
}
