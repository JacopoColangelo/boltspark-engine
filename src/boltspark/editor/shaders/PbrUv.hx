package boltspark.editor.shaders;

/**
 * Applies material tiling/offset to the shared `calculatedUV` used by the
 * albedo, metallic, normal and occlusion samplers. The `__init__vertex`
 * assignment keeps the variable defined even when no albedo texture is bound
 * (Heaps' Texture shader is the usual writer, but it is absent in that case).
 */
class PbrUv extends hxsl.Shader {
    static var SRC = {
        @input var input : {
            var uv : Vec2;
        };

        @param var tiling : Vec2;
        @param var offset : Vec2;

        var calculatedUV : Vec2;

        function __init__vertex() {
            calculatedUV = input.uv;
        }

        function vertex() {
            // Texture.vertex also writes calculatedUV; this shader reads it,
            // so hxsl schedules the transform after that assignment.
            calculatedUV = calculatedUV * tiling + offset;
        }
    };

    public function new() {
        super();
        tiling.set(1, 1);
        offset.set(0, 0);
    }
}
