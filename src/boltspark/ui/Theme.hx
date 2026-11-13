package boltspark.ui;

/**
 * BoltUI theme tokens.
 *
 * All colors are sRGB hex values (0xRRGGBB) and all sizes are logical
 * pixels at 1x scale. The palette follows a compact native-editor language:
 * neutral graphite surfaces are separated by crisp one-pixel rules, while a
 * restrained teal accent is reserved for focus, selection, and active tools.
 */
class Theme {
    // Logical UI scaling; the project uses logical pixels before any future
    // DPI-specific adaptation, which keeps the editor shell predictable while
    // the native window still owns final OS sizing.
    public static var uiScale:Float = 1.0;
    public static inline function px(value:Float):Float {
        return value * uiScale;
    }

    // Layout metrics.
    public static inline var TITLE_BAR_HEIGHT:Int = 30;
    public static inline var TOOLBAR_HEIGHT:Int = 36;
    public static inline var TOP_BAR_HEIGHT:Int = TITLE_BAR_HEIGHT + TOOLBAR_HEIGHT;
    public static inline var STATUS_BAR_HEIGHT:Int = 20;
    public static inline var CONSOLE_HEIGHT:Int = 160;
    public static inline var LEFT_PANEL_WIDTH:Int = 250;
    public static inline var RIGHT_PANEL_WIDTH:Int = 318;
    public static inline var SPLITTER_SIZE:Int = 4;
    public static inline var SPLITTER_VISIBLE_WIDTH:Int = 1;
    public static inline var SPLITTER_HOVER:Int = 0x45C7A1;
    public static inline var MIN_LEFT_PANEL_WIDTH:Int = 200;
    public static inline var MIN_CENTER_PANEL_WIDTH:Int = 240;
    public static inline var MIN_RIGHT_PANEL_WIDTH:Int = 260;
    public static inline var SPACING:Int = 8;
    public static inline var BUTTON_WIDTH:Int = 168;
    public static inline var BUTTON_HEIGHT:Int = 26;
    public static inline var CONTROL_HEIGHT:Int = 24;
    public static inline var PANEL_HEADER_HEIGHT:Int = 32;
    public static inline var PANEL_META_HEIGHT:Int = 22;
    public static inline var SECTION_HEADER_HEIGHT:Int = 24;
    // Palette. Flat neutral surfaces in the Unreal/Unity/GritGene family:
    // structure comes from borders and inset fields, never floating cards.
    public static inline var APP_BG:Int = 0x111214;
    public static inline var TITLE_BAR:Int = 0x1B1C1E;
    public static inline var TOOLBAR:Int = 0x252629;
    public static inline var TOP_BAR:Int = TITLE_BAR;
    public static inline var PANEL:Int = 0x292A2D;
    public static inline var PANEL_ALT:Int = 0x2D2E31;
    public static inline var PANEL_HEADER:Int = 0x303134;
    public static inline var SECTION_HEADER:Int = 0x323337;
    public static inline var SURFACE_1:Int = 0x303135;
    public static inline var SURFACE_2:Int = 0x37383C;
    public static inline var SURFACE_3:Int = 0x404146;
    public static inline var BORDER:Int = 0x46474C;
    public static inline var BORDER_STRONG:Int = 0x5A5C62;
    public static inline var PANEL_EDGE:Int = 0x1C1D1F;
    public static inline var VIEWPORT_BG:Int = 0x121519;
    public static inline var CONSOLE_BG:Int = 0x202124;
    public static inline var FIELD_BG:Int = 0x202124;
    public static inline var FIELD_FOCUS:Int = 0x252B2A;
    public static inline var ACCENT:Int = 0x45C7A1;
    public static inline var ACCENT_HOVER:Int = 0x61D6B4;
    public static inline var ACCENT_MUTED:Int = 0x285448;
    public static inline var BRAND:Int = 0xF2A14B;
    public static inline var TEXT:Int = 0xE7E8EA;
    public static inline var TEXT_SECONDARY:Int = 0xC0C2C6;
    public static inline var MUTED:Int = 0x8A8D93;
    public static inline var DISABLED:Int = 0x5D6066;
    public static inline var BUTTON:Int = SURFACE_2;
    public static inline var BUTTON_HOVER:Int = SURFACE_3;
    public static inline var BUTTON_ACTIVE:Int = ACCENT_MUTED;
    public static inline var PROPERTY_BG:Int = PANEL;
    public static inline var SCROLL_TRACK:Int = 0x232427;
    public static inline var SCROLL_THUMB:Int = 0x55575C;
    public static inline var SCROLL_THUMB_HOVER:Int = 0x707278;
    public static inline var SWATCH_EDGE:Int = 0x17181A;
    public static inline var SWATCH_SELECTED:Int = 0xFFFFFF;
    public static inline var SUCCESS:Int = 0x58C48D;
    public static inline var WARNING:Int = 0xE6B85C;
    public static inline var DANGER:Int = 0xE36B6B;
    public static inline var AXIS_X:Int = 0xE26868;
    public static inline var AXIS_Y:Int = 0x69C183;
    public static inline var AXIS_Z:Int = 0x5F91E8;
    // Brighter variants used when a viewport gizmo axis is hovered/dragged.
    public static inline var AXIS_X_HOVER:Int = 0xFF8B8B;
    public static inline var AXIS_Y_HOVER:Int = 0x8FE5AC;
    public static inline var AXIS_Z_HOVER:Int = 0x93B8FF;
    // Two-axis plane handles blend their two axis hues (Unreal-style quad
    // handles), with brighter hover variants.
    public static inline var AXIS_XY:Int = 0xC9B84C;
    public static inline var AXIS_YZ:Int = 0x4FB5C4;
    public static inline var AXIS_ZX:Int = 0xB27BC8;
    public static inline var AXIS_XY_HOVER:Int = 0xE8D96A;
    public static inline var AXIS_YZ_HOVER:Int = 0x78D6E8;
    public static inline var AXIS_ZX_HOVER:Int = 0xD0A2E8;
    // Vivid viewport gizmo colors - deliberately more saturated than the
    // softer inspector label colors above, matching the Unreal reference.
    public static inline var GIZMO_AXIS_X:Int = 0xE8443C;
    public static inline var GIZMO_AXIS_Y:Int = 0x33C85A;
    public static inline var GIZMO_AXIS_Z:Int = 0x3D6EF5;
    public static inline var GIZMO_AXIS_X_HOVER:Int = 0xFF7A6E;
    public static inline var GIZMO_AXIS_Y_HOVER:Int = 0x63E88F;
    public static inline var GIZMO_AXIS_Z_HOVER:Int = 0x7A9CFF;
    public static inline var GIZMO_PLANE_XY:Int = 0xD8C020;
    public static inline var GIZMO_PLANE_YZ:Int = 0x20B8D8;
    public static inline var GIZMO_PLANE_ZX:Int = 0xA855D6;
    public static inline var GIZMO_PLANE_XY_HOVER:Int = 0xF0DC3C;
    public static inline var GIZMO_PLANE_YZ_HOVER:Int = 0x55D8F0;
    public static inline var GIZMO_PLANE_ZX_HOVER:Int = 0xC678F0;
    // Tool-neutral gizmo handles (uniform scale box, move center ball).
    public static inline var GIZMO_NEUTRAL:Int = 0x9AA0A8;
    public static inline var GIZMO_NEUTRAL_HOVER:Int = 0xC8CDD4;

    // Editor cube sample colors (also used by the inspector swatches).
    public static inline var CUBE_ORANGE:Int = 0xE58A3A;
    public static inline var CUBE_STEEL:Int = 0x7FA6C9;
    public static inline var CUBE_MOSS:Int = 0x7FB069;
    public static inline var CUBE_VIOLET:Int = 0xA78BFA;
}
