package boltspark.ui.widgets;

import boltspark.ui.HierarchyEntry;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiIcons;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.UiTextInput;

/** One retained hierarchy row with nesting, rename, and drag interaction. */
class HierarchyRow extends h2d.Object {
    public static inline var DROP_NONE:Int = 0;
    public static inline var DROP_CHILD:Int = 1;
    public static inline var DROP_BEFORE:Int = 2;
    public static inline var DROP_AFTER:Int = 3;

    public var objectId:Int;
    public var parentId:Int = -1;
    public var depth(default, null):Int = 0;
    public var hasChildren(default, null):Bool = false;
    public var onWheel:Null<Float->Void>;
    public var onSelect:Null<Int->Bool->Bool->Void>;
    public var onToggle:Null<Int->Void>;
    public var onToggleVisibility:Null<Int->Void>;
    public var onContextMenu:Null<Int->Void>;
    public var onRename:Null<Int->String->Void>;
    public var onDragStart:Null<Int->Void>;
    public var onDragMove:Null<Int->Float->Float->Void>;
    public var onDragEnd:Null<Int->Float->Float->Void>;

    final ctx:UiContext;
    final surface:UiSurface;
    final background:h2d.Interactive;
    final selectionEdge:h2d.Graphics;
    final disclosure:h2d.Graphics;
    final disclosureHit:h2d.Interactive;
    final objectIcon:h2d.Graphics;
    final visibilityIcon:h2d.Graphics;
    final visibilityHit:h2d.Interactive;
    final label:h2d.Text;
    final renameSurface:UiSurface;
    final renameInput:UiTextInput;
    final dropFeedback:h2d.Graphics;
    var fullName:String;
    var renderable:Bool = false;
    var visibleFlag:Bool = true;
    var enabledFlag:Bool = true;
    var expanded:Bool = true;
    var selected:Bool = false;
    var hovered:Bool = false;
    var renaming:Bool = false;
    var renameOriginal:String = "";
    var rowWidth:Float = 1;
    var dragStartX:Float = 0;
    var dragStartY:Float = 0;
    var dragging:Bool = false;
    var deferSingleSelection:Bool = false;
    var lastClickAt:Float = -10;

    public function new(ctx:UiContext, initialObjectId:Int, name:String,
            ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;
        this.objectId = initialObjectId;
        fullName = name;

        surface = new UiSurface(ctx, this);
        surface.visible = false;
        background = new h2d.Interactive(1, 22, this);
        background.cursor = hxd.Cursor.Default;
        background.backgroundColor = 0;
        background.enableRightButton = true;
        background.onOver = function(_) {
            hovered = true;
            updateStyle();
        };
        background.onOut = function(_) {
            hovered = false;
            updateStyle();
        };
        background.onPush = beginPointerInteraction;
        background.onWheel = function(event) {
            if (onWheel == null) return;
            onWheel(event.wheelDelta);
            event.propagate = false;
        };

        selectionEdge = new h2d.Graphics(this);
        disclosure = new h2d.Graphics(this);
        disclosureHit = new h2d.Interactive(16, 22, this);
        disclosureHit.backgroundColor = 0;
        disclosureHit.cursor = hxd.Cursor.Button;
        disclosureHit.enableRightButton = true;
        disclosureHit.onPush = function(event) {
            if (event.button == 1) {
                if (onSelect != null && !selected) {
                    onSelect(this.objectId, false, false);
                }
                if (onContextMenu != null) onContextMenu(this.objectId);
                event.propagate = false;
            } else if (event.button == 0 && hasChildren) {
                // Rows are retained and reassigned after filtering/reordering.
                // Read the current field rather than capturing the constructor
                // parameter, which may belong to a previous entry.
                if (onToggle != null) onToggle(this.objectId);
                event.propagate = false;
            }
        };
        disclosureHit.onWheel = function(event) {
            if (onWheel == null) return;
            onWheel(event.wheelDelta);
            event.propagate = false;
        };
        objectIcon = new h2d.Graphics(this);

        visibilityIcon = new h2d.Graphics(this);
        visibilityHit = new h2d.Interactive(18, 22, this);
        visibilityHit.backgroundColor = 0;
        visibilityHit.cursor = hxd.Cursor.Default;
        visibilityHit.onPush = function(event) {
            if (onToggleVisibility != null) onToggleVisibility(this.objectId);
            event.propagate = false;
        };

        label = new UiText(ctx.font, this);
        label.textColor = Theme.TEXT;
        label.lineBreak = false;
        setName(name);
        ctx.centerY(label, 0, background.height);

        renameSurface = new UiSurface(ctx, this);
        renameSurface.setStyle(Theme.FIELD_BG, Theme.ACCENT, 0);
        renameSurface.visible = false;
        renameInput = new UiTextInput(ctx.font, this);
        renameInput.textColor = Theme.TEXT;
        renameInput.useSoftwareKeyboard = false;
        renameInput.visible = false;
        renameInput.onKeyDown = function(event) {
            if (event.keyCode == hxd.Key.ESCAPE) {
                cancelRename();
                event.propagate = false;
            } else if (event.keyCode == hxd.Key.ENTER
                    || event.keyCode == hxd.Key.NUMPAD_ENTER) {
                commitRename();
                event.propagate = false;
            }
        };
        renameInput.onFocusLost = function(_) {
            if (renaming) commitRename();
        };

        dropFeedback = new h2d.Graphics(this);
        refreshEntryVisuals();
    }

