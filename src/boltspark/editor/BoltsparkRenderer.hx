package boltspark.editor;

import boltspark.editor.shaders.BoltsparkIndirect;

/** Hook signature for per-frame deferred pipeline extensions. */
typedef BoltsparkFrameHook = BoltsparkRenderer->Void;

/**
 * Boltspark's deferred renderer, built on Heaps' PBR renderer.
 *
 * The stock pipeline already supplies MRT G-buffers, HDR lighting, a linear
 * depth buffer, optional velocity, shadow maps, tonemapping and FXAA. This
 * subclass swaps only the indirect-lighting shader for colored per-material
 * emission and exposes the existing frame hooks as an extension point for
 * future techniques (SSAO, SSR, bloom, volumetrics, TAA, ...).
 */
class BoltsparkRenderer extends h3d.scene.pbr.Renderer {
    public var beforeFullScreenLightsHooks:Array<BoltsparkFrameHook> = [];
    public var afterFullScreenLightsHooks:Array<BoltsparkFrameHook> = [];
    public var beforeIndirectHooks:Array<BoltsparkFrameHook> = [];
    public var afterIndirectHooks:Array<BoltsparkFrameHook> = [];

    public function new(?env) {
        super(env);
        @:privateAccess {
            pbrOut.removeShader(pbrIndirect);
            pbrIndirect = new BoltsparkIndirect();
            pbrOut.addShader(pbrIndirect);
        }
        skyMode = Hide;
        toneMode = Reinhard;
    }

    override function beforeFullScreenLights() {
        for (hook in beforeFullScreenLightsHooks) hook(this);
    }

    override function afterFullScreenLights() {
        for (hook in afterFullScreenLightsHooks) hook(this);
    }

    override function beforeIndirect() {
        for (hook in beforeIndirectHooks) hook(this);
    }

    override function afterIndirect() {
        for (hook in afterIndirectHooks) hook(this);
    }
}
