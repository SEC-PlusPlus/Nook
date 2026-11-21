# 影院(宿主+中继)断言:进入→播放器入宿主→真实滚轮滑动(切换发生)→再入→退出回家;隐藏/唤回
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void WheelAt(IntPtr hwnd, int notch) {
    RECT rc; GetWindowRect(hwnd, out rc);
    SetCursorPos((rc.L + rc.R) / 2, (rc.T + rc.B) / 2);
    System.Threading.Thread.Sleep(250);
    for (int i = 0; i < notch; i++) { mouse_event(0x800, 0, 0, -120, UIntPtr.Zero); System.Threading.Thread.Sleep(60); }
  }
}
"@
. d:\Code\DouYinWin\tools\verify\windiag.ps1
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 2200
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
    if (-not $t.Wait(5000)) { break }
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

# 体检:可见视频是否在宿主、播放中、尺寸、画面指纹(videoWidth 换视频必变)
$check = "(function(){var all=document.querySelectorAll('video');var v=null;for(var i=0;i<all.length;i++){var b=all[i].getBoundingClientRect();if(b.width>0&&b.top>-b.height*0.5&&b.top<innerHeight*0.5){v=all[i];break;}}if(!v)return JSON.stringify({novideo:1,inHost:false});var b=v.getBoundingClientRect();var host=document.getElementById('dywin-vfsbox');return JSON.stringify({inHost:!!(host&&host.contains(v)),playing:!v.paused,fill:[Math.round(b.width),Math.round(b.height)],vp:[innerWidth,innerHeight],w:v.videoWidth,t:Math.round(v.currentTime)});})()"

Write-Output ('视频就绪: ' + (Eval "(function(){return new Promise(function(r){var n=0;var iv=setInterval(function(){var v=document.querySelector('video');if(v&&v.videoWidth){clearInterval(iv);r('ready w='+v.videoWidth);}else if(++n>60){clearInterval(iv);r('timeout');}},250);});})()"))
Write-Output ('进影院: ' + (Eval "(function(){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('done');},700);});})()"))
Write-Output ('  体检: ' + (Eval $check))

$dp = Get-Process nook | Select-Object -First 1
for ($i = 1; $i -le 2; $i++) {
  [M]::WheelAt($dp.MainWindowHandle, 6)
  Start-Sleep -Milliseconds 2200
  Write-Output ("滑$i 后: " + (Eval $check))
}
Write-Output ('退影院: ' + (Eval "(function(){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){var host=document.getElementById('dywin-vfsbox');var v=document.querySelector('video');r(JSON.stringify({hostGone:!host,inFeed:!!(v&&v.closest&&!v.closest('#dywin-vfsbox'))}));},900);});})()"))
Write-Output ('二次进入: ' + (Eval "(function(){document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('ok');},800);});})()"))
Write-Output ('  体检: ' + (Eval $check))
Write-Output ('再退出: ' + (Eval "(function(){document.getElementById('dywin-fs').click();return 'off';})()"))
Start-Sleep -Milliseconds 800

Write-Output ('🗕隐藏: ' + (Eval "__TAURI__.core.invoke('hide_main').then(function(){return 'invoked-ok';},function(e){return 'invoked-ERR:'+String(e).slice(0,90);})"))
Start-Sleep -Milliseconds 600
$h2 = (Get-Process nook | Select-Object -First 1).MainWindowHandle
Write-Output ("  visible(期望False)=" + [WinDiag]::IsWindowVisible($h2))
Write-Output ('唤回: ' + (Eval "__TAURI__.core.invoke('show_main_cmd').then(function(){return 'invoked';})"))
Start-Sleep -Milliseconds 600
Write-Output ("  visible(期望True)=" + [WinDiag]::IsWindowVisible($h2))
$ws.Dispose()
