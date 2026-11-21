package boltspark.ui.windows;

/**
 * Application-level editor windows hosted outside the main editor surface.
 *
 * The serialized value is also the command-line route used when the current
 * executable starts a dedicated native window process.
 */
enum abstract ApplicationWindowKind(String) to String {
    var EditorKeybindings = "editor-keybindings";
    /** Dedicated native HWND hosting one floating dock panel. */
    var DockPanel = "dock-panel";

    static inline var ARGUMENT_PREFIX:String = "--boltspark-window=";

    public function displayName():String {
        return switch (this) {
            case EditorKeybindings: "Editor Keybindings";
            case DockPanel: "Dock Panel";
            default: "Editor Window";
        };
    }

    public inline function commandArgument():String {
        return ARGUMENT_PREFIX + (this : String);
    }

    /** Return the requested application window, or null for the main editor. */
    public static function fromArguments(arguments:Array<String>):Null<ApplicationWindowKind> {
        for (argument in arguments) {
            if (!StringTools.startsWith(argument, ARGUMENT_PREFIX)) continue;
            var value = argument.substr(ARGUMENT_PREFIX.length);
            if (value == (EditorKeybindings : String)) return EditorKeybindings;
            if (value == (DockPanel : String)) return DockPanel;
        }
        return null;
    }
}
