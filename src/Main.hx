import boltspark.ui.BoltUI;

/**
 * Windows-first native Boltspark bootstrap.
 *
 * hxd.App owns the Heaps application lifecycle and creates the default 2D and
 * 3D scenes. The HashLink target is launched by the HashLink VM; hldx supplies
 * Heaps' native DirectX backend. This project selects the DirectX 12 driver
 * with `-D dx12`. No browser, WebView, Electron, NW.js, CEF, or SDL backend
 * is part of this Windows-first application target.
 */
class Main extends hxd.App {
    var boltUI:BoltUI;
    var sampleCube:h3d.scene.Mesh;
    var nativeWindow:hxd.Window;
    var spinSpeed:Float = 0.35;

    @:hlNative("directx", "win_set_interactive_resize_callback")
    static function setInteractiveResizeCallback(callback:Void->Void):Void return;

    static function interactiveResizeFrame():Void {
        try {
            @:privateAccess hxd.System.mainLoop();
        } catch (error:Dynamic) {
            Sys.println('[resize] frame failed: ${Std.string(error)}');
            setInteractiveResizeCallback(null);
        }
    }

    override function init():Void {
        setInteractiveResizeCallback(interactiveResizeFrame);
        nativeWindow = hxd.Window.getInstance();
        nativeWindow.title = "Boltspark Engine";
        nativeWindow.vsync = true;

        // M0 evidence: log which Heaps driver backend is actually running.
        var engine = h3d.Engine.getCurrent();
        var driverName = Type.getClassName(Type.getClass(engine.driver));
        Sys.println('[M0] renderer driver = ${driverName}');

        // Minimal 3D proof: a real Heaps mesh rendered by the native 3D scene.
        var cubePrimitive = new h3d.prim.Cube(1, 1, 1, true);
        cubePrimitive.addNormals();
        cubePrimitive.addUVs();

        sampleCube = new h3d.scene.Mesh(cubePrimitive, s3d);
        sampleCube.name = "sampleCube";
        sampleCube.setPosition(0, 0, 0);
        sampleCube.material.color.setColor(boltspark.ui.Theme.CUBE_ORANGE);

        s3d.camera.pos.set(5, 5, 5);

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        boltUI = new BoltUI(s2d, nativeWindow);
        boltUI.onViewportClick = onViewportClick;
        boltUI.log('renderer driver: ${driverName}');
        boltUI.log("editor shell ready — hierarchy, inspector, console live");

        // Editor commands flow UI -> command -> engine object; widgets never
        // mutate engine state directly.
        boltUI.onTestAction = function() {
            boltUI.log("command: test native input (click registered)");
        };
        boltUI.onSpinSpeedChanged = function(v:Float) {
            spinSpeed = v;
            boltUI.log("command: spin speed = " + Std.string(v));
        };
        boltUI.onColorChanged = function(color:Int) {
            sampleCube.material.color.setColor(color);
            boltUI.log("command: cube base color = 0x" + StringTools.hex(color, 6));
        };
        boltUI.onObjectNameChanged = function(name:String) {
            sampleCube.name = name;
            boltUI.setObjectName(name);
            boltUI.log("command: object name = " + name);
        };
    }

    override function update(dt:Float):Void {
        boltUI.update(dt);

        // Visible motion confirms the 3D update path is alive; the editor
        // controls the rate through the inspector stepper.
        sampleCube.rotate(0.0, 0.0, dt * spinSpeed);
    }

    override function render(engine:h3d.Engine):Void {
        var viewport = boltUI.getViewportRect();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        var x = Std.int(Math.round(viewport.x * scaleX));
        var y = Std.int(Math.round(viewport.y * scaleY));
        var width = Std.int(Math.max(0, Math.round(viewport.width * scaleX)));
        var height = Std.int(Math.max(0, Math.round(viewport.height * scaleY)));
        if (width > 0 && height > 0) {
            var centerX = x + width * 0.5;
            var centerY = y + height * 0.5;
            s3d.camera.setFovX(70, engine.width / engine.height);
            s3d.camera.viewX = centerX * 2 / engine.width - 1;
            s3d.camera.viewY = 1 - centerY * 2 / engine.height;
            engine.setRenderZone(x, y, width, height);
            s3d.render(engine);
            engine.setRenderZone();
        }
        s2d.render(engine);
    }

    function onViewportClick(x:Float, y:Float):Void {
        var viewport = boltUI.getViewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        var ray = s3d.camera.rayFromScreen(
            (viewport.x + x) * scaleX,
            (viewport.y + y) * scaleY,
            engine.width,
            engine.height);
        var collider = sampleCube.getCollider();
        var hit = collider != null && collider.rayIntersection(ray, true) >= 0;
        boltUI.setSampleCubeSelected(hit);
        boltUI.log(hit ? "viewport: selected sampleCube" : "viewport: no object at pointer");
    }

    static function main():Void {
        new Main();
    }
}
