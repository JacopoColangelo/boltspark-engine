package boltspark.ui.widgets;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;

class HierarchyRow extends h2d.Object {
    public var objectId:Int;
    public var onWheel:Null<Float->Void>;

    final background:h2d.Interactive;
    final selectionEdge:h2d.Graphics;
    final label:h2d.Text;
    var fullName:String;

    public function new(ctx:UiContext, objectId:Int, name:String, ?parent:h2d.Object) {
        super(parent);
        this.objectId = objectId;
        fullName = name;

        background = new h2d.Interactive(1, 26, this);
        background.cursor = hxd.Cursor.Button;
        background.backgroundColor = 0;
        background.onClick = function(_) {
            if (onSelect != null) {
                onSelect(this.objectId, hxd.Key.isDown(hxd.Key.CTRL), hxd.Key.isDown(hxd.Key.SHIFT));
            }
        };
        background.onWheel = function(event) {
            if (onWheel == null) return;
            onWheel(event.wheelDelta);
            event.propagate = false;
        };

        label = new h2d.Text(ctx.font, this);
        label.x = 12;
        label.y = 6;
        label.textColor = Theme.TEXT;
        label.lineBreak = false;
        selectionEdge = new h2d.Graphics(this);
        setName(name);
    }

    public var onSelect:Null<Int->Bool->Bool->Void>;

    public function setName(name:String):Void {
        fullName = name;
        fitLabel(background.width);
    }

    public function setBounds(x:Float, y:Float, width:Float, selected:Bool):Void {
        this.x = x;
        this.y = y;
        background.width = width;
        background.backgroundColor = selected ? Theme.BUTTON_ACTIVE : 0;
        label.textColor = selected ? Theme.ACCENT : Theme.TEXT;
        selectionEdge.clear();
        if (selected) {
            selectionEdge.beginFill(Theme.ACCENT);
            selectionEdge.drawRect(0, 0, 3, background.height);
            selectionEdge.endFill();
        }
        fitLabel(width - label.x - 8);
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
