import boltspark.editor.commands.CommandHistory;
import boltspark.editor.commands.CompositeCommand;
import boltspark.editor.commands.EditorCommand;

private class IntegerCommand implements EditorCommand {
    public var label(get, never):String;
    final name:String;
    final target:{value:Int};
    final delta:Int;

    public function new(name:String, target:{value:Int}, delta:Int) {
        this.name = name;
        this.target = target;
        this.delta = delta;
    }

    public function execute():Void target.value += delta;
    public function undo():Void target.value -= delta;
    inline function get_label():String return name;
}

private class FailingCommand implements EditorCommand {
    public var label(get, never):String;
    public function new() {}
    public function execute():Void throw "expected composite failure";
    public function undo():Void {}
    inline function get_label():String return "fail";
}

/** Headless command-history regression for the M3/M4 editing foundation. */
class CommandHistoryRepro {
    static function main():Void {
        var value = {value: 0};
        var history = new CommandHistory(2);
        history.execute(new IntegerCommand("one", value, 1));
        history.execute(new CompositeCommand("group", [
            new IntegerCommand("two", value, 2),
            new IntegerCommand("three", value, 3)
        ]));
        assertTrue(value.value == 6 && history.undoLabel == "group", "execute/group failed");
        assertTrue(history.undo() && value.value == 1, "undo failed");
        assertTrue(history.redo() && value.value == 6, "redo failed");
        assertTrue(history.undo(), "second undo failed");
        history.execute(new IntegerCommand("branch", value, 10));
        assertTrue(value.value == 11 && !history.canRedo, "new branch did not clear redo");
        history.execute(new IntegerCommand("bounded", value, 1));
        assertTrue(history.undo() && history.undo(), "bounded history entries missing");
        assertTrue(!history.undo(), "history exceeded configured capacity");
        var beforeFailure = value.value;
        try {
            new CompositeCommand("rollback", [
                new IntegerCommand("temporary", value, 7),
                new FailingCommand()
            ]).execute();
            throw "failing composite unexpectedly succeeded";
        } catch (error:Dynamic) {
            if (Std.string(error) == "failing composite unexpectedly succeeded") throw error;
        }
        assertTrue(value.value == beforeFailure, "composite failure did not roll back children");
        var transactionValue = {value: 0};
        var transactionHistory = new CommandHistory(8);
        transactionHistory.beginTransaction("Atomic gesture");
        transactionHistory.execute(new IntegerCommand("first", transactionValue, 4));
        transactionHistory.execute(new IntegerCommand("second", transactionValue, 6));
        assertTrue(transactionHistory.commitTransaction()
            && transactionValue.value == 10
            && transactionHistory.undoLabel == "Atomic gesture",
            "transaction did not become one history entry");
        assertTrue(transactionHistory.undo() && transactionValue.value == 0,
            "transaction undo was not atomic");
        transactionHistory.beginTransaction("Cancelled gesture");
        transactionHistory.execute(new IntegerCommand("temporary", transactionValue, 9));
        transactionHistory.cancelTransaction();
        assertTrue(transactionValue.value == 0,
            "cancelled transaction did not roll back executed commands");
        Sys.println("[command-history] execute, composite, undo, redo, branch, and capacity passed");
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
