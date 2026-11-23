package boltspark.editor.shaders;

/**
 * Deferred indirect lighting with per-material emission color.
 *
 * Inherits every parameter and variable from Heaps' `Indirect` shader and only
 * replaces its `fragment()` body: the emissive term is rebuilt from the RGB
 * emission packed by `PbrSurfaceProps` into the G-buffer's
 * emissive/custom1/custom2 channels. Kept in src/ so the pinned toolchain
 * (Heaps 2.1.0 + DX12) stays untouched.
 */
class BoltsparkIndirect extends h3d.shader.pbr.Lighting.Indirect {
    static var SRC = {
        function fragment() {
            #if !MRT_low
            var isSky = normal.dot(normal) <= 0;
            #else
            var isSky = normal.dot(normal) > 1.1;
            #end
            if( isSky ) {
                if( showSky ) {
                    var color : Vec3;
                    if( skyColor ) {
                        color = skyColorValue;
                        if( gammaCorrect ) color *= color;
                    } else {
                        var normal = (vec3(uvToScreen(calculatedUV), 1.)
                            * cameraInvViewProj.mat3x4()).normalize();
                        color = skyMap.get(rotateNormal(normal)).rgb;
                        color = min(color, skyHdrMax);
                        if( gammaCorrect ) color *= color;
                        color *= irrPower;
                    }
                    pixelColor.rgb += color;
                } else
                    discard;
            } else {
                var diffuse = vec3(0.);
                var specular = vec3(0.);

                var F0 = pbrSpecularColor;
                var F = F0 + (max(vec3(1 - roughness), F0) - F0)
                    * exp2((-5.55473 * NdV - 6.98316) * NdV);

                if( drawIndirectDiffuse ) {
                    diffuse = getEnvDiffuse(normal) * albedo;
                }
                if( drawIndirectSpecular ) {
                    var reflectVec = reflect(-view, normal);
                    var envSpec = getEnvSpecular(reflectVec, roughness);
                    var envBRDF = irrLut.get(vec2(roughness, NdV));
                    specular = envSpec * (F * envBRDF.x + envBRDF.y);
                }

                var indirect = (diffuse * (1 - metalness) * (1 - F) + specular) * irrPower;
                var emission = vec3(emissive, custom1, custom2) * emissivePower;
                pixelColor.rgb += indirect * occlusion + emission;
            }
        }
    };
}
