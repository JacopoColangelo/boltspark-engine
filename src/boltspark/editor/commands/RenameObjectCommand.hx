package boltspark.editor.commands;

import boltspark.editor.EditorSession;

class RenameObjectCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final persistentId:String;
    final before:String;
    final after:String;

    public function new(session:EditorSession, persistentId:String,
            before:String, after:String) {
        this.session = session;
        this.persistentId = persistentId;
        this.before = before;
        this.after = after;
    }

    public function execute():Void session.commandRenameObject(persistentId, after);
    public function undo():Void session.commandRenameObject(persistentId, before);
    inline function get_label():String return 'Rename ${before}';
}
