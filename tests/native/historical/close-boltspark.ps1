Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CloseNative {
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
$p = Get-Process -Name hl -ErrorAction Stop | Select-Object -First 1
[void][CloseNative]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
$exited = $p.WaitForExit(8000)
if ($exited) { 'closed cleanly (exit code ' + $p.ExitCode + ')' } else { 'window did not close on WM_CLOSE' }
