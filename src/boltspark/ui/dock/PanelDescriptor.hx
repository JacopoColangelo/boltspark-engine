package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockSide;

/** Immutable registration record for a dockable editor panel. */
typedef PanelDescriptor = {
    /** Stable, persisted identifier. Use reverse-DNS style, e.g. "boltspark.inspector". */
    var id:String;
    /** Human-readable name shown in tabs and the Window menu. */
    var displayName:String;
    /** Optional UiIconKind integer; 0 means no icon. */
    var ?icon:Int;
    /** Creates a fresh native view. Called at most once per instance key. */
    var factory:Void->DockPanelView;
    /** Preferred initial location, used by the default layout. */
    var ?defaultSide:DockSide;
    var ?minWidth:Float;
    var ?minHeight:Float;
    /** Whether the tab close button and Window menu may close this panel. */
    var ?canClose:Bool;
    /** Whether the panel may be undocked into a floating window. */
    var ?canFloat:Bool;
    /** Whether the panel may be docked into another tab group. */
    var ?canDock:Bool;
    /** Whether more than one instance key may exist at the same time. */
    var ?allowMultiple:Bool;
    /** Fixed panels stay visible, cannot be closed/floated/dragged/tabbed. */
    var ?fixed:Bool;
}
