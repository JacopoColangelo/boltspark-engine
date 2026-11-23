package boltspark.ui.widgets;

import boltspark.engine.Material;
import boltspark.engine.MaterialCulling;
import boltspark.engine.MaterialTextureLibrary;
import boltspark.engine.inspector.AssetType;
import boltspark.project.MaterialDocument;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.widgets.MenuDropdown.MenuItem;
import boltspark.ui.widgets.ScrollBar;

/**
 * Unity-style metallic/smoothness material editor, laid out with the same
 * collapsible `InspectorSection` groups, label column and row rhythm as the
 * regular Inspector. Every PBR map is a typed drop target fed directly by the
 * Asset Browser's texture payload, with picker/clear fallbacks.
 *
 * All persistence and live preview still flow out through callbacks: this
 * widget never writes documents to disk or mutates engine state directly.
 */
class MaterialEditor extends h2d.Object {
    public var onSave:Null<String->MaterialDocument->Void>;
    public var onNewMaterial:Null<Void->Void>;
    public var onDeleteMaterial:Null<String->Void>;
    public var onStatus:Null<String->Void>;
    /** Live preview: apply the edited document to the runtime material. */
    public var onChanged:Null<MaterialDocument->Void>;
    public var onQueryTextureTile:Null<String->Null<h2d.Tile>>;
    public var onBrowseTexture:Null<String->Void>;

    static inline var HEADER_HEIGHT:Float = 12;
    static inline var STATUS_HEIGHT:Float = 26;
    static inline var LABEL_WIDTH:Float = 92;
    static inline var EDGE:Float = 12;
    static inline var GAP:Float = Theme.SPACING;
    static inline var ROW:Float = Theme.CONTROL_HEIGHT;
    static inline var SLOT:Float = AssetSlotField.SLOT_HEIGHT;

    var ctx:UiContext;
    var background:UiSurface;
    var statusText:UiText;
    var mask:h2d.Mask;
    var content:h2d.Object;
    var wheelHit:h2d.Interactive;
    var scrollBar:ScrollBar;

    var nameField:TextInputField;
    var mainSection:InspectorSection;
    var emissionSection:InspectorSection;
    var tilingSection:InspectorSection;
    var advancedSection:InspectorSection;
    var colorField:TextInputField;
    var colorSwatch:UiSurface;
    var albedoSlot:AssetSlotField;
    var metallicSlider:UiSlider;
    var metallicSlot:AssetSlotField;
    var smoothnessSlider:UiSlider;
    var roughnessSlot:AssetSlotField;
    var sourceButton:UiButton;
    var normalSlot:AssetSlotField;
    var occlusionSlot:AssetSlotField;
    var emissionField:TextInputField;
    var emissionSwatch:UiSurface;
    var emissionSlider:UiSlider;
    var tilingX:NumericDragField;
    var tilingY:NumericDragField;
    var offsetX:NumericDragField;
    var offsetY:NumericDragField;
    var cullingButton:UiButton;
    var shadowsCheckbox:UiCheckbox;

    var menu:Null<MenuDropdown> = null;
    var currentSource:String = "";
    var currentDocument:Null<MaterialDocument> = null;
    var widthValue:Float = 320;
    var heightValue:Float = 360;
    var innerWidth:Float = 296;
    var contentHeightValue:Float = 600;
    var scrollY:Float = 0;
    var suppressChange:Bool = false;
    /** Last width whose controls were reflowed; resize passes reuse it. */
    var layoutFieldWidth:Float = -1;

