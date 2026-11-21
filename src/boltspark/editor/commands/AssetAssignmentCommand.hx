package boltspark.editor.commands;

import boltspark.editor.EditorSession;

/**
 * Undoable inspector asset assignment (mesh or material slot) on one object.
 * Stores stable asset ids only, never native references.
 */
class AssetAssignmentCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final persistentId:String;
    final propertyId:String;
    final before:String;
    final after:String;
    final description:String;

    public function new(session:EditorSession, persistentId:String,
            propertyId:String, before:String, after:String,
            description:String) {
        this.session = session;
        this.persistentId = persistentId;
        this.propertyId = propertyId;
        this.before = before == null ? "" : before;
        this.after = after == null ? "" : after;
        this.description = description;
    }

    public function execute():Void
        session.commandSetMeshAsset(persistentId, propertyId, after);
    public function undo():Void
        session.commandSetMeshAsset(persistentId, propertyId, before);
    inline function get_label():String return description;
}
