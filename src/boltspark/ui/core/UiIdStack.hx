package boltspark.ui.core;

/** Explicit ID scopes prevent labels and list rows from sharing state. */
class UiIdStack {
    final parts:Array<String> = [];

    public var depth(get, never):Int;

    public function new(root:String = "ui") {
        parts.push(normalize(root));
    }

    public function reset(root:String = "ui"):Void {
        parts.resize(0);
        parts.push(normalize(root));
    }

    public function push(part:String):Void parts.push(normalize(part));

    public function pop():Bool {
        if (parts.length <= 1) return false;
        parts.pop();
        return true;
    }

    public function resolve(name:String):UiId {
        return new UiId(parts.join("/") + "/" + normalize(name));
    }

    function get_depth():Int return parts.length - 1;

    static function normalize(value:String):String {
        var result = StringTools.trim(value);
        if (result.length == 0) return "_";
        return StringTools.replace(result, "/", "_");
    }
}
