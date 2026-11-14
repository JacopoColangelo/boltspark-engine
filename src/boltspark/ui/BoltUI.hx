package boltspark.ui;

import boltspark.editor.GridSnapping;
import boltspark.editor.Keybindings;
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
 *  - widgets/     — buttons, transform fields, hierarchy, console panel
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
    public var onObjectNameChanged:Null<String->Void>;
    public var onTransformChanged:Null<Int->Float->Void>;
    public var onRotationChanged:Null<Int->Float->Void>;
    public var onScaleChanged:Null<Int->Float->Void>;
    /** Row index: 0 Position, 1 Rotation, 2 Scale. */
    public var onTransformReset:Null<Int->Void>;
    public var onScaleLinkChanged:Null<Bool->Void>;
    public var onViewportClick:Null<Float->Float->Void>;
    public var onToolChanged:Null<Int->Void>;
    public var onTransformSpaceChanged:Null<Bool->Void>;
    public var onViewportHover:Null<Float->Float->Void>;
    public var onViewportPush:Null<Float->Float->Bool>;
    public var onViewportDrag:Null<Float->Float->Void>;
    public var onViewportRelease:Null<Float->Float->Void>;
    /** Fired when the viewport snap bar toggles or changes a preset. */
    public var onSnapChanged:Null<Int->Void>;
    /** Ctrl+End: snap the primary selection onto the translation grid. */
    public var onSnapToGrid:Null<Void->Void>;
    /** Hold key (default V): true while held to suspend translation snapping. */
    public var onSnapHoldChanged:Null<Bool->Void>;

    public function new(parent:h2d.Scene, window:hxd.Window, snapping:GridSnapping,
            keybindings:Keybindings) {
        ctx = new UiContext(window);
        var input = new InputAdapter(parent, keybindings);
        shell = new EditorShell(parent, ctx, input, snapping, keybindings);
        shell.onCreateObject = function() if (onCreateObject != null) onCreateObject();
        shell.onCreateObjectAt = function(x, y) if (onCreateObjectAt != null) onCreateObjectAt(x, y);
        shell.onDeleteObjects = function(ids) if (onDeleteObjects != null) onDeleteObjects(ids);
        shell.onObjectsSelected = function(ids, primary) {
            if (onObjectsSelected != null) onObjectsSelected(ids, primary);
        };
        shell.onObjectNameChanged = function(name) if (onObjectNameChanged != null) onObjectNameChanged(name);
        shell.onTransformChanged = function(axis, value) if (onTransformChanged != null) onTransformChanged(axis, value);
        shell.onRotationChanged = function(axis, value) if (onRotationChanged != null) onRotationChanged(axis, value);
        shell.onScaleChanged = function(axis, value) if (onScaleChanged != null) onScaleChanged(axis, value);
        shell.onTransformReset = function(row) if (onTransformReset != null) onTransformReset(row);
        shell.onScaleLinkChanged = function(linked) {
            if (onScaleLinkChanged != null) onScaleLinkChanged(linked);
        };
        shell.onViewportClick = function(x, y) if (onViewportClick != null) onViewportClick(x, y);
        shell.onToolChanged = function(tool) if (onToolChanged != null) onToolChanged(tool);
        shell.onTransformSpaceChanged = function(local) {
            if (onTransformSpaceChanged != null) onTransformSpaceChanged(local);
        };
        shell.onViewportHover = function(x, y) if (onViewportHover != null) onViewportHover(x, y);
        shell.onViewportPush = function(x, y) {
            return onViewportPush != null && onViewportPush(x, y);
        };
        shell.onViewportDrag = function(x, y) if (onViewportDrag != null) onViewportDrag(x, y);
        shell.onViewportRelease = function(x, y) if (onViewportRelease != null) onViewportRelease(x, y);
        shell.onSnapChanged = function(mode) if (onSnapChanged != null) onSnapChanged(mode);
        shell.onSnapToGrid = function() if (onSnapToGrid != null) onSnapToGrid();
        shell.onSnapHoldChanged = function(active) {
            if (onSnapHoldChanged != null) onSnapHoldChanged(active);
        };
    }

    /** Editor console access. */
    public function log(line:String):Void {
        shell.log(line);
        // Mirror the editor console to stdout so automated runs can verify
        // command flow without screenshots.
        Sys.println('[console] ' + line);
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
            name:String, posX:Float = 0, posY:Float = 0, posZ:Float = 0,
            rotX:Float = 0, rotY:Float = 0, rotZ:Float = 0,
            scaleX:Float = 1, scaleY:Float = 1, scaleZ:Float = 1):Void {
        shell.setSelectedObjects(ids, primaryId, name, posX, posY, posZ,
            rotX, rotY, rotZ, scaleX, scaleY, scaleZ);
    }

    public function setObjectName(name:String):Void {
        shell.setObjectName(name);
    }

    /** Live transform field update during viewport gizmo drags. */
    public function updateTransformValues(posX:Float, posY:Float, posZ:Float,
            rotX:Float = 0, rotY:Float = 0, rotZ:Float = 0,
            scaleX:Float = 1, scaleY:Float = 1, scaleZ:Float = 1):Void {
        shell.updateTransformValues(posX, posY, posZ, rotX, rotY, rotZ,
            scaleX, scaleY, scaleZ);
    }
}
