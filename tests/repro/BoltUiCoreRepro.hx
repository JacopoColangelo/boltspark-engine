import boltspark.ui.core.UiFrame;
import boltspark.ui.layout.BoxLayout;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.render.UiDrawList;
import boltspark.diagnostics.FrameStats;

/** Headless contract tests for stable IDs, input, layout, and draw pooling. */
class BoltUiCoreRepro {
    static function main():Void {
        var frame = new UiFrame();
        frame.begin(800, 600, "test");
        frame.pushScope("panel");
        var id = frame.register("button", new LayoutRect(0, 0, 80, 24));
        frame.setState(id, 41);
        frame.register("button", new LayoutRect(0, 0, 80, 24));
        frame.popScope();
        var diagnostics = frame.end();
        assertTrue(has(diagnostics, "duplicate widget ID"), "duplicate ID was not diagnosed");

        frame.begin(800, 600, "test");
        frame.pushScope("panel");
        var same = frame.register("button", new LayoutRect(0, 0, 80, 24));
        assertTrue(id.path == same.path && id.hash == same.hash, "widget ID was not stable");
        assertTrue(frame.state(same, function() return 0) == 41, "persistent state was lost");
        frame.popScope();
        assertTrue(frame.end().length == 0, "valid frame emitted diagnostics");

        frame.begin(10, 10);
        frame.pushScope("forgotten");
        assertTrue(has(frame.end(), "unbalanced ID scopes"), "unbalanced scope was not diagnosed");

        frame.begin(10, 10);
        frame.begin(10, 10);
        assertTrue(has(frame.end(), "previous frame ended"), "nested begin was not diagnosed");

        frame.input.keyDown(65);
        assertTrue(frame.input.isKeyDown(65), "key-down state missing");
        frame.input.keyUp(65);
        frame.input.keyUp(66);
        assertTrue(frame.input.orphanKeyUps == 1, "orphan key-up was not recorded");

        var row = BoxLayout.row(new LayoutRect(0, 0, 300, 20), [50, 0, 0], 5);
        assertNear(row[0].width, 50, "fixed row width");
        assertNear(row[1].width, 120, "first flexible row width");
        assertNear(row[2].x, 180, "second flexible row x");
        var stack = BoxLayout.stack(new LayoutRect(0, 0, 100, 80), 2, 4);
        assertNear(stack[0].width, 92, "stack inset width");

        var draw = new UiDrawList();
        draw.fillRect(new LayoutRect(0, 0, 10, 10), 0xFFFFFF);
        var pooled = draw.get(0);
        draw.reset();
        draw.line(0, 0, 1, 1, 0);
        assertTrue(draw.get(0) == pooled, "draw command was allocated instead of reused");

        var stats = new FrameStats(0.03);
        assertTrue(stats.sample(0.01) == null, "frame report flushed too early");
        stats.sample(0.01);
        var report = stats.sample(0.01);
        assertTrue(report != null && report.frames == 3, "frame report sample count mismatch");
        assertNear(report.averageMs, 10, "average frame time");

        Sys.println("[bolt-ui-core] IDs, frame state, input, layout, draw pooling, and frame stats passed");
    }

    static function has(messages:Array<String>, fragment:String):Bool {
        for (message in messages) if (message.indexOf(fragment) >= 0) return true;
        return false;
    }

    static function assertNear(actual:Float, expected:Float, label:String):Void {
        if (Math.abs(actual - expected) > 0.000001) {
            throw '${label}: expected ${expected}, got ${actual}';
        }
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
