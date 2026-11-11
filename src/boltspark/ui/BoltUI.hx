package boltspark.ui;

import boltspark.ui.layout.LayoutRect;
import boltspark.ui.HierarchyEntry;

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
    public var onCreateObject:Null<Void->Void>;
    public var onCreateObjectAt:Null<Float->Float->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onSpinSpeedChanged:Null<Float->Void>;
    public var onColorChanged:Null<Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onViewportClick:Null<Float->Float->Void>;

    public function new(parent:h2d.Scene, window:hxd.Window) {
        ctx = new UiContext(window);
        var input = new InputAdapter(parent);
        shell = new EditorShell(parent, ctx, input);
        shell.onCreateObject = function() if (onCreateObject != null) onCreateObject();
        shell.onCreateObjectAt = function(x, y) if (onCreateObjectAt != null) onCreateObjectAt(x, y);
        shell.onDeleteObjects = function(ids) if (onDeleteObjects != null) onDeleteObjects(ids);
        shell.onObjectsSelected = function(ids, primary) {
            if (onObjectsSelected != null) onObjectsSelected(ids, primary);
        };
        shell.onSpinSpeedChanged = function(v) if (onSpinSpeedChanged != null) onSpinSpeedChanged(v);
        shell.onColorChanged = function(c) if (onColorChanged != null) onColorChanged(c);
        shell.onObjectNameChanged = function(name) if (onObjectNameChanged != null) onObjectNameChanged(name);
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

    public function setHierarchyEntries(entries:Array<HierarchyEntry>):Void {
        shell.setHierarchyEntries(entries);
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, speed:Float, color:Int, posX:Float = 0, posY:Float = 0,
            posZ:Float = 0):Void {
        shell.setSelectedObjects(ids, primaryId, name, speed, color, posX, posY, posZ);
    }

    public function setObjectName(name:String):Void {
        shell.setObjectName(name);
    }
}
