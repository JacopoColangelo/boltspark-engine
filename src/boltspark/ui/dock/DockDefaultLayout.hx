package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockOrientation;
import boltspark.ui.layout.DockLayout;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.Theme;

/**
 * Builds the default editor arrangement from real registered panels:
 *   left = Scene Hierarchy, center = Scene View, right = Inspector,
 *   bottom center = Asset Browser + Output Log tabs.
 * Legacy left/right/console preferences seed the split ratios so the first
 * dock-system launch matches the previous fixed layout exactly.
 */
class DockDefaultLayout {
    public static function create(registry:PanelRegistry, body:LayoutRect,
            ?legacy:DockLayout):DockNode {
        var leftWidth = legacy == null ? Theme.LEFT_PANEL_WIDTH : legacy.preferredLeftPanelWidth;
        var rightWidth = legacy == null ? Theme.RIGHT_PANEL_WIDTH : legacy.preferredRightPanelWidth;
        var consoleHeight = legacy == null ? Theme.CONSOLE_HEIGHT : legacy.preferredConsoleHeight;
        var bottomTab = legacy == null ? 0 : legacy.bottomTab;

        var handle = SplitNode.HANDLE_SIZE;
        var panelSpace = Math.max(0, body.width - handle * 2);
        var left:Float;
        var right:Float;
        var center:Float;
        if (panelSpace >= Theme.MIN_LEFT_PANEL_WIDTH + Theme.MIN_CENTER_PANEL_WIDTH
                + Theme.MIN_RIGHT_PANEL_WIDTH) {
            var maxLeft = panelSpace - Theme.MIN_CENTER_PANEL_WIDTH
                - Theme.MIN_RIGHT_PANEL_WIDTH;
            left = DockNode.clamp(leftWidth, Theme.MIN_LEFT_PANEL_WIDTH, maxLeft);
            var maxRight = panelSpace - left - Theme.MIN_CENTER_PANEL_WIDTH;
            right = DockNode.clamp(rightWidth, Theme.MIN_RIGHT_PANEL_WIDTH, maxRight);
            center = Math.max(0, panelSpace - left - right);
        } else {
            left = Math.min(Theme.MIN_LEFT_PANEL_WIDTH, panelSpace * 0.3);
            right = Math.min(Theme.MIN_RIGHT_PANEL_WIDTH, panelSpace * 0.35);
            center = Math.max(0, panelSpace - left - right);
        }

        var bodyHeight = Math.max(0, body.height);
        var consoleHeightValue:Float;
        if (bodyHeight >= 168 + handle + 96) {
            consoleHeightValue = DockNode.clamp(consoleHeight, 140,
                bodyHeight - 168 - handle);
        } else {
            consoleHeightValue = bodyHeight * 0.4;
        }
        var viewportHeight = Math.max(0, bodyHeight - consoleHeightValue - handle);

        // The root split's handle is shared with the nested one: its ratio is
        // measured against W - handle, while left+center+right live in W - 2h.
        var rootAvailable = Math.max(1, body.width - handle);
        var rootRatio = panelSpace <= 0 ? 0.25 : left / rootAvailable;
        var restSpace = center + right;
        var restRatio = restSpace <= 0 ? 0.6 : center / restSpace;
        var verticalSpace = viewportHeight + consoleHeightValue;
        var verticalRatio = verticalSpace <= 0 ? 0.75 : viewportHeight / verticalSpace;

        var hierarchy = tab(registry, "boltspark.hierarchy");
        var viewport = tab(registry, "boltspark.viewport");
        // The 3D view renders behind its tab strip; a slim bar keeps the
        // camera/ray rectangle aligned with the legacy full-size viewport.
        viewport.tabBarHeight = 16;
        var inspector = tab(registry, "boltspark.inspector");
        var bottom = tab(registry, "boltspark.assets,boltspark.console");
        bottom.activeIndex = bottomTab == 1 ? 1 : 0;

        var centerSplit = new SplitNode(DockOrientation.Vertical, viewport, bottom, verticalRatio,
            Math.max(120, viewport.minSize().h), 120);
        var restSplit = new SplitNode(DockOrientation.Horizontal, centerSplit, inspector, restRatio,
            Math.max(200, Theme.MIN_CENTER_PANEL_WIDTH), Theme.MIN_RIGHT_PANEL_WIDTH);
        var root = new SplitNode(DockOrientation.Horizontal, hierarchy, restSplit, rootRatio,
            Theme.MIN_LEFT_PANEL_WIDTH,
            Theme.MIN_CENTER_PANEL_WIDTH + Theme.MIN_RIGHT_PANEL_WIDTH + handle);

        root.layout(body);
        return root;
    }

    static function tab(registry:PanelRegistry, ids:String):TabNode {
        var node = new TabNode();
        for (id in ids.split(",")) {
            if (!registry.has(id)) continue;
            node.add(registry.slot(id));
        }
        return node;
    }
}
