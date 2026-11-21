# 差分探针:区分「应用命令 ACL 拦截」与「远程 origin 整体 IPC 丢弃」
$ErrorActionPreference = 'Stop'
Get-Process nook -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
$d = Start-Process -FilePath 'd:\Code\DouYinWin\src-tauri\target\debug\nook.exe' -WindowStyle Hidden -PassThru
Write-Output "debug PID=$($d.Id)"
Start-Sleep 12

$targets = Invoke-RestMethod 'http://127.0.0.1:9222/json' -TimeoutSec 10
$page = $targets | Where-Object { $_.url -like '*douyin.com*' } | Select-Object -First 1
if (-not $page) { Write-Output 'CDP: 没有 douyin target'; exit 1 }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()

function Send-Msg($obj) {
  $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 6))
  $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$b)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}
function Recv-Json($wantId, $maxFrames) {
  for ($i = 0; $i -lt $maxFrames; $i++) {
    $buf = New-Object byte[] 262144
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
    $t = $ws.ReceiveAsync($seg, $ct)
    if (-not $t.Wait(4000)) { return $null }
    $j = $null
    try { $j = ([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count)) | ConvertFrom-Json } catch { continue }
    if ($j -and $j.id -eq $wantId) { return $j }
  }
  return $null
}

$expr = Get-Content 'd:\Code\DouYinWin\tools/verify\probe.js' -Raw
Send-Msg @{ id = 7; method = 'Runtime.evaluate'; params = @{ expression = $expr; awaitPromise = $true; returnByValue = $true } }
$j = Recv-Json 7 60
if ($j) {
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  Write-Output ('RAW: ' + ($j | ConvertTo-Json -Depth 12 -Compress))
} else {
  Write-Output '探针: 无回应'
}
$ws.Dispose()
