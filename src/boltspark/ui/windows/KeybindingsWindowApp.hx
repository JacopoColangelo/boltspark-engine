package boltspark.ui.windows;

import boltspark.editor.Keybindings;
import boltspark.platform.InteractiveResize;
import boltspark.platform.NativeWindow;
import boltspark.ui.AppIcon;
import boltspark.ui.InputAdapter;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import sys.thread.Deque;
import sys.thread.Thread;

/** Dedicated native hldx/DX12 application window for editor keybindings. */
class KeybindingsWindowApp extends hxd.App {
    var nativeWindow:hxd.Window;
    var keybindings:Keybindings;
    var content:KeybindingsWindowContent;
    final controlCommands = new Deque<String>();
    var hosted:Bool = false;
    var windowVisible:Bool = true;
    var quitting:Bool = false;

    override function init():Void {
        InteractiveResize.install();
        hxd.Res.initEmbed();
        nativeWindow = hxd.Window.getInstance();
        AppIcon.applyToWindow(nativeWindow);
        hosted = ApplicationWindowProtocol.isHosted(Sys.args());
        var ownerProcessId = ApplicationWindowProtocol.ownerProcessId(Sys.args());
        if (ownerProcessId != null) {
            NativeWindow.setOwnerProcess(nativeWindow, ownerProcessId);
        }
        nativeWindow.title = "Editor Keybindings — Boltspark Engine";
        nativeWindow.vsync = true;
        nativeWindow.resize(KeybindingsWindowContent.DEFAULT_WIDTH,
            KeybindingsWindowContent.DEFAULT_HEIGHT);

        #if hldx
        @:privateAccess {
            nativeWindow.window.setMinSize(KeybindingsWindowContent.MIN_WIDTH,
                KeybindingsWindowContent.MIN_HEIGHT);
            nativeWindow.window.setDarkMode(true);
            nativeWindow.window.center(true);
            if (hosted) nativeWindow.window.visible = false;
        }
        #end
        if (hosted) {
            windowVisible = false;
            nativeWindow.vsync = false;
        }

        engine.backgroundColor = 0xFF000000 | Theme.PANEL;
        s2d.defaultSmooth = false;
        keybindings = new Keybindings();
        var context = new UiContext(nativeWindow);
        content = new KeybindingsWindowContent(context, keybindings, s2d);
        var input = new InputAdapter(s2d, keybindings);
        input.onEscapePressed = closeWindow;
        nativeWindow.onClose = function() {
            keybindings.cancelCapture();
            if (hosted && !quitting) {
                hideWindow();
                return false;
            }
            InteractiveResize.uninstall();
            return true;
        };
        if (hosted) startControlReader();
        Sys.println("[window] Editor Keybindings native window ready");
    }

    override function update(dt:Float):Void {
        content.update();
        // If another editor instance changes the shared persisted map, keep
        // this window synchronized without stealing an active capture.
        keybindings.pollExternalChanges();
        if (hosted) {
            var command = controlCommands.pop(false);
            while (command != null) {
                handleControlCommand(command);
                command = controlCommands.pop(false);
            }
            // Hidden hosts retain their DX12 device and glyph cache but should
            // consume virtually no CPU while waiting to be shown again.
            if (!windowVisible && !quitting) Sys.sleep(0.05);
        }
    }

    override function onResize():Void {
        if (content != null) content.resize();
    }

    override function render(engine:h3d.Engine):Void {
        if (windowVisible) s2d.render(engine);
    }

    function closeWindow():Void {
        keybindings.cancelCapture();
        if (hosted) {
            hideWindow();
        } else {
            InteractiveResize.uninstall();
            nativeWindow.close();
        }
    }

    function startControlReader():Void {
        Thread.create(function() {
            try {
                var input = Sys.stdin();
                while (true) controlCommands.add(input.readLine());
            } catch (_:Dynamic) {
                // The parent process closing its pipe is also a quit request.
                controlCommands.add(ApplicationWindowProtocol.QUIT);
            }
        });
    }

    function handleControlCommand(command:String):Void {
        switch (StringTools.trim(command)) {
            case ApplicationWindowProtocol.SHOW:
                showWindow();
            case ApplicationWindowProtocol.QUIT:
                quitting = true;
                InteractiveResize.uninstall();
                nativeWindow.close();
            case _:
        }
    }

    function showWindow():Void {
        if (quitting) return;
        keybindings.pollExternalChanges();
        #if hldx
        @:privateAccess {
            nativeWindow.window.visible = true;
            nativeWindow.window.restore();
        }
        #end
        NativeWindow.activate(nativeWindow);
        nativeWindow.vsync = true;
        windowVisible = true;
    }

    function hideWindow():Void {
        keybindings.cancelCapture();
        #if hldx
        @:privateAccess nativeWindow.window.visible = false;
        #end
        nativeWindow.vsync = false;
        windowVisible = false;
    }
}
