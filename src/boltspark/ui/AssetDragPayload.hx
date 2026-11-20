package boltspark.ui;

import boltspark.engine.inspector.AssetType;

/** What a cross-panel asset drag is carrying. */
typedef AssetDragPayload = {
    /** Concrete asset id understood by `Component.setInspectorAsset`. */
    var assetId:String;
    /** Human-readable label for the drag ghost. */
    var label:String;
    /** Family the drop slot must accept. */
    var assetType:AssetType;
    /** Asset Browser source key the drag started from. */
    var source:String;
};
