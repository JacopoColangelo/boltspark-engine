package boltspark.editor.commands;

import boltspark.editor.EditorSession;
import boltspark.engine.PrimitiveSettings;

/** Undoable primitive-settings edit on one object's MeshRenderer. */
class PrimitiveSettingsCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final persistentId:String;
    final before:PrimitiveSettings;
    final after:PrimitiveSettings;
    final description:String;

    public function new(session:EditorSession, persistentId:String,
            before:PrimitiveSettings, after:PrimitiveSettings,
            description:String) {
        this.session = session;
        this.persistentId = persistentId;
        this.before = before.clone();
        this.after = after.clone();
        this.description = description;
    }

    public function execute():Void
        session.commandPrimitiveSettings(persistentId, after);
    public function undo():Void
        session.commandPrimitiveSettings(persistentId, before);
    inline function get_label():String return description;
}
