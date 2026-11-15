package boltspark.editor.commands;

/** Bounded execute/undo/redo history; new edits invalidate the redo branch. */
class CommandHistory {
    final undoStack:Array<EditorCommand> = [];
    final redoStack:Array<EditorCommand> = [];
    final capacity:Int;

    public var canUndo(get, never):Bool;
    public var canRedo(get, never):Bool;
    public var undoLabel(get, never):Null<String>;
    public var redoLabel(get, never):Null<String>;

    public function new(capacity:Int = 256) {
        if (capacity < 1) throw "Command history capacity must be positive";
        this.capacity = capacity;
    }

    public function execute(command:EditorCommand):Void {
        if (command == null) throw "Cannot execute a null editor command";
        command.execute();
        undoStack.push(command);
        if (undoStack.length > capacity) undoStack.shift();
        redoStack.resize(0);
    }

    public function undo():Bool {
        if (undoStack.length == 0) return false;
        var command = undoStack.pop();
        command.undo();
        redoStack.push(command);
        return true;
    }

    public function redo():Bool {
        if (redoStack.length == 0) return false;
        var command = redoStack.pop();
        command.execute();
        undoStack.push(command);
        return true;
    }

    public function clear():Void {
        undoStack.resize(0);
        redoStack.resize(0);
    }

    inline function get_canUndo():Bool return undoStack.length > 0;
    inline function get_canRedo():Bool return redoStack.length > 0;
    function get_undoLabel():Null<String> return canUndo ? undoStack[undoStack.length - 1].label : null;
    function get_redoLabel():Null<String> return canRedo ? redoStack[redoStack.length - 1].label : null;
}
