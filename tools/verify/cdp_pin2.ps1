# M3 验收补跑:确认当前钉住→截图(前台窗口应盖住小窗)→取消→断言回归
$ErrorActionPreference = 'Stop'
. d:\Code\DouYinWin\tools/verify\windiag.ps1
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class PinDiag2 {
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static string ClassOf(IntPtr h) {
    if (h == IntPtr.Zero) return "NULL";
    var sb = new StringBuilder(64); GetClassNameW(h, sb, 64); return sb.ToString();
  }
}
"@
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 1300
function Eval([string]$js) {
  $global:vid++
  $m = '{"id":' + $global:vid + ',"method":"Runtime.evaluate","params":{"expression":"' + (Esc $js) + '","awaitPromise":true,"returnByValue":true}}'
  $b = [Text.Encoding]::UTF8.GetBytes($m)
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  $want = $global:vid
  $sb = New-Object System.Text.StringBuilder
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    $buf = New-Object byte[] 262144
    $seg2 = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $t = $ws.ReceiveAsync($seg2, $ct)
    if (-not $t.Wait(4000)) { break }
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count))
    if (-not $t.Result.EndOfMessage) { continue }
    $j = $null
    try { $j = $sb.ToString() | ConvertFrom-Json } catch { $sb.Clear() | Out-Null; continue }
    $sb.Clear() | Out-Null
    if ($j -and $j.id -eq $want) {
      if ($j.result.exceptionDetails) { return 'JS_EXC:' + $j.result.exceptionDetails.exception.description }
      if ($null -eq $j.result.result.value) { return 'FALSE_OR_NULL' }
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NO_REPLY'
}

# 用窗口枚举在钉住状态下找回句柄(此时已非顶层,MainWindowHandle 可能失效):
# 直接问页面里的 Tauri 也行,但我们手里有 pid
$dp = Get-Process nook | Select-Object -First 1
# 兜底句柄:从注册表拿不到就靠 CDP 问 JS 不行;但 unpin 走 Rust 自己的 PINNED_HWND,无需句柄
$fh = [PinDiag2]::GetForegroundWindow()
Write-Output ("前台窗口类: " + [PinDiag2]::ClassOf($fh))

Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2 = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b2.Width, $b2.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X, $b2.Y, 0, 0, $bmp.Size)
$bmp.Save('d:\Code\DouYinWin\tools/verify\pin_covered.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot: pin_covered.png (钉住状态;前台为 VSCode 时小窗应被盖住,桌面壁纸之上可见——视前台而定)'

Write-Output ('取消钉: ' + (Eval "__TAURI__.core.invoke('toggle_pin').then(v=>'pinned='+v,e=>'ERR:'+String(e).slice(0,120))"))
Start-Sleep 1
$h2 = (Get-Process -Id $dp.Id).MainWindowHandle
Write-Output ("取消后: hwnd={0:X} 父={1} visible={2}" -f $h2.ToInt64(), [PinDiag2]::ClassOf([PinDiag2]::GetParent($h2)), [WinDiag]::IsWindowVisible($h2))
Write-Output ('config: ' + ((Get-Content "$env:APPDATA\cn.nook.desktop\config.json" -Raw) -replace '\s+',' '))
$ws.Dispose()
