package boltspark.editor.shaders;

/**
 * Depth-aware editor overlays in the deferred pipeline.
 *
 * The grid, selection outlines and gizmos are drawn in the PBR renderer's
 * "overlay" pass, after tonemapping, into the LDR target. That target has no
 * depth buffer, so this shader reads the PBR depth texture (installed as the
 * `depthMap` global by the renderer) and discards overlay fragments hidden by
 * scene geometry. This preserves the historical "grid behind objects" and
 * "object silhouettes" behavior without a separate forward pass.
 */
class OverlayDepthOcclusion extends hxsl.Shader {
    static var SRC = {
        @global var depthMap : Channel;

        var screenUV : Vec2;
        var depth : Float;

        function fragment() {
            var sceneDepth = depthMap.get(screenUV).r;
            if( sceneDepth < depth - 0.00015 ) discard;
        }
    };

    public function new() super();
}
