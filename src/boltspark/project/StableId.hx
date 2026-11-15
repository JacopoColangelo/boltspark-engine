package boltspark.project;

import haxe.crypto.Sha256;

/** Durable lowercase 128-bit identifier serialized as 32 hexadecimal digits. */
class StableId {
    static var sequence:Int = 0;

    public static function create(?namespace:String):String {
        sequence++;
        var source = (namespace == null ? "boltspark" : namespace)
            + ":" + Date.now().getTime()
            + ":" + sequence
            + ":" + Math.random();
        return Sha256.encode(source).substr(0, 32).toLowerCase();
    }

    public static function isValid(value:Null<String>):Bool {
        if (value == null || value.length != 32) return false;
        for (index in 0...value.length) {
            var code = value.charCodeAt(index);
            var digit = code >= "0".code && code <= "9".code;
            var lowerHex = code >= "a".code && code <= "f".code;
            if (!digit && !lowerHex) return false;
        }
        return true;
    }

    public static function require(value:Null<String>, context:String):String {
        if (!isValid(value)) throw '${context} must be a 32-character lowercase hexadecimal ID';
        return value;
    }
}