    public function setEntry(entry:HierarchyEntry, expanded:Bool):Void {
        if (objectId != entry.id) {
            // Retained rows are reused by visible index after filtering and
            // reordering. Never carry click timing or an inline rename over
            // to the different object that now occupies this row instance.
            if (renaming) cancelRename();
            lastClickAt = -10;
        }
        objectId = entry.id;
        parentId = entry.parentId;
        depth = entry.depth;
        // Both flags come from the same model snapshot; trust the count so a
        // stale "has children" hint can never draw a chevron on a leaf row.
        hasChildren = entry.hasChildren && entry.childCount > 0;
        renderable = entry.renderable;
        visibleFlag = entry.visible;
        enabledFlag = entry.enabled;
        this.expanded = expanded;
        setName(entry.name);
        refreshEntryVisuals();
    }

    public function setName(name:String):Void {
        fullName = name;
        fitLabel(rowWidth - label.x - 8);
    }

    public function setBounds(x:Float, y:Float, width:Float,
            selected:Bool):Void {
        this.x = x;
        this.y = y;
        this.selected = selected;
        rowWidth = width;
        background.width = width;
        surface.setSize(width, background.height);
        updateStyle();
        layoutContents();
    }

    public function beginRename():Void {
        if (renaming) return;
        renaming = true;
        renameOriginal = fullName;
        renameInput.text = fullName;
        label.visible = false;
        renameSurface.visible = true;
        renameInput.visible = true;
        layoutContents();
        renameInput.focus();
    }

    public inline function isRenaming():Bool return renaming;

    public function setDropFeedback(mode:Int, valid:Bool):Void {
        dropFeedback.clear();
        if (mode == DROP_NONE) return;
        var color = valid ? Theme.ACCENT : Theme.DANGER;
        if (mode == DROP_CHILD) {
            dropFeedback.lineStyle(1.5, color, 1);
            dropFeedback.drawRect(1, 1, Math.max(0, rowWidth - 2), 20);
            dropFeedback.lineStyle();
        } else {
            var y = mode == DROP_BEFORE ? 1.0 : 21.0;
            dropFeedback.lineStyle(2, color, 1);
            dropFeedback.moveTo(Math.max(2, 5 + depth * 14), y);
            dropFeedback.lineTo(Math.max(2, rowWidth - 2), y);
            dropFeedback.lineStyle();
        }
    }

    function beginPointerInteraction(event:hxd.Event):Void {
        if (renaming) return;
        if (event.button == 1) {
            if (onSelect != null && !selected) onSelect(objectId, false, false);
            if (onContextMenu != null) onContextMenu(objectId);
            event.propagate = false;
            return;
        }
        if (event.button != 0) return;
        var control = hxd.Key.isDown(hxd.Key.CTRL);
        var shift = hxd.Key.isDown(hxd.Key.SHIFT);
        // Pressing one row in an existing multi-selection must keep the whole
        // selection alive if this becomes a drag. Collapse to one only when it
        // proves to be a click on release.
        deferSingleSelection = selected && !control && !shift;
        if (!deferSingleSelection && onSelect != null) {
            onSelect(objectId, control, shift);
        }
        dragStartX = ctx.window.mouseX;
        dragStartY = ctx.window.mouseY;
        dragging = false;
        background.startCapture(function(captured) {
            switch (captured.kind) {
                case EMove:
                    var mouseX = ctx.window.mouseX;
                    var mouseY = ctx.window.mouseY;
                    if (!dragging && Math.abs(mouseX - dragStartX)
                            + Math.abs(mouseY - dragStartY) > 5) {
                        dragging = true;
                        if (onDragStart != null) onDragStart(objectId);
                    }
                    if (dragging && onDragMove != null) {
                        onDragMove(objectId, mouseX, mouseY);
                    }
                    captured.propagate = false;
                case ERelease, EReleaseOutside:
                    var mouseX = ctx.window.mouseX;
                    var mouseY = ctx.window.mouseY;
                    background.stopCapture();
                    if (dragging) {
                        if (onDragEnd != null) onDragEnd(objectId, mouseX, mouseY);
                    } else {
                        if (deferSingleSelection && onSelect != null) {
                            onSelect(objectId, false, false);
                        }
                        var now = haxe.Timer.stamp();
                        if (now - lastClickAt <= 0.35) beginRename();
                        lastClickAt = now;
                    }
                    dragging = false;
                    deferSingleSelection = false;
                    captured.propagate = false;
                case EFocusLost:
                    background.stopCapture();
                    if (dragging && onDragEnd != null) {
                        onDragEnd(objectId, ctx.window.mouseX, ctx.window.mouseY);
                    }
                    dragging = false;
                    deferSingleSelection = false;
                    captured.propagate = false;
                case _:
                    captured.propagate = false;
            }
        });
        event.propagate = false;
    }

