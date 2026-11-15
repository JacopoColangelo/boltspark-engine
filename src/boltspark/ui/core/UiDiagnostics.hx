package boltspark.ui.core;

/** Frame-local contract diagnostics for the reusable BoltUI core. */
class UiDiagnostics {
    final messages:Array<String> = [];

    public var count(get, never):Int;

    public function new() {}

    public function reset():Void messages.resize(0);

    public function report(message:String):Void {
        if (messages.indexOf(message) < 0) messages.push(message);
    }

    public function all():Array<String> return messages.copy();

    public function contains(fragment:String):Bool {
        for (message in messages) if (message.indexOf(fragment) >= 0) return true;
        return false;
    }

    function get_count():Int return messages.length;
}
