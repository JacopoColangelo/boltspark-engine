package boltspark.ui.windows;

/** Private parent/host protocol for reusable native editor windows. */
class ApplicationWindowProtocol {
    public static inline var HOST_ARGUMENT:String = "--boltspark-window-host";
    static inline var OWNER_PROCESS_PREFIX:String = "--boltspark-owner-process=";
    public static inline var SHOW:String = "show";
    public static inline var QUIT:String = "quit";
    public static inline var DOCK_PANEL_PREFIX:String = "--boltspark-panel=";
    public static inline var TITLE_PREFIX:String = "--boltspark-title=";

    public static function dockPanelId(arguments:Array<String>):Null<String> {
        for (argument in arguments) {
            if (StringTools.startsWith(argument, DOCK_PANEL_PREFIX)) {
                return StringTools.urlDecode(argument.substr(DOCK_PANEL_PREFIX.length));
            }
        }
        return null;
    }

    public static function dockPanelTitle(arguments:Array<String>):String {
        for (argument in arguments) {
            if (StringTools.startsWith(argument, TITLE_PREFIX)) {
                return StringTools.urlDecode(argument.substr(TITLE_PREFIX.length));
            }
        }
        return "Dock Panel";
    }

    public static function isHosted(arguments:Array<String>):Bool {
        return arguments.indexOf(HOST_ARGUMENT) >= 0;
    }

    public static function ownerProcessArgument(processId:Int):String {
        return OWNER_PROCESS_PREFIX + processId;
    }

    public static function ownerProcessId(arguments:Array<String>):Null<Int> {
        for (argument in arguments) {
            if (!StringTools.startsWith(argument, OWNER_PROCESS_PREFIX)) continue;
            var processId = Std.parseInt(argument.substr(OWNER_PROCESS_PREFIX.length));
            if (processId != null && processId > 0) return processId;
        }
        return null;
    }
}
