# 综合验证:影院滑动切换+新播放器铺满 / hide / show
$ErrorActionPreference = 'Stop'
. d:\Code\DouYinWin\tools\verify\windiag.ps1
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W4 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void Wheel(IntPtr hwnd, int n) {
    RECT rc; GetWindowRect(hwnd, out rc);
    SetCursorPos((rc.L + rc.R) / 2, (rc.T + rc.B) / 2);
    System.Threading.Thread.Sleep(200);
    for (int i = 0; i < n; i++) { mouse_event(0x800, 0, 0, -120, UIntPtr.Zero); System.Threading.Thread.Sleep(70); }
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
$global:vid = 2300
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

# host 内"正在播的 video":取 !paused 且 readyState>=2 的
$check = "(function(){var host=document.getElementById('dywin-vfsbox');if(!host)return JSON.stringify({nohost:1});var vs=host.querySelectorAll('video');var cur=null;for(var i=0;i<vs.length;i++){if(!vs[i].paused){cur=vs[i];}}if(!cur&&vs.length)cur=vs[vs.length-1];if(!cur)return JSON.stringify({videos:vs.length});var b=cur.getBoundingClientRect();return JSON.stringify({videos:vs.length,playing:!cur.paused,fill:[Math.round(b.width),Math.round(b.height)],vp:[innerWidth,innerHeight],w:cur.videoWidth});})()"

Write-Output ('进影院: ' + (Eval "(function(){if(!window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('ok');},700);});})()"))
Write-Output ('  初始: ' + (Eval $check))
$dp = Get-Process nook | Select-Object -First 1
[W4]::Wheel($dp.MainWindowHandle, 8)
Start-Sleep -Milliseconds 2500
Write-Output ('  滑后: ' + (Eval $check))
[W4]::Wheel($dp.MainWindowHandle, 8)
Start-Sleep -Milliseconds 2500
Write-Output ('  再滑: ' + (Eval $check))
Write-Output ('退影院: ' + (Eval "(function(){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('hostGone='+!document.getElementById('dywin-vfsbox'));},800);});})()"))

# hide / show 用窗口枚举验证
Write-Output ('hide: ' + (Eval "__TAURI__.core.invoke('hide_main').then(function(){return 'ok';},function(e){return 'ERR:'+String(e).slice(0,120);})"))
Start-Sleep -Milliseconds 800
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
Write-Output ('show: ' + (Eval "__TAURI__.core.invoke('show_main_cmd').then(function(){return 'ok';},function(e){return 'ERR:'+String(e).slice(0,120);})"))
Start-Sleep -Milliseconds 800
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
$ws.Dispose()
