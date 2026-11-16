package boltspark.editor.commands;

/** Bounded execute/undo/redo history; new edits invalidate the redo branch. */
class CommandHistory {
    final undoStack:Array<EditorCommand> = [];
    final redoStack:Array<EditorCommand> = [];
    final capacity:Int;
    var transactionDepth:Int = 0;
    var transactionLabel:String;
    final transactionCommands:Array<EditorCommand> = [];

    public var canUndo(get, never):Bool;
    public var canRedo(get, never):Bool;
    public var undoLabel(get, never):Null<String>;
    public var redoLabel(get, never):Null<String>;
    /** Monotonic edit counter; selection and view changes do not advance it. */
    public var revision(default, null):Int = 0;

    public function new(capacity:Int = 256) {
        if (capacity < 1) throw "Command history capacity must be positive";
        this.capacity = capacity;
    }

    public function execute(command:EditorCommand):Void {
        if (command == null) throw "Cannot execute a null editor command";
        command.execute();
        if (transactionDepth > 0) {
            transactionCommands.push(command);
            return;
        }
        pushExecuted(command);
    }

    /** Begin a possibly nested transaction that will become one undo entry. */
    public function beginTransaction(label:String):Void {
        if (label == null || StringTools.trim(label).length == 0) {
            throw "Command transaction label cannot be empty";
        }
        if (transactionDepth == 0) {
            transactionLabel = StringTools.trim(label);
            transactionCommands.resize(0);
        }
        transactionDepth++;
    }

    /** Commit the outermost active transaction. Empty transactions are ignored. */
    public function commitTransaction():Bool {
        if (transactionDepth <= 0) throw "No command transaction is active";
        transactionDepth--;
        if (transactionDepth > 0) return false;
        if (transactionCommands.length == 0) {
            transactionLabel = null;
            return false;
        }
        var command:EditorCommand = transactionCommands.length == 1
            && transactionCommands[0].label == transactionLabel
            ? transactionCommands[0]
            : new CompositeCommand(transactionLabel, transactionCommands);
        transactionCommands.resize(0);
        transactionLabel = null;
        pushExecuted(command);
        return true;
    }

    /** Roll back every command already executed in the active transaction. */
    public function cancelTransaction():Void {
        if (transactionDepth <= 0) return;
        var index = transactionCommands.length - 1;
        while (index >= 0) transactionCommands[index--].undo();
        transactionCommands.resize(0);
        transactionDepth = 0;
        transactionLabel = null;
    }

    function pushExecuted(command:EditorCommand):Void {
        revision++;
        undoStack.push(command);
        if (undoStack.length > capacity) undoStack.shift();
        redoStack.resize(0);
    }

    public function undo():Bool {
        if (transactionDepth > 0) throw "Cannot undo during a command transaction";
        if (undoStack.length == 0) return false;
        var command = undoStack.pop();
        command.undo();
        redoStack.push(command);
        revision++;
        return true;
    }

    public function redo():Bool {
        if (transactionDepth > 0) throw "Cannot redo during a command transaction";
        if (redoStack.length == 0) return false;
        var command = redoStack.pop();
        command.execute();
        undoStack.push(command);
        revision++;
        return true;
    }

    public function clear():Void {
        cancelTransaction();
        undoStack.resize(0);
        redoStack.resize(0);
        revision = 0;
    }

    inline function get_canUndo():Bool return undoStack.length > 0;
    inline function get_canRedo():Bool return redoStack.length > 0;
    function get_undoLabel():Null<String> return canUndo ? undoStack[undoStack.length - 1].label : null;
    function get_redoLabel():Null<String> return canRedo ? redoStack[redoStack.length - 1].label : null;
}
