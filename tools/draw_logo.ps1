Add-Type -AssemblyName System.Drawing
$S = 1024
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'

$rust = [System.Drawing.Color]::FromArgb(255, 206, 66, 43)
$dark = [System.Drawing.Color]::FromArgb(255, 140, 38, 24)
$cyan = [System.Drawing.Color]::FromArgb(255, 37, 244, 238)
$red  = [System.Drawing.Color]::FromArgb(255, 254, 44, 85)
$bgc  = [System.Drawing.Color]::FromArgb(255, 22, 22, 28)

$bRust = New-Object System.Drawing.SolidBrush $rust
$bDark = New-Object System.Drawing.SolidBrush $dark
$bCyan = New-Object System.Drawing.SolidBrush $cyan
$bRed  = New-Object System.Drawing.SolidBrush $red
$bBg   = New-Object System.Drawing.SolidBrush $bgc
$bShine    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60,255,255,255))
$bShineClaw= New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70,255,255,255))
$bText  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(210,210,212,222))

# 背景圆角方块
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 200
$gp.AddArc(20, 20, $r, $r, 180, 90); $gp.AddArc($S-20-$r, 20, $r, $r, 270, 90)
$gp.AddArc($S-20-$r, $S-20-$r, $r, $r, 0, 90); $gp.AddArc(20, $S-20-$r, $r, $r, 90, 90)
$gp.CloseFigure()
$g.FillPath($bBg, $gp)
$g.DrawPath([System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255,42,42,52), 10), $gp)
$gp.Dispose()

$penRust = [System.Drawing.Pen]::new($rust, 34)
$penRust.StartCap='Round'; $penRust.EndCap='Round'
$penDark = [System.Drawing.Pen]::new($dark, 40)
$penDark.StartCap='Round'; $penDark.EndCap='Round'
$penStalk = [System.Drawing.Pen]::new($rust, 24)
$penStalkD  = [System.Drawing.Pen]::new($dark, 30)

# 腿(身体下层)
foreach ($side in @(1,-1)) {
  $bx = 512 + $side*150
  foreach ($i in 0..2) {
    $y0 = 560 + $i*55
    $x1 = $bx + $side*110; $y1 = $y0 + 20 + $i*18
    $x2 = $bx + $side*205; $y2 = $y0 + 60 + $i*30
    $gp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp2.AddBezier($bx, $y0, $x1, ($y0+$y1)/2, $x1, ($y1+$y2)/2, $x2, $y2)
    $g.DrawPath($penDark, $gp2); $g.DrawPath($penRust, $gp2)
    $gp2.Dispose()
  }
}

# 身体
$g.FillEllipse($bDark, 312, 452, 400, 300)
$g.FillEllipse($bRust, 320, 440, 400, 300)
$g.FillEllipse($bShine, 380, 470, 150, 60)

# 眼睛:挪在身体脸上,不挡音符
foreach ($side in @(1,-1)) {
  $ex = 512 + $side*62
  $g.FillEllipse([System.Drawing.Brushes]::White, $ex - 28, 520, 56, 56)
  $g.FillEllipse([System.Drawing.Brushes]::Black, $ex - 8, 538, 20, 20)
}

# 音符故障双色(下层)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment='Center'; $fmt.LineAlignment='Center'
$noteRect = New-Object System.Drawing.RectangleF(206, 40, 602, 360)
$font = New-Object System.Drawing.Font('Segoe UI Symbol', 240, [System.Drawing.FontStyle]::Bold)
foreach ($p in @(@( -14, 9, $bCyan), @(14, -9, $bRed))) {
  $state = $g.Save()
  $g.TranslateTransform($p[0], $p[1])
  $g.DrawString([char]0x266A, $font, $p[2], $noteRect, $fmt)
  $g.Restore($state)
}

# 手臂(身体连钳掌)
$armL = New-Object System.Drawing.Drawing2D.GraphicsPath
$armL.AddBezier(400, 480, 330, 430, 290, 410, 270, 375)
$g.DrawPath($penDark, $armL); $g.DrawPath($penRust, $armL)
$armR = New-Object System.Drawing.Drawing2D.GraphicsPath
$armR.AddBezier(620, 480, 700, 420, 740, 390, 748, 330)
$g.DrawPath($penDark, $armR); $g.DrawPath($penRust, $armR)
$armL.Dispose(); $armR.Dispose()

# 钳掌(分列音符两侧)
$claws = @(
  @{x = 270; y = 355; dir =  1; jawY = 255},   # 左钳夹符干
  @{x = 748; y = 300; dir = -1; jawY = 145}    # 右钳夹符尾
)
foreach ($cl in $claws) {
  $g.FillEllipse($bDark, $cl.x-93, $cl.y-93, 186, 186)
  $g.FillEllipse($bRust, $cl.x-86, $cl.y-86, 172, 172)
  $g.FillEllipse($bShineClaw, $cl.x-54, $cl.y-56, 60, 36)
}

# 音符白芯
$g.DrawString([char]0x266A, $font, [System.Drawing.Brushes]::White, $noteRect, $fmt)

# 钳指(最上层,真夹住音符)
foreach ($cl in $claws) {
  foreach ($jaw in @(-1, 1)) {
    $state = $g.Save()
    $g.TranslateTransform($cl.x, $cl.jawY)
    $ang = if ($cl.dir -eq 1) { $jaw*15 } else { 180 + $jaw*15 }
    $g.RotateTransform($ang)
    $g.FillEllipse($bDark, 50, -34, 170, 70)
    $g.FillEllipse($bRust, 56, -28, 158, 58)
    $g.Restore($state)
  }
}

# 底部 NOOK
$fontT = New-Object System.Drawing.Font('Segoe UI', 64, [System.Drawing.FontStyle]::Bold)
$tr = New-Object System.Drawing.RectangleF(160, 760, 704, 160)
$g.DrawString('NOOK', $fontT, $bText, $tr, $fmt)

$bmp.Save('D:\Code\DouYinWin\app-icon.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved $((Get-Item 'D:\Code\DouYinWin\app-icon.png').Length) bytes"
