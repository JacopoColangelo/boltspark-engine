/* Boltspark raw-Win32 floating dock panel host.
 *
 * A floating panel is a real top-level HWND owned by the editor process. It has
 * no swapchain, no second GPU device and no foreign event loop: messages are
 * pumped with an hwnd-filtered PeekMessage from Heaps' update(), and the panel
 * is painted with GDI from a CPU RGBA buffer supplied by Haxe.
 *
 * Rules learned from the failed experiments (see docs/FLOATING_WINDOWS_PLAN.md):
 *   - never PostQuitMessage from here (it would kill Heaps' main loop),
 *   - never pump with a system-wide message filter (it would steal editor input),
 *   - never call DestroyWindow from inside the Haxe event callback (the handle
 *     is still in use by pump()); report "closed" and let Haxe destroy later.
 */

#define HL_NAME(n) winfloat_##n

#include <hl.h>

/* hl.h uses _GUID as a HashLink signature; the Windows SDK needs the real tag. */
#undef _GUID
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <dwmapi.h>
#ifndef GET_X_LPARAM
#define GET_X_LPARAM(lp) ((int)(short)LOWORD(lp))
#define GET_Y_LPARAM(lp) ((int)(short)HIWORD(lp))
#endif

#include <stdlib.h>
#include <string.h>

#define _WINFLOAT _ABSTRACT(winfloat_panel)
#define _WINFLOAT_LABEL _ABSTRACT(winfloat_label)

typedef struct {
    HWND hwnd;
    vclosure *on_event;
    int destroyed;
    /* Focus/capture messages can be sent synchronously while HashLink is
     * already inside another native call. Latch them and notify Haxe only from
     * winfloat_pump(), never by re-entering the VM from that WndProc stack. */
    int pending_focus_lost;
    int pending_focus_gained;
    /* Buffer handed to paint() for the next WM_PAINT. Only valid during the
     * synchronous UpdateWindow() call in winfloat_paint(). */
    void *pixels;
    int pixel_w;
    int pixel_h;
    int header_h; /* client rows treated as the draggable title strip */
    int buttons_x; /* rightmost header region owned by the H2D close/minimize buttons */
} Panel;

/* ReleaseCapture() synchronously sends WM_CAPTURECHANGED. A release requested
 * by Haxe is the successful end/cancellation of a gesture, not a new external
 * interruption that should be delivered on the next frame. */
static int intentional_capture_release = 0;

