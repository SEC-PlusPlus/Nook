# 实验:影院模式下,合成 ArrowDown / scroller.scrollBy 哪种能驱动抖音切换
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 1900
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

# 确保在影院中
Write-Output ('ensure-vfs: ' + (Eval "(function(){if(!window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();return 'on='+!!window.__DYWIN_VFSTOP;})()"))
$srcQ = "(function(){var v=document.querySelector('video');return (v.currentSrc||v.src||'').slice(-14);})()"
Write-Output ('before: ' + (Eval $srcQ))

# A) 合成键盘 ArrowDown
Write-Output ('A keydown: ' + (Eval "(function(){document.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',code:'ArrowDown',keyCode:40,which:40,bubbles:true}));return new Promise(function(r){setTimeout(function(){var v=document.querySelector('video');r((v.currentSrc||'').slice(-14));},1800);});})()"))

# B) 找候选滚动容器:scrollHeight>clientHeight 的祖先链 + window.scrollBy
Write-Output ('B scrollers: ' + (Eval "(function(){var out=[];var v=document.querySelector('video');var p=v;for(var i=0;i<12&&p;i++){if(p.scrollHeight>p.clientHeight+50)out.push(p.tagName+'.'+String(p.className).split(' ')[0].slice(0,10)+':'+p.scrollHeight+'/'+p.clientHeight);p=p.parentElement;}out.push('doc:'+document.documentElement.scrollHeight+'/'+innerHeight);return out.join(' | ');})()"))

# C) window.scrollBy + wheel 事件直发 document
Write-Output ('C doc-wheel: ' + (Eval "(function(){var before=(document.querySelector('video').currentSrc||'').slice(-14);document.dispatchEvent(new WheelEvent('wheel',{deltaY:300,bubbles:true,cancelable:true}));window.dispatchEvent(new WheelEvent('wheel',{deltaY:300,bubbles:true}));return new Promise(function(r){setTimeout(function(){var v=document.querySelector('video');r((v.currentSrc||'').slice(-14)+' was:'+before);},1800);});})()"))

$ws.Dispose()
