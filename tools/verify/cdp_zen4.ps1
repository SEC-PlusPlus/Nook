# zen 缩小版验证:调 __DYWIN_ZEN 后统计被缩元素 + header/左栏/右栏 zoom + 视频尺寸变化 + 截图
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Ev($js, $id) {
  $m = @{id=$id;method='Runtime.evaluate';params=@{expression=$js;returnByValue=$true}} | ConvertTo-Json -Compress -Depth 6
  $b=[Text.Encoding]::UTF8.GetBytes($m); $seg=New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg,[Net.WebSockets.WebSocketMessageType]::Text,$true,$ct).Wait()
  $sb=New-Object Text.StringBuilder; $dl=(Get-Date).AddSeconds(15)
  while((Get-Date) -lt $dl){
    $buf=New-Object byte[] 262144; $s2=New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $t=$ws.ReceiveAsync($s2,$ct); if(-not $t.Wait(5000)){break}
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf,0,$t.Result.Count))
    if(-not $t.Result.EndOfMessage){continue}
    $j=$null; try{$j=$sb.ToString()|ConvertFrom-Json}catch{$sb.Clear()|Out-Null;continue}; $sb.Clear()|Out-Null
    if($j -and $j.id -eq $id){
      if($j.result.exceptionDetails){return 'EXC: '+$j.result.exceptionDetails.exception.description}
      if($null -eq $j.result.result.value){return 'NULL'}
      return $j.result.result.value }
  }
  return 'NOREPLY'
}
# 视频 rect(zen 前)
Write-Output ('zen前: ' + (Ev "(function(){var area=innerWidth*innerHeight,v=null,best=0;for(var x of document.querySelectorAll('video')){var b=x.getBoundingClientRect();var r=b.width*b.height/area;if(b.bottom>0&&b.top<innerHeight&&r>best){best=r;v=b;}}return JSON.stringify({vw:v?Math.round(v.width):0,vh:v?Math.round(v.height):0});})()" 71))
# 触发一次 zen 并汇报命中明细
Write-Output ('zen后: ' + (Ev "(function(){window.__DYWIN_ZEN();var shrunk=0;for(var e of document.body.querySelectorAll('*')){if(e.style&&e.style.zoom==='0.55')shrunk++;}var h=document.querySelector('header');return JSON.stringify({shrunkCount:shrunk,headerZoom:h?h.style.zoom||'-':'noheader'});})()" 72))
$ws.Dispose()
Start-Sleep 2
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b2.Width,$b2.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X,$b2.Y,0,0,$bmp.Size)
$bmp.Save('d:\Code\DouYinWin\.shots\zen_shrunk.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot: .shots/zen_shrunk.png'
