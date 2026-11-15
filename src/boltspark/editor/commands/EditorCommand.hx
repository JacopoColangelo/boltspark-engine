package boltspark.editor.commands;

interface EditorCommand {
    public var label(get, never):String;
    public function execute():Void;
    public function undo():Void;
}
