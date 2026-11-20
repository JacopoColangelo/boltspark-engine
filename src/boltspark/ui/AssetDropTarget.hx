package boltspark.ui;

import boltspark.engine.inspector.AssetType;

/**
 * One live drop slot. Targets register themselves while their owning widget is
 * mounted; dead targets (rebuilt inspector sections) are pruned on the next
 * drag, so a static registry is safe across inspector refreshes.
 */
class AssetDropTarget {
    public final assetType:AssetType;
    public final owner:h2d.Object;
    public final rectProvider:Void->AssetDropRect;
    public final onHighlight:Bool->Void;
    public final onDrop:AssetDragPayload->Void;
    /** Optional liveness override for headless tests; production uses the scene. */
    public var aliveProvider:Null<Void->Bool> = null;

    public function new(assetType:AssetType, owner:h2d.Object,
            rectProvider:Void->AssetDropRect, onHighlight:Bool->Void,
            onDrop:AssetDragPayload->Void) {
        this.assetType = assetType;
        this.owner = owner;
        this.rectProvider = rectProvider;
        this.onHighlight = onHighlight;
        this.onDrop = onDrop;
    }

    public function isAlive():Bool {
        if (aliveProvider != null) return aliveProvider();
        return owner != null && owner.getScene() != null;
    }

    public function rect():AssetDropRect return rectProvider();
}
