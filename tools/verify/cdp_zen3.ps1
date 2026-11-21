# 直接复刻 zen 判定,看每步命中情况
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
$js = @'
(function(){
  var h=document.querySelector('header');
  var hb=h?h.getBoundingClientRect():null;
  // header 距 body 深度
  var depth=-1,a=h;while(a){if(a===document.body){depth=0;break}a=a.parentElement;depth++;}
  var depthB=0;a=h;while(a&&a!==document.body){depthB++;a=a.parentElement;}
  // 大视频面积比
  var area=innerWidth*innerHeight;var best=0,bv=null;
  for(var x of document.querySelectorAll('video')){var b=x.getBoundingClientRect();var r=b.width*b.height/area;if(b.bottom>0&&b.top<innerHeight&&r>best){best=r;bv=b;}}
  var zenOn=(function(){try{return localStorage.getItem('nook.zen')!=='0';}catch(e){return true;}})();
  var topbarTest = hb? (hb.top<=6 && hb.height<=90 && hb.width>=innerWidth*0.4):false;
  return JSON.stringify({
    zenOn:zenOn,
    headerRect:hb?[Math.round(hb.left),Math.round(hb.top),Math.round(hb.width),Math.round(hb.height)]:null,
    headerDisplay:h?getComputedStyle(h).display:'?',
    headerDepthFromBody:depthB,
    bestVideoArea:+(best).toFixed(3),
    topBarWouldMatch:topbarTest,
    videoTop: bv?Math.round(bv.top):null
  });
})()
'@
$b=[Text.Encoding]::UTF8.GetBytes((@{id=60;method='Runtime.evaluate';params=@{expression=$js;returnByValue=$true}}|ConvertTo-Json -Compress -Depth 6))
$seg=New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
$ws.SendAsync($seg,[Net.WebSockets.WebSocketMessageType]::Text,$true,$ct).Wait()
$sb=New-Object Text.StringBuilder;$dl=(Get-Date).AddSeconds(12)
while((Get-Date) -lt $dl){$buf=New-Object byte[] 131072;$s2=New-Object System.ArraySegment[byte] -ArgumentList @(,$buf);$r=$ws.ReceiveAsync($s2,$ct);if(-not $r.Wait(4000)){break};[void]$sb.Append([Text.Encoding]::UTF8.GetString($buf,0,$r.Result.Count));if(-not $r.Result.EndOfMessage){continue};try{$j=$sb.ToString()|ConvertFrom-Json}catch{continue};if($j -and $j.id -eq 60){ if($j.result.exceptionDetails){Write-Output ('EXC: '+$j.result.exceptionDetails.exception.description)} else {Write-Output $j.result.result.value};break}}
$ws.Dispose()
