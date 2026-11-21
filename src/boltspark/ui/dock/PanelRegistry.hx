package boltspark.ui.dock;

import boltspark.ui.dock.DockPanelView.PanelSlot;

/**
 * Central registry of dockable panel types and their live view instances.
 *
 * Registration is permanent for the lifetime of the editor. Closing a panel
 * only detaches its view from the docking tree; the descriptor (factory) and
 * the cached instance remain here so a reopen never creates a duplicate.
 */
class PanelRegistry {
    final descriptors:Map<String, PanelDescriptor> = [];
    final instances:Map<String, DockPanelView> = [];

    public function new() {}

    public function register(descriptor:PanelDescriptor):Void {
        if (descriptors.exists(descriptor.id)) {
            throw 'Panel id "${descriptor.id}" is already registered';
        }
        if (descriptor.id == null || descriptor.id == "") {
            throw "Panel id must be a non-empty stable string";
        }
        descriptors.set(descriptor.id, descriptor);
    }

    public function has(id:String):Bool return descriptors.exists(id);

    public function descriptor(id:String):Null<PanelDescriptor> return descriptors.get(id);

    /** Cached live instance, if one has already been created. */
    public function peek(id:String, ?instanceKey:String):Null<DockPanelView> {
        return instances.get(instanceKey == null || instanceKey == "" ? id : instanceKey);
    }

    /** Create or return the cached view for this id/instance key. */
    public function create(id:String, ?instanceKey:String):DockPanelView {
        var descriptor = descriptors.get(id);
        if (descriptor == null) throw 'Unknown panel id "${id}"';
        var key = instanceKey == null || instanceKey == "" ? id : instanceKey;
        var cached = instances.get(key);
        if (cached != null) return cached;
        var view = descriptor.factory();
        if (view == null) throw 'Panel factory "${id}" returned null';
        instances.set(key, view);
        return view;
    }

    /** Create a slot with the descriptor's fixed/locked state applied. */
    public function slot(id:String, ?instanceKey:String):PanelSlot {
        return {
            view: create(id, instanceKey),
            instanceKey: instanceKey == null || instanceKey == "" ? id : instanceKey,
            locked: flag(id, "fixed", false)
        };
    }

    /** All registered ids in registration order (map order is stable on HL). */
    public function ids():Array<String> return [for (id in descriptors.keys()) id];

    public function count():Int return descriptors.size();

    /** Minimum dimensions declared for a registered panel. */
    public function minSize(id:String):{w:Float, h:Float} {
        var descriptor = descriptors.get(id);
        return {
            w: descriptor == null ? 80 : (descriptor.minWidth == null ? 80 : descriptor.minWidth),
            h: descriptor == null ? 60 : (descriptor.minHeight == null ? 60 : descriptor.minHeight)
        };
    }

    public function flag(id:String, name:String, fallback:Bool):Bool {
        var descriptor = descriptors.get(id);
        if (descriptor == null) return fallback;
        return switch (name) {
            case "close": descriptor.canClose == null ? fallback : descriptor.canClose;
            case "float": descriptor.canFloat == null ? fallback : descriptor.canFloat;
            case "dock": descriptor.canDock == null ? fallback : descriptor.canDock;
            case "multiple": descriptor.allowMultiple == null ? fallback : descriptor.allowMultiple;
            case "fixed": descriptor.fixed == null ? fallback : descriptor.fixed;
            default: fallback;
        };
    }
}
