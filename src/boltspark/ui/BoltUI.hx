package boltspark.ui;

import boltspark.ui.layout.LayoutRect;

/**
 * BoltUI foundation facade.
 *
 * This is a native H2D implementation layered over the Heaps 2D scene —
 * it is not the final immediate-mode API, and it is not HTML, DOM, CSS,
 * Electron, NW.js, CEF, or a WebView of any kind.
 *
 * Structure:
 *  - Theme        — tokens (colors, metrics)
 *  - UiContext    — shared window/font state handed to widgets
 *  - InputAdapter — central keyboard/focus/pointer reporting (Gate 3)
 *  - widgets/     — button, stepper, swatch picker, console panel
 *  - EditorShell  — editor chrome: top bar, hierarchy, viewport, inspector,
 *                   console, status bar
 *
 * The facade keeps Main simple: build, wire editor commands, update per frame.
 */
class BoltUI {
    final ctx:UiContext;
    final shell:EditorShell;

    /** Editor commands forwarded to the engine by Main. */
    public var onTestAction:Null<Void->Void>;
    public var onSpinSpeedChanged:Null<Float->Void>;
    public var onColorChanged:Null<Int->Void>;
    public var onViewportClick:Null<Float->Float->Void>;

    public function new(parent:h2d.Scene, window:hxd.Window) {
        ctx = new UiContext(window, hxd.res.DefaultFont.get());
        var input = new InputAdapter(parent);
        shell = new EditorShell(parent, ctx, input);
        shell.onTestAction = function() if (onTestAction != null) onTestAction();
        shell.onSpinSpeedChanged = function(v) if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        shell.onColorChanged = function(c) if (onColorChanged != null) onColorChanged(c);
        shell.onViewportClick = function(x, y) if (onViewportClick != null) onViewportClick(x, y);
    }

    /** Editor console access. */
    public function log(line:String):Void {
        shell.log(line);
    }

    /** Called once per app frame. Re-layout only when the OS window changes size. */
    public function update(dt:Float):Void {
        shell.update(dt);
    }

    /** Rebuild static 2D chrome in response to a native window resize. */
    public function resize():Void {
        shell.resize();
    }

    public function getViewportRect():LayoutRect {
        return shell.viewportRect;
    }

    public function setSampleCubeSelected(selected:Bool):Void {
        shell.setSampleCubeSelected(selected);
    }
}
