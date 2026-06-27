Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $root "docs\passband_flatness_spur_trend.png"

$frequenciesGHz = @(0.01, 0.05, 0.1, 0.2, 0.4, 0.6, 0.8, 1.0, 1.4, 2.0)
$labels = @("0", "0.5", "1.0", "1.5", "2.0")
$carrierPower = @(-6.32, -6.38, -6.41, -6.59, -6.56, -6.44, -6.58, -6.74, -6.64, -6.23)
$harmonicSuppression = @(44.3, 45.7, 46.5, 47.65, 47.07, 48.43, 47.28, 45.69, 47.8, 43.94)
$nonharmonicSuppression = @(65.37, 66.32, 65.51, 63.54, 64.61, 63.44, 62.24, 60.81, 68.59, 48.10)
$flatness = (($carrierPower | Measure-Object -Maximum).Maximum - ($carrierPower | Measure-Object -Minimum).Minimum)

function U($codes) {
    return -join ($codes | ForEach-Object { [char]$_ })
}

$txtSpectrumTrend = U @(0x9891,0x8c31,0x7eaf,0x5ea6,0x8d8b,0x52bf)
$txtSuppression = U @(0x6291,0x5236,0x5ea6)
$txtHarmonicSuppression = U @(0x8c10,0x6ce2,0x6291,0x5236)
$txtNonharmonicSuppression = U @(0x975e,0x8c10,0x6ce2,0x6742,0x6563,0x6291,0x5236)
$txtHigherBetter = U @(0x8d8a,0x9ad8,0x8d8a,0x597d)
$txtPowerFlatness = U @(0x8f7d,0x6ce2,0x529f,0x7387,0x5e73,0x5766,0x5ea6)
$txtCarrierPower = U @(0x8f7d,0x6ce2,0x529f,0x7387)
$txtFlatness = U @(0x5e73,0x5766,0x5ea6)
$txtFrequencyGHz = U @(0x9891,0x7387)

$width = 1728
$height = 780
$bmp = New-Object System.Drawing.Bitmap $width, $height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

