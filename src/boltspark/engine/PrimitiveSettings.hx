package boltspark.engine;

/**
 * Renderer-independent geometry parameters for a primitive MeshRenderer.
 *
 * Settings belong to the renderer instance (not to the shared Mesh asset), so
 * two entities may reference the same mesh asset yet use different segment
 * counts or cap modes. Geometries with identical settings are still cached and
 * shared by HeapsMeshFactory.
 */
class PrimitiveSettings {
    public var segments:Int = 16;
    public var rings:Int = 12;
    public var radius:Float = 0.5;
    public var height:Float = 1;
    public var width:Float = 1;
    public var depth:Float = 1;
    /** Cylinder: closed ends by default; turn off for a hollow tube. */
    public var capped:Bool = true;

    public function new() {}

    public function clone():PrimitiveSettings {
        var result = new PrimitiveSettings();
        result.segments = segments;
        result.rings = rings;
        result.radius = radius;
        result.height = height;
        result.width = width;
        result.depth = depth;
        result.capped = capped;
        return result;
    }

    public function sameAs(other:Null<PrimitiveSettings>):Bool {
        return other != null
            && other.segments == segments && other.rings == rings
            && other.radius == radius && other.height == height
            && other.width == width && other.depth == depth
            && other.capped == capped;
    }

    /** Cache key suffix; identical settings always produce identical geometry. */
    public function signature():String {
        return 's${segments}/r${rings}/a${radius}/h${height}/'
            + 'w${width}/d${depth}/c${capped ? 1 : 0}';
    }

    public function toData():Dynamic {
        return {
            segments: segments,
            rings: rings,
            radius: radius,
            height: height,
            width: width,
            depth: depth,
            capped: capped
        };
    }

    public static function fromData(value:Dynamic):PrimitiveSettings {
        var result = new PrimitiveSettings();
        if (value == null || !Reflect.isObject(value)) return result;
        result.segments = positiveInt(Reflect.field(value, "segments"), result.segments, 3, 64);
        result.rings = positiveInt(Reflect.field(value, "rings"), result.rings, 3, 48);
        result.radius = positiveFloat(Reflect.field(value, "radius"), result.radius, 0.01, 8);
        result.height = positiveFloat(Reflect.field(value, "height"), result.height, 0.01, 16);
        result.width = positiveFloat(Reflect.field(value, "width"), result.width, 0.01, 16);
        result.depth = positiveFloat(Reflect.field(value, "depth"), result.depth, 0.01, 16);
        if (Std.isOfType(Reflect.field(value, "capped"), Bool)) {
            result.capped = Reflect.field(value, "capped");
        }
        return result;
    }

    static function positiveInt(value:Dynamic, fallback:Int,
            min:Int, max:Int):Int {
        if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int)) return fallback;
        var number = Std.parseInt(Std.string(value));
        if (number == null || !Math.isFinite(number)) return fallback;
        return clampInt(Std.int(number), min, max);
    }

    static function positiveFloat(value:Dynamic, fallback:Float,
            min:Float, max:Float):Float {
        if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int)) return fallback;
        var number = Std.parseFloat(Std.string(value));
        if (!Math.isFinite(number)) return fallback;
        return number < min ? min : number > max ? max : number;
    }

    static inline function clampInt(value:Int, min:Int, max:Int):Int {
        return value < min ? min : value > max ? max : value;
    }
}
