# VFS 取证 v2:幂等强制开/关,消除自动连播造成的状态错位
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 600
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
    if (-not $t.Wait(5000)) { break }
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count))
    if (-not $t.Result.EndOfMessage) { continue }
    $j = $null
    try { $j = $sb.ToString() | ConvertFrom-Json } catch { $sb.Clear() | Out-Null; continue }
    $sb.Clear() | Out-Null
    if ($j -and $j.id -eq $want) {
      if ($j.result.exceptionDetails) { return 'JS_EXC:' + $j.result.exceptionDetails.exception.description }
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NO_REPLY'
}

Write-Output ('off0: ' + (Eval "(function(){return new Promise(function(r){if(!window.__DYWIN_VFSTOP)return r('already-off');document.getElementById('dywin-fs').click();setTimeout(function(){r('off='+!window.__DYWIN_VFSTOP);},600);});})()"))
Write-Output ('on: ' + (Eval "(function(){return new Promise(function(r){if(window.__DYWIN_VFSTOP)return r('already-on');document.getElementById('dywin-fs').click();setTimeout(function(){var v=document.querySelector('video');var info={vfs:!!window.__DYWIN_VFSTOP};var pts=[[10,(innerHeight*0.5)|0],[(innerWidth/2)|0,60],[(innerWidth-12)|0,(innerHeight*0.35)|0],[(innerWidth/2)|0,(innerHeight-40)|0]];info.hits=pts.map(function(p){var e=document.elementFromPoint(p[0],p[1]);return e?e.tagName+'|'+String(e.className).split(' ')[0].slice(0,16):'null';});if(v){var b=v.getBoundingClientRect();info.vr=[b.width|0,b.height|0];}var bh=document.elementFromPoint((innerWidth/2)|0,16);info.barHit=bh?(bh.closest('#dywin-bar')?'BAR':bh.tagName+'|'+String(bh.className).slice(0,14)):'null';info.vp=[innerWidth,innerHeight];r(JSON.stringify(info));},700);});})()"))

Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b2.Width,$b2.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X,$b2.Y,0,0,$bmp.Size)
$bmp.Save('d:\Code\DouYinWin\tools/verify\vfs_forced_on.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot: vfs_forced_on.png (应为 VFS ON 状态)'

Write-Output ('off1: ' + (Eval "(function(){return new Promise(function(r){if(!window.__DYWIN_VFSTOP)return r('already-off');document.getElementById('dywin-fs').click();setTimeout(function(){var e=document.elementFromPoint(10,(innerHeight*0.5)|0);r(JSON.stringify({off:!window.__DYWIN_VFSTOP,leftHit:e?e.tagName+'|'+String(e.className).split(' ')[0].slice(0,16):'null'}));},600);});})()"))
$ws.Dispose()
