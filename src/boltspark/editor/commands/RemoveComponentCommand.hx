package boltspark.editor.commands;

import boltspark.editor.EditorSession;
import boltspark.engine.Component;

/** Remove one component while retaining a detached undo template. */
class RemoveComponentCommand implements EditorCommand {
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

    public function execute():Void session.commandRemoveComponent(objectId, index);

    public function undo():Void {
        session.commandInsertComponent(objectId, index,
            template.cloneComponent());
    }

    inline function get_label():String return "Remove " + template.displayName;
}