static void blit_panel(Panel *panel, HDC dc, void *pixels, int width,
        int height) {
    BITMAPINFO info;
    if (panel == NULL || pixels == NULL || width <= 0 || height <= 0)
        return;
    memset(&info, 0, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height; /* top-down rows */
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    StretchDIBits(dc, 0, 0, width, height, 0, 0, width, height,
        pixels, &info, DIB_RGB_COLORS, SRCCOPY);
}

/* Event kinds are part of the Haxe binding: (kind, a, b, c). */
enum {
    WF_CLOSE = 0,
    WF_DESTROY = 1,
    WF_RESIZE = 2,
    WF_MOUSEMOVE = 3,
    WF_LBUTTONDOWN = 4,
    WF_LBUTTONUP = 5,
    WF_WHEEL = 6,
    WF_PAINT = 7,
    WF_KEYDOWN = 8,
    WF_KEYUP = 9,
    WF_CHAR = 10,
    WF_RBUTTONDOWN = 11,
    WF_RBUTTONUP = 12,
    /* Focus/capture changes: the OS stole the mouse (Alt+Tab, Win key,
     * screenshot overlay). Haxe cancels any active gesture after WndProc and
     * winfloat_pump() have returned to a safe frame boundary. */
    WF_FOCUS_LOST = 13,
    WF_FOCUS_GAINED = 14
};

static void fire(Panel *panel, int kind, int a, int b, int c) {
    vdynamic va, vb, vc, vd;
    vdynamic *args[4];
    bool exception = false;

    if (panel == NULL || panel->on_event == NULL)
        return;
    va.t = &hlt_i32; va.v.i = kind;
    vb.t = &hlt_i32; vb.v.i = a;
    vc.t = &hlt_i32; vc.v.i = b;
    vd.t = &hlt_i32; vd.v.i = c;
    args[0] = &va; args[1] = &vb; args[2] = &vc; args[3] = &vd;
    hl_dyn_call_safe(panel->on_event, args, 4, &exception);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    Panel *panel = (Panel *)GetWindowLongPtr(hwnd, GWLP_USERDATA);

    switch (msg) {
        case WM_CLOSE:
            /* DestroyWindow is safe here: fire() only queues a Haxe message,
             * it never calls back into winfloat_destroy(). */
            fire(panel, WF_CLOSE, 0, 0, 0);
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            if (panel != NULL) panel->destroyed = 1;
            fire(panel, WF_DESTROY, 0, 0, 0);
            return 0; /* never PostQuitMessage: that would kill Heaps' loop */
        case WM_ACTIVATE:
            if (panel != NULL) {
                if (LOWORD(wp) == WA_INACTIVE)
                    panel->pending_focus_lost = 1;
                else
                    panel->pending_focus_gained = 1;
            }
            break;
        case WM_SETFOCUS:
            if (panel != NULL) panel->pending_focus_gained = 1;
            break;
        case WM_KILLFOCUS:
            if (panel != NULL) panel->pending_focus_lost = 1;
            break;
        case WM_CANCELMODE:
            /* Windows sends this when it revokes mouse capture. */
            if (panel != NULL) panel->pending_focus_lost = 1;
            break;
        case WM_CAPTURECHANGED:
            /* Capture can be stolen without an activation transition. This is
             * still terminal for any H2D gesture owned by this float. */
            if (panel != NULL && !intentional_capture_release
                    && (HWND)lp != hwnd)
                panel->pending_focus_lost = 1;
            break;
        case WM_SIZE:
            fire(panel, WF_RESIZE, LOWORD(lp), HIWORD(lp), 0);
            return 0;
        case WM_MOUSEMOVE:
            fire(panel, WF_MOUSEMOVE, GET_X_LPARAM(lp), GET_Y_LPARAM(lp), 0);
            return 0;
        case WM_LBUTTONDOWN:
            fire(panel, WF_LBUTTONDOWN, GET_X_LPARAM(lp), GET_Y_LPARAM(lp), 0);
            return 0;
        case WM_LBUTTONUP:
            fire(panel, WF_LBUTTONUP, GET_X_LPARAM(lp), GET_Y_LPARAM(lp), 0);
            return 0;
        case WM_RBUTTONDOWN:
            fire(panel, WF_RBUTTONDOWN, GET_X_LPARAM(lp), GET_Y_LPARAM(lp), 0);
            return 0;
        case WM_RBUTTONUP:
            fire(panel, WF_RBUTTONUP, GET_X_LPARAM(lp), GET_Y_LPARAM(lp), 0);
            return 0;
        case WM_MOUSEWHEEL: {
            /* lParam is screen-based for wheel messages; Heaps needs client
             * coordinates so the widget under the cursor receives the scroll. */
            POINT pt;
            pt.x = GET_X_LPARAM(lp);
            pt.y = GET_Y_LPARAM(lp);
            ScreenToClient(hwnd, &pt);
            fire(panel, WF_WHEEL, pt.x, pt.y,
                (int)GET_WHEEL_DELTA_WPARAM(wp));
            return 0;
        }
        case WM_KEYDOWN:
            fire(panel, WF_KEYDOWN, (int)wp, 0, 0);
            return 0;
        case WM_KEYUP:
            fire(panel, WF_KEYUP, (int)wp, 0, 0);
            return 0;
        case WM_CHAR:
            fire(panel, WF_CHAR, (int)wp, 0, 0);
            return 0;
        case WM_NCPAINT: {
            /* Paint the resize frame in the editor palette. The default frame
             * is a bright white strip above our dark header. */
            HDC dc = GetWindowDC(hwnd);
            RECT wr, cr, band;
            POINT origin;
            int borderL, borderT, borderR, borderB;
            HBRUSH brush;
            if (dc == NULL) return 0;
            GetWindowRect(hwnd, &wr);
            GetClientRect(hwnd, &cr);
            origin.x = 0;
            origin.y = 0;
            ClientToScreen(hwnd, &origin);
            borderL = origin.x - wr.left;
            borderT = origin.y - wr.top;
            borderR = wr.right - wr.left - (borderL + cr.right);
            borderB = wr.bottom - wr.top - (borderT + cr.bottom);
            brush = CreateSolidBrush(RGB(0x30, 0x31, 0x34));
            band.left = 0; band.top = 0;
            band.right = wr.right - wr.left; band.bottom = borderT;
            FillRect(dc, &band, brush);
            band.top = borderT + cr.bottom;
            band.bottom = band.top + borderB;
            FillRect(dc, &band, brush);
            band.top = borderT;
            band.bottom = band.top + cr.bottom;
            band.left = 0; band.right = borderL;
            FillRect(dc, &band, brush);
            band.left = borderL + cr.right;
            band.right = band.left + borderR;
            FillRect(dc, &band, brush);
            DeleteObject(brush);
            ReleaseDC(hwnd, dc);
            return 0;
        }
        case WM_NCHITTEST: {
            /* Frameless popup: synthesize the caption strip and 4px resize
             * edges. Returning resize hit codes still engages Windows' modal
             * sizing loop without giving DWM a frame to paint. */
            POINT pt;
            RECT cr;
            int w, h;
            if (panel == NULL || !GetClientRect(hwnd, &cr))
                return HTCLIENT;
            pt.x = GET_X_LPARAM(lp);
            pt.y = GET_Y_LPARAM(lp);
            if (!ScreenToClient(hwnd, &pt))
                return HTCLIENT;
            w = cr.right;
            h = cr.bottom;
            {
                int left = pt.x <= 4;
                int right = pt.x >= w - 5;
                int top = pt.y <= 4;
                int bottom = pt.y >= h - 5;
                /* Resize edges win over the caption strip so the top border of
                 * the frameless window can still be dragged to resize. */
                if (top && left) return HTTOPLEFT;
                if (top && right) return HTTOPRIGHT;
                if (bottom && left) return HTBOTTOMLEFT;
                if (bottom && right) return HTBOTTOMRIGHT;
                if (left) return HTLEFT;
                if (right) return HTRIGHT;
                if (top) return HTTOP;
                if (bottom) return HTBOTTOM;
            }
            if (pt.y >= 0 && pt.y < panel->header_h
                    && (panel->buttons_x <= 0 || pt.x < panel->buttons_x)) {
                return HTCAPTION;
            }
            return HTCLIENT;
        }
        case WM_SETCURSOR:
            /* Restore the arrow as soon as the pointer enters the client area;
             * leave non-client hit tests (resize borders) to DefWindowProc. */
            switch (LOWORD(lp)) {
                case HTCLIENT:
                    /* Heaps' SceneEvents chooses the client cursor (arrow,
                     * text I-beam, splitter resize) while dispatching float
                     * input. Resetting it to the arrow here made every H2D
                     * cursor invisible inside floating panels. */
                    return TRUE;
                case HTLEFT: case HTRIGHT:
                    SetCursor(LoadCursorA(NULL, IDC_SIZEWE));
                    return TRUE;
                case HTTOP: case HTBOTTOM:
                    SetCursor(LoadCursorA(NULL, IDC_SIZENS));
                    return TRUE;
                case HTTOPLEFT: case HTBOTTOMRIGHT:
                    SetCursor(LoadCursorA(NULL, IDC_SIZENWSE));
                    return TRUE;
                case HTTOPRIGHT: case HTBOTTOMLEFT:
                    SetCursor(LoadCursorA(NULL, IDC_SIZENESW));
                    return TRUE;
                default:
                    break;
            }
            break;
        case WM_ERASEBKGND:
            /* We paint the whole client area from the CPU buffer. */
            return 1;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            BeginPaint(hwnd, &paint);
            /* Paint into the HDC supplied by BeginPaint. Painting through a
             * GetDC obtained outside WM_PAINT leaves DWM showing a stale frame. */
            blit_panel(panel, paint.hdc, panel == NULL ? NULL : panel->pixels,
                panel == NULL ? 0 : panel->pixel_w,
                panel == NULL ? 0 : panel->pixel_h);
            EndPaint(hwnd, &paint);
            fire(panel, WF_PAINT, 0, 0, 0);
            return 0;
        }
    }
    return DefWindowProc(hwnd, msg, wp, lp);
}

