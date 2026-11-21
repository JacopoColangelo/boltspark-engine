package boltspark.ui.windows;

import boltspark.platform.InteractiveResize;
import boltspark.platform.NativeWindow;
import boltspark.ui.AppIcon;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import sys.thread.Deque;
import sys.thread.Thread;

/**
 * Dedicated native HWND + DX12 host for one floating dock panel. All panel
 * state arrives as JSON snapshots from the editor; edits are reported back.
 */
class DockPanelWindowApp extends hxd.App {
    final commands = new Deque<String>();
    var nativeWindow:hxd.Window;
    var content:DockPanelWindowContent;
    var panelId:String = "";
    var title:String = "Dock Panel";
    var hosted:Bool = false;
    var windowVisible:Bool = true;
    var quitting:Bool = false;

    override function init():Void {
        InteractiveResize.install();
        hxd.Res.initEmbed();
        nativeWindow = hxd.Window.getInstance();
        AppIcon.applyToWindow(nativeWindow);
        hosted = ApplicationWindowProtocol.isHosted(Sys.args());
        panelId = ApplicationWindowProtocol.dockPanelId(Sys.args()) == null
            ? "unknown" : ApplicationWindowProtocol.dockPanelId(Sys.args());
        title = ApplicationWindowProtocol.dockPanelTitle(Sys.args());
        var ownerProcessId = ApplicationWindowProtocol.ownerProcessId(Sys.args());
        if (ownerProcessId != null) NativeWindow.setOwnerProcess(nativeWindow, ownerProcessId);
        nativeWindow.title = title + " — Boltspark Engine";
        nativeWindow.vsync = false;
        nativeWindow.resize(360, 420);
        #if hldx
        @:privateAccess {
            nativeWindow.window.setMinSize(220, 180);
            nativeWindow.window.setDarkMode(true);
            if (hosted) nativeWindow.window.visible = false;
        }
        #end
        if (hosted) windowVisible = false;
        engine.backgroundColor = 0xFF000000 | Theme.PANEL;
        s2d.defaultSmooth = false;
        var context = new UiContext(nativeWindow);
        content = new DockPanelWindowContent(context, panelId, title, s2d);
        content.send = function(payload:Dynamic) send(payload);
        nativeWindow.onClose = function() {
            if (hosted && !quitting) {
                hideWindow();
                return false;
            }
            return true;
        };
        if (hosted) startReader();
        Sys.println('{"cmd":"ready","panelId":' + haxe.Json.stringify(panelId) + "}");
        Sys.stdout().flush();
    }

    override function update(dt:Float):Void {
        content.update();
        var command = commands.pop(false);
        while (command != null) {
            handleCommand(command);
            command = commands.pop(false);
        }
        if (!windowVisible && !quitting && hosted) Sys.sleep(0.05);
    }

    override function onResize():Void {
        if (content != null) content.resize();
    }

    override function render(engine:h3d.Engine):Void {
        if (windowVisible) s2d.render(engine);
    }

    function send(payload:Dynamic):Void {
        Sys.println(haxe.Json.stringify(payload));
        Sys.stdout().flush();
    }

    function startReader():Void {
        Thread.create(function() {
            try {
                var input = Sys.stdin();
                while (true) commands.add(input.readLine());
            } catch (_:Dynamic) {
                commands.add(ApplicationWindowProtocol.QUIT);
            }
        });
    }

    function handleCommand(raw:String):Void {
        var text = StringTools.trim(raw);
        if (text == "") return;
        if (text == ApplicationWindowProtocol.SHOW) {
            showWindow();
            return;
        }
        if (text == ApplicationWindowProtocol.QUIT) {
            quitting = true;
            InteractiveResize.uninstall();
            nativeWindow.close();
            return;
        }
        var data:Dynamic = null;
        try {
            data = haxe.Json.parse(text);
        } catch (_:Dynamic) {
            return;
        }
        if (!Reflect.isObject(data)) return;
        switch (Std.string(Reflect.field(data, "cmd"))) {
            case "snapshot":
                content.applySnapshot(Reflect.field(data, "data"));
            case "geometry":
                var x = fieldInt(data, "x", 0);
                var y = fieldInt(data, "y", 0);
                var w = fieldInt(data, "width", 360);
                var h = fieldInt(data, "height", 420);
                #if hldx
                @:privateAccess nativeWindow.window.setPosition(x, y);
                #end
                nativeWindow.resize(w, h);
            case _:
        }
    }

    static function fieldInt(data:Dynamic, field:String, fallback:Int):Int {
        var value = Reflect.field(data, field);
        if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) return fallback;
        var number:Float = value;
        return number == number ? Std.int(number) : fallback;
    }

    function showWindow():Void {
        if (quitting) return;
        #if hldx
        @:privateAccess {
            nativeWindow.window.visible = true;
            nativeWindow.window.restore();
        }
        #end
        NativeWindow.activate(nativeWindow);
        windowVisible = true;
        send({cmd: "shown", panelId: panelId});
    }

    function hideWindow():Void {
        #if hldx
        @:privateAccess nativeWindow.window.visible = false;
        #end
        windowVisible = false;
        send({cmd: "closed", panelId: panelId});
    }
}
