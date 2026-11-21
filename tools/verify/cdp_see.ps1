# 穿透取证:常态100 / 常态30(截图×2)/ VFS 顶边距;结束恢复
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) {
  $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}
$global:vid = 700
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
function Shot([string]$name) {
  Add-Type -AssemblyName System.Drawing,System.Windows.Forms
  $b2 = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b2.Width, $b2.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b2.X, $b2.Y, 0, 0, $bmp.Size)
  $bmp.Save("d:\Code\DouYinWin\tools/verify\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Output "shot: $name.png"
}
$bgChk ="(function(){return JSON.stringify({body:getComputedStyle(document.body).backgroundColor,html:getComputedStyle(document.documentElement).backgroundColor});})()"
$vfsProbe = "(function(){return new Promise(function(r){if(!window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();setTimeout(function(){var v=document.querySelector('video');var info={vfs:!!window.__DYWIN_VFSTOP};if(v){var b=v.getBoundingClientRect();info.top=Math.round(b.top);info.rect=[Math.round(b.width),Math.round(b.height)];info.anc=[];var p=v;for(var i=0;i<5&&p;i++){var rp=p.getBoundingClientRect();info.anc.push(p.tagName+'.'+String(p.className).split(' ')[0].slice(0,9)+'@'+Math.round(rp.top));p=p.parentElement;}}info.vp=[innerWidth,innerHeight];var eL=document.elementFromPoint(4,((innerHeight*0.75)|0));info.corner=eL?eL.tagName+'|'+String(eL.className).split(' ')[0].slice(0,12):'null';r(JSON.stringify(info));},1400);});})()"

Write-Output ('底板色: ' + (Eval $bgChk))
Write-Output ('30%: ' + (Eval "(function(){var s=document.getElementById('dywin-alpha');s.value='30';s.dispatchEvent(new Event('input'));return 'ok';})()"))
Start-Sleep 1
Shot 'see_alpha30'
Write-Output ('VFS: ' + (Eval $vfsProbe))
Start-Sleep 1
Shot 'vfs_topflush'
Write-Output ('恢复: ' + (Eval "(function(){if(window.__DYWIN_VFSTOP)document.getElementById('dywin-fs').click();var s=document.getElementById('dywin-alpha');s.value='100';s.dispatchEvent(new Event('input'));return 'off+100';})()"))
Start-Sleep 1
Shot 'norm_alpha100'
$ws.Dispose()
