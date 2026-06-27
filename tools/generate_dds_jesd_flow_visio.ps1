param(
    [string]$OutPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow.vsdx",
    [string]$PngPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow_visio.png",
    [switch]$NoPreview
)

$ErrorActionPreference = "Stop"

function Set-Cell($shape, [string]$cell, [string]$formula) {
    try { $shape.CellsU($cell).FormulaU = $formula } catch {}
}

function Set-TextStyle($shape, [double]$pt = 8, [bool]$bold = $false, [string]$color = "RGB(17,17,17)") {
    Set-Cell $shape "Char.Size" "$pt pt"
    Set-Cell $shape "Char.Style" ($(if ($bold) { "1" } else { "0" }))
    Set-Cell $shape "Char.Color" $color
    Set-Cell $shape "Para.HorzAlign" "1"
    Set-Cell $shape "VerticalAlign" "1"
    Set-Cell $shape "TxtWidth" "Width"
}

function Add-Region($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$line, [string]$fill) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = ""
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "LinePattern" "2"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "FillTransparency" "18%"
    Set-Cell $s "Rounding" "0.04 in"
    return $s
}

function Add-Box($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill, [double]$pt = 8, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "Rounding" "0.03 in"
    Set-TextStyle $s $pt $bold
    return $s
}

function Add-Text($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$color, [double]$pt = 8, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LinePattern" "0"
    Set-Cell $s "FillPattern" "0"
    Set-TextStyle $s $pt $bold $color
    return $s
}

function Add-Line($page, [double[]]$pts, [bool]$arrow = $true, [bool]$dash = $false, [string]$color = "RGB(17,17,17)") {
    for ($i = 0; $i -lt ($pts.Length - 2); $i += 2) {
        $s = $page.DrawLine($pts[$i], $pts[$i + 1], $pts[$i + 2], $pts[$i + 3])
        Set-Cell $s "LineColor" $color
        Set-Cell $s "LineWeight" "0.9 pt"
        if ($dash) { Set-Cell $s "LinePattern" "2" }
        if ($arrow -and $i -ge ($pts.Length - 4)) {
            Set-Cell $s "EndArrow" "4"
            Set-Cell $s "EndArrowSize" "2"
        }
    }
}

function Add-Circle($page, [double]$x, [double]$y, [double]$r, [string]$text, [string]$line, [string]$fill, [double]$pt = 8) {
    $s = $page.DrawOval($x - $r, $y - $r, $x + $r, $y + $r)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-TextStyle $s $pt $true
    return $s
}

function Add-Sine($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$color) {
    $lastX = $x - $w / 2
    $lastY = $y
    $segments = 28
    for ($i = 1; $i -le $segments; $i++) {
        $nx = $x - $w / 2 + $w * $i / $segments
        $ny = $y + [Math]::Sin(2 * [Math]::PI * $i / $segments) * $h / 2
        $s = $page.DrawLine($lastX, $lastY, $nx, $ny)
        Set-Cell $s "LineColor" $color
        Set-Cell $s "LineWeight" "1.2 pt"
        $lastX = $nx
        $lastY = $ny
    }
}

$outDir = Split-Path -Parent $OutPath
if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (Test-Path $OutPath) {
    $backup = [System.IO.Path]::ChangeExtension($OutPath, ".backup-$(Get-Date -Format yyyyMMdd-HHmmss).vsdx")
    Copy-Item -LiteralPath $OutPath -Destination $backup
}

