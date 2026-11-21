# 决定性实验:wheel 转发到 feed 滚动容器能否触发切换(host 方案的最后拼图)
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 2100
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

Write-Output ('reload: ' + (Eval "location.reload()||'reloading'"))
Start-Sleep 12
Write-Output ('video就绪: ' + (Eval "(function(){return new Promise(function(r){var n=0;var iv=setInterval(function(){var v=document.querySelector('video');if(v&&v.videoWidth){clearInterval(iv);r('ready src:'+(v.currentSrc||'').slice(-14));}else if(++n>50){clearInterval(iv);r('timeout');}},250);});})()"))

# 找 feed 主滚动容器(最高 scrollHeight 的祖先)
$find = "(function(){var v=document.querySelector('video');var best=null;var p=v;for(var i=0;i<15&&p;i++){if(p.scrollHeight>p.clientHeight+200){best=p;}p=p.parentElement;}window.__EXP_SC=best;return best? best.tagName+'.'+String(best.className).split(' ')[0].slice(0,14)+' sh='+best.scrollHeight+' ch='+best.clientHeight : 'none';})()"
Write-Output ('滚动容器: ' + (Eval $find))

# 向容器 dispatch 3 个合成 wheel
Write-Output ('wheel转发结果: ' + (Eval "(function(){var sc=window.__EXP_SC;if(!sc)return 'no-scroller';var before=(document.querySelector('video').currentSrc||'').slice(-14);for(var i=0;i<3;i++){sc.dispatchEvent(new WheelEvent('wheel',{deltaY:400,bubbles:true,cancelable:true,clientX:innerWidth/2,clientY:innerHeight/2}));}return new Promise(function(r){setTimeout(function(){var v=document.querySelector('video');r('was:'+before+' now:'+(v.currentSrc||'').slice(-14)+' changed:'+(v.currentSrc.indexOf(before)<0));},2500);});})()"))

# 对照:直接真实滚轮(不经 host)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MW {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void Wheel(IntPtr hwnd, int n) {
    RECT rc; GetWindowRect(hwnd, out rc);
    SetCursorPos((rc.L+rc.R)/2, (rc.T+rc.B)/2);
    System.Threading.Thread.Sleep(200);
    mouse_event(0x800, 0, 0, n*-120, UIntPtr.Zero);
  }
}
"@
$dp = Get-Process nook | Select-Object -First 1
[MW]::Wheel($dp.MainWindowHandle, 5)
Start-Sleep -Milliseconds 2200
Write-Output ('真实滚轮对照: ' + (Eval "(function(){var v=document.querySelector('video');return 'src:'+(v.currentSrc||'').slice(-14)+' paused:'+v.paused;})()"))
$ws.Dispose()