/* ---------------------------------------------------------------------------
 * Drag-label overlay: one small, always-on-top, click-through HWND that draws
 * the shared drag label above every window. Keeping it in its own HWND avoids
 * duplicate labels (main editor + float scene) and stops the float's header
 * from covering the label when the pointer crosses the title bar.
 * --------------------------------------------------------------------------- */

static LRESULT CALLBACK LabelWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    Panel *panel = (Panel *)GetWindowLongPtr(hwnd, GWLP_USERDATA);
    switch (msg) {
        case WM_NCHITTEST:
            return HTTRANSPARENT; /* never steal clicks from the editor/floats */
        case WM_NCPAINT:
        case WM_ERASEBKGND:
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            HDC dc = BeginPaint(hwnd, &paint);
            blit_panel(panel, dc, panel == NULL ? NULL : panel->pixels,
                panel == NULL ? 0 : panel->pixel_w,
                panel == NULL ? 0 : panel->pixel_h);
            EndPaint(hwnd, &paint);
            return 0;
        }
        case WM_CLOSE:
            return 0;
        case WM_DESTROY:
            return 0;
    }
    return DefWindowProc(hwnd, msg, wp, lp);
}

HL_PRIM void *HL_NAME(overlay_create)(void) {
    static bool registered = false;
    Panel *panel;

    if (!registered) {
        WNDCLASSEXA cls;
        memset(&cls, 0, sizeof(cls));
        cls.cbSize = sizeof(cls);
        cls.lpfnWndProc = LabelWndProc;
        cls.hInstance = GetModuleHandleA(NULL);
        cls.lpszClassName = "BoltSparkDragLabel";
        cls.hCursor = LoadCursorA(NULL, IDC_ARROW);
        if (RegisterClassExA(&cls) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            return NULL;
        registered = true;
    }
    panel = (Panel *)calloc(1, sizeof(Panel));
    if (panel == NULL)
        return NULL;
    panel->hwnd = CreateWindowExA(
        WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
        "BoltSparkDragLabel", "Boltspark Drag Label", WS_POPUP,
        0, 0, 1, 1, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (panel->hwnd == NULL) {
        free(panel);
        return NULL;
    }
    SetWindowLongPtr(panel->hwnd, GWLP_USERDATA, (LONG_PTR)panel);
    /* Magenta is the transparent key; Haxe fills the rest of the buffer with
     * it and paints the label frame/text in real colours. */
    SetLayeredWindowAttributes(panel->hwnd, RGB(255, 0, 255), 0, LWA_COLORKEY);
    return panel;
}

HL_PRIM void HL_NAME(overlay_paint)(void *handle, vbyte *pixels, int w, int h,
        int x, int y) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL || pixels == NULL || !IsWindow(panel->hwnd)
            || w <= 0 || h <= 0)
        return;
    if (w != panel->pixel_w || h != panel->pixel_h || panel->pixels == NULL) {
        free(panel->pixels);
        panel->pixels = malloc((size_t)w * h * 4);
        panel->pixel_w = w;
        panel->pixel_h = h;
    }
    if (panel->pixels == NULL)
        return;
    memcpy(panel->pixels, pixels, (size_t)w * h * 4);
    SetWindowPos(panel->hwnd, HWND_TOPMOST, x, y, w, h,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(panel->hwnd, NULL, FALSE);
    UpdateWindow(panel->hwnd);
}

HL_PRIM void HL_NAME(overlay_hide)(void *handle) {
    Panel *panel = (Panel *)handle;
    if (panel != NULL && IsWindow(panel->hwnd))
        ShowWindow(panel->hwnd, SW_HIDE);
}

HL_PRIM void HL_NAME(overlay_destroy)(void *handle) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL)
        return;
    if (IsWindow(panel->hwnd))
        DestroyWindow(panel->hwnd);
    free(panel->pixels);
    free(panel);
}

