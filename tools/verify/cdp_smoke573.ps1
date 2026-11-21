# 0.7.3 冒烟:影院配型进出 + 隐藏/唤回(不含 ✕,那是退出)
$ErrorActionPreference = 'Stop'
. d:\Code\DouYinWin\tools\verify\windiag.ps1
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 2400
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
      if ($j.result.exceptionDetails) { return 'EXC:' + $j.result.exceptionDetails.exception.description }
      if ($null -eq $j.result.result.value) { return 'NULL' }
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NOREPLY'
}
Write-Output ('video ready: ' + (Eval "(function(){return new Promise(function(r){var n=0;var iv=setInterval(function(){var v=document.querySelector('video');if(v&&v.videoWidth){clearInterval(iv);r('ok '+v.videoWidth+':'+v.videoHeight);}else if(++n>60){clearInterval(iv);r('timeout');}},250);});})()"))
Write-Output ('theater ON: ' + (Eval "(function(){document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('vfstop='+!!window.__DYWIN_VFSTOP);},1500);});})()"))
$dp = Get-Process nook | Select-Object -First 1
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
Write-Output ('theater OFF: ' + (Eval "(function(){document.getElementById('dywin-fs').click();return new Promise(function(r){setTimeout(function(){r('vfstop='+!!window.__DYWIN_VFSTOP);},1200);});})()"))
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
Write-Output ('hide: ' + (Eval "__TAURI__.core.invoke('hide_main').then(function(){return 'ok';},function(e){return 'ERR:'+String(e).slice(0,80);})"))
Start-Sleep -Milliseconds 700
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
Write-Output ('restore: ' + (Eval "__TAURI__.core.invoke('show_main_cmd').then(function(){return 'ok';})"))
Start-Sleep -Milliseconds 700
[WinDiag]::Dump($dp.Id) | Select-String 'Tauri'
$ws.Dispose()
