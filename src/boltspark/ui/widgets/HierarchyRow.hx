package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;

class HierarchyRow extends h2d.Object {
    public var objectId:Int;
    public var onWheel:Null<Float->Void>;
    public var onSelect:Null<Int->Bool->Bool->Void>;
    public var onContextMenu:Null<Void->Void>;

    final surface:UiSurface;
    final background:h2d.Interactive;
    final selectionEdge:h2d.Graphics;
    final disclosure:h2d.Graphics;
    final objectIcon:h2d.Graphics;
    final label:h2d.Text;
    var fullName:String;
    var selected:Bool = false;
    var hovered:Bool = false;

    public function new(ctx:UiContext, objectId:Int, name:String, ?parent:h2d.Object) {
        super(parent);
        this.objectId = objectId;
        fullName = name;

        surface = new UiSurface(ctx, this);
        surface.visible = false;
        background = new h2d.Interactive(1, 22, this);
        background.cursor = hxd.Cursor.Default;
        background.backgroundColor = 0;
        background.enableRightButton = true;
        background.onOver = function(_) {
            hovered = true;
            updateStyle();
        };
        background.onOut = function(_) {
            hovered = false;
            updateStyle();
        };
        background.onClick = function(event) {
            if (event.button == 1) {
                if (onContextMenu != null) onContextMenu();
                event.propagate = false;
            } else if (onSelect != null) {
                onSelect(this.objectId, hxd.Key.isDown(hxd.Key.CTRL),
                    hxd.Key.isDown(hxd.Key.SHIFT));
            }
        };
        background.onWheel = function(event) {
            if (onWheel == null) return;
            onWheel(event.wheelDelta);
            event.propagate = false;
        };

        selectionEdge = new h2d.Graphics(this);
        disclosure = new h2d.Graphics(this);
        UiIcons.draw(disclosure, ChevronRight, 0, 0, 11, Theme.MUTED);
        disclosure.x = 5;
        disclosure.y = 6;
        objectIcon = new h2d.Graphics(this);
        UiIcons.draw(objectIcon, Cube, 0, 0, 13, Theme.TEXT_SECONDARY);
        objectIcon.x = 21;
        objectIcon.y = 5;

        label = new UiText(ctx.font, this);
        label.x = 41;
        label.textColor = Theme.TEXT;
        label.lineBreak = false;
        setName(name);
        // The exact-size Inter face has a 22px line box, matching this row.
        // Center from the font metrics instead of retaining the old 4px offset
        // that placed the visible glyphs below the cube icon.
        ctx.centerY(label, 0, background.height);
    }

    public function setName(name:String):Void {
        fullName = name;
        fitLabel(background.width - label.x - 8);
    }

    public function setBounds(x:Float, y:Float, width:Float, selected:Bool):Void {
        this.x = x;
        this.y = y;
        this.selected = selected;
        background.width = width;
        surface.setSize(width, background.height);
        updateStyle();
        fitLabel(width - label.x - 8);
    }

    function updateStyle():Void {
        surface.visible = selected || hovered;
        if (selected) {
            surface.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT_MUTED, 0, 0);
        } else if (hovered) {
            surface.setStyle(Theme.SURFACE_2, Theme.SURFACE_2, 0, 0);
        }
        label.textColor = selected ? 0xF3F7FF : Theme.TEXT;
        selectionEdge.clear();
        if (selected) {
            selectionEdge.beginFill(Theme.ACCENT);
            selectionEdge.drawRect(0, 0, 2, background.height);
            selectionEdge.endFill();
        }
    }

    function fitLabel(maxWidth:Float):Void {
        if (maxWidth <= 0) {
            label.text = "";
            return;
        }
        label.text = fullName;
        if (label.calcTextWidth(fullName) <= maxWidth) return;
        label.text = "";
        for (i in 0...fullName.length) {
            var candidate = fullName.substr(0, i + 1) + "...";
            if (label.calcTextWidth(candidate) > maxWidth) break;
            label.text = candidate;
        }
    }
}
