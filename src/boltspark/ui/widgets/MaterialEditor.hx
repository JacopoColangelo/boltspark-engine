package boltspark.ui.widgets;

import boltspark.engine.Material;
import boltspark.engine.MaterialCulling;
import boltspark.engine.MaterialTextureLibrary;
import boltspark.project.MaterialDocument;
import boltspark.ui.Theme;
import boltspark.ui.UiContext;
import boltspark.ui.UiSurface;
import boltspark.ui.UiText;
import boltspark.ui.widgets.MenuDropdown;
import boltspark.ui.widgets.MenuDropdown.MenuItem;

/**
 * Editor for project-authored Material assets. Docked by default, and floated
 * as a real native HWND by the standard dock-panel path when dragged out.
 * All persistence goes through callbacks; this widget never touches documents.
 */
class MaterialEditor extends h2d.Object {
    public var onSave:Null<String->MaterialDocument->Void>;
    public var onNewMaterial:Null<Void->Void>;
    public var onDeleteMaterial:Null<String->Void>;
    public var onStatus:Null<String->Void>;

    final ctx:UiContext;
    final background:UiSurface;
    final title:UiText;
    final materialButton:UiButton;
    final newButton:UiButton;
    final deleteButton:UiButton;
    final saveButton:UiButton;
    final nameField:TextInputField;
    final colorField:TextInputField;
    final albedoButton:UiButton;
    final specAmountField:TextInputField;
    final specPowerField:TextInputField;
    final cullingButton:UiButton;
    final shadowsCheckbox:UiCheckbox;
    final statusText:UiText;
    final menu:MenuDropdown;

    var currentSource:String = "";
    var currentDocument:Null<MaterialDocument> = null;
    var widthValue:Float = 320;
    var heightValue:Float = 360;

    public function new(ctx:UiContext, ?parent:h2d.Object) {
        super(parent);
        this.ctx = ctx;

        background = new UiSurface(ctx, this);
        background.setStyle(Theme.PANEL, Theme.BORDER, 0);

        title = new UiText(ctx.font, this);
        title.text = "Material Editor";
        title.textColor = Theme.TEXT;
        title.lineBreak = false;
        title.x = 12;
        title.y = 10;

        materialButton = new UiButton(ctx, "No material", 150, 26, this);
        materialButton.onClick = openMaterialMenu;
        newButton = new UiButton(ctx, "New", 48, 26, this);
        newButton.onClick = function() {
            if (onNewMaterial != null) onNewMaterial();
        };
        deleteButton = new UiButton(ctx, "Delete", 60, 26, this);
        deleteButton.onClick = function() {
            if (currentSource == "") return;
            if (onDeleteMaterial != null) onDeleteMaterial(currentSource);
        };
        saveButton = new UiButton(ctx, "Save", 56, 26, this);
        saveButton.onClick = saveCurrent;

        nameField = new TextInputField(ctx, "Name", 260, 26, "", this);
        nameField.onCommit = function(value) {
            if (currentDocument != null) currentDocument.name = value;
        };
        colorField = new TextInputField(ctx, "Base color", 260, 26, "FFFFFF", this);
        colorField.onCommit = function(value) {
            if (currentDocument == null) return;
            var parsed = Std.parseInt("0x" + StringTools.replace(
                StringTools.trim(value), "#", ""));
            if (parsed != null) currentDocument.baseColor = parsed;
        };
        albedoButton = new UiButton(ctx, "Albedo: None", 260, 26, this);
        albedoButton.onClick = openTextureMenu;
        specAmountField = new TextInputField(ctx, "Specular", 260, 26, "0.18", this);
        specAmountField.onCommit = function(value) {
            if (currentDocument != null) currentDocument.specularAmount = parseNumber(value, currentDocument.specularAmount);
        };
        specPowerField = new TextInputField(ctx, "Shininess", 260, 26, "24", this);
        specPowerField.onCommit = function(value) {
            if (currentDocument != null) currentDocument.specularPower = parseNumber(value, currentDocument.specularPower);
        };
        cullingButton = new UiButton(ctx, "Culling: Back", 260, 26, this);
        cullingButton.onClick = openCullingMenu;
        shadowsCheckbox = new UiCheckbox(ctx, "Cast shadows", this);
        shadowsCheckbox.onChanged = function(value) {
            if (currentDocument != null) currentDocument.shadows = value;
        };

        statusText = new UiText(ctx.font, this);
        statusText.textColor = Theme.TEXT_SECONDARY;
        statusText.lineBreak = false;

        var scene = getScene();
        menu = new MenuDropdown(ctx, scene == null ? this : scene);
        layout(widthValue, heightValue);
    }

