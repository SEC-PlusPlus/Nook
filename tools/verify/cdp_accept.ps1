# v0.5 自动验收:把手/透明/VFS/面板/最小化/隐藏显隐,全程 CDP + Win32 状态断言
$ErrorActionPreference = 'Stop'
. d:\Code\DouYinWin\tools/verify\windiag.ps1

Get-Process nook -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
$d = Start-Process -FilePath 'd:\Code\DouYinWin\src-tauri\target\debug\nook.exe' -WindowStyle Hidden -PassThru
Write-Output "PID=$($d.Id)"
Start-Sleep 15
$hw = $d.MainWindowHandle

function WinState([string]$tag) {
  $iconic = [WinDiag]::IsIconic($hw)
  $vis = [WinDiag]::IsWindowVisible($hw)
  Write-Output ("[{0}] iconic={1} visible={2}" -f $tag, $iconic, $vis)
}

$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

function Esc([string]$s) {
  $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
  return $s
}
$msgId = 100
function Eval([string]$js, [bool]$await) {
  $script:msgId++
  $m = '{"id":' + $script:msgId + ',"method":"Runtime.evaluate","params":{"expression":"' + (Esc $js) + '","awaitPromise":' + $($await.ToString().ToLower()) + ',"returnByValue":true}}'
  $b = [Text.Encoding]::UTF8.GetBytes($m)
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  $want = $script:msgId
  $sb = New-Object System.Text.StringBuilder
  $deadline = (Get-Date).AddSeconds(12)
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
      return ($j.result.result.value | Out-String).Trim()
    }
  }
  return 'NO_REPLY'
}

Write-Output ('A 把手存在: ' + (Eval "!!document.getElementById('dywin-bar')" $false))
Write-Output ('B 透明到30%: ' + (Eval "(()=>{const s=document.getElementById('dywin-alpha');if(!s)return 'NO_SLIDER';s.value='30';s.dispatchEvent(new Event('input'));const el=[...document.body.children].find(e=>e.nodeType===1&&e.id!=='dywin-bar'&&e.id!=='dywin-panel');return 'opacity='+el.style.opacity+' zoom='+el.style.zoom;})()" $false))

# 截图验证 see-through(窗口半透时)
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$b2=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b2.Width,$b2.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b2.X,$b2.Y,0,0,$bmp.Size)
$bmp.Save('d:\Code\DouYinWin\tools/verify\accept_30pct.png',[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

WinState 'before-minimize'
Write-Output ('C 最小化invoke: ' + (Eval "__TAURI__.core.invoke('minimize_main_cmd').then(()=>'OK')" $true))
Start-Sleep 1
WinState 'after-minimize(expect iconic=True)'
Write-Output ('D 还原show: ' + (Eval "__TAURI__.core.invoke('show_main_cmd').then(()=>'OK')" $true))
Start-Sleep 1
WinState 'after-show(expect iconic=False visible=True)'
Write-Output ('E 隐藏hide: ' + (Eval "__TAURI__.core.invoke('hide_main').then(()=>'OK')" $true))
Start-Sleep 1
WinState 'after-hide(expect visible=False)'
Write-Output ('F 再显示: ' + (Eval "__TAURI__.core.invoke('show_main_cmd').then(()=>'OK')" $true))
Start-Sleep 1
WinState 'after-show2(expect visible=True)'

Write-Output ('G VFS进入: ' + (Eval "(()=>{document.getElementById('dywin-fs').click();return new Promise(r=>setTimeout(()=>{const v=document.querySelector('video');if(!v)return r('NO_VIDEO');let top=v;while(top.parentElement&&top.parentElement!==document.body)top=top.parentElement;r('VFSTOP='+(!!window.__DYWIN_VFSTOP)+' topZoom='+top.style.zoom+' videoVisible='+!!v.offsetParent);},400);})()" $true))
Write-Output ('H VFS退出: ' + (Eval "(()=>{document.getElementById('dywin-fs').click();return 'VFSTOP_after='+!!window.__DYWIN_VFSTOP;})()" $false))
Write-Output ('I 设置面板: ' + (Eval "(()=>{window.__DYWIN_PANEL.toggle(true);return getComputedStyle(document.getElementById('dywin-panel')).display;})()" $false))
Write-Output ('J 透明复原: ' + (Eval "(()=>{const s=document.getElementById('dywin-alpha');s.value='100';s.dispatchEvent(new Event('input'));return 'done';})()" $false))
Start-Sleep 1
$ws.Dispose()

Write-Output '--- config.json ---'
Get-Content "$env:APPDATA\cn.nook.desktop\config.json" -Raw
