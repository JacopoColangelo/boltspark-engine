package boltspark.editor.shaders;

/**
 * Tangent-space normal mapping with an author-controlled strength slider.
 * Mirrors `h3d.shader.NormalMap` but blends the sampled normal toward the
 * geometric normal, so Unity-like values of 0..1 behave predictably.
 */
class PbrNormalMap extends hxsl.Shader {
    static var SRC = {
        @global var global : {
            @perObject var modelView : Mat4;
        };

        @input var input : {
            var normal : Vec3;
            var tangent : Vec3;
        };

        @param var texture : Sampler2D;
        @param var strength : Float;

        var calculatedUV : Vec2;
        var transformedNormal : Vec3;

        @var var transformedTangent : Vec4;

        function __init__vertex() {
            transformedTangent = vec4(input.tangent * global.modelView.mat3(),
                input.tangent.dot(input.tangent) > 0.5 ? 1. : -1.);
        }

        function fragment() {
            var geometric = transformedNormal;
            var sampled = unpackNormal(texture.get(calculatedUV));
            sampled = mix(vec3(0., 0., 1.), sampled, strength);
            var tanX = transformedTangent.xyz.normalize();
            var tanY = geometric.cross(tanX) * -transformedTangent.w;
            transformedNormal = (sampled.x * tanX + sampled.y * tanY
                + sampled.z * geometric).normalize();
        }
    };

    public function new(?tex:h3d.mat.Texture, power:Float = 1) {
        super();
        texture = tex;
        strength = power;
    }
}
