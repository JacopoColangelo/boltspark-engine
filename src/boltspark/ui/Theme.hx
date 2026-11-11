package boltspark.ui;

/**
 * BoltUI theme tokens.
 *
 * All colors are sRGB hex values (0xRRGGBB) and all sizes are logical
 * pixels at 1x scale. The palette intentionally keeps contrast restrained:
 * surfaces carry structure while the blue accent is reserved for focus,
 * selection, and primary actions.
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
    public static inline var TITLE_BAR_HEIGHT:Int = 36;
    public static inline var TOOLBAR_HEIGHT:Int = 46;
    public static inline var TOP_BAR_HEIGHT:Int = TITLE_BAR_HEIGHT + TOOLBAR_HEIGHT;
    public static inline var STATUS_BAR_HEIGHT:Int = 26;
    public static inline var CONSOLE_HEIGHT:Int = 190;
    public static inline var LEFT_PANEL_WIDTH:Int = 268;
    public static inline var RIGHT_PANEL_WIDTH:Int = 326;
    public static inline var SPLITTER_SIZE:Int = 6;
    public static inline var SPLITTER_VISIBLE_WIDTH:Int = 1;
    public static inline var SPLITTER_HOVER:Int = 0x4C9AFF;
    public static inline var MIN_LEFT_PANEL_WIDTH:Int = 220;
    public static inline var MIN_CENTER_PANEL_WIDTH:Int = 240;
    public static inline var MIN_RIGHT_PANEL_WIDTH:Int = 240;
    public static inline var SPACING:Int = 12;
    public static inline var BUTTON_WIDTH:Int = 184;
    public static inline var BUTTON_HEIGHT:Int = 30;
    public static inline var CONTROL_HEIGHT:Int = 28;
    public static inline var PANEL_HEADER_HEIGHT:Int = 42;
    public static inline var SECTION_HEADER_HEIGHT:Int = 28;
    public static inline var RADIUS:Int = 6;

    // Palette. Flat neutral dark surfaces in the Unreal/CryEngine family:
    // structure comes from borders and inset fields, not from tinted cards.
    public static inline var APP_BG:Int = 0x0D0D0F;
    public static inline var TITLE_BAR:Int = 0x141416;
    public static inline var TOOLBAR:Int = 0x1A1A1D;
    public static inline var TOP_BAR:Int = TITLE_BAR;
    public static inline var PANEL:Int = 0x1D1D20;
    public static inline var PANEL_ALT:Int = 0x212124;
    public static inline var PANEL_HEADER:Int = 0x222225;
    public static inline var SURFACE_1:Int = 0x242427;
    public static inline var SURFACE_2:Int = 0x2A2A2E;
    public static inline var SURFACE_3:Int = 0x323236;
    public static inline var BORDER:Int = 0x35353A;
    public static inline var BORDER_STRONG:Int = 0x46464C;
    public static inline var PANEL_EDGE:Int = 0x2A2A2E;
    public static inline var VIEWPORT_BG:Int = 0x131316;
    public static inline var CONSOLE_BG:Int = 0x141417;
    public static inline var FIELD_BG:Int = 0x141416;
    public static inline var FIELD_FOCUS:Int = 0x1A1A1E;
    public static inline var ACCENT:Int = 0x4C9AFF;
    public static inline var ACCENT_HOVER:Int = 0x68AAFF;
    public static inline var ACCENT_MUTED:Int = 0x243B59;
    public static inline var BRAND:Int = 0xF2A14B;
    public static inline var TEXT:Int = 0xE8ECF2;
    public static inline var TEXT_SECONDARY:Int = 0xB0B8C5;
    public static inline var MUTED:Int = 0x788392;
    public static inline var DISABLED:Int = 0x505965;
    public static inline var BUTTON:Int = SURFACE_2;
    public static inline var BUTTON_HOVER:Int = SURFACE_3;
    public static inline var BUTTON_ACTIVE:Int = ACCENT_MUTED;
    public static inline var PROPERTY_BG:Int = PANEL_ALT;
    public static inline var SCROLL_TRACK:Int = 0x1A1A1D;
    public static inline var SCROLL_THUMB:Int = 0x45454B;
    public static inline var SCROLL_THUMB_HOVER:Int = 0x5C5C63;
    public static inline var SWATCH_EDGE:Int = 0x080A0D;
    public static inline var SWATCH_SELECTED:Int = 0xFFFFFF;
    public static inline var SUCCESS:Int = 0x58C48D;
    public static inline var WARNING:Int = 0xE6B85C;
    public static inline var DANGER:Int = 0xE36B6B;
    public static inline var AXIS_X:Int = 0xE26868;
    public static inline var AXIS_Y:Int = 0x69C183;
    public static inline var AXIS_Z:Int = 0x5F91E8;

    // Editor cube sample colors (also used by the inspector swatches).
    public static inline var CUBE_ORANGE:Int = 0xE58A3A;
    public static inline var CUBE_STEEL:Int = 0x7FA6C9;
    public static inline var CUBE_MOSS:Int = 0x7FB069;
    public static inline var CUBE_VIOLET:Int = 0xA78BFA;
}
