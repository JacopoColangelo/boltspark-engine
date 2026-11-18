package boltspark.ui;

import boltspark.ui.layout.DockLayout.DockLayoutGeometry;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.render.H2dDrawRenderer;
import boltspark.ui.render.UiDrawList;

/** Allocation-stable static editor chrome composition, rebuilt only on layout. */
class EditorChromeRenderer {
    final commands:UiDrawList = new UiDrawList();
    final renderer:H2dDrawRenderer = new H2dDrawRenderer();

    public function new() {}

    /** With no selection the meta row under the title is omitted. */
    public function draw(target:h2d.Graphics, width:Float, height:Float,
            geometry:DockLayoutGeometry, inspectorExpanded:Bool = true):Void {
        commands.reset();
        commands.fillRect(new LayoutRect(0, 0, width,
            Theme.TITLE_BAR_HEIGHT), Theme.TITLE_BAR);
        commands.fillRect(new LayoutRect(0, Theme.TITLE_BAR_HEIGHT, width,
            Theme.TOOLBAR_HEIGHT), Theme.TOOLBAR);
        commands.fillRect(geometry.leftPanel, Theme.PANEL);
        commands.fillRect(geometry.rightPanel, Theme.PANEL);
        commands.fillRect(geometry.console, Theme.PANEL);
        commands.fillRect(new LayoutRect(geometry.leftPanel.x,
            geometry.leftPanel.y, geometry.leftPanel.width,
            Theme.PANEL_HEADER_HEIGHT), Theme.PANEL_HEADER);
        var inspectorHeaderHeight = Theme.PANEL_HEADER_HEIGHT
            + (inspectorExpanded ? Theme.PANEL_META_HEIGHT : 0);
        commands.fillRect(new LayoutRect(geometry.rightPanel.x,
            geometry.rightPanel.y, geometry.rightPanel.width,
            inspectorHeaderHeight), Theme.PANEL_HEADER);

        // Restrained top markers identify active dock tabs without floating cards.
        commands.fillRect(new LayoutRect(geometry.leftPanel.x,
            geometry.leftPanel.y, Math.min(112, geometry.leftPanel.width), 2),
            Theme.ACCENT);
        commands.fillRect(new LayoutRect(geometry.rightPanel.x,
            geometry.rightPanel.y, Math.min(88, geometry.rightPanel.width), 2),
            Theme.ACCENT);
        commands.fillRect(new LayoutRect(0,
            height - Theme.STATUS_BAR_HEIGHT, width, Theme.STATUS_BAR_HEIGHT),
            Theme.TITLE_BAR);

        commands.line(0, Theme.TITLE_BAR_HEIGHT, width,
            Theme.TITLE_BAR_HEIGHT, Theme.BORDER);
        commands.line(0, Theme.TOP_BAR_HEIGHT, width,
            Theme.TOP_BAR_HEIGHT, Theme.BORDER);
        commands.line(geometry.leftPanel.x,
            geometry.leftPanel.y + Theme.PANEL_HEADER_HEIGHT - 0.5,
            geometry.leftPanel.x + geometry.leftPanel.width,
            geometry.leftPanel.y + Theme.PANEL_HEADER_HEIGHT - 0.5, Theme.BORDER);
        commands.line(geometry.rightPanel.x,
            geometry.rightPanel.y + inspectorHeaderHeight - 0.5,
            geometry.rightPanel.x + geometry.rightPanel.width,
            geometry.rightPanel.y + inspectorHeaderHeight - 0.5,
            Theme.BORDER);
        commands.line(0, height - Theme.STATUS_BAR_HEIGHT, width,
            height - Theme.STATUS_BAR_HEIGHT, Theme.BORDER);
        commands.strokeRect(geometry.viewport, Theme.BORDER);
        renderer.render(commands, target);
    }
}
