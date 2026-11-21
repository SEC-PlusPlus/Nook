# 沉浸模式冒烟:播放态隐藏左栏/顶栏 → 开关关掉还原 → 面板存在
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
}
$global:vid = 2600
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

# 播放态体检:大视频存在、chrome 隐藏数、视频左缘位置(隐藏后应左移/变宽)
$st = "(function(){var vs=document.querySelectorAll('video');var v=null;for(var i=0;i<vs.length;i++){var b=vs[i].getBoundingClientRect();if(b.width>=innerWidth*0.4&&b.height>=innerHeight*0.4){v=vs[i];break;}}var hidden=0;for(var e of document.querySelectorAll('header,aside,nav')){var b=e.getBoundingClientRect();if(b.width===0&&b.height===0)hidden++;}var vb=v?v.getBoundingClientRect():null;return JSON.stringify({bigVideo:!!v,chromeHidden:hidden,vLeft:vb?Math.round(vb.left):null,vW:vb?Math.round(vb.width):null,vp:innerWidth});})()"

Start-Sleep 5
Write-Output ('① 当前页: ' + (Eval "location.href.slice(0,60)"))
Write-Output ('② 播放态体检: ' + (Eval $st))
# 关掉开关(localStorage 模拟面板取消勾选后再跑一轮 applyScale)
Write-Output ('③ 关开关: ' + (Eval "localStorage.setItem('nook.zen','0');'set'"))
Write-Output ('   reload 后体检(关闭态): ')
$ws.Dispose()
