package boltspark.ui.render;

/** Executes a pooled BoltUI draw list into one retained H2D Graphics object. */
class H2dDrawRenderer {
    public function new() {}

    public function render(list:UiDrawList, target:h2d.Graphics):Void {
        target.clear();
        for (index in 0...list.count) {
            var command = list.get(index);
            switch (command.kind) {
                case FillRect:
                    target.beginFill(command.color, command.alpha);
                    target.drawRect(command.x1, command.y1, command.x2, command.y2);
                    target.endFill();
                case StrokeRect:
                    target.lineStyle(command.thickness, command.color, command.alpha);
                    target.drawRect(command.x1, command.y1, command.x2, command.y2);
                    target.lineStyle();
                case Line:
                    target.lineStyle(command.thickness, command.color, command.alpha);
                    target.moveTo(command.x1, command.y1);
                    target.lineTo(command.x2, command.y2);
                    target.lineStyle();
            }
        }
    }
}