$visio = New-Object -ComObject Visio.Application
$visio.Visible = $false
try {
    $doc = $visio.Documents.Add("")
    $page = $visio.ActivePage
    $page.Name = "DDS-JESD204C 数据路径"
    $page.PageSheet.CellsU("PageWidth").FormulaU = "16.5 in"
    $page.PageSheet.CellsU("PageHeight").FormulaU = "6.2 in"
    $page.PageSheet.CellsU("PrintPageOrientation").FormulaU = "2"

    $blue = "RGB(45,105,180)"
    $purple = "RGB(105,70,180)"
    $green = "RGB(45,135,70)"
    $orange = "RGB(230,118,24)"
    $red = "RGB(220,45,45)"
    $black = "RGB(20,20,20)"
    $fillBlue = "RGB(240,246,255)"
    $fillPurple = "RGB(246,242,255)"
    $fillGreen = "RGB(241,250,244)"
    $fillOrange = "RGB(255,246,235)"
    $fillRed = "RGB(255,242,242)"
    $fillWhite = "RGB(255,255,255)"

    Add-Region $page 1.15 3.45 2.05 5.35 $blue $fillBlue | Out-Null
    Add-Region $page 4.15 3.45 3.8 5.35 $purple $fillPurple | Out-Null
    Add-Region $page 7.55 3.65 2.1 4.95 $green $fillGreen | Out-Null
    Add-Region $page 9.75 3.65 1.85 4.95 $orange $fillOrange | Out-Null
    Add-Region $page 11.75 3.65 1.9 4.95 $red $fillRed | Out-Null
    Add-Region $page 13.55 3.65 1.25 4.95 $red $fillRed | Out-Null
    Add-Region $page 15.0 3.65 1.75 4.95 $red $fillRed | Out-Null

    Add-Text $page 1.15 5.8 1.8 0.22 "频率配置（软件侧）" $blue 8.5 $true | Out-Null
    Add-Box $page 1.15 5.25 0.65 0.42 "上位机`n或 MicroBlaze" $blue $fillWhite 6.5 $true | Out-Null
    Add-Text $page 1.15 4.78 1.7 0.22 "下发目标频率 f_out" $blue 6.8 $true | Out-Null
    Add-Box $page 1.15 4.25 1.55 0.55 "软件计算 FTW（48 bit）`nFTW = f_out / f_s × 2^48" $blue $fillWhite 6.6 $true | Out-Null
    Add-Box $page 1.15 3.45 1.55 0.55 "写入 FPGA 寄存器`nftw[47:0]" $blue $fillWhite 6.7 $true | Out-Null
    Add-Box $page 1.15 1.7 1.7 1.05 "设计参数示例`nJESD 工作时钟：245.76 MHz`n并行因子：4`nDDS 等效采样率：983.04 MSPS`n相位宽度：48 bit`n输出位宽：16 bit" $blue $fillWhite 5.7 $false | Out-Null
    Add-Line $page @(1.15,5.03,1.15,4.55) $true $false $blue
    Add-Line $page @(1.15,3.98,1.15,3.73) $true $false $blue

    Add-Text $page 4.15 5.8 3.35 0.24 "相位累加与并行相位生成（pattern_gen_256.v）" $purple 8.2 $true | Out-Null
    Add-Box $page 3.0 4.75 1.55 0.75 "48 bit 相位累加器`n每个 DAC 通道独立`nphase_reg[47:0]" $purple $fillWhite 6.7 $true | Out-Null
    Add-Circle $page 3.0 3.95 0.2 "+" $purple $fillWhite 8 | Out-Null
    Add-Box $page 3.0 3.3 1.2 0.38 "+ 4×FTW" $purple $fillWhite 7 $true | Out-Null
    Add-Line $page @(3.0,4.37,3.0,4.15) $true $false $black
    Add-Line $page @(3.0,3.75,3.0,3.49) $true $false $black
    Add-Line $page @(3.6,3.3,3.9,3.3,3.9,4.75,3.78,4.75) $true $false $black
    Add-Box $page 5.0 5.05 2.1 0.36 "同一 JESD 时钟周期内`n并行生成 4 个相位值" $purple $fillWhite 6.5 $true | Out-Null
    Add-Box $page 5.0 4.55 1.95 0.34 "phase_0 = phase" $purple $fillWhite 6.4 $true | Out-Null
    Add-Box $page 5.0 4.13 1.95 0.34 "phase_1 = phase + 1×FTW" $purple $fillWhite 6.4 $true | Out-Null
    Add-Box $page 5.0 3.71 1.95 0.34 "phase_2 = phase + 2×FTW" $purple $fillWhite 6.4 $true | Out-Null
    Add-Box $page 5.0 3.29 1.95 0.34 "phase_3 = phase + 3×FTW" $purple $fillWhite 6.4 $true | Out-Null
    Add-Box $page 5.0 2.55 1.95 0.45 "周期结束后：`nphase_next = phase + 4×FTW" $purple $fillWhite 6.2 $true | Out-Null
    Add-Text $page 4.15 0.85 3.3 0.35 "每个 DAC 通道维护独立的 48 bit 相位累加器`n实现 4 倍并行采样：245.76 MHz → 983.04 MSPS 等效采样率" $purple 6.1 $true | Out-Null
    Add-Line $page @(1.93,3.45,2.23,3.45,2.23,4.75) $true $false $black
    Add-Line $page @(3.78,4.75,4.02,4.75) $true $false $black

    Add-Text $page 7.55 5.8 1.7 0.25 "4 路 DDS 封装模块`n(dds48_phase_to_sine_quad.v)" $green 7.6 $true | Out-Null
    $ddsY = @(4.85,4.2,3.55,2.9)
    for ($i = 0; $i -lt 4; $i++) {
        $y = $ddsY[$i]
        Add-Box $page 6.75 $y 0.65 0.36 "相位输入`n16 bit`n[47:32]" $green $fillWhite 5.6 $true | Out-Null
        Add-Box $page 7.75 $y 1.15 0.42 "Xilinx DDS Compiler IP`ndds_phase_to_sine`n相位 → 正弦" $green $fillWhite 5.2 $true | Out-Null
        Add-Line $page @(6.02,(4.55 - 0.42*$i),6.42,$y) $true $false $black
        Add-Line $page @(7.08,$y,7.17,$y) $true $false $black
        Add-Line $page @(8.32,$y,8.75,$y) $true $false $black
    }
    Add-Box $page 7.55 1.35 1.7 0.62 "dds_phase_to_sine 为 Xilinx DDS Compiler IP`n使用相位查表（LUT）输出 CORDIC 完成正弦量化`n每周期生成 4 路并行 16 bit 正弦采样" $green $fillWhite 5.3 $false | Out-Null

    Add-Text $page 9.75 5.8 1.5 0.25 "幅度控制`n(pattern_gen_256.v)" $orange 7.5 $true | Out-Null
    for ($i = 0; $i -lt 4; $i++) {
        $y = $ddsY[$i]
        Add-Circle $page 9.45 $y 0.18 "×" $orange $fillWhite 8 | Out-Null
        Add-Line $page @(8.75,$y,9.27,$y) $true $false $black
        Add-Text $page 9.1 ($y + 0.18) 0.42 0.16 ("S{0}[15:0]" -f $i) $black 5.5 $false | Out-Null
        Add-Line $page @(9.45,5.35,9.45,($y + 0.18)) $true $true $black
        Add-Line $page @(9.63,$y,10.35,$y) $true $false $black
        Add-Text $page 10.0 ($y + 0.14) 0.5 0.14 "16 bit`n缩放输出" $black 5.0 $false | Out-Null
    }
    Add-Circle $page 9.45 5.45 0.22 "Q1.15`nscale" $orange $fillWhite 5.3 | Out-Null
    Add-Box $page 9.75 1.45 1.35 0.55 "scale：unsigned Q1.15`n0x0000 = 静音`n0x7FFF = 满幅输出" $orange $fillWhite 5.7 $false | Out-Null

    Add-Text $page 11.75 5.8 1.5 0.25 "四通道并行打包`n(pattern_gen_256.v)" $red 7.4 $true | Out-Null
    $names = @("DAC0","DAC1","DAC2","DAC3")
    for ($i = 0; $i -lt 4; $i++) {
        $y = $ddsY[$i]
        Add-Text $page 10.95 ($y + 0.12) 0.5 0.16 $names[$i] $black 5.5 $true | Out-Null
        Add-Box $page 11.75 $y 1.15 0.44 "n=0   n=1   n=2   n=3" $red $fillWhite 5.4 $true | Out-Null
        Add-Line $page @(10.35,$y,11.18,$y) $true $false $black
    }
    Add-Box $page 12.78 3.55 0.75 0.78 "256 bit`n并行数据`n4 Ch ×`n4 采样 ×`n16 bit" $red $fillWhite 5.4 $true | Out-Null
    Add-Line $page @(12.33,4.85,12.78,3.94) $true $false $black
    Add-Line $page @(12.33,4.2,12.78,3.72) $true $false $black
    Add-Line $page @(12.33,3.55,12.78,3.55) $true $false $black
    Add-Line $page @(12.33,2.9,12.78,3.36) $true $false $black

    Add-Text $page 13.55 5.8 1.1 0.25 "JESD204C`nTX IP" $red 8 $true | Out-Null
    Add-Box $page 13.55 5.0 0.95 0.72 "高速串行发送" $red $fillWhite 6.4 $true | Out-Null
    Add-Box $page 13.55 3.75 0.95 0.72 "JESD 数据映射`n(tx_mapper.v)`n数据打包与`n字节重排" $red $fillWhite 5.5 $true | Out-Null
    Add-Line $page @(13.55,4.64,13.55,4.11) $true $false $red
    Add-Line $page @(13.15,3.55,13.08,3.55) $true $false $black
    Add-Line $page @(13.55,3.39,13.55,2.55) $true $false $red

    Add-Text $page 15.0 5.8 1.3 0.25 "AD9173 DAC" $red 8.5 $true | Out-Null
    Add-Box $page 15.0 4.55 1.15 0.65 "256 bit`n并行输入" $red $fillWhite 6.2 $true | Out-Null
    Add-Sine $page 15.0 3.5 0.85 0.55 $red
    Add-Text $page 15.0 2.95 1.3 0.25 "模拟正弦输出" $red 6.5 $true | Out-Null
    Add-Line $page @(13.55,2.55,15.0,4.22) $true $false $red

    if (Test-Path $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
    $doc.SaveAs($OutPath)
    if (!$NoPreview -and $PngPath) {
        if (Test-Path $PngPath) { Remove-Item -LiteralPath $PngPath -Force }
        $page.Export($PngPath)
    }
    Write-Output "Saved: $OutPath"
    if (!$NoPreview -and $PngPath) { Write-Output "Preview: $PngPath" }
}
finally {
    if ($doc) { $doc.Close() | Out-Null }
    $visio.Quit() | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($visio) | Out-Null
}