    public function new(ctx:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;

        background = new UiSurface(ctx, this);
        background.setStyle(Theme.PANEL, Theme.BORDER, 0);

        statusText = new UiText(ctx.font, this);
        statusText.textColor = Theme.TEXT_SECONDARY;
        statusText.lineBreak = false;

        mask = new h2d.Mask(200, 100, this);
        content = new h2d.Object(mask);
        content.x = Std.int(EDGE);

        // Title row: same label/field grid as every Inspector property.
        rowLabel(content, 0, ROW, "Name");
        nameField = new TextInputField(ctx, "", 200, Std.int(ROW), "", content);
        nameField.x = fieldX();
        nameField.onCommit = function(value) {
            if (currentDocument == null) return;
            currentDocument.name = value;
            notifyChanged();
        };

        mainSection = createSection("Main Maps", true);
        emissionSection = createSection("Emission", true);
        tilingSection = createSection("Tiling / Offset", true);
        advancedSection = createSection("Advanced", false);

        buildMainRows();
        buildEmissionRows();
        buildTilingRows();
        buildAdvancedRows();

        // Wheel-only body capture. Heaps propagates wheel events by default,
        // and propagateEvents keeps clicks reaching every control underneath.
        wheelHit = new h2d.Interactive(200, 100, this);
        wheelHit.backgroundColor = 0;
        // h2d.Interactive defaults to the pointing-hand cursor; this catcher
        // spans the whole body, so leave the cursor to the control beneath.
        wheelHit.cursor = null;
        wheelHit.propagateEvents = true;
        wheelHit.onWheel = function(event) {
            if (scrollBy(event.wheelDelta)) event.propagate = false;
        };

        // Same scrollbar/catcher pattern as the Inspector: the mask owns the
        // scroll offset so h2d keeps clipped interactives aligned while the
        // thumb provides a draggable fallback.
        scrollBar = new ScrollBar(ctx, this);
        scrollBar.onChange = function(value) {
            scrollY = maxScroll() * value;
            applyScroll();
        };
        scrollBar.onWheel = scrollBy;

        layout(widthValue, heightValue);
    }

    // ------------------------------------------------------------------
    // Construction helpers
    // ------------------------------------------------------------------

    inline function fieldX():Float return LABEL_WIDTH + GAP;

    inline function fieldWidth():Float return Math.max(80, innerWidth - fieldX());

    function rowLabel(parent:h2d.Object, y:Float, height:Float,
            text:String):UiText {
        var result = new UiText(ctx.labelFont, parent);
        result.text = text;
        result.textColor = Theme.TEXT_SECONDARY;
        result.lineBreak = false;
        // Integer placement keeps hlfreetype's exact-size glyphs pixel-aligned;
        // fractional positions make the atlas sample blurry.
        result.y = Math.round(y + (height - result.textHeight) * 0.5);
        return result;
    }

    function createSection(title:String, expanded:Bool):InspectorSection {
        var section = new InspectorSection(ctx, title, content);
        if (!expanded) section.setExpanded(false);
        section.onToggle = function() {
            relayoutSections();
            refreshScroll();
        };
        return section;
    }

    function buildMainRows():Void {
        var rows = mainSection.content;
        var y = 0.0;
        rowLabel(rows, y, ROW, "Base Color");
        colorField = new TextInputField(ctx, "", 200, Std.int(ROW), "FFFFFF", rows);
        colorField.x = fieldX();
        colorField.y = y;
        colorField.onCommit = function(value) {
            if (currentDocument == null) return;
            var parsed = parseHex(value);
            if (parsed != null) {
                currentDocument.baseColor = parsed;
                refreshFields();
                notifyChanged();
            }
        };
        colorSwatch = new UiSurface(ctx, rows);
        colorSwatch.setSize(26, ROW);
        colorSwatch.y = y;
        y += ROW + GAP;

        rowLabel(rows, y, SLOT, "Albedo");
        albedoSlot = makeTextureSlot(rows, y, "Albedo: None", "albedoTexture");
        y += SLOT + GAP;

        rowLabel(rows, y, ROW, "Metallic");
        metallicSlider = makeSlider(rows, y, 0, 1, 0, "metallic");
        y += ROW + GAP;

        rowLabel(rows, y, SLOT, "Metallic Map");
        metallicSlot = makeTextureSlot(rows, y, "Metallic: None", "metallicTexture");
        y += SLOT + GAP;

        rowLabel(rows, y, ROW, "Smoothness");
        smoothnessSlider = makeSlider(rows, y, 0, 1, 0.5, "smoothness");
        y += ROW + GAP;

        rowLabel(rows, y, ROW, "Source");
        sourceButton = new UiButton(ctx, "Source: Metallic Alpha", 200,
            Std.int(ROW), rows);
        sourceButton.x = fieldX();
        sourceButton.y = y;
        sourceButton.onClick = openSourceMenu;
        y += ROW + GAP;

        rowLabel(rows, y, SLOT, "Roughness Map");
        roughnessSlot = makeTextureSlot(rows, y, "Roughness: None", "roughnessTexture");
        y += SLOT + GAP;

        rowLabel(rows, y, SLOT, "Normal Map");
        normalSlot = makeTextureSlot(rows, y, "Normal: None", "normalTexture");
        y += SLOT + GAP;

        rowLabel(rows, y, SLOT, "Occlusion");
        occlusionSlot = makeTextureSlot(rows, y, "Occlusion: None", "occlusionTexture");
        y += SLOT;
        mainSection.contentHeight = y;
    }

