package boltspark.ui.windows;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;

private typedef ManagedApplicationWindow = {
    var process:Process;
    var shown:Bool;
}

/**
 * Launches and owns native top-level editor windows.
 *
 * Heaps 2.1's DX12 driver binds one swap chain to one process. Starting the
 * same application with a window route gives every detached editor window a
 * real HWND and its own DX12 swap chain without changing the locked driver.
 */
class ApplicationWindowManager {
    final processes:Map<String, ManagedApplicationWindow> = [];

    public function new() {
    }

    /** Start a hidden host early so a subsequent open only has to show it. */
    public function prepare(kind:ApplicationWindowKind):Null<String> {
        discardCompleted();
        var key:String = kind;
        if (processes.exists(key)) return null;
        return launchHost(kind);
    }

    /** Open one instance of this application window and return a log message. */
    public function open(kind:ApplicationWindowKind):String {
        discardCompleted();
        var key:String = kind;
        var existing = processes.get(key);
        if (existing != null) {
            if (sendCommand(existing, ApplicationWindowProtocol.SHOW)) {
                var message = existing.shown
                    ? 'window: showed cached ${kind.displayName()} window'
                    : 'window: opened ${kind.displayName()} as a separate native window';
                existing.shown = true;
                return message;
            }
            closeHandle(existing);
            processes.remove(key);
        }

        var launchError = launchHost(kind);
        if (launchError != null) return launchError;
        var managed = processes.get(key);
        if (!sendCommand(managed, ApplicationWindowProtocol.SHOW)) {
            closeHandle(managed);
            processes.remove(key);
            return 'window: could not initialize ${kind.displayName()}';
        }
        managed.shown = true;
        return 'window: opened ${kind.displayName()} as a separate native window';
    }

    function launchHost(kind:ApplicationWindowKind):Null<String> {
        var key:String = kind;

        var program = Sys.programPath();
        var command = program;
        var arguments = [kind.commandArgument(), ApplicationWindowProtocol.HOST_ARGUMENT];
        // In development Sys.programPath() is the .hl bytecode. Native builds
        // return Boltspark.exe directly. The child therefore uses the current
        // HashLink VM only when this process is itself running bytecode.
        if (Path.extension(program).toLowerCase() == "hl") {
            var repository = Path.directory(Path.directory(program));
            var projectRuntime = Path.join([repository, "toolchain", "hashlink", "hl.exe"]);
            command = FileSystem.exists(projectRuntime) ? projectRuntime : "hl.exe";
            arguments.unshift(program);
        }

        try {
            // The piped process starts hidden, then receives `show` over stdin
            // once its native window host is ready. Keeping that process and
            // HWND alive lets close/reopen reuse the DX12 device and font cache.
            var managed:ManagedApplicationWindow = {
                process: new Process(command, arguments, false),
                shown: false
            };
            processes.set(key, managed);
            return null;
        } catch (error:Dynamic) {
            return 'window: could not open ${kind.displayName()}: ${Std.string(error)}';
        }
    }

    /** Reap child handles after a host process exits unexpectedly. */
    public function update():Void {
        discardCompleted();
    }

    /** Close auxiliary windows when the main editor exits. */
    public function shutdown():Void {
        for (managed in processes) {
            sendCommand(managed, ApplicationWindowProtocol.QUIT);
            closeHandle(managed);
        }
        processes.clear();
    }

    function discardCompleted():Void {
        var completed:Array<String> = [];
        for (key => managed in processes) {
            var finished = false;
            try {
                finished = managed.process.exitCode(false) != null;
            } catch (_:Dynamic) {
                finished = true;
            }
            if (!finished) continue;
            closeHandle(managed);
            completed.push(key);
        }
        for (key in completed) processes.remove(key);
    }

    function sendCommand(managed:ManagedApplicationWindow, command:String):Bool {
        try {
            managed.process.stdin.writeString(command + "\n");
            managed.process.stdin.flush();
            return true;
        } catch (_:Dynamic) {
            return false;
        }
    }

    function closeHandle(managed:ManagedApplicationWindow):Void {
        try {
            managed.process.close();
        } catch (_:Dynamic) {
        }
    }
}