HL_PRIM void *HL_NAME(create)(vbyte *title, int x, int y, int w, int h,
        vclosure *on_event) {
    static bool registered = false;
    Panel *panel;

    if (!registered) {
        WNDCLASSEXA cls;
        memset(&cls, 0, sizeof(cls));
        cls.cbSize = sizeof(cls);
        cls.lpfnWndProc = WndProc;
        cls.hInstance = GetModuleHandleA(NULL);
        cls.lpszClassName = "BoltSparkFloatPanel";
        cls.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
        /* Without an explicit class cursor, the sizing arrows chosen over the
         * resize borders stay visible when the pointer enters the client area. */
        cls.hCursor = LoadCursorA(NULL, IDC_ARROW);
        if (RegisterClassExA(&cls) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            return NULL;
        registered = true;
    }
    panel = (Panel *)calloc(1, sizeof(Panel));
    if (panel == NULL)
        return NULL;
    panel->on_event = on_event;
    if (on_event != NULL)
        hl_add_root(&panel->on_event);
    /* Fully frameless: the float renders its own editor-themed header and
     * synthesizes resize hit tests, so DWM cannot paint a bright frame. */
    panel->hwnd = CreateWindowExA(WS_EX_APPWINDOW, "BoltSparkFloatPanel",
        title == NULL ? "Boltspark" : (LPCSTR)title,
        WS_POPUP | WS_CLIPCHILDREN | WS_VISIBLE,
        x, y, w, h, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (panel->hwnd == NULL) {
        if (on_event != NULL) hl_remove_root(&panel->on_event);
        free(panel);
        return NULL;
    }
    SetWindowLongPtr(panel->hwnd, GWLP_USERDATA, (LONG_PTR)panel);
    {
        /* DWM paints the 1px resize frame even when WM_NCPAINT is handled;
         * give it the editor palette instead of the default bright white. */
        COLORREF border = RGB(0x30, 0x31, 0x34);
        DwmSetWindowAttribute(panel->hwnd, 34 /* DWMWA_BORDER_COLOR */,
            &border, sizeof(border));
    }
    UpdateWindow(panel->hwnd);
    return panel;
}

HL_PRIM void HL_NAME(pump)(void *handle) {
    Panel *panel = (Panel *)handle;
    MSG msg;
    int focus_lost;
    int focus_gained;

    if (panel == NULL)
        return;
    /* IsWindow check matters after WM_CLOSE destroyed the HWND mid-drain.
     * PM_NOREMOVE first gives Windows a chance to deliver cross-thread sent
     * focus messages. Once focus loss is latched, leave later pointer input in
     * the queue until Haxe has cancelled the old gesture. */
    while (IsWindow(panel->hwnd)) {
        if (!PeekMessageA(&msg, panel->hwnd, 0, 0, PM_NOREMOVE))
            break;
        if (panel->pending_focus_lost)
            break;
        if (!PeekMessageA(&msg, panel->hwnd, 0, 0, PM_REMOVE))
            continue;
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
        if (panel->pending_focus_lost)
            break;
    }
    /* Focus notifications are intentionally emitted only here. In particular,
     * ReleaseCapture/SetForegroundWindow can invoke WndProc synchronously from
     * arbitrary native calls, where calling back into HashLink can corrupt the
     * active VM/event stack. */
    focus_lost = panel->pending_focus_lost;
    focus_gained = panel->pending_focus_gained;
    panel->pending_focus_lost = 0;
    panel->pending_focus_gained = 0;
    if (!panel->destroyed && focus_lost)
        fire(panel, WF_FOCUS_LOST, 0, 0, 0);
    if (!panel->destroyed && focus_gained)
        fire(panel, WF_FOCUS_GAINED, 0, 0, 0);
}

HL_PRIM void HL_NAME(paint)(void *handle, vbyte *pixels, int width, int height) {
    Panel *panel = (Panel *)handle;

    if (panel == NULL || pixels == NULL || width <= 0 || height <= 0)
        return;
    if (!IsWindow(panel->hwnd))
        return;
    /* Hand the buffer to WM_PAINT and force an immediate paint. UpdateWindow
     * dispatches WM_PAINT synchronously, so the pointer stays valid; clear it
     * afterwards so a later exposure never uses a stale Haxe Bytes pointer. */
    panel->pixels = pixels;
    panel->pixel_w = width;
    panel->pixel_h = height;
    InvalidateRect(panel->hwnd, NULL, FALSE);
    UpdateWindow(panel->hwnd);
    panel->pixels = NULL;
    panel->pixel_w = 0;
    panel->pixel_h = 0;
}

HL_PRIM void HL_NAME(set_geometry)(void *handle, int x, int y, int w, int h) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL || !IsWindow(panel->hwnd))
        return;
    SetWindowPos(panel->hwnd, NULL, x, y, w, h,
        SWP_NOZORDER | SWP_NOACTIVATE);
}

