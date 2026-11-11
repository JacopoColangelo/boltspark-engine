package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.layout.LayoutRect;

class GameObjectPalette extends h2d.Object {
    static inline var WIDTH:Int = 248;
    static inline var HEIGHT:Int = 122;

    public var onCreateCube:Null<Void->Void>;
    public var onDropCube:Null<Float->Float->Void>;

    final context:UiContext;
    final background:UiSurface;
    final title:h2d.Text;
    final subtitle:h2d.Text;
    final cubeSurface:UiSurface;
    final cubeRow:h2d.Interactive;
    final cubeLabel:h2d.Text;
    final cubeDescription:h2d.Text;
    final cubeIcon:h2d.Graphics;
    final closeButton:UiButton;
    final dragPreviewBackground:UiSurface;
    final dragPreview:h2d.Text;
    final dragPreviewIcon:h2d.Graphics;
    var viewport:LayoutRect;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        background = new UiSurface(context, this);
        background.setSize(WIDTH, HEIGHT);
        background.setStyle(Theme.PANEL_ALT, Theme.BORDER_STRONG, 0.48);

        title = new h2d.Text(context.semiboldFont, this);
        title.text = "Add object";
        title.textColor = Theme.TEXT;
        title.lineBreak = false;
        title.x = 14;
        title.y = 10;
        subtitle = new h2d.Text(context.captionFont, this);
        subtitle.text = "Click to create or drag into the viewport";
        subtitle.textColor = Theme.MUTED;
        subtitle.lineBreak = false;
        subtitle.x = 14;
        subtitle.y = 29;

        closeButton = new UiButton(context, "", 26, 26, this);
        closeButton.setIcon(Close).setQuiet();
        closeButton.x = WIDTH - 34;
        closeButton.y = 7;
        closeButton.onClick = close;

        cubeSurface = new UiSurface(context, this);
        cubeSurface.x = 10;
        cubeSurface.y = 57;
        cubeSurface.setSize(WIDTH - 20, 54);
        cubeSurface.setStyle(Theme.SURFACE_2, Theme.BORDER, 0.12);
        cubeRow = new h2d.Interactive(WIDTH - 20, 54, this);
        cubeRow.x = 10;
        cubeRow.y = 57;
        cubeRow.backgroundColor = 0;
        cubeRow.cursor = hxd.Cursor.Move;
        cubeRow.onOver = function(_) cubeSurface.setStyle(Theme.SURFACE_3, Theme.ACCENT, 0.16);
        cubeRow.onOut = function(_) cubeSurface.setStyle(Theme.SURFACE_2, Theme.BORDER, 0.12);
        cubeRow.onPush = beginCubeDrag;

        cubeIcon = new h2d.Graphics(this);
        UiIcons.draw(cubeIcon, Cube, 0, 0, 24, Theme.CUBE_ORANGE);
        cubeIcon.x = 24;
        cubeIcon.y = 71;
        cubeLabel = new h2d.Text(context.semiboldFont, this);
        cubeLabel.text = "Cube";
        cubeLabel.textColor = Theme.TEXT;
        cubeLabel.lineBreak = false;
        cubeLabel.x = 60;
        cubeLabel.y = 65;
        cubeDescription = new h2d.Text(context.captionFont, this);
        cubeDescription.text = "3D primitive";
        cubeDescription.textColor = Theme.MUTED;
        cubeDescription.lineBreak = false;
        cubeDescription.x = 60;
        cubeDescription.y = 86;

        dragPreviewBackground = new UiSurface(context, parent);
        dragPreviewBackground.setSize(92, 32);
        dragPreviewBackground.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT, 0.30);
        dragPreviewBackground.visible = false;
        dragPreviewIcon = new h2d.Graphics(parent);
        UiIcons.draw(dragPreviewIcon, Cube, 0, 0, 15, Theme.CUBE_ORANGE);
        dragPreviewIcon.visible = false;
        dragPreview = new h2d.Text(context.semiboldFont, parent);
        dragPreview.text = "Cube";
        dragPreview.textColor = Theme.TEXT;
        dragPreview.visible = false;
    }

    public function toggleAt(x:Float, y:Float, viewport:LayoutRect):Void {
        if (visible) close() else openAt(x, y, viewport);
    }

    public function openAt(x:Float, y:Float, viewport:LayoutRect):Void {
        this.viewport = viewport;
        this.x = Math.max(6, Math.min(Math.max(6, context.width - WIDTH - 6), x));
        this.y = Math.max(Theme.TOP_BAR_HEIGHT + 6,
            Math.min(Math.max(Theme.TOP_BAR_HEIGHT + 6, context.height - HEIGHT - 6), y));
        visible = true;
    }

    public function close():Void {
        visible = false;
        dragPreviewBackground.visible = false;
        dragPreview.visible = false;
        dragPreviewIcon.visible = false;
    }

    function beginCubeDrag(event:hxd.Event):Void {
        if (event.button != 0) return;
        dragStartX = context.window.mouseX;
        dragStartY = context.window.mouseY;
        dragPreview.visible = false;
        cubeRow.startCapture(function(captured) {
            switch (captured.kind) {
                case EMove:
                    var mouseX = context.window.mouseX;
                    var mouseY = context.window.mouseY;
                    if (!dragPreview.visible
                        && Math.abs(mouseX - dragStartX) + Math.abs(mouseY - dragStartY) > 5) {
                        dragPreview.visible = true;
                        dragPreviewBackground.visible = true;
                        dragPreviewIcon.visible = true;
                    }
                    dragPreviewBackground.x = mouseX + 10;
                    dragPreviewBackground.y = mouseY + 8;
                    dragPreviewIcon.x = mouseX + 19;
                    dragPreviewIcon.y = mouseY + 16;
                    dragPreview.x = mouseX + 42;
                    dragPreview.y = mouseY + 13;
                    captured.propagate = false;
                case ERelease, EReleaseOutside:
                    var wasDrag = dragPreview.visible;
                    var mouseX = context.window.mouseX;
                    var mouseY = context.window.mouseY;
                    cubeRow.stopCapture();
                    if (wasDrag && viewport != null
                        && mouseX >= viewport.x && mouseX < viewport.x + viewport.width
                        && mouseY >= viewport.y && mouseY < viewport.y + viewport.height) {
                        if (onDropCube != null) onDropCube(mouseX - viewport.x, mouseY - viewport.y);
                    } else if (!wasDrag && onCreateCube != null) {
                        onCreateCube();
                    }
                    close();
                    captured.propagate = false;
                case EFocusLost:
                    cubeRow.stopCapture();
                    close();
                    captured.propagate = false;
                case _:
                    captured.propagate = false;
            }
        });
        event.cancel = true;
        event.propagate = false;
    }
}