    function buildEmissionRows():Void {
        var rows = emissionSection.content;
        var y = 0.0;
        rowLabel(rows, y, ROW, "Color");
        emissionField = new TextInputField(ctx, "", 200, Std.int(ROW), "000000", rows);
        emissionField.x = fieldX();
        emissionField.y = y;
        emissionField.onCommit = function(value) {
            if (currentDocument == null) return;
            var parsed = parseHex(value);
            if (parsed != null) {
                currentDocument.emissionColor = parsed;
                refreshFields();
                notifyChanged();
            }
        };
        emissionSwatch = new UiSurface(ctx, rows);
        emissionSwatch.setSize(26, ROW);
        emissionSwatch.y = y;
        y += ROW + GAP;

        rowLabel(rows, y, ROW, "Intensity");
        emissionSlider = makeSlider(rows, y, 0, 8, 1, "emissionIntensity");
        y += ROW;
        emissionSection.contentHeight = y;
    }

    function buildTilingRows():Void {
        var rows = tilingSection.content;
        tilingX = makeNumber(rows, 0, "X", 1, function(v) {
            if (currentDocument != null) currentDocument.tilingX = v;
        });
        tilingY = makeNumber(rows, 0, "Y", 1, function(v) {
            if (currentDocument != null) currentDocument.tilingY = v;
        });
        offsetX = makeNumber(rows, ROW + GAP, "X", 0, function(v) {
            if (currentDocument != null) currentDocument.offsetX = v;
        });
        offsetY = makeNumber(rows, ROW + GAP, "Y", 0, function(v) {
            if (currentDocument != null) currentDocument.offsetY = v;
        });
        rowLabel(rows, 0, ROW, "Tiling");
        rowLabel(rows, ROW + GAP, ROW, "Offset");
        tilingSection.contentHeight = ROW * 2 + GAP;
    }

    function buildAdvancedRows():Void {
        var rows = advancedSection.content;
        rowLabel(rows, 0, ROW, "Culling");
        cullingButton = new UiButton(ctx, "Culling: Back", 200, Std.int(ROW), rows);
        cullingButton.x = fieldX();
        cullingButton.onClick = openCullingMenu;
        rowLabel(rows, ROW + GAP, ROW, "Shadows");
        shadowsCheckbox = new UiCheckbox(ctx, "Cast shadows", rows);
        shadowsCheckbox.x = fieldX();
        shadowsCheckbox.y = ROW + GAP;
        shadowsCheckbox.onChanged = function(value) {
            if (currentDocument == null) return;
            currentDocument.shadows = value;
            notifyChanged();
        };
        advancedSection.contentHeight = ROW * 2 + GAP;
    }

    function makeSlider(parent:h2d.Object, y:Float, min:Float, max:Float,
            initial:Float, property:String):UiSlider {
        var slider = new UiSlider(ctx, 200, min, max, initial, "", parent);
        slider.x = fieldX();
        slider.y = y;
        slider.displayDecimals = 2;
        slider.onChange = function(value) {
            if (currentDocument == null) return;
            Reflect.setField(currentDocument, property, value);
            notifyChanged();
        };
        return slider;
    }

    function makeNumber(parent:h2d.Object, y:Float, prefix:String,
            initial:Float, apply:Float->Void):NumericDragField {
        var field = new NumericDragField(ctx, 120, Std.int(ROW), -100, 100, 0.1,
            initial, function(v) return Std.string(Math.round(v * 100) / 100),
            prefix, Theme.TEXT_SECONDARY, parent);
        field.y = y;
        field.onValueChanged = function(value) {
            apply(value);
            notifyChanged();
        };
        return field;
    }