HL_PRIM int HL_NAME(client_width)(void *handle) {
    Panel *panel = (Panel *)handle;
    RECT rect;
    if (panel == NULL || !IsWindow(panel->hwnd)
            || !GetClientRect(panel->hwnd, &rect))
        return 0;
    return (int)(rect.right - rect.left);
}

HL_PRIM int HL_NAME(client_height)(void *handle) {
    Panel *panel = (Panel *)handle;
    RECT rect;
    if (panel == NULL || !IsWindow(panel->hwnd)
            || !GetClientRect(panel->hwnd, &rect))
        return 0;
    return (int)(rect.bottom - rect.top);
}

HL_PRIM int HL_NAME(get_dpi)(void *handle) {
    Panel *panel = (Panel *)handle;
    UINT dpi;
    if (panel == NULL || !IsWindow(panel->hwnd))
        return 96;
    dpi = GetDpiForWindow(panel->hwnd);
    return dpi > 0 ? (int)dpi : 96;
}

HL_PRIM void HL_NAME(set_header_height)(void *handle, int height,
        int buttonsX) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL)
        return;
    panel->header_h = height > 0 ? height : 0;
    panel->buttons_x = buttonsX > 0 ? buttonsX : 0;
}

HL_PRIM void HL_NAME(minimize)(void *handle) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL || !IsWindow(panel->hwnd))
        return;
    ShowWindow(panel->hwnd, SW_MINIMIZE);
}

