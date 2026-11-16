package boltspark.ui;

import boltspark.editor.GridSnapping;
import boltspark.editor.Keybindings;
import boltspark.engine.ComponentTypeInfo;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.HierarchyEntry;
import boltspark.ui.windows.ApplicationWindowKind;

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
    final input:InputAdapter;
    final shell:EditorShell;

    /** Editor commands forwarded to the engine by Main. */
    public var onCreateObject:Null<Void->Void>;
    public var onCreateObjectAt:Null<Float->Float->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onHierarchyObjectNameChanged:Null<Int->String->Void>;
    public var onCreateChildObject:Null<Int->Bool->Void>;
    public var onCreateEmptyParent:Null<Array<Int>->Void>;
    public var onDuplicateObjects:Null<Array<Int>->Void>;
    public var onCopyObjects:Null<Array<Int>->Void>;
    public var onPasteObjects:Null<Int->Void>;
    public var onUnparentObjects:Null<Array<Int>->Void>;
    public var onSelectSubtree:Null<Int->Void>;
    public var onCanHierarchyDrop:Null<Array<Int>->Int->Bool>;
    public var onHierarchyDrop:Null<Array<Int>->Int->Int->Bool->Void>;
    public var onInspectorNumberChanged:Null<Int->String->Int->Float->Void>;
    public var onInspectorTextChanged:Null<Int->String->String->Void>;
    public var onInspectorEditBegin:Null<Int->String->Int->Void>;
    public var onInspectorEditEnd:Null<Int->String->Int->Void>;
    public var onInspectorReset:Null<Int->String->Void>;
    public var onInspectorLinkChanged:Null<Int->String->Bool->Void>;
    public var onAddComponent:Null<String->Void>;
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
    /** Open an editor dialog as its own native top-level application window. */
    public var onOpenApplicationWindow:Null<ApplicationWindowKind->Void>;
    /** Start an editor-window host before the user reaches its menu leaf. */
    public var onPrepareApplicationWindow:Null<ApplicationWindowKind->Void>;
    public var onUndo:Null<Void->Void>;
    public var onRedo:Null<Void->Void>;
    /** Mouse wheel over the viewport (positive delta scrolls down). */
    public var onViewportWheel:Null<Float->Void>;
    /** Camera gesture start: GESTURE_* kind + viewport-local pointer. */
    public var onViewportCameraBegin:Null<Int->Float->Float->Bool>;
    /** Camera gesture movement: kind + viewport-local pointer. */
    public var onViewportCameraMove:Null<Int->Float->Float->Void>;
    /** Camera gesture end: kind + viewport-local pointer (-1 when cancelled). */
    public var onViewportCameraEnd:Null<Int->Float->Float->Void>;
    /** Viewport contextual focus (hover or owned gesture) changed. */
    public var onViewportFocusChanged:Null<Bool->Void>;
    /** The native window lost keyboard focus. */
    public var onWindowFocusLost:Null<Void->Void>;
    /** G: toggle the independent editor grid. */
    public var onToggleGrid:Null<Void->Void>;
    /** F: frame the primary selection in the viewport. */
    public var onFocusSelection:Null<Void->Void>;

    public function new(parent:h2d.Scene, window:hxd.Window, snapping:GridSnapping,
            keybindings:Keybindings) {
        ctx = new UiContext(window);
        input = new InputAdapter(parent, keybindings, ctx.frame.input);
        shell = new EditorShell(parent, ctx, input, snapping);
        shell.onCreateObject = function() if (onCreateObject != null) onCreateObject();
        shell.onCreateObjectAt = function(x, y) if (onCreateObjectAt != null) onCreateObjectAt(x, y);
        shell.onDeleteObjects = function(ids) if (onDeleteObjects != null) onDeleteObjects(ids);
        shell.onObjectsSelected = function(ids, primary) {
            if (onObjectsSelected != null) onObjectsSelected(ids, primary);
        };
        shell.onObjectNameChanged = function(name) if (onObjectNameChanged != null) onObjectNameChanged(name);
        shell.onHierarchyObjectNameChanged = function(id, name) {
            if (onHierarchyObjectNameChanged != null) onHierarchyObjectNameChanged(id, name);
        };
        shell.onCreateChildObject = function(parentId, empty) {
            if (onCreateChildObject != null) onCreateChildObject(parentId, empty);
        };
        shell.onCreateEmptyParent = function(ids) {
            if (onCreateEmptyParent != null) onCreateEmptyParent(ids);
        };
        shell.onDuplicateObjects = function(ids) {
            if (onDuplicateObjects != null) onDuplicateObjects(ids);
        };
        shell.onCopyObjects = function(ids) {
            if (onCopyObjects != null) onCopyObjects(ids);
        };
        shell.onPasteObjects = function(parentId) {
            if (onPasteObjects != null) onPasteObjects(parentId);
        };
        shell.onUnparentObjects = function(ids) {
            if (onUnparentObjects != null) onUnparentObjects(ids);
        };
        shell.onSelectSubtree = function(id) {
            if (onSelectSubtree != null) onSelectSubtree(id);
        };
        shell.onCanHierarchyDrop = function(ids, parentId) {
            return onCanHierarchyDrop != null && onCanHierarchyDrop(ids, parentId);
        };
        shell.onHierarchyDrop = function(ids, parentId, index, preserveWorld) {
            if (onHierarchyDrop != null) {
                onHierarchyDrop(ids, parentId, index, preserveWorld);
            }
        };
        shell.onInspectorNumberChanged = function(component, property, axis, value) {
            if (onInspectorNumberChanged != null) {
                onInspectorNumberChanged(component, property, axis, value);
            }
        };
        shell.onInspectorTextChanged = function(component, property, value) {
            if (onInspectorTextChanged != null) {
                onInspectorTextChanged(component, property, value);
            }
        };
        shell.onInspectorEditBegin = function(component, property, axis) {
            if (onInspectorEditBegin != null) {
                onInspectorEditBegin(component, property, axis);
            }
        };
        shell.onInspectorEditEnd = function(component, property, axis) {
            if (onInspectorEditEnd != null) {
                onInspectorEditEnd(component, property, axis);
            }
        };
        shell.onInspectorReset = function(component, property) {
            if (onInspectorReset != null) onInspectorReset(component, property);
        };
        shell.onInspectorLinkChanged = function(component, property, linked) {
            if (onInspectorLinkChanged != null) {
                onInspectorLinkChanged(component, property, linked);
            }
        };
        shell.onAddComponent = function(typeId) {
            if (onAddComponent != null) onAddComponent(typeId);
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
        shell.onOpenApplicationWindow = function(kind) {
            if (onOpenApplicationWindow != null) onOpenApplicationWindow(kind);
        };
        shell.onPrepareApplicationWindow = function(kind) {
            if (onPrepareApplicationWindow != null) onPrepareApplicationWindow(kind);
        };
        shell.onUndo = function() if (onUndo != null) onUndo();
        shell.onRedo = function() if (onRedo != null) onRedo();
        shell.onViewportWheel = function(delta) {
            if (onViewportWheel != null) onViewportWheel(delta);
        };
        shell.onViewportCameraBegin = function(kind, x, y) {
            return onViewportCameraBegin != null
                && onViewportCameraBegin(kind, x, y);
        };
        shell.onViewportCameraMove = function(kind, x, y) {
            if (onViewportCameraMove != null) onViewportCameraMove(kind, x, y);
        };
        shell.onViewportCameraEnd = function(kind, x, y) {
            if (onViewportCameraEnd != null) onViewportCameraEnd(kind, x, y);
        };
        shell.onViewportFocusChanged = function(focused) {
            if (onViewportFocusChanged != null) onViewportFocusChanged(focused);
        };
        shell.onWindowFocusLost = function() {
            if (onWindowFocusLost != null) onWindowFocusLost();
        };
        shell.onToggleGrid = function() {
            if (onToggleGrid != null) onToggleGrid();
        };
        shell.onFocusSelection = function() {
            if (onFocusSelection != null) onFocusSelection();
        };
        // Camera-key-bound shortcuts are suppressed only while RMB fly
        // navigation is actually captured. Hover alone must leave E and the
        // other editor shortcuts available, matching Unreal's input model.
        input.viewportNavigationQuery = function() {
            return shell.isViewportNavigationActive();
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
        ctx.beginFrame();
        ctx.frame.register("editor-shell",
            new LayoutRect(0, 0, ctx.width, ctx.height));
        shell.update(dt);
        shell.registerFrame(ctx.frame);
        var diagnostics = ctx.endFrame();
        if (diagnostics.length > 0) {
            // Contract failures are exceptional and de-duplicated per frame.
            // Keep them out of the normal Output Log unless they actually occur.
            for (message in diagnostics) Sys.println('[BoltUI] ${message}');
        }
    }

    /** Rebuild static 2D chrome in response to a native window resize. */
    public function resize():Void {
        shell.resize();
    }

    public function getViewportRect():LayoutRect {
        return shell.viewportRect;
    }

    /** UI font for editor overlay text (viewport axis gizmo letters). */
    public function viewportFont():h2d.Font {
        return shell.viewportFont();
    }

    /** Small viewport overlay showing the current camera movement speed. */
    public function setCameraSpeedLabel(text:String):Void {
        shell.setCameraSpeedLabel(text);
    }

    public function setHierarchyEntries(entries:Array<HierarchyEntry>):Void {
        shell.setHierarchyEntries(entries);
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, ?components:Array<ComponentInspectorData>,
            ?availableTypes:Array<ComponentTypeInfo>):Void {
        shell.setSelectedObjects(ids, primaryId, name, components, availableTypes);
    }

    public function setObjectName(name:String):Void {
        shell.setObjectName(name);
    }

    public function setHistoryState(undoLabel:Null<String>,
            redoLabel:Null<String>):Void {
        shell.setHistoryState(undoLabel, redoLabel);
    }

    /** Live component-vector update during viewport gizmo drags. */
    public function updateInspectorVector(componentIndex:Int,
            propertyId:String, x:Float, y:Float, z:Float):Void {
        shell.updateInspectorVector(componentIndex, propertyId, x, y, z);
    }
}