function Color($hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function Font($size, $style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font -ArgumentList @("Microsoft YaHei UI", $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Brush($hex) {
    return New-Object System.Drawing.SolidBrush (Color $hex)
}

function Pen($hex, $width = 1) {
    $p = New-Object System.Drawing.Pen (Color $hex), $width
    $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    return $p
}

function RoundRectPath($x, $y, $w, $h, $r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function DrawBadge($text, $x, $y, $fillHex) {
    $font = Font 21 ([System.Drawing.FontStyle]::Bold)
    $size = $g.MeasureString($text, $font)
    $padX = 18
    $padY = 8
    $w = [int]($size.Width + $padX * 2)
    $h = [int]($size.Height + $padY * 2 - 2)
    $path = RoundRectPath ($x - $w) $y $w $h 18
    $brush = Brush $fillHex
    $textBrush = Brush "#ffffff"
    $g.FillPath($brush, $path)
    $g.DrawString($text, $font, $textBrush, ($x - $w + $padX), ($y + $padY - 2))
    $path.Dispose()
    $brush.Dispose()
    $textBrush.Dispose()
    $font.Dispose()
}

function DrawSeries($plot, $xValues, $values, $minX, $maxX, $minY, $maxY, $lineHex) {
    $n = $values.Count
    $points = New-Object 'System.Drawing.PointF[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $x = $plot.Left + $plot.Width * (($xValues[$i] - $minX) / ($maxX - $minX))
        $y = $plot.Top + $plot.Height * ($maxY - $values[$i]) / ($maxY - $minY)
        $points[$i] = New-Object System.Drawing.PointF $x, $y
    }
    $linePen = Pen $lineHex 4
    $g.DrawLines($linePen, $points)
    $linePen.Dispose()

    $fill = Brush $lineHex
    $white = Brush "#ffffff"
    for ($i = 0; $i -lt $n; $i++) {
        $px = $points[$i].X
        $py = $points[$i].Y
        $g.FillEllipse($white, $px - 6, $py - 6, 12, 12)
        $g.FillEllipse($fill, $px - 4, $py - 4, 8, 8)
    }
    $fill.Dispose()
    $white.Dispose()
}

function DrawAxes($plot, $xTicks, $xLabels, $yTicks, $minX, $maxX, $minY, $maxY) {
    $gridPen = Pen "#e8edf4" 2
    $axisPen = Pen "#9aa4b2" 3
    $textBrush = Brush "#4b5563"
    $font = Font 22
    foreach ($tick in $yTicks) {
        $y = $plot.Top + $plot.Height * ($maxY - $tick) / ($maxY - $minY)
        $g.DrawLine($gridPen, $plot.Left, $y, $plot.Left + $plot.Width, $y)
        $label = if ([Math]::Abs($tick - [Math]::Round($tick)) -lt 0.0001) { "{0:0}" -f $tick } else { "{0:0.0}" -f $tick }
        $size = $g.MeasureString($label, $font)
        $g.DrawString($label, $font, $textBrush, $plot.Left - $size.Width - 15, $y - $size.Height / 2)
    }
    $g.DrawLine($axisPen, $plot.Left, $plot.Top, $plot.Left, $plot.Top + $plot.Height)
    $g.DrawLine($axisPen, $plot.Left, $plot.Top + $plot.Height, $plot.Left + $plot.Width, $plot.Top + $plot.Height)
    for ($i = 0; $i -lt $xTicks.Count; $i++) {
        $x = $plot.Left + $plot.Width * (($xTicks[$i] - $minX) / ($maxX - $minX))
        $g.DrawLine($axisPen, $x, $plot.Top + $plot.Height, $x, $plot.Top + $plot.Height + 8)
        $size = $g.MeasureString($xLabels[$i], $font)
        $g.DrawString($xLabels[$i], $font, $textBrush, $x - $size.Width / 2, $plot.Top + $plot.Height + 18)
    }
    $gridPen.Dispose()
    $axisPen.Dispose()
    $textBrush.Dispose()
    $font.Dispose()
}

function DrawLegendItem($x, $y, $text, $hex) {
    $font = Font 21
    $pen = Pen $hex 4
    $brush = Brush $hex
    $white = Brush "#ffffff"
    $labelBrush = Brush "#111827"
    $g.DrawLine($pen, $x, $y + 11, $x + 48, $y + 11)
    $g.FillEllipse($white, $x + 19, $y + 5, 12, 12)
    $g.FillEllipse($brush, $x + 22, $y + 8, 6, 6)
    $g.DrawString($text, $font, $labelBrush, $x + 62, $y)
    $pen.Dispose()
    $brush.Dispose()
    $white.Dispose()
    $labelBrush.Dispose()
    $font.Dispose()
}

$bg = Brush "#f6f9fc"
$g.FillRectangle($bg, 0, 0, $width, $height)
$bg.Dispose()

$cardPen = Pen "#dfe6ef" 2
$cardBrush = Brush "#ffffff"
$card1 = RoundRectPath 42 18 1644 435 16
$card2 = RoundRectPath 42 500 1644 236 16
$g.FillPath($cardBrush, $card1)
$g.DrawPath($cardPen, $card1)
$g.FillPath($cardBrush, $card2)
$g.DrawPath($cardPen, $card2)

$plot1 = [PSCustomObject]@{ Left = 128; Top = 114; Width = 1490; Height = 260 }
$plot2 = [PSCustomObject]@{ Left = 128; Top = 586; Width = 1490; Height = 92 }

$titleFont = Font 29 ([System.Drawing.FontStyle]::Bold)
$subFont = Font 19
$titleBrush = Brush "#111827"
$subBrush = Brush "#64748b"
$g.DrawString($txtSpectrumTrend, $titleFont, $titleBrush, 74, 52)
$g.DrawString(($txtSuppression + " / dBc"), $subFont, $subBrush, 292, 58)
$g.DrawString(($txtFrequencyGHz + " / GHz"), $subFont, $subBrush, 1475, 395)
DrawLegendItem 548 56 $txtHarmonicSuppression "#ef2525"
DrawLegendItem 814 56 $txtNonharmonicSuppression "#16a34a"
DrawBadge $txtHigherBetter 1640 42 "#16a34a"

DrawAxes $plot1 @(0, 0.5, 1.0, 1.5, 2.0) $labels @(40, 50, 60, 70) 0 2.0 40 75
DrawSeries $plot1 $frequenciesGHz $harmonicSuppression 0 2.0 40 75 "#ef2525"
DrawSeries $plot1 $frequenciesGHz $nonharmonicSuppression 0 2.0 40 75 "#16a34a"

$g.DrawString($txtPowerFlatness, $titleFont, $titleBrush, 74, 530)
$g.DrawString(($txtCarrierPower + " / dBm"), $subFont, $subBrush, 315, 536)
$g.DrawString(($txtFrequencyGHz + " / GHz"), $subFont, $subBrush, 1475, 700)
DrawBadge (($txtFlatness + " {0:0.00} dB") -f $flatness) 1640 518 "#2563eb"
DrawAxes $plot2 @(0, 0.5, 1.0, 1.5, 2.0) $labels @(-6.8, -6.6, -6.4, -6.2) 0 2.0 -6.85 -6.15
DrawSeries $plot2 $frequenciesGHz $carrierPower 0 2.0 -6.85 -6.15 "#2563eb"

$card1.Dispose()
$card2.Dispose()
$cardPen.Dispose()
$cardBrush.Dispose()
$titleFont.Dispose()
$subFont.Dispose()
$titleBrush.Dispose()
$subBrush.Dispose()

[System.IO.Directory]::CreateDirectory((Split-Path -Parent $out)) | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

Write-Output $out
