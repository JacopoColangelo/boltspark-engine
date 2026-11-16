package boltspark.engine;

/**
 * One Inspector control published by a primitive mesh asset. The id names a
 * field on PrimitiveSettings; the renderer never needs to know which primitive
 * it is drawing beyond reading the schema from PrimitiveMeshes.
 */
class PrimitiveParameter {
    public static inline var NUMBER:String = "number";
    public static inline var INTEGER:String = "integer";
    public static inline var BOOLEAN:String = "boolean";

    public final id:String;
    public final label:String;
    /** `NUMBER`, `INTEGER`, or `BOOLEAN`. */
    public final kind:String;
    public final min:Float;
    public final max:Float;
    public final step:Float;

    public function new(id:String, label:String, kind:String,
            min:Float = 0, max:Float = 1, step:Float = 0.1) {
        this.id = id;
        this.label = label;
        this.kind = kind;
        this.min = min;
        this.max = max;
        this.step = step;
    }

    public static function number(id:String, label:String,
            min:Float, max:Float, step:Float = 0.1):PrimitiveParameter {
        return new PrimitiveParameter(id, label, NUMBER, min, max, step);
    }

    public static function integer(id:String, label:String,
            min:Int, max:Int):PrimitiveParameter {
        return new PrimitiveParameter(id, label, INTEGER, min, max, 1);
    }

    public static function boolean(id:String, label:String):PrimitiveParameter {
        return new PrimitiveParameter(id, label, BOOLEAN);
    }
}
