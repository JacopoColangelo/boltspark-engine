package boltspark.ui.windows;

import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiText;
import boltspark.ui.widgets.NumericDragField;
import boltspark.ui.widgets.UiCheckbox;

/**
 * Generic snapshot-driven view for a dock panel hosted in its own native
 * window. It never touches editor state directly: rows come from the parent
 * process and every interaction is reported back through `send`.
 */
class DockPanelWindowContent {
    public var send:Dynamic->Void = function(_) {};

    final ctx:UiContext;
    final panelId:String;
    final root:h2d.Object;
    final background:h2d.Graphics;
    final rowLayer:h2d.Object;
    final header:UiText;
    final consoleText:UiText;
    var rows:Array<Dynamic> = [];

    public function new(ctx:UiContext, panelId:String, title:String,
            parent:h2d.Object) {
        this.ctx = ctx;
        this.panelId = panelId;
        root = new h2d.Object(parent);
        background = new h2d.Graphics(root);
        rowLayer = new h2d.Object(root);
        header = new UiText(ctx.semiboldFont, root);
        header.text = title;
        header.textColor = Theme.TEXT;
        header.lineBreak = false;
        consoleText = new UiText(ctx.monoFont, root);
        consoleText.textColor = Theme.TEXT_SECONDARY;
        consoleText.lineBreak = false;
        resize();
    }

    public function applySnapshot(data:Dynamic):Void {
        rows = [];
        rowLayer.removeChildren();
        consoleText.visible = false;
        header.visible = true;
        if (data == null || !Reflect.isObject(data)) {
            resize();
            return;
        }
        var title = Reflect.field(data, "title");
        if (Std.isOfType(title, String)) header.text = title;
        var lines:Dynamic = Reflect.field(data, "lines");
        if (lines != null && Std.isOfType(lines, Array)) {
            header.visible = false;
            consoleText.visible = true;
            var lineArray:Array<Dynamic> = cast lines;
            consoleText.text = [for (line in lineArray) Std.string(line)].join("\n");
            resize();
            return;
        }
        var entries:Dynamic = Reflect.field(data, "rows");
        if (entries == null || !Std.isOfType(entries, Array)) {
            resize();
            return;
        }
        for (entry in cast(entries, Array<Dynamic>)) {
            if (!Reflect.isObject(entry)) continue;
            rows.push(entry);
            buildRow(entry);
        }
        resize();
    }

    function report(id:String, value:Dynamic):Void {
        send({cmd: "edit", panelId: panelId, id: id, value: value});
    }

    function buildRow(entry:Dynamic):Void {
        var kind = Std.string(Reflect.field(entry, "kind"));
        var label = Std.string(Reflect.field(entry, "label"));
        var id = Std.string(Reflect.field(entry, "id"));
        var value = Reflect.field(entry, "value");
        if (kind == "number") {
            var valueText = Std.string(value);
            var parsed = Std.parseFloat(valueText);
            if (!Math.isFinite(parsed)) parsed = 0;
            var minValue = numberField(entry, "min", -100000, 100000, -100000);
            var maxValue = numberField(entry, "max", -100000, 100000, 100000);
            var stepValue = numberField(entry, "step", 0.001, 1000, 0.01);
            var field = new NumericDragField(ctx, 118, Theme.CONTROL_HEIGHT,
                minValue, maxValue, stepValue, parsed,
                function(v:Float):String return Std.string(Math.round(v * 1000) / 1000),
                "", Theme.TEXT, rowLayer);
            field.name = "row:" + id;
            field.onValueChanged = function(v:Float) report(id, v);
            var caption = new UiText(ctx.captionFont, rowLayer);
            caption.text = label;
            caption.textColor = Theme.TEXT_SECONDARY;
            caption.lineBreak = false;
            caption.name = "label:" + id;
            return;
        }
        if (kind == "bool") {
            var checkbox = new UiCheckbox(ctx, label, rowLayer, ctx.captionFont);
            checkbox.name = "row:" + id;
            checkbox.value = Std.isOfType(value, Bool) ? value : false;
            checkbox.onChanged = function(v:Bool) report(id, v);
            return;
        }
        var row = new h2d.Interactive(1, 1, rowLayer);
        row.backgroundColor = 0;
        row.cursor = hxd.Cursor.Default;
        row.name = "row:" + id;
        row.onPush = function(event) {
            if (event.button != 0) return;
            event.propagate = false;
            report(id, "click");
        };
        var text = new UiText(ctx.captionFont, rowLayer);
        text.text = label;
        text.textColor = Reflect.field(entry, "selected") == true
            ? Theme.ACCENT : Theme.TEXT_SECONDARY;
        text.lineBreak = false;
        text.name = "label:" + id;
    }

    static function numberField(data:Dynamic, field:String, fallback:Float,
            min:Float, max:Float):Float {
        var value = Reflect.field(data, field);
        if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) return fallback;
        var number:Float = value;
        return number == number && number >= min && number <= max ? number : fallback;
    }

    public function resize():Void {
        var width = ctx.width;
        var height = ctx.height;
        background.clear();
        background.beginFill(Theme.PANEL, 1);
        background.drawRect(0, 0, width, height);
        background.endFill();
        header.x = 10;
        header.y = 8;
        consoleText.x = 8;
        consoleText.y = 8;
        var y = header.visible ? 34 : 8;
        for (index in 0...rows.length) {
            var entry = rows[index];
            var id = Std.string(Reflect.field(entry, "id"));
            var label = findChild("label:" + id);
            var control = findChild("row:" + id);
            var depthValue = Reflect.field(entry, "depth");
            var depth = Std.isOfType(depthValue, Int) ? depthValue : 0;
            var indent = 8 + depth * 14;
            if (label != null) {
                label.x = indent;
                label.y = y + 5;
            }
            if (control != null) {
                control.x = indent;
                control.y = y;
                var interactive = Std.downcast(control, h2d.Interactive);
                if (interactive != null) {
                    interactive.width = Math.max(1, width - indent - 8);
                    interactive.height = Theme.CONTROL_HEIGHT;
                } else if (Std.isOfType(control, boltspark.ui.widgets.NumericDragField)) {
                    cast(control, boltspark.ui.widgets.NumericDragField).setWidth(118);
                } else if (Std.isOfType(control, UiCheckbox)) {
                    cast(control, UiCheckbox).setWidth(Math.max(1, width - indent - 8));
                }
            }
            y += Theme.CONTROL_HEIGHT + 2;
        }
    }

    function findChild(name:String):Null<h2d.Object> {
        for (index in 0...rowLayer.numChildren) {
            var child = rowLayer.getChildAt(index);
            if (child.name == name) return child;
        }
        return null;
    }

    public function update():Void {}
}
