# v0.7 验收:锁屏蔽层生效/解除;Ctrl+Q 全局键两下=最小化→弹回
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Kbd {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void CtrlQ() {
    keybd_event(0x11, 0, 0, UIntPtr.Zero);
    keybd_event(0x51, 0, 0, UIntPtr.Zero);
    keybd_event(0x51, 0, 2, UIntPtr.Zero);
    keybd_event(0x11, 0, 2, UIntPtr.Zero);
  }
}
"@
. d:\Code\DouYinWin\tools/verify\windiag.ps1

$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 1400
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

Write-Output ('锁API: ' + (Eval "typeof window.__DYWIN_SET_LOCK"))
Write-Output ('上锁: ' + (Eval "(function(){window.__DYWIN_SET_LOCK(true);var e=document.elementFromPoint((innerWidth/2)|0,(innerHeight/2)|0);return 'overlay='+(e&&e.id==='dywin-lock');})()"))
Write-Output ('模拟点击视频区: ' + (Eval "(function(){var before=document.querySelector('video').paused;var ev=new MouseEvent('click',{bubbles:true,clientX:innerWidth/2,clientY:innerHeight/2});var ov=document.getElementById('dywin-lock');ov.dispatchEvent(ev);var e=document.elementFromPoint((innerWidth/2)|0,(innerHeight/2)|0);return 'hitStillLock='+(e&&e.id==='dywin-lock');})()"))
Write-Output ('解锁: ' + (Eval "(function(){window.__DYWIN_SET_LOCK(false);return 'overlayGone='+!document.getElementById('dywin-lock');})()"))
$ws.Dispose()

# Ctrl+Q 全局往返
$dp = Get-Process nook | Select-Object -First 1
$h = $dp.MainWindowHandle
[Kbd]::CtrlQ(); Start-Sleep 2
$iconic1 = [WinDiag]::IsIconic($h)
Write-Output ("第一下 Ctrl+Q → 期望 minimized=true, 实际=$iconic1")
[Kbd]::CtrlQ(); Start-Sleep 2
$h2 = (Get-Process -Id $dp.Id).MainWindowHandle
$iconic2 = [WinDiag]::IsIconic($h2)
Write-Output ("第二下 Ctrl+Q → 期望 minimized=false, 实际=$iconic2 visible=" + [WinDiag]::IsWindowVisible($h2))