    static function parseNumber(value:String, fallback:Float):Float {
        var parsed = Std.parseFloat(StringTools.trim(value));
        return Math.isFinite(parsed) ? parsed : fallback;
    }

    public function layout(width:Float, height:Float):Void {
        widthValue = width < 120 ? 120 : width;
        heightValue = height < 200 ? 200 : height;
        background.setSize(widthValue, heightValue);
        materialButton.setPosition(12, 40);
        newButton.setPosition(166, 40);
        deleteButton.setPosition(218, 40);
        saveButton.setPosition(282, 40);

        var fieldWidth = Math.max(150, widthValue - 24);
        nameField.setWidth(fieldWidth);
        nameField.setPosition(12, 78);
        colorField.setWidth(fieldWidth);
        colorField.setPosition(12, 110);
        albedoButton.setWidth(fieldWidth);
        albedoButton.setPosition(12, 142);
        specAmountField.setWidth((fieldWidth - 12) * 0.5);
        specAmountField.setPosition(12, 174);
        specPowerField.setWidth((fieldWidth - 12) * 0.5);
        specPowerField.setPosition(12 + (fieldWidth - 12) * 0.5 + 12, 174);
        cullingButton.setWidth(fieldWidth);
        cullingButton.setPosition(12, 206);
        shadowsCheckbox.setWidth(fieldWidth);
        shadowsCheckbox.setPosition(12, 238);
        statusText.setPosition(12, heightValue - 26);

        if (currentSource != "") refreshFields();
    }

    /** Load a material document for editing. */
    public function edit(source:String, document:MaterialDocument):Void {
        currentSource = source;
        currentDocument = document;
        refreshFields();
        setStatus('Editing ${document.name}');
    }

    public function currentSourcePath():String return currentSource;

    /** Clear the editor after its material was deleted. */
    public function clear():Void {
        currentSource = "";
        currentDocument = null;
        materialButton.setText("No material");
        nameField.setValue("");
        colorField.setValue("FFFFFF");
        albedoButton.setText("Albedo: None");
        specAmountField.setValue("0.18");
        specPowerField.setValue("24");
        cullingButton.setText("Culling: Back");
        shadowsCheckbox.value = false;
        statusText.text = "";
    }

    function refreshFields():Void {
        if (currentDocument == null) return;
        nameField.setValue(currentDocument.name);
        colorField.setValue(StringTools.hex(currentDocument.baseColor, 6).toUpperCase());
        specAmountField.setValue(Std.string(currentDocument.specularAmount));
        specPowerField.setValue(Std.string(currentDocument.specularPower));
        shadowsCheckbox.value = currentDocument.shadows;
        albedoButton.setText("Albedo: " + textureLabel(currentDocument.albedoTexture));
        cullingButton.setText("Culling: " + currentDocument.culling.charAt(0).toUpperCase()
            + currentDocument.culling.substr(1));
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

    function saveCurrent():Void {
        if (currentDocument == null || currentSource == "") {
            setStatus("Create or select a material first.");
            return;
        }
        if (currentDocument.name.length == 0) {
            setStatus("Material name cannot be empty.");
            return;
        }
        if (onSave != null) onSave(currentSource, currentDocument);
    }

    function openMaterialMenu():Void {
        var items:Array<MenuItem> = [];
        for (material in Material.all()) {
            if (material.source == "") continue;
            var source = material.source;
            items.push({
                label: material.name,
                selected: source == currentSource,
                onClick: function() {
                    if (onStatus != null) onStatus('open:${source}');
                }
            });
        }
        if (items.length == 0) items.push({ label: "No project materials", separator: true });
        showMenu(materialButton, items);
    }

    function openTextureMenu():Void {
        var items:Array<MenuItem> = [{
            label: "None",
            selected: currentDocument == null || currentDocument.albedoTexture == "",
            onClick: function() {
                if (currentDocument != null) {
                    currentDocument.albedoTexture = "";
                    refreshFields();
                }
            }
        }];
        for (texture in MaterialTextureLibrary.all()) {
            var id = texture.id;
            items.push({
                label: texture.label,
                selected: currentDocument != null && currentDocument.albedoTexture == id,
                onClick: function() {
                    if (currentDocument != null) {
                        currentDocument.albedoTexture = id;
                        refreshFields();
                    }
                }
            });
        }
        showMenu(albedoButton, items);
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
                    if (currentDocument != null) {
                        currentDocument.culling = value;
                        refreshFields();
                    }
                }
            });
        }
        showMenu(cullingButton, items);
    }

    function showMenu(anchor:UiButton, items:Array<MenuItem>):Void {
        var point = anchor.localToGlobal(new h2d.col.Point(0, anchor.height + 2));
        menu.open(point.x, point.y, items);
    }
}
