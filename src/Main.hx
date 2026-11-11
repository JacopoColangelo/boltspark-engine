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
    var lastWindowWidth:Int = -1;
    var lastWindowHeight:Int = -1;
    var spinSpeed:Float = 0.35;

    override function init():Void {
        nativeWindow = hxd.Window.getInstance();
        nativeWindow.title = "Boltspark Engine — Native Foundation";
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
        sampleCube.setPosition(0, 0, 0);
        sampleCube.material.color.setColor(boltspark.ui.Theme.CUBE_ORANGE);

        s3d.camera.pos.set(5, 5, 5);
        s3d.camera.setFovX(70, nativeWindow.width / Math.max(1, nativeWindow.height));
        lastWindowWidth = nativeWindow.width;
        lastWindowHeight = nativeWindow.height;

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        boltUI = new BoltUI(s2d, nativeWindow);
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
    }

    override function update(dt:Float):Void {
        boltUI.update(dt);

        if (nativeWindow.width != lastWindowWidth || nativeWindow.height != lastWindowHeight) {
            lastWindowWidth = nativeWindow.width;
            lastWindowHeight = nativeWindow.height;
            s3d.camera.setFovX(70, nativeWindow.width / Math.max(1, nativeWindow.height));
        }

        // Visible motion confirms the 3D update path is alive; the editor
        // controls the rate through the inspector stepper.
        sampleCube.rotate(0.0, 0.0, dt * spinSpeed);
    }

    static function main():Void {
        new Main();
    }
}
