# zen 实况:隐藏了多少 chrome + 截图看观感
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) { $s.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",'\n') }
$global:vid = 2800
function Eval([string]$js) {
  $global:vid++
  $m = '{"id":'+$global:vid+',"method":"Runtime.evaluate","params":{"expression":"'+(Esc $js)+'","returnByValue":true}}'
  $b=[Text.Encoding]::UTF8.GetBytes($m); $seg=New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg,[Net.WebSockets.WebSocketMessageType]::Text,$true,$ct).Wait()
  $want=$global:vid; $sb=New-Object Text.StringBuilder; $dl=(Get-Date).AddSeconds(15)
  while((Get-Date) -lt $dl){
    $buf=New-Object byte[] 262144; $s2=New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $t=$ws.ReceiveAsync($s2,$ct); if(-not $t.Wait(5000)){break}
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf,0,$t.Result.Count))
    if(-not $t.Result.EndOfMessage){continue}
    $j=$null; try{$j=$sb.ToString()|ConvertFrom-Json}catch{$sb.Clear()|Out-Null;continue}; $sb.Clear()|Out-Null
    if($j -and $j.id -eq $want){ if($j.result.exceptionDetails){return 'EXC:'+$j.result.exceptionDetails.exception.description}; if($null -eq $j.result.result.value){return 'NULL'}; return ($j.result.result.value|Out-String).Trim() }
  }
  return 'NOREPLY'
}
# header 是否已被隐藏(display none → rect 0)
Write-Output ('header 隐藏: ' + (Eval "(()=>{var h=document.querySelector('header');var b=h?h.getBoundingClientRect():{width:-1};return JSON.stringify({exists:!!h,rectW:Math.round(b.width)})})()"))
$ws.Dispose()
# 截图
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b2.Width,$b2.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X,$b2.Y,0,0,$bmp.Size)
$bmp.Save('d:\Code\DouYinWin\.shots\zen_view.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot: .shots/zen_view.png'