    function makeTextureSlot(parent:h2d.Object, y:Float, fallback:String,
            property:String):AssetSlotField {
        var slot = new AssetSlotField(ctx, 200, fallback, parent);
        slot.x = fieldX();
        slot.y = y;
        slot.assetType = AssetType.TextureAsset;
        slot.onQueryThumbnail = function(id) {
            return onQueryTextureTile != null ? onQueryTextureTile(id) : null;
        };
        slot.onAssetDrop = function(id) {
            if (currentDocument == null) return;
            Reflect.setField(currentDocument, property, id);
            refreshFields();
            notifyChanged();
        };
        slot.onClear = function() {
            if (currentDocument == null) return;
            Reflect.setField(currentDocument, property, "");
            refreshFields();
            notifyChanged();
        };
        slot.onPick = function() {
            var items:Array<MenuItem> = [{
                label: "None",
                selected: currentDocument != null
                    && Reflect.field(currentDocument, property) == "",
                onClick: function() { assignTexture(property, ""); }
            }];
            for (texture in MaterialTextureLibrary.all()) {
                var id = texture.id;
                items.push({
                    label: texture.label,
                    selected: currentDocument != null
                        && Reflect.field(currentDocument, property) == id,
                    onClick: function() { assignTexture(property, id); }
                });
            }
            showMenu(slot, SLOT, items);
        };
        slot.onBrowse = function() {
            var id = currentDocument == null ? "" : Reflect.field(currentDocument, property);
            if (id != "" && onBrowseTexture != null) onBrowseTexture(id);
        };
        return slot;
    }

