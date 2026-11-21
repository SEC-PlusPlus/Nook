# 影院异常定位:手动触发 toggleVfs 拿堆栈,并检查环境
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 1600
function Eval([string]$js) {
  $global:vid++
  $m = '{"id":' + $global:vid + ',"method":"Runtime.evaluate","params":{"expression":"' + (Esc $js) + '","returnByValue":true}}'
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
Write-Output ('booted: ' + (Eval "typeof window.__DYWIN_TOGGLE_VFS"))
Write-Output ('manual: ' + (Eval "(function(){try{window.__DYWIN_TOGGLE_VFS();return 'ok vfstop='+!!window.__DYWIN_VFSTOP;}catch(e){return 'ERR:'+e.message+' @ '+String(e.stack).split(String.fromCharCode(10)).slice(0,2).join(' | ');}})()"))
Write-Output ('recheck: ' + (Eval "'vfstop='+!!window.__DYWIN_VFSTOP+' fit='+(document.querySelector('video')?getComputedStyle(document.querySelector('video')).objectFit:'novideo')"))
$ws.Dispose()
