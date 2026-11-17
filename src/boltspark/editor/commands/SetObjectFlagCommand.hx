package boltspark.editor.commands;

import boltspark.editor.EditorSession;

/** Toggles a single editor flag (visibility or enabled) with full undo support. */
class SetObjectFlagCommand implements EditorCommand {
    public static inline var VISIBLE:Int = 0;
    public static inline var ENABLED:Int = 1;

    public var label(get, never):String;
    final session:EditorSession;
    final persistentId:String;
    final flag:Int;
    final before:Bool;
    final after:Bool;

    public function new(session:EditorSession, persistentId:String, flag:Int,
            before:Bool, after:Bool) {
        this.session = session;
        this.persistentId = persistentId;
        this.flag = flag;
        this.before = before;
        this.after = after;
    }

    public function execute():Void session.commandSetObjectFlag(persistentId, flag, after);
    public function undo():Void session.commandSetObjectFlag(persistentId, flag, before);

    inline function get_label():String {
        return (flag == VISIBLE ? "Visibility" : "Enabled")
            + (after ? " on" : " off");
    }
}
