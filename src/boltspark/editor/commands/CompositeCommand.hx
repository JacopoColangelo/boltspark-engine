package boltspark.editor.commands;

/** One history entry composed of commands executed and undone in safe order. */
class CompositeCommand implements EditorCommand {
    public var label(get, never):String;
    final description:String;
    final commands:Array<EditorCommand>;

    public function new(description:String, commands:Array<EditorCommand>) {
        if (commands == null || commands.length == 0) {
            throw "Composite command requires at least one child";
        }
        this.description = description;
        this.commands = commands.copy();
    }

    public function execute():Void {
        var completed = 0;
        try {
            for (command in commands) {
                command.execute();
                completed++;
            }
        } catch (error:Dynamic) {
            while (completed > 0) commands[--completed].undo();
            throw error;
        }
    }

    public function undo():Void {
        var index = commands.length - 1;
        while (index >= 0) commands[index--].undo();
    }

    inline function get_label():String return description;
}