HL_PRIM int HL_NAME(cursor_x)(void) {
    POINT pt;
    return GetCursorPos(&pt) ? (int)pt.x : 0;
}

HL_PRIM int HL_NAME(cursor_y)(void) {
    POINT pt;
    return GetCursorPos(&pt) ? (int)pt.y : 0;
}

HL_PRIM int HL_NAME(window_x)(void *handle) {
    Panel *panel = (Panel *)handle;
    RECT rect;
    if (panel == NULL || !IsWindow(panel->hwnd)
            || !GetWindowRect(panel->hwnd, &rect))
        return 0;
    return (int)rect.left;
}

HL_PRIM int HL_NAME(window_y)(void *handle) {
    Panel *panel = (Panel *)handle;
    RECT rect;
    if (panel == NULL || !IsWindow(panel->hwnd)
            || !GetWindowRect(panel->hwnd, &rect))
        return 0;
    return (int)rect.top;
}

/* Client origin of an arbitrary HWND in screen coordinates. The editor's
 * hldx Window.x/y report the *window rect* (frame) origin, not the client
 * origin; using those for cross-window drag coordinates puts drops below
 * their target by the height of the title bar. `win` is hldx's dx_window
 * handle, which is exactly an HWND. */
HL_PRIM int HL_NAME(client_origin_x)(void *win) {
    POINT pt;
    pt.x = 0;
    pt.y = 0;
    if (win == NULL || !ClientToScreen((HWND)win, &pt))
        return 0;
    return (int)pt.x;
}

