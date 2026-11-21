# 诊断辅助:枚举指定进程的所有顶层窗口(样式/坐标/可见性)。用法: . .\windiag.ps1; [WinDiag]::Dump($pid)
if (-not ('WinDiag' -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinDiag {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int idx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static void Dump(int targetPid) {
    EnumWindows((h, l) => {
      int pid; GetWindowThreadProcessId(h, out pid);
      if (pid == targetPid) {
        var sb = new StringBuilder(256); GetWindowTextW(h, sb, 256);
        var cls = new StringBuilder(256); GetClassNameW(h, cls, 256);
        RECT r; GetWindowRect(h, out r);
        long st = GetWindowLongPtr(h, -16).ToInt64(); long ex = GetWindowLongPtr(h, -20).ToInt64();
        Console.WriteLine(string.Format("hwnd={0:X} cls={1} title={2} vis={3} min={4} rect={5},{6}-{7},{8} style={9:X} ex={10:X} topmost={11} popup={12}",
          h.ToInt64(), cls, sb, IsWindowVisible(h), IsIconic(h), r.L, r.T, r.R, r.B, st, ex, (ex & 0x8L) != 0, (st & 0x80000000L) != 0));
      }
      return true;
    }, IntPtr.Zero);
  }
}
"@
}
