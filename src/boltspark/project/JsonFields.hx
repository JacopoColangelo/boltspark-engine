package boltspark.project;

/** Strict JSON field readers plus unknown-field preservation helpers. */
class JsonFields {
    public static function object(value:Dynamic, context:String):Dynamic {
        if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
            throw '${context} must be an object';
        }
        return value;
    }

    public static function array(value:Dynamic, context:String):Array<Dynamic> {
        if (!Std.isOfType(value, Array)) throw '${context} must be an array';
        return cast value;
    }

    public static function stringField(data:Dynamic, name:String,
            context:String):String {
        var value = Reflect.field(data, name);
        if (!Std.isOfType(value, String)) throw '${context}.${name} must be a string';
        return value;
    }

    public static function nullableStringField(data:Dynamic, name:String,
            context:String):Null<String> {
        var value = Reflect.field(data, name);
        if (value == null) return null;
        if (!Std.isOfType(value, String)) throw '${context}.${name} must be a string or null';
        return value;
    }

    public static function intField(data:Dynamic, name:String,
            context:String):Int {
        var value = Reflect.field(data, name);
        if (!Std.isOfType(value, Int)) throw '${context}.${name} must be an integer';
        return value;
    }

    public static function numberField(data:Dynamic, name:String,
            context:String):Float {
        var value = Reflect.field(data, name);
        if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) {
            throw '${context}.${name} must be a number';
        }
        var result:Float = value;
        if (!finite(result)) throw '${context}.${name} must be finite';
        return result;
    }

    public static function extras(data:Dynamic, known:Array<String>):Dynamic {
        var result:Dynamic = {};
        for (field in Reflect.fields(data)) {
            if (known.indexOf(field) < 0) Reflect.setField(result, field, Reflect.field(data, field));
        }
        return result;
    }

    public static function withExtras(extras:Dynamic):Dynamic {
        var result:Dynamic = {};
        if (extras != null && Reflect.isObject(extras)) {
            for (field in Reflect.fields(extras)) {
                Reflect.setField(result, field, Reflect.field(extras, field));
            }
        }
        return result;
    }

    static inline function finite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY
            && value != Math.NEGATIVE_INFINITY;
    }
}
