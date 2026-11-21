# 单视频影院冒烟:进入窗不变/宿主在/滑动屏蔽(wheel+方向键)/播完重播/Esc退出
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class S5 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void Wheel(IntPtr h, int n) {
    RECT rc; GetWindowRect(h, out rc);
    SetCursorPos((rc.L+rc.R)/2, (rc.T+rc.B)/2);
    System.Threading.Thread.Sleep(200);
    for (int i=0;i<n;i++){ mouse_event(0x800,0,0,-120,UIntPtr.Zero); System.Threading.Thread.Sleep(60); }
  }
  public static void Tap(byte vk) {
    keybd_event(vk,0,0,UIntPtr.Zero); keybd_event(vk,0,2,UIntPtr.Zero);
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
$global:vid = 2500
function Eval([string]$js) {
  $global:vid++
  $m = '{"id":' + $global:vid + ',"method":"Runtime.evaluate","params":{"expression":"' + (Esc $js) + '","awaitPromise":true,"returnByValue":true}}'
  $b = [Text.Encoding]::UTF8.GetBytes($m)
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  $want = $global:vid
  $sb = New-Object System.Text.StringBuilder
  $deadline = (Get-Date).AddSeconds(25)
  while ((Get-Date) -lt $deadline) {
    $buf = New-Object byte[] 262144
    $seg2 = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $t = $ws.ReceiveAsync($seg2, $ct)
    if (-not $t.Wait(6000)) { break }
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count))
    if (-not $t.Result.EndOfMessage) { continue }
    $j = $null
    try { $j = $sb.ToString() | ConvertFrom-Json } catch { $sb.Clear() | Out-Null; continue }
    $sb.Clear() | Out-Null
    if ($j -and $j.id -eq $want) {
      if ($j.result.exceptionDetails) { return 'EXC:' + $j.result.exceptionDetails.exception.description }
      if ($null -eq $j.result.result.value) { return 'NULL' }
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NOREPLY'
}

$state = "(function(){var host=document.getElementById('dywin-vfsbox');var v=host?host.querySelector('video'):null;return JSON.stringify({vfs:!!window.__DYWIN_VFSTOP,inHost:!!v,playing:v?!v.paused:false,t:v?Math.round(v.currentTime):0,dur:v?Math.round(v.duration):0,win:[innerWidth,innerHeight],fit:v?getComputedStyle(v).objectFit:'x',rootZoom:(document.body.firstElementChild||{style:{}}).style.zoom||'x'});})()"

Write-Output ('video ready: ' + (Eval "(function(){return new Promise(function(r){var n=0;var iv=setInterval(function(){var v=document.querySelector('video');if(v&&v.videoWidth){clearInterval(iv);r('ok');}else if(++n>60){clearInterval(iv);r('timeout');}},250);});})()"))
Write-Output ('before: ' + (Eval $state))
Write-Output ('进影院: ' + (Eval "(function(){document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('ok');},700);});})()"))
Write-Output ('  after ON: ' + (Eval $state))

$dp = Get-Process nook | Select-Object -First 1
[S5]::Wheel($dp.MainWindowHandle, 10)
Start-Sleep -Milliseconds 1500
Write-Output ('  wheel x10 后: ' + (Eval $state))
for ($i=0; $i -lt 3; $i++) { [S5]::Tap(0x28); Start-Sleep -Milliseconds 400 }
Write-Output ('  ArrowDown x3 后: ' + (Eval $state))

Write-Output ('跳到片尾: ' + (Eval "(function(){var v=document.querySelector('#dywin-vfsbox video');v.currentTime=Math.max(0,v.duration-1.2);return 'at '+Math.round(v.currentTime)+'/'+Math.round(v.duration);})()"))
Start-Sleep -Milliseconds 5000
Write-Output ('  5秒后(期望重播中 t小): ' + (Eval $state))

[S5]::Tap(0x1B)
Start-Sleep -Milliseconds 1200
Write-Output ('  Esc 后: ' + (Eval $state))
$ws.Dispose()