    function assignTexture(property:String, id:String):Void {
        if (currentDocument == null) return;
        Reflect.setField(currentDocument, property, id);
        refreshFields();
        notifyChanged();
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------

    public function layout(width:Float, height:Float):Void {
        widthValue = width < 120 ? 120 : width;
        heightValue = height < 200 ? 200 : height;
        // Reserve the gutter for the scrollbar so no field is hidden under it.
        innerWidth = Math.max(150, widthValue - EDGE * 2 - 8);
        background.setSize(widthValue, heightValue);

        mask.width = Std.int(widthValue);
        mask.height = Std.int(Math.max(1, heightValue - HEADER_HEIGHT - STATUS_HEIGHT));
        mask.x = 0;
        mask.y = HEADER_HEIGHT;
        wheelHit.x = 0;
        wheelHit.y = HEADER_HEIGHT;
        wheelHit.width = widthValue;
        wheelHit.height = mask.height;
        statusText.setPosition(EDGE, heightValue - 22);

        // Dock resize and splitter drags call layout() on every frame. The
        // panel's mask/scrollbar must follow each pass, but the control grid
        // only changes when the field column changes width. Skipping the
        // unchanged pass avoids re-measuring labels and rebuilding thumbnails.
        var fieldW = fieldWidth();
        if (Math.abs(fieldW - layoutFieldWidth) > 0.5) {
            layoutFieldWidth = fieldW;
            // TextInputField keeps an 82px label column by default; our labels
            // live in the left grid column, so the input fills the whole field.
            for (field in [nameField, colorField, emissionField]) field.setLabelWidth(0);
            nameField.setWidth(fieldW);
            colorField.setWidth(fieldW - 34);
            emissionField.setWidth(fieldW - 34);
            colorSwatch.x = innerWidth - 26;
            emissionSwatch.x = innerWidth - 26;
            for (slot in [albedoSlot, metallicSlot, roughnessSlot, normalSlot, occlusionSlot]) {
                slot.setWidth(fieldW);
            }
            for (slider in [metallicSlider, smoothnessSlider, emissionSlider]) {
                slider.setWidth(fieldW);
            }
            sourceButton.setWidth(fieldW);
            cullingButton.setWidth(fieldW);
            shadowsCheckbox.setWidth(fieldW);
            var pairWidth = Math.max(60, (fieldW - GAP) * 0.5);
            tilingX.x = fieldX();
            tilingY.x = fieldX() + pairWidth + GAP;
            tilingX.setWidth(pairWidth);
            tilingY.setWidth(pairWidth);
            tilingY.x = fieldX() + pairWidth + GAP;
            offsetX.x = fieldX();
            offsetY.x = fieldX() + pairWidth + GAP;
            offsetX.setWidth(pairWidth);
            offsetY.setWidth(pairWidth);
            offsetY.x = fieldX() + pairWidth + GAP;
        }

        relayoutSections();
        scrollBar.setBounds(widthValue - 7, HEADER_HEIGHT + 2, 5, mask.height - 4);
        refreshScroll();
    }

    function relayoutSections():Void {
        for (section in [mainSection, emissionSection, tilingSection, advancedSection]) {
            section.setWidth(innerWidth);
        }
        var y = ROW + GAP;
        mainSection.y = y;
        y += mainSection.totalHeight() + GAP;
        emissionSection.y = y;
        y += emissionSection.totalHeight() + GAP;
        tilingSection.y = y;
        y += tilingSection.totalHeight() + GAP;
        advancedSection.y = y;
        contentHeightValue = y + advancedSection.totalHeight() + GAP;
    }

    function refreshScroll():Void {
        scrollY = Math.max(0, Math.min(maxScroll(), scrollY));
        applyScroll();
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] material scroll metrics max=${Std.int(maxScroll())}'
                + ' content=${Std.int(contentHeightValue)} view=${Std.int(mask.height)}');
        }
    }

    function applyScroll():Void {
        // The mask (not a content offset) owns the scroll: this keeps wheel
        // routing, clipping and all widget hit boxes in the same coordinates.
        mask.scrollY = scrollY;
        var visible = mask.height / Math.max(1, contentHeightValue);
        scrollBar.setMetrics(visible, maxScroll() <= 0 ? 0 : scrollY / maxScroll());
        scrollBar.visible = visible < 1;
    }

    /** Wheel scroll; positive delta moves toward later properties. */
    function scrollBy(delta:Float):Bool {
        var maximum = maxScroll();
        if (maximum <= 0) return false;
        scrollY = Math.max(0, Math.min(maximum, scrollY + delta * 36));
        applyScroll();
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] material scroll y=${Std.int(scrollY)}'
                + ' max=${Std.int(maximum)} content=${Std.int(contentHeightValue)}'
                + ' view=${Std.int(mask.height)}');
        }
        return true;
    }

    inline function maxScroll():Float {
        return Math.max(0, contentHeightValue - mask.height);
    }

    // ------------------------------------------------------------------
    // Document binding
    // ------------------------------------------------------------------

    /** Load a material document for editing. */
    public function edit(source:String, document:MaterialDocument):Void {
        currentSource = source;
        currentDocument = document;
        scrollY = 0;
        applyScroll();
        refreshFields();
        setStatus('Editing ${document.name}');
    }

    public function currentSourcePath():String return currentSource;

    /** Clear the editor after its material was deleted. */
    public function clear():Void {
        currentSource = "";
        currentDocument = null;
        refreshFields();
        statusText.text = "";
    }

    function refreshFields():Void {
        suppressChange = true;
        var document = currentDocument;
        nameField.setValue(document == null ? "" : document.name);
        colorField.setValue(document == null ? "FFFFFF" : hex(document.baseColor));
        colorSwatch.setStyle(document == null ? 0xFFFFFF : document.baseColor,
            Theme.BORDER, 0);
        emissionField.setValue(document == null ? "000000" : hex(document.emissionColor));
        emissionSwatch.setStyle(document == null ? 0 : document.emissionColor,
            Theme.BORDER, 0);
        metallicSlider.setValue(document == null ? 0 : document.metallic);
        smoothnessSlider.setValue(document == null ? 0.5 : document.smoothness);
        emissionSlider.setValue(document == null ? 1 : document.emissionIntensity);
        sourceButton.setText("Source: " + sourceLabel(document == null
            ? Material.SMOOTHNESS_METALLIC_ALPHA : document.smoothnessSource));
        cullingButton.setText("Culling: " + (document == null ? "Back"
            : document.culling.charAt(0).toUpperCase() + document.culling.substr(1)));
        shadowsCheckbox.value = document != null && document.shadows;

        albedoSlot.assetId = document == null ? "" : document.albedoTexture;
        albedoSlot.setValue("Albedo: " + textureLabel(albedoSlot.assetId));
        metallicSlot.assetId = document == null ? "" : document.metallicTexture;
        metallicSlot.setValue("Metallic: " + textureLabel(metallicSlot.assetId));
        roughnessSlot.assetId = document == null ? "" : document.roughnessTexture;
        roughnessSlot.setValue("Roughness: " + textureLabel(roughnessSlot.assetId));
        normalSlot.assetId = document == null ? "" : document.normalTexture;
        normalSlot.setValue("Normal: " + textureLabel(normalSlot.assetId));
        occlusionSlot.assetId = document == null ? "" : document.occlusionTexture;
        occlusionSlot.setValue("Occlusion: " + textureLabel(occlusionSlot.assetId));

        tilingX.setValue(document == null ? 1 : document.tilingX);
        tilingY.setValue(document == null ? 1 : document.tilingY);
        offsetX.setValue(document == null ? 0 : document.offsetX);
        offsetY.setValue(document == null ? 0 : document.offsetY);
        suppressChange = false;
    }

    function notifyChanged():Void {
        if (suppressChange || currentDocument == null || currentSource == "") return;
        if (onChanged != null) onChanged(currentDocument);
        // Changes persist automatically; Main debounces the disk write.
        if (onSave != null) onSave(currentSource, currentDocument);
    }

    static function sourceLabel(value:String):String {
        return value == Material.SMOOTHNESS_ALBEDO_ALPHA
            ? "Albedo Alpha" : "Metallic Alpha";
    }

    static function hex(color:Int):String {
        return StringTools.hex(color, 6).toUpperCase();
    }

    static function parseHex(value:String):Null<Int> {
        var parsed = Std.parseInt("0x" + StringTools.replace(
            StringTools.trim(value), "#", ""));
        return parsed == null ? null : parsed & 0xFFFFFF;
    }

    static function textureLabel(id:String):String {
        if (id == null || id.length == 0) return "None";
        var name = new haxe.io.Path(id).file;
        return name == null ? id : name;
    }

    function setStatus(message:String):Void {
        statusText.text = message;
        if (onStatus != null) onStatus(message);
    }

    function openSourceMenu():Void {
        var items:Array<MenuItem> = [];
        for (value in [Material.SMOOTHNESS_METALLIC_ALPHA, Material.SMOOTHNESS_ALBEDO_ALPHA]) {
            var label = sourceLabel(value);
            items.push({
                label: label,
                selected: currentDocument != null && currentDocument.smoothnessSource == value,
                onClick: function() {
                    if (currentDocument == null) return;
                    currentDocument.smoothnessSource = value;
                    refreshFields();
                    notifyChanged();
                }
            });
        }
        showMenu(sourceButton, Std.int(ROW), items);
    }

    function openCullingMenu():Void {
        var modes = [MaterialCulling.Back, MaterialCulling.Front,
            MaterialCulling.None, MaterialCulling.Both];
        var items:Array<MenuItem> = [];
        for (mode in modes) {
            var value:String = mode;
            items.push({
                label: value.charAt(0).toUpperCase() + value.substr(1),
                selected: currentDocument != null && currentDocument.culling == value,
                onClick: function() {
                    if (currentDocument == null) return;
                    currentDocument.culling = value;
                    refreshFields();
                    notifyChanged();
                }
            });
        }
        showMenu(cullingButton, Std.int(ROW), items);
    }

    function showMenu(anchor:h2d.Object, height:Float, items:Array<MenuItem>):Void {
        var scene = getScene();
        if (menu == null || menu.getScene() != scene) {
            if (menu != null) menu.remove();
            menu = new MenuDropdown(ctx, scene == null ? this : scene);
        }
        var point = anchor.localToGlobal(new h2d.col.Point(0, height + 2));
        menu.open(point.x, point.y, items);
    }
}
