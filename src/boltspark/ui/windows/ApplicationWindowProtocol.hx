package boltspark.ui.windows;

/** Private parent/host protocol for reusable native editor windows. */
class ApplicationWindowProtocol {
    public static inline var HOST_ARGUMENT:String = "--boltspark-window-host";
    public static inline var SHOW:String = "show";
    public static inline var QUIT:String = "quit";

    public static function isHosted(arguments:Array<String>):Bool {
        return arguments.indexOf(HOST_ARGUMENT) >= 0;
    }
}
