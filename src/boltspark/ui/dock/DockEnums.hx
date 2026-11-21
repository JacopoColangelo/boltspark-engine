package boltspark.ui.dock;

/** Where a panel is dropped relative to an existing tab group. */
enum DockSide {
    Left;
    Right;
    Top;
    Bottom;
    /** Join the target group as another tab (or reorder inside its tab bar). */
    Center;
}

/** Split axis. Horizontal splits place children side by side (left/right). */
enum DockOrientation {
    Horizontal;
    Vertical;
}
