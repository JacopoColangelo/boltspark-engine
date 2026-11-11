package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.layout.LayoutRect;

class GameObjectPalette extends h2d.Object {
    public var onCreateCube:Null<Void->Void>;
    public var onDropCube:Null<Float->Float->Void>;

    final context:UiContext;
    final background:h2d.Graphics;
    final title:h2d.Text;
    final cubeRow:h2d.Interactive;
    final cubeLabel:h2d.Text;
    final cubeIcon:h2d.Graphics;
    final closeButton:UiButton;
    final dragPreviewBackground:h2d.Graphics;
    final dragPreview:h2d.Text;
    var viewport:LayoutRect;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;

    public function new(context:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.context = context;
        visible = false;

        background = new h2d.Graphics(this);
        background.beginFill(Theme.PANEL);
        background.drawRect(0, 0, 196, 86);
        background.endFill();
        background.lineStyle(1, Theme.PANEL_EDGE, 1);
        background.drawRect(0, 0, 196, 86);
        background.lineStyle();

        title = new h2d.Text(context.font, this);
        title.text = "CREATE GAME OBJECT";
        title.textColor = Theme.MUTED;
        title.lineBreak = false;
        title.x = 10;
        title.y = 7;

        closeButton = new UiButton(context, "x", 22, 22, this);
        closeButton.x = 166;
        closeButton.y = 3;
        closeButton.onClick = function() close();

        cubeRow = new h2d.Interactive(176, 34, this);
        cubeRow.x = 10;
        cubeRow.y = 42;
        cubeRow.backgroundColor = Theme.BUTTON;
        cubeRow.cursor = hxd.Cursor.Move;
        cubeRow.onOver = function(_) cubeRow.backgroundColor = Theme.BUTTON_HOVER;
        cubeRow.onOut = function(_) cubeRow.backgroundColor = Theme.BUTTON;
        cubeRow.onPush = beginCubeDrag;

        cubeIcon = new h2d.Graphics(cubeRow);
        cubeIcon.beginFill(Theme.CUBE_ORANGE);
        cubeIcon.drawRect(9, 8, 18, 18);
        cubeIcon.endFill();
        cubeLabel = new h2d.Text(context.font, cubeRow);
        cubeLabel.text = "Cube";
        cubeLabel.textColor = Theme.TEXT;
        cubeLabel.lineBreak = false;
        cubeLabel.x = 38;
        cubeLabel.y = 8;

        dragPreviewBackground = new h2d.Graphics(parent);
        dragPreviewBackground.beginFill(Theme.BUTTON_ACTIVE);
        dragPreviewBackground.drawRect(0, 0, 62, 28);
        dragPreviewBackground.endFill();
        dragPreviewBackground.visible = false;
        dragPreview = new h2d.Text(context.font, parent);
        dragPreview.text = "Cube";
        dragPreview.textColor = Theme.TEXT;
        dragPreview.visible = false;
    }

    public function toggleAt(x:Float, y:Float, viewport:LayoutRect):Void {
        if (visible) {
            close();
        } else {
            openAt(x, y, viewport);
        }
    }

    public function openAt(x:Float, y:Float, viewport:LayoutRect):Void {
        this.viewport = viewport;
        this.x = Math.max(4, Math.min(Math.max(4, context.width - 200), x));
        this.y = Math.max(Theme.TOP_BAR_HEIGHT + 4,
            Math.min(Math.max(Theme.TOP_BAR_HEIGHT + 4, context.height - 92), y));
        visible = true;
    }

    public function close():Void {
        visible = false;
        dragPreviewBackground.visible = false;
        dragPreview.visible = false;
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
                    }
                    dragPreviewBackground.x = mouseX + 8;
                    dragPreviewBackground.y = mouseY + 6;
                    dragPreviewBackground.visible = dragPreview.visible;
                    dragPreview.x = mouseX + 12;
                    dragPreview.y = mouseY + 10;
                    captured.propagate = false;
                case ERelease, EReleaseOutside:
                    var wasDrag = dragPreview.visible;
                    var mouseX = context.window.mouseX;
                    var mouseY = context.window.mouseY;
                    cubeRow.stopCapture();
                    if (wasDrag && viewport != null
                        && mouseX >= viewport.x && mouseX < viewport.x + viewport.width
                        && mouseY >= viewport.y && mouseY < viewport.y + viewport.height) {
                        if (onDropCube != null) {
                            onDropCube(mouseX - viewport.x, mouseY - viewport.y);
                        }
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
