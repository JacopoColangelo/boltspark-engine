package boltspark.ui.dock;

import boltspark.ui.layout.LayoutRect;

/**
 * One live panel view. The docking model only knows this interface, which keeps
 * the tree, drag logic and serializer independent of H2D and fully testable.
 * A view is created once by the registry and cached, so closing a panel removes
 * it from the layout without destroying or duplicating its native content.
 */
interface DockPanelView {
    /** Stable registration id (never a display name). */
    var panelId(default, null):String;

    /** Apply a new absolute rectangle; implementations lay out their own content. */
    function layout(rect:LayoutRect):Void;

    /** Show/hide the native content while it is detached from the layout. */
    function setVisible(visible:Bool):Void;

    /** Panel-specific persistent state, or null when the panel has none. */
    function serializeState():Dynamic;

    /** Restore panel-specific state; unknown/outdated keys must be ignored. */
    function restoreState(state:Dynamic):Void;
}

/** A view plus the key used to distinguish instances of multi-instance panels. */
typedef PanelSlot = {
    var view:DockPanelView;
    var instanceKey:String;
    /** Fixed panels (the scene viewport) are never moved, closed or tabbed. */
    var ?locked:Bool;
}
