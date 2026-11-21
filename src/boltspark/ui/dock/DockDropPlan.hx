package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.dock.DockLayoutRenderer.DockPreview;

/** Resolved target of a panel drag, plus the preview to show while hovering. */
typedef DockDropPlan = {
    var target:Null<TabNode>;
    var side:DockSide;
    var index:Int;
    var floating:Bool;
    var preview:DockPreview;
}
