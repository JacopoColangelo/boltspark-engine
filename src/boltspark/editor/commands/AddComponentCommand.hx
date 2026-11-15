package boltspark.editor.commands;

import boltspark.editor.EditorSession;
import boltspark.engine.Component;

/** Add one cloned component at a stable collection index. */
class AddComponentCommand implements EditorCommand {
    public var label(get, never):String;
    final session:EditorSession;
    final objectId:String;
    final index:Int;
    final template:Component;

    public function new(session:EditorSession, objectId:String, index:Int,
            component:Component) {
        this.session = session;
        this.objectId = objectId;
        this.index = index;
        template = component.cloneComponent();
    }

    public function execute():Void {
        session.commandInsertComponent(objectId, index,
            template.cloneComponent());
    }

    public function undo():Void session.commandRemoveComponent(objectId, index);

    inline function get_label():String return "Add " + template.displayName;
}