    function commitRename():Void {
        if (!renaming) return;
        var value = StringTools.trim(renameInput.text);
        renaming = false;
        renameInput.visible = false;
        renameSurface.visible = false;
        label.visible = true;
        if (value.length == 0) value = renameOriginal;
        if (value != renameOriginal && onRename != null) onRename(objectId, value);
        clearRenameFocus();
    }

    public function cancelRename():Void {
        if (!renaming) return;
        renaming = false;
        renameInput.text = renameOriginal;
        renameInput.visible = false;
        renameSurface.visible = false;
        label.visible = true;
        clearRenameFocus();
    }

    function clearRenameFocus():Void {
        var scene = getScene();
        if (scene == null) return;
        var focused = scene.getFocus();
        if (focused != null) focused.blur();
    }

    function refreshEntryVisuals():Void {
        // UiIcons.draw() attaches an h2d.Bitmap child; Graphics.clear() only
        // drops vector commands. Remove the old chevron bitmap too, or a row
        // that stops having children keeps showing a stale disclosure arrow.
        disclosure.removeChildren();
        disclosure.clear();
        if (hasChildren) {
            UiIcons.draw(disclosure, expanded ? ChevronDown : ChevronRight,
                0, 0, 11, Theme.MUTED);
        }
        objectIcon.clear();
        var iconColor = !enabledFlag ? Theme.DISABLED
            : renderable ? Theme.CUBE_ORANGE : Theme.TEXT_SECONDARY;
        UiIcons.draw(objectIcon,
            renderable ? Cube : Box,
            0, 0, 13, iconColor);
        visibilityIcon.clear();
        UiIcons.draw(visibilityIcon, visibleFlag ? Eye : EyeOff,
            0, 0, 13, visibleFlag ? Theme.TEXT_SECONDARY : Theme.DISABLED);
        disclosureHit.visible = hasChildren;
        updateStyle();
        layoutContents();
    }

    function layoutContents():Void {
        var indent = 5 + depth * 14;
        disclosure.x = indent;
        disclosure.y = 6;
        disclosureHit.x = indent - 2;
        disclosureHit.y = 0;
        objectIcon.x = indent + 16;
        objectIcon.y = 5;
        var reserved = 28;
        label.x = indent + 36;
        fitLabel(rowWidth - label.x - reserved);
        visibilityIcon.x = Math.max(label.x + 4, rowWidth - 22);
        visibilityIcon.y = 5;
        visibilityHit.x = Math.max(label.x, rowWidth - 26);
        visibilityHit.y = 0;
        renameSurface.x = label.x - 3;
        renameSurface.y = 2;
        renameSurface.setSize(Math.max(0, rowWidth - label.x - 4), 18);
        renameInput.x = label.x;
        renameInput.y = 0;
        renameInput.inputWidth = Std.int(Math.max(0, rowWidth - label.x - reserved));
    }

    function updateStyle():Void {
        surface.visible = selected || hovered;
        if (selected) {
            surface.setStyle(Theme.ACCENT_MUTED, Theme.ACCENT_MUTED, 0, 0);
        } else if (hovered) {
            surface.setStyle(Theme.SURFACE_2, Theme.SURFACE_2, 0, 0);
        }
        label.textColor = !visibleFlag || !enabledFlag
            ? Theme.DISABLED
            : selected ? 0xF3F7FF : Theme.TEXT;
        selectionEdge.clear();
        if (selected) {
            selectionEdge.beginFill(Theme.ACCENT);
            selectionEdge.drawRect(0, 0, 2, background.height);
            selectionEdge.endFill();
        }
    }

    function fitLabel(maxWidth:Float):Void {
        if (maxWidth <= 0) {
            label.text = "";
            return;
        }
        label.text = fullName;
        if (label.calcTextWidth(fullName) <= maxWidth) return;
        label.text = "";
        for (i in 0...fullName.length) {
            var candidate = fullName.substr(0, i + 1) + "...";
            if (label.calcTextWidth(candidate) > maxWidth) break;
            label.text = candidate;
        }
    }
}
