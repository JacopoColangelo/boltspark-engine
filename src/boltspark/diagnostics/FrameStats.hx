package boltspark.diagnostics;

typedef FrameStatsReport = {
    final seconds:Float;
    final frames:Int;
    final averageMs:Float;
    final minimumMs:Float;
    final maximumMs:Float;
    final fps:Float;
}

/** Allocation-free rolling update/frame-time statistics for explicit probes. */
class FrameStats {
    final intervalSeconds:Float;
    var elapsed:Float = 0;
    var frames:Int = 0;
    var total:Float = 0;
    var minimum:Float = Math.POSITIVE_INFINITY;
    var maximum:Float = 0;

    public function new(intervalSeconds:Float = 60) {
        if (intervalSeconds <= 0 || !Math.isFinite(intervalSeconds)) {
            throw "Frame statistics interval must be finite and positive";
        }
        this.intervalSeconds = intervalSeconds;
    }

    public function sample(dt:Float):Null<FrameStatsReport> {
        if (dt < 0 || !Math.isFinite(dt)) return null;
        elapsed += dt;
        frames++;
        total += dt;
        if (dt < minimum) minimum = dt;
        if (dt > maximum) maximum = dt;
        return elapsed >= intervalSeconds ? flush() : null;
    }

    public function flush():Null<FrameStatsReport> {
        if (frames == 0) return null;
        var report:FrameStatsReport = {
            seconds: elapsed,
            frames: frames,
            averageMs: total * 1000 / frames,
            minimumMs: minimum * 1000,
            maximumMs: maximum * 1000,
            fps: elapsed <= 0 ? 0 : frames / elapsed
        };
        elapsed = 0;
        frames = 0;
        total = 0;
        minimum = Math.POSITIVE_INFINITY;
        maximum = 0;
        return report;
    }

    public static function format(report:FrameStatsReport):String {
        return '[perf] seconds=${round(report.seconds)} frames=${report.frames}'
            + ' avgFrameMs=${round(report.averageMs)} minFrameMs=${round(report.minimumMs)}'
            + ' maxFrameMs=${round(report.maximumMs)} fps=${round(report.fps)}';
    }

    static inline function round(value:Float):Float {
        return Math.round(value * 1000) / 1000;
    }
}