HL_PRIM int HL_NAME(client_origin_y)(void *win) {
    POINT pt;
    pt.x = 0;
    pt.y = 0;
    if (win == NULL || !ClientToScreen((HWND)win, &pt))
        return 0;
    return (int)pt.y;
}

HL_PRIM void HL_NAME(move_window)(void *handle, int x, int y) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL || !IsWindow(panel->hwnd))
        return;
    SetWindowPos(panel->hwnd, NULL, x, y, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

HL_PRIM void HL_NAME(set_capture)(void *handle) {
    Panel *panel = (Panel *)handle;
    if (panel != NULL && IsWindow(panel->hwnd))
        SetCapture(panel->hwnd);
}

HL_PRIM void HL_NAME(release_capture)(void) {
    intentional_capture_release = 1;
    ReleaseCapture();
    intentional_capture_release = 0;
}

HL_PRIM void HL_NAME(set_title)(void *handle, vbyte *title) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL || title == NULL || !IsWindow(panel->hwnd))
        return;
    SetWindowTextA(panel->hwnd, (LPCSTR)title);
}

HL_PRIM void HL_NAME(destroy)(void *handle) {
    Panel *panel = (Panel *)handle;
    if (panel == NULL)
        return;
    if (IsWindow(panel->hwnd))
        DestroyWindow(panel->hwnd);
    if (panel->on_event != NULL)
        hl_remove_root(&panel->on_event);
    free(panel);
}

DEFINE_PRIM(_WINFLOAT, create,
    _BYTES _I32 _I32 _I32 _I32 _FUN(_VOID, _I32 _I32 _I32 _I32));
DEFINE_PRIM(_VOID, pump, _WINFLOAT);
DEFINE_PRIM(_VOID, paint, _WINFLOAT _BYTES _I32 _I32);
DEFINE_PRIM(_VOID, set_geometry, _WINFLOAT _I32 _I32 _I32 _I32);
DEFINE_PRIM(_I32, client_width, _WINFLOAT);
DEFINE_PRIM(_I32, client_height, _WINFLOAT);
DEFINE_PRIM(_I32, get_dpi, _WINFLOAT);
DEFINE_PRIM(_VOID, set_title, _WINFLOAT _BYTES);
DEFINE_PRIM(_VOID, set_header_height, _WINFLOAT _I32 _I32);
DEFINE_PRIM(_VOID, minimize, _WINFLOAT);
DEFINE_PRIM(_I32, cursor_x,);
DEFINE_PRIM(_I32, cursor_y,);
DEFINE_PRIM(_I32, window_x, _WINFLOAT);
DEFINE_PRIM(_I32, window_y, _WINFLOAT);
DEFINE_PRIM(_I32, client_origin_x, _ABSTRACT(dx_window));
DEFINE_PRIM(_I32, client_origin_y, _ABSTRACT(dx_window));
DEFINE_PRIM(_VOID, move_window, _WINFLOAT _I32 _I32);
DEFINE_PRIM(_VOID, set_capture, _WINFLOAT);
DEFINE_PRIM(_VOID, release_capture,);
DEFINE_PRIM(_VOID, destroy, _WINFLOAT);
DEFINE_PRIM(_WINFLOAT_LABEL, overlay_create,);
DEFINE_PRIM(_VOID, overlay_paint, _WINFLOAT_LABEL _BYTES _I32 _I32 _I32 _I32);
DEFINE_PRIM(_VOID, overlay_hide, _WINFLOAT_LABEL);
DEFINE_PRIM(_VOID, overlay_destroy, _WINFLOAT_LABEL);
