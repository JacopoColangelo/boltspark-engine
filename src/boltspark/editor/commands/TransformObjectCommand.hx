package boltspark.editor.commands;

import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;

class TransformObjectCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final persistentId:String;
    final before:EditorTransform;
    final after:EditorTransform;
    final description:String;

    public function new(session:EditorSession, persistentId:String,
            before:EditorTransform, after:EditorTransform, description:String) {
        this.session = session;
        this.persistentId = persistentId;
        this.before = before.clone();
        this.after = after.clone();
        this.description = description;
    }

    public function execute():Void session.commandTransformObject(persistentId, after);
    public function undo():Void session.commandTransformObject(persistentId, before);
    inline function get_label():String return description;
}
