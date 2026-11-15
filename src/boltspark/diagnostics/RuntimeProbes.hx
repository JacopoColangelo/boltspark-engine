package boltspark.diagnostics;

import boltspark.platform.NativeWindow;

/** Opt-in diagnostics kept outside the normal editor lifecycle/integration code. */
class RuntimeProbes {
    final performanceEnabled:Bool = Sys.getEnv("BOLTSPARK_PERF_PROBE") != null;
    final dpiEnabled:Bool = Sys.getEnv("BOLTSPARK_DPI_PROBE") != null;
    final deviceResetEnabled:Bool = Sys.getEnv("BOLTSPARK_DEVICE_RESET_PROBE") != null;
    var frameStats:Null<FrameStats>;
    var deviceResetFrames:Int = 0;
    var deviceResetRequested:Bool = false;

    public function new() {}

    public function start(window:hxd.Window, engine:h3d.Engine):Void {
        if (performanceEnabled) frameStats = new FrameStats(60);
        if (dpiEnabled) {
            Sys.println('[dpi] displayScale=${NativeWindow.displayScale(window)}'
                + ' client=${window.width}x${window.height}'
                + ' backbuffer=${engine.width}x${engine.height}');
        }
    }

    public function update(dt:Float, engine:h3d.Engine):Void {
        if (frameStats != null) {
            var report = frameStats.sample(dt);
            if (report != null) Sys.println(FrameStats.format(report));
        }
        if (deviceResetEnabled && !deviceResetRequested
                && ++deviceResetFrames >= 120) {
            var dx12 = Std.downcast(engine.driver, h3d.impl.DX12Driver);
            if (dx12 == null) throw "Device-reset probe requires h3d.impl.DX12Driver";
            deviceResetRequested = true;
            Sys.println("[device-reset] forcing Heaps DX12 context-loss path");
            dx12.forceDeviceError();
        }
    }

    public function contextRestored():Void {
        if (deviceResetEnabled) {
            Sys.println("[device-reset] DX12 context recreated and scene resources restored");
        }
    }

    public function shutdown():Void {
        if (frameStats == null) return;
        var report = frameStats.flush();
        if (report != null) Sys.println(FrameStats.format(report));
    }
}
