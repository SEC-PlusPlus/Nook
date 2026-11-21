# 迷你影院断言:进出窗口尺寸不变;视频 cover 满视口;退出样式还原
# 用法:先起 debug(带 CDP 9222),再跑本脚本
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 1500
function Eval([string]$js) {
  $global:vid++
  $m = '{"id":' + $global:vid + ',"method":"Runtime.evaluate","params":{"expression":"' + (Esc $js) + '","awaitPromise":true,"returnByValue":true}}'
  $b = [Text.Encoding]::UTF8.GetBytes($m)
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  $want = $global:vid
  $sb = New-Object System.Text.StringBuilder
  $deadline = (Get-Date).AddSeconds(20)
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
      if ($null -eq $j.result.result.value) { return 'FALSE_OR_NULL' }
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NO_REPLY'
}

$ready = "(function(){return new Promise(function(r){var n=0;var iv=setInterval(function(){var v=document.querySelector('video');if(v&&v.videoWidth){clearInterval(iv);r('ready');}else if(++n>60){clearInterval(iv);r('timeout');}},250);});})()"
Write-Output ('视频就绪: ' + (Eval $ready))
Write-Output ('进影院: ' + (Eval "(function(){return new Promise(function(r){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();var before=[innerWidth,innerHeight];document.getElementById('dywin-fs').click();setTimeout(function(){var v=document.querySelector('video');var b=v.getBoundingClientRect();var st=getComputedStyle(v);r(JSON.stringify({vfstop:!!window.__DYWIN_VFSTOP,winBefore:before,winNow:[innerWidth,innerHeight],fit:st.objectFit,cover:[Math.round(b.width),Math.round(b.height)],origin:[Math.round(b.left),Math.round(b.top)],pos:st.position,cssTop:st.top,vp:[innerWidth,innerHeight]}));},2500);});})()"))
Write-Output ('退影院: ' + (Eval "(function(){return new Promise(function(r){document.getElementById('dywin-fs').click();setTimeout(function(){var v=document.querySelector('video');var st=getComputedStyle(v);r(JSON.stringify({vfstop:!!window.__DYWIN_VFSTOP,fitBack:st.objectFit,win:[innerWidth,innerHeight]}));},900);});})()"))
$ws.Dispose()
