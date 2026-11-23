/* Boltspark multi-file image picker.
 *
 * HashLink's hl.UI.loadFile() wraps IFileDialog without FOS_ALLOWMULTISELECT
 * and returns a single string, so importing a full texture set (for example
 * Metal049C_2K's albedo/normal/roughness/metalness maps) requires one dialog
 * per file. This module is a small, project-local native extension that uses
 * the same Windows common item dialog with multi-select enabled and returns
 * the chosen paths as an array of UCS-2 byte strings (the format HashLink's
 * String.fromUCS2 expects).
 *
 * No toolchain file is modified: this is built alongside winfloat.hdll from
 * tools/native/ by tools/build.ps1 and linked into the native release.
 */

#define HL_NAME(n) multifile_##n

#include <hl.h>

/* hl.h uses _GUID as a HashLink signature; the Windows SDK needs the real tag. */
#undef _GUID
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <shobjidl.h>

#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* HashLink byte strings are not guaranteed to be NUL-terminated, so every
 * input carries an explicit byte length from Haxe. */
static WCHAR *utf8_to_utf16(const vbyte *text, int byte_length) {
    int length;
    WCHAR *result;
    if (text == NULL || byte_length <= 0)
        return NULL;
    length = MultiByteToWideChar(CP_UTF8, 0, (LPCSTR)text, byte_length, NULL, 0);
    if (length <= 0)
        return NULL;
    result = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (result == NULL)
        return NULL;
    MultiByteToWideChar(CP_UTF8, 0, (LPCSTR)text, byte_length, result, length);
    result[length] = 0;
    return result;
}

HL_PRIM varray *HL_NAME(load_images)(vbyte *title, int title_length,
        vbyte *filter_name, int filter_name_length,
        vbyte *filter_spec, int filter_spec_length) {
    HRESULT hr;
    int com_initialized;
    IFileOpenDialog *dialog = NULL;
    IShellItemArray *items = NULL;
    WCHAR *wide_title = NULL;
    WCHAR *wide_name = NULL;
    WCHAR *wide_spec = NULL;
    WCHAR **paths = NULL;
    DWORD count = 0;
    DWORD accepted = 0;
    DWORD index;
    varray *result = NULL;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    com_initialized = SUCCEEDED(hr);
    wide_title = utf8_to_utf16(title, title_length);
    wide_name = utf8_to_utf16(filter_name, filter_name_length);
    wide_spec = utf8_to_utf16(filter_spec, filter_spec_length);
    if (wide_title == NULL || wide_name == NULL || wide_spec == NULL)
        goto cleanup;

    hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
        &IID_IFileOpenDialog, (void **)&dialog);
    if (FAILED(hr))
        goto cleanup;

    FILEOPENDIALOGOPTIONS options;
    if (FAILED(dialog->lpVtbl->GetOptions(dialog, &options)))
        goto cleanup;
    options |= FOS_ALLOWMULTISELECT | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST;
    if (FAILED(dialog->lpVtbl->SetOptions(dialog, options)))
        goto cleanup;
    dialog->lpVtbl->SetTitle(dialog, wide_title);

    /* One image-only filter: no "All Files" escape hatch. */
    COMDLG_FILTERSPEC filters[1];
    filters[0].pszName = wide_name;
    filters[0].pszSpec = wide_spec;
    if (FAILED(dialog->lpVtbl->SetFileTypes(dialog, 1, filters)))
        goto cleanup;
    if (FAILED(dialog->lpVtbl->SetFileTypeIndex(dialog, 1)))
        goto cleanup;

    if (FAILED(dialog->lpVtbl->Show(dialog, NULL)))
        goto cleanup; /* ERROR_CANCELLED is the normal Cancel path. */
    if (FAILED(dialog->lpVtbl->GetResults(dialog, &items)))
        goto cleanup;

    items->lpVtbl->GetCount(items, &count);
    if (count == 0)
        goto cleanup;
    paths = (WCHAR **)calloc(count, sizeof(WCHAR *));
    if (paths == NULL)
        goto cleanup;
    for (index = 0; index < count; index++) {
        IShellItem *item = NULL;
        WCHAR *path = NULL;
        if (FAILED(items->lpVtbl->GetItemAt(items, index, &item)))
            continue;
        if (SUCCEEDED(item->lpVtbl->GetDisplayName(item, SIGDN_FILESYSPATH, &path))
                && path != NULL) {
            paths[accepted++] = path;
        }
        item->lpVtbl->Release(item);
    }
    if (accepted == 0)
        goto cleanup;

    /* HashLink allocates through its GC; the array keeps these bytes rooted. */
    result = hl_alloc_array(&hlt_bytes, (int)accepted);
    for (index = 0; index < accepted; index++) {
        int chars = (int)wcslen(paths[index]) + 1;
        vbyte *bytes = hl_alloc_bytes(chars * (int)sizeof(WCHAR));
        memcpy(bytes, paths[index], (size_t)chars * sizeof(WCHAR));
        hl_aptr(result, vbyte *)[index] = bytes;
    }

cleanup:
    if (paths != NULL) {
        for (index = 0; index < count; index++) {
            if (paths[index] != NULL)
                CoTaskMemFree(paths[index]);
        }
        free(paths);
    }
    if (items != NULL)
        items->lpVtbl->Release(items);
    if (dialog != NULL)
        dialog->lpVtbl->Release(dialog);
    free(wide_title);
    free(wide_name);
    free(wide_spec);
    if (com_initialized)
        CoUninitialize();
    return result;
}

DEFINE_PRIM(_ARR, load_images, _BYTES _I32 _BYTES _I32 _BYTES _I32);
