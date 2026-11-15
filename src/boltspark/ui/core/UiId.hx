package boltspark.ui.core;

/** Stable widget identity derived from an explicit scope path. */
class UiId {
    public final path:String;
    public final hash:Int;

    public function new(path:String) {
        this.path = path;
        hash = hashPath(path);
    }

    public inline function toString():String return path;

    /** Deterministic 32-bit FNV-1a hash. The path remains the collision guard. */
    public static function hashPath(value:String):Int {
        var result:Int = cast 0x811C9DC5;
        for (index in 0...value.length) {
            result ^= value.charCodeAt(index);
            result *= 0x01000193;
        }
        return result;
    }
}
