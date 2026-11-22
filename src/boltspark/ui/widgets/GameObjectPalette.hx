package boltspark.ui.widgets;

import boltspark.engine.PrimitiveMeshes;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.layout.LayoutRect;

/**
 * Add-Object palette listing the built-in primitive assets. Every row is both
 * clickable (create at the origin) and draggable (drop into the viewport).
 */
class GameObjectPalette extends h2d.Object {
    static inline var WIDTH:Int = 210;
    static inline var ROW_HEIGHT:Int = 28;
    static inline var TOP:Int = 31;

    public var onCreatePrimitive:Null<String->Void>;
    public var onDropPrimitive:Null<String->Float->Float->Void>;

    final context:UiContext;
    final background:UiSurface;
    final title:h2d.Text;
    final rows:Array<PaletteRow> = [];
    final closeButton:UiButton;
    final dragPreviewBackground:UiSurface;
    final dragPreview:h2d.Text;
    final dragPreviewIcon:h2d.Graphics;
    var viewport:LayoutRect;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;
    var activeMeshId:String = "";

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        var meshes = [PrimitiveMeshes.cube(), PrimitiveMeshes.sphere(),
            PrimitiveMeshes.cylinder(), PrimitiveMeshes.capsule(),
            PrimitiveMeshes.plane()];
        background = new UiSurface(context, this);
        background.setSize(WIDTH, TOP + meshes.length * ROW_HEIGHT + 6);
        background.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.36);

        title = new UiText(context.semiboldFont, this);
        title.text = "Add Primitive";
        title.textColor = Theme.TEXT;
        title.lineBreak = false;
        title.x = 8;
        title.y = 5;

        closeButton = new UiButton(context, "", 20, 20, this);
        closeButton.setIcon(Close).setQuiet();
        closeButton.x = WIDTH - 23;
        closeButton.y = 3;
        closeButton.onClick = close;

        for (index in 0...meshes.length) {
            var mesh = meshes[index];
            var row = new PaletteRow(mesh.id);
            row.y = TOP + index * ROW_HEIGHT;
            row.surface = new UiSurface(context, this);
            row.surface.x = 4;
            row.surface.y = row.y;
            row.surface.setSize(WIDTH - 8, ROW_HEIGHT);
            row.surface.setStyle(Theme.SURFACE_2, Theme.BORDER, 0);
            row.hit = new h2d.Interactive(WIDTH - 8, ROW_HEIGHT, this);
            row.hit.x = 4;
            row.hit.y = row.y;
            row.hit.backgroundColor = 0;
            row.hit.cursor = hxd.Cursor.Move;
            var capturedRow = row;
            row.hit.onOver = function(_) row.surface.setStyle(
                Theme.SURFACE_3, Theme.ACCENT, 0);
            row.hit.onOut = function(_) row.surface.setStyle(
                Theme.SURFACE_2, Theme.BORDER, 0);
            row.hit.onPush = function(event) beginPrimitiveDrag(capturedRow, event);

            row.icon = new h2d.Graphics(this);
            UiIcons.draw(row.icon, Cube, 0, 0, 14, Theme.CUBE_ORANGE);
            row.icon.x = 11;
            row.icon.y = row.y + 7;
            row.label = new UiText(context.semiboldFont, this);
            row.label.text = mesh.name;
            row.label.textColor = Theme.TEXT;
            row.label.lineBreak = false;
            row.label.x = 33;
            row.label.y = row.y + 4;
            rows.push(row);
        }

        dragPreviewBackground = new UiSurface(context, parent);
        dragPreviewBackground.setSize(78, 26);
        dragPreviewBackground.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT, 0.30);
        dragPreviewBackground.visible = false;
        dragPreviewIcon = new h2d.Graphics(parent);
        UiIcons.draw(dragPreviewIcon, Cube, 0, 0, 15, Theme.CUBE_ORANGE);
        dragPreviewIcon.visible = false;
        dragPreview = new UiText(context.semiboldFont, parent);
        dragPreview.text = "Primitive";
        dragPreview.textColor = Theme.TEXT;
        dragPreview.visible = false;
    }

    public function toggleAt(x:Float, y:Float, viewport:LayoutRect):Void {
        if (visible) close() else openAt(x, y, viewport);
    }

    public function openAt(x:Float, y:Float, viewport:LayoutRect):Void {
        this.viewport = viewport;
        this.x = Math.max(6, Math.min(Math.max(6, context.width - WIDTH - 6), x));
        var height = TOP + rows.length * ROW_HEIGHT + 6;
        this.y = Math.max(Theme.TOP_BAR_HEIGHT + 6,
            Math.min(Math.max(Theme.TOP_BAR_HEIGHT + 6,
                context.height - height - 6), y));
        for (row in rows) row.hit.cursor = hxd.Cursor.Move;
        visible = true;
    }

    public function close():Void {
        for (row in rows) row.hit.cursor = hxd.Cursor.Default;
        visible = false;
        dragPreviewBackground.visible = false;
        dragPreview.visible = false;
        dragPreviewIcon.visible = false;
        context.restoreArrowCursor();
    }

    function beginPrimitiveDrag(row:PaletteRow, event:hxd.Event):Void {
        if (event.button != 0) return;
        activeMeshId = row.meshId;
        dragStartX = context.mouseX;
        dragStartY = context.mouseY;
        dragPreview.visible = false;
        row.hit.startCapture(function(captured) {
            switch (captured.kind) {
                case EMove:
                    var mouseX = context.mouseX;
                    var mouseY = context.mouseY;
                    if (!dragPreview.visible
                        && Math.abs(mouseX - dragStartX) + Math.abs(mouseY - dragStartY) > 5) {
                        dragPreview.visible = true;
                        dragPreviewBackground.visible = true;
                        dragPreviewIcon.visible = true;
                        dragPreview.text = PrimitiveMeshes.find(row.meshId).name;
                    }
                    dragPreviewBackground.x = mouseX + 8;
                    dragPreviewBackground.y = mouseY + 6;
                    dragPreviewIcon.x = mouseX + 15;
                    dragPreviewIcon.y = mouseY + 12;
                    dragPreview.x = mouseX + 34;
                    dragPreview.y = mouseY + 9;
                    captured.propagate = false;
                case ERelease, EReleaseOutside:
                    var wasDrag = dragPreview.visible;
                    var mouseX = context.mouseX;
                    var mouseY = context.mouseY;
                    row.hit.stopCapture();
                    if (wasDrag && viewport != null
                        && mouseX >= viewport.x && mouseX < viewport.x + viewport.width
                        && mouseY >= viewport.y && mouseY < viewport.y + viewport.height) {
                        if (onDropPrimitive != null) {
                            onDropPrimitive(activeMeshId,
                                mouseX - viewport.x, mouseY - viewport.y);
                        }
                    } else if (!wasDrag && onCreatePrimitive != null) {
                        onCreatePrimitive(activeMeshId);
                    }
                    close();
                    captured.propagate = false;
                case EFocusLost:
                    row.hit.stopCapture();
                    close();
                    captured.propagate = false;
                case _:
                    captured.propagate = false;
            }
        });
        event.propagate = false;
    }
}

private class PaletteRow {
    public final meshId:String;
    public var y:Float = 0;
    public var surface:UiSurface;
    public var hit:h2d.Interactive;
    public var icon:h2d.Graphics;
    public var label:h2d.Text;

    public function new(meshId:String) {
        this.meshId = meshId;
    }
}
