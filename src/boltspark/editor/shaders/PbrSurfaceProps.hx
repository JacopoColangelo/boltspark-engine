package boltspark.editor.shaders;

/**
 * Boltspark's PBR surface properties shader for the deferred G-buffer.
 *
 * Heaps' stock `PropsValues`/`PropsTexture` only expose a scalar emissive
 * multiplier (tinted by the albedo). This shader keeps the same G-buffer
 * contract but reads a Unity-style metallic map (R = metallic, A = smoothness),
 * a separate occlusion map (R) and a true emission color packed into the
 * emissive/custom1/custom2 channels. `BoltsparkIndirect` reassembles them.
 */
class PbrSurfaceProps extends hxsl.Shader {
    static var SRC = {
        @param var metalnessValue : Float;
        @param var roughnessValue : Float;
        @param var occlusionStrength : Float;
        @param var emissiveColor : Vec3;
        @param var emissiveIntensity : Float;
        @param var metallicMap : Sampler2D;
        @param var roughnessMap : Sampler2D;
        @param var occlusionMap : Sampler2D;

        @const var hasRoughnessMap : Bool;
        @const var hasMetallicMap : Bool;
        @const var hasOcclusionMap : Bool;
        @const var smoothnessFromAlbedoAlpha : Bool;

        var output : {
            metalness : Float,
            roughness : Float,
            occlusion : Float,
            emissive : Float,
            custom1 : Float,
            custom2 : Float,
        };

        var metalness : Float;
        var roughness : Float;
        var occlusion : Float;
        var emissive : Float;
        var custom1 : Float;
        var custom2 : Float;

        var calculatedUV : Vec2;
        var pixelColor : Vec4;

        function __init__() {
            metalness = metalnessValue;
            roughness = roughnessValue;
            occlusion = 1.;
        }

        function fragment() {
            if( hasRoughnessMap ) {
                // Dedicated roughness slot: G channel is roughness (glTF
                // convention), matching Unity's inverted smoothness value.
                roughness = roughnessMap.get(calculatedUV).g;
            } else if( hasMetallicMap ) {
                var props = metallicMap.get(calculatedUV);
                metalness = props.r;
                var smoothness = smoothnessFromAlbedoAlpha ? pixelColor.a : props.a;
                roughness = 1 - smoothness.saturate();
            }
            if( hasOcclusionMap ) {
                var ao = occlusionMap.get(calculatedUV).r;
                occlusion = mix(1., ao, occlusionStrength);
            }
            // The albedo channel is gamma-decoded in PropsImport; match it so
            // emission retains the same perceived color as the author picked.
            var e = emissiveColor * emissiveIntensity;
            emissive = e.r * e.r;
            custom1 = e.g * e.g;
            custom2 = e.b * e.b;

            output.metalness = metalness.saturate();
            output.roughness = roughness.saturate().max(0.045);
            output.occlusion = occlusion.saturate();
            output.emissive = emissive;
            output.custom1 = custom1;
            output.custom2 = custom2;
        }
    };

    public function new() {
        super();
        emissiveColor.set(0, 0, 0);
        hasRoughnessMap = false;
        hasMetallicMap = false;
        hasOcclusionMap = false;
        smoothnessFromAlbedoAlpha = false;
    }
}
