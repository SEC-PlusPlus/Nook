# 探查:大视频祖先链上每个兄弟的几何,定位"左栏/顶栏"到底是哪个元素
$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
function Esc([string]$s) { $s.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",'\n') }
$global:vid = 2700
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
$js = @"
(function(){
  var vs=document.querySelectorAll('video');var v=null;
  for(var i=0;i<vs.length;i++){var b=vs[i].getBoundingClientRect();if(b.width>=innerWidth*0.4){v=vs[i];break;}}
  if(!v)return 'no big video';
  var vb=v.getBoundingClientRect();
  var report=['VP='+innerWidth+'x'+innerHeight+' videoL='+Math.round(vb.left)+' T='+Math.round(vb.top)];
  var cur=v,g=0;
  while(cur&&cur.parentElement&&cur!==document.body&&g<10){
    var par=cur.parentElement;
    var pl=[];
    for(var s of par.children){
      if(s===cur||s.nodeType!==1)continue;
      var b=s.getBoundingClientRect();
      pl.push(s.tagName+'['+Math.round(b.left)+','+Math.round(b.top)+' '+Math.round(b.width)+'x'+Math.round(b.height)+']');
    }
    report.push('d'+g+' '+(par.tagName||'')+'.'+String(par.className||'').split(' ')[0].slice(0,12)+' -> '+pl.join(' ; '));
    cur=par;g++;
  }
  // 语义标签全景
  var sem=[];
  for(var e of document.querySelectorAll('header,aside,nav')){var b=e.getBoundingClientRect();sem.push(e.tagName+'['+Math.round(b.left)+','+Math.round(b.top)+' '+Math.round(b.width)+'x'+Math.round(b.height)+']')}
  report.push('SEM: '+sem.join(' ; '));
  return report.join('\n');
})()
"@
Write-Output (Eval $js)
$ws.Dispose()
