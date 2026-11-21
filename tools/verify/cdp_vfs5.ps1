# VFS 等比配型取证:记录初始窗口→进VFS→比例/无缝隙断言→截图→退出→几何还原断言
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 900
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

Write-Output ('初始: ' + (Eval "JSON.stringify({win:[innerWidth,innerHeight],vfstop:!!window.__DYWIN_VFSTOP})"))
Write-Output ('进VFS: ' + (Eval "(function(){return new Promise(function(r){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();setTimeout(function(){document.getElementById('dywin-fs').click();setTimeout(function(){var v=document.querySelector('video');var b=v.getBoundingClientRect();var info={win:[innerWidth,innerHeight],vidAr:v.videoWidth?+(v.videoWidth/v.videoHeight).toFixed(3):0,winAr:+(innerWidth/innerHeight).toFixed(3),cover:[Math.round(b.width),Math.round(b.height)],gap:[innerWidth-Math.round(b.width),innerHeight-Math.round(b.height)],top:Math.round(b.top)};r(JSON.stringify(info));},1800);},500);});})()"))
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b2.Width,$b2.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X,$b2.Y,0,0,$bmp.Size)
$bmp.Save('d:\Code\DouYinWin\tools/verify\vfs_aspect_on.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot: vfs_aspect_on.png'
Write-Output ('退VFS: ' + (Eval "(function(){return new Promise(function(r){if(!window.__DYWIN_VFSTOP)return r('not-on');document.getElementById('dywin-fs').click();setTimeout(function(){r(JSON.stringify({win:[innerWidth,innerHeight],vfstop:!!window.__DYWIN_VFSTOP}));},900);});})()"))
$ws.Dispose()
