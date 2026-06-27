param(
    [string]$OutPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow_editable_v3.vsdx",
    [string]$PngPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow_editable_v3.png",
    [switch]$NoPreview
)

$ErrorActionPreference = "Stop"

function Set-Cell($shape, [string]$cell, [string]$formula) {
    try { $shape.CellsU($cell).FormulaU = $formula } catch {}
}

function Text-Style($shape, [double]$pt, [bool]$bold = $false, [string]$color = "RGB(20,20,20)") {
    Set-Cell $shape "Char.Size" "$pt pt"
    Set-Cell $shape "Char.Style" ($(if ($bold) { "1" } else { "0" }))
    Set-Cell $shape "Char.Color" $color
    Set-Cell $shape "Para.HorzAlign" "1"
    Set-Cell $shape "VerticalAlign" "1"
    Set-Cell $shape "TxtWidth" "Width"
}

function Box($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill, [double]$pt = 7.0, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.85 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "Rounding" "0.025 in"
    Text-Style $s $pt $bold
    return $s
}

function Region($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$line, [string]$fill) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = ""
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "LinePattern" "2"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "FillTransparency" "10%"
    Set-Cell $s "Rounding" "0.035 in"
    return $s
}

function Label($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$color, [double]$pt = 7.0, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LinePattern" "0"
    Set-Cell $s "FillPattern" "0"
    Text-Style $s $pt $bold $color
    return $s
}

function Line($page, [double[]]$pts, [bool]$arrow = $true, [bool]$dash = $false, [string]$color = "RGB(20,20,20)", [double]$weight = 0.85) {
    for ($i = 0; $i -lt ($pts.Length - 2); $i += 2) {
        $s = $page.DrawLine($pts[$i], $pts[$i+1], $pts[$i+2], $pts[$i+3])
        Set-Cell $s "LineColor" $color
        Set-Cell $s "LineWeight" "$weight pt"
        if ($dash) { Set-Cell $s "LinePattern" "2" }
        if ($arrow -and $i -ge ($pts.Length - 4)) {
            Set-Cell $s "EndArrow" "4"
            Set-Cell $s "EndArrowSize" "2"
        }
    }
}

function Oval($page, [double]$x, [double]$y, [double]$rx, [double]$ry, [string]$text, [string]$line, [string]$fill, [double]$pt = 7.0) {
    $s = $page.DrawOval($x - $rx, $y - $ry, $x + $rx, $y + $ry)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.85 pt"
    Set-Cell $s "FillForegnd" $fill
    Text-Style $s $pt $true
    return $s
}

function Sine($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$color) {
    $lastX = $x - $w/2
    $lastY = $y
    for ($i=1; $i -le 36; $i++) {
        $nx = $x - $w/2 + $w*$i/36
        $ny = $y + [Math]::Sin(2*[Math]::PI*$i/36)*$h/2
        $s = $page.DrawLine($lastX, $lastY, $nx, $ny)
        Set-Cell $s "LineColor" $color
        Set-Cell $s "LineWeight" "1.1 pt"
        $lastX=$nx; $lastY=$ny
    }
}

function BusCell($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill) {
    return Box $page $x $y $w $h $text $line $fill 5.5 $true
}

$outDir = Split-Path -Parent $OutPath
if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$visio = New-Object -ComObject Visio.Application
$visio.Visible = $false
try {
    $doc = $visio.Documents.Add("")
    $page = $visio.ActivePage
    $page.Name = "DDS 并行波形到 JESD204C"
    $page.PageSheet.CellsU("PageWidth").FormulaU = "18 in"
    $page.PageSheet.CellsU("PageHeight").FormulaU = "6.4 in"
    $page.PageSheet.CellsU("PrintPageOrientation").FormulaU = "2"

    $blue="RGB(45,105,180)"; $purple="RGB(105,70,180)"; $green="RGB(35,130,65)"
    $orange="RGB(230,116,20)"; $red="RGB(220,45,45)"; $black="RGB(20,20,20)"
    $fb="RGB(240,246,255)"; $fp="RGB(247,243,255)"; $fg="RGB(241,250,244)"
    $fo="RGB(255,247,236)"; $fr="RGB(255,242,242)"; $white="RGB(255,255,255)"

    # Main dashed regions, matched to the reference layout.
    Region $page 1.25 3.3 2.35 5.75 $blue $fb | Out-Null
    Region $page 4.2 3.3 3.55 5.75 $purple $fp | Out-Null
    Region $page 7.65 3.35 2.15 5.2 $green $fg | Out-Null
    Region $page 9.8 3.35 1.55 5.2 $orange $fo | Out-Null
    Region $page 11.55 3.35 1.75 5.2 $red $fr | Out-Null
    Region $page 13.25 3.35 1.15 5.2 $red $fr | Out-Null
    Region $page 15.3 3.35 2.75 5.2 $red $fr | Out-Null

    # Region titles.
    Label $page 1.25 5.9 1.8 0.22 "频率配置（软件侧）" $blue 7.4 $true | Out-Null
    Label $page 4.2 5.9 3.15 0.22 "相位累加与并行相位生成（pattern_gen_256.v）" $purple 7.0 $true | Out-Null
    Label $page 7.65 5.9 1.7 0.32 "4 路 DDS 封装模块`n(dds48_phase_to_sine_quad.v)" $green 6.4 $true | Out-Null
    Label $page 9.8 5.9 1.2 0.32 "幅度控制`n(pattern_gen_256.v)" $orange 6.2 $true | Out-Null
    Label $page 11.55 5.9 1.45 0.32 "四通道并行打包`n(pattern_gen_256.v)" $red 6.2 $true | Out-Null
    Label $page 13.25 5.9 1.0 0.3 "JESD204C`nTX IP" $red 6.8 $true | Out-Null
    Label $page 15.3 5.9 1.15 0.22 "AD9173 DAC" $red 7.2 $true | Out-Null

    # Frequency config block.
    Box $page 1.25 5.25 0.62 0.48 "上位机`n或 MicroBlaze" $blue $white 5.8 $true | Out-Null
    Label $page 1.25 4.72 1.45 0.2 "下发目标频率 f_out" $blue 5.8 $true | Out-Null
    Box $page 1.25 4.18 1.55 0.55 "软件计算 FTW（48 bit）`nFTW = f_out / f_s × 2^48" $blue $white 5.9 $true | Out-Null
    Box $page 1.25 3.38 1.55 0.55 "写入 FPGA 寄存器`nftw[47:0]" $blue $white 6.0 $true | Out-Null
    Box $page 1.25 1.45 1.75 1.25 "设计参数示例`nJESD 工作时钟：245.76 MHz`n并行因子：4（4 个采样点/clk）`nDDS 等效采样率：983.04 MSPS`n相位宽度：48 bit`n幅度格式：Q1.15 unsigned`n采样位宽：16 bit" $blue $white 4.8 $false | Out-Null
    Line $page @(1.25,5.01,1.25,4.48) $true $false $blue
    Line $page @(1.25,3.9,1.25,3.66) $true $false $blue

    # Phase accumulator and parallel phase block.
    Box $page 3.25 4.55 1.25 1.0 "48 bit 相位累加器`n每个 DAC 通道独立`nphase_reg[47:0]" $purple $white 5.6 $true | Out-Null
    Oval $page 3.25 3.58 0.22 0.22 "+" $purple $white 8 | Out-Null
    Box $page 3.25 2.98 1.05 0.42 "+ 4×FTW" $purple $white 6.0 $true | Out-Null
    Line $page @(3.25,4.05,3.25,3.8) $true
    Line $page @(3.25,3.36,3.25,3.19) $true
    Line $page @(3.78,2.98,4.0,2.98,4.0,4.55,3.88,4.55) $true
    Line $page @(2.02,3.38,2.35,3.38,2.35,4.55,2.62,4.55) $true
    Label $page 2.25 4.72 0.55 0.18 "FTW[47:0]" $black 5.2 $false | Out-Null

    Box $page 5.0 5.15 2.15 0.5 "同一 JESD 时钟周期内`n并行生成 4 个相位值" $purple $white 5.6 $true | Out-Null
    $phaseRows = @(
        @{y=4.55; t="phase_0 = phase"; o="phase_0[47:0]"},
        @{y=4.08; t="phase_1 = phase + 1×FTW"; o="phase_1[47:0]"},
        @{y=3.61; t="phase_2 = phase + 2×FTW"; o="phase_2[47:0]"},
        @{y=3.14; t="phase_3 = phase + 3×FTW"; o="phase_3[47:0]"}
    )
    foreach ($r in $phaseRows) {
        Box $page 5.0 $r.y 2.0 0.34 $r.t $purple $white 5.7 $true | Out-Null
        Label $page 6.25 $r.y 0.68 0.18 $r.o $black 4.8 $false | Out-Null
    }
    Box $page 5.0 2.28 2.05 0.48 "周期结束后，相位状态更新`nphase_next = phase + 4×FTW" $purple $white 5.3 $true | Out-Null
    Label $page 4.2 0.55 3.25 0.35 "每个 DAC 通道维护独立的 48 bit 相位累加器`n实现 4 倍并行采样：245.76 MHz → 983.04 MSPS 等效采样率" $purple 5.4 $true | Out-Null
    Line $page @(3.88,4.55,4.0,4.55) $true

    # DDS block, 4 rows.
    $rows = @(4.85,4.15,3.45,2.75)
    for ($i=0; $i -lt 4; $i++) {
        $y=$rows[$i]
        Box $page 6.75 $y 0.58 0.42 "相位高`n16 bit`n[47:32]" $green $white 4.6 $true | Out-Null
        Box $page 7.72 $y 1.08 0.5 "Xilinx DDS Compiler IP`ndds_phase_to_sine`n相位 → 正弦" $green $white 4.5 $true | Out-Null
        Line $page @(6.0,$phaseRows[$i].y,6.45,$y) $true
        Line $page @(7.04,$y,7.18,$y) $true
        Label $page 8.43 ($y+0.12) 0.45 0.16 ("S{0}[15:0]" -f $i) $black 4.5 $false | Out-Null
    }
    Box $page 7.65 1.1 1.8 0.65 "dds_phase_to_sine 为 Xilinx DDS Compiler IP`n使用相位查表（LUT）或 CORDIC 完成正弦量化`n每周期生成 4 路并行 16 bit 正弦采样" $green $white 4.7 $false | Out-Null

    # Scale control.
    Oval $page 9.58 5.15 0.28 0.28 "Q1.15`nscale" $orange $white 4.8 | Out-Null
    for ($i=0; $i -lt 4; $i++) {
        $y=$rows[$i]
        Line $page @(8.26,$y,9.3,$y) $true
        Oval $page 9.58 $y 0.2 0.2 "×" $orange $white 7 | Out-Null
        Line $page @(9.58,4.88,9.58,($y+0.2)) $true $true
        Line $page @(9.78,$y,10.48,$y) $true
        Label $page 10.16 ($y+0.15) 0.48 0.16 "16 bit`n缩放输出" $black 4.3 $false | Out-Null
    }
    Box $page 9.8 0.9 1.22 0.58 "scale：unsigned Q1.15`n0x0000 = 静音`n0x7FFF = 满幅输出" $orange $white 4.8 $false | Out-Null

    # DAC channel packing.
    $dacNames=@("DAC0","DAC1","DAC2","DAC3")
    for ($i=0; $i -lt 4; $i++) {
        $y=$rows[$i]
        Label $page 10.78 ($y+0.15) 0.4 0.16 $dacNames[$i] $black 4.6 $true | Out-Null
        Line $page @(10.48,$y,10.88,$y) $true
        $x0=11.22
        for ($j=0; $j -lt 4; $j++) {
            BusCell $page ($x0 + 0.28*$j) $y 0.28 0.34 ("n={0}" -f $j) $red $white | Out-Null
        }
    }
    Box $page 12.55 3.8 0.72 0.78 "256 bit`n并行数据`n4 Ch ×`n4 采样 ×`n16 bit" $red $white 4.8 $true | Out-Null
    $mergeYs = @(4.07,3.89,3.71,3.53)
    for ($i=0; $i -lt 4; $i++) {
        Line $page @(11.92,$rows[$i],12.18,$mergeYs[$i],12.18,$mergeYs[$i],12.19,$mergeYs[$i]) $false
        Line $page @(12.19,$mergeYs[$i],12.55,$mergeYs[$i]) $true
    }

    # JESD and AD9173.
    Box $page 13.25 5.0 0.9 0.78 "高速串行发送" $red $white 5.7 $true | Out-Null
    Box $page 13.25 3.45 0.95 0.95 "JESD 数据映射`n(tx_mapper.v)`n数据打包与`n字节重排" $red $white 4.8 $true | Out-Null
    Line $page @(13.25,4.61,13.25,3.93) $true $false $red 1.0
    Line $page @(13.25,2.98,13.25,2.25) $true $false $red 1.0
    Line $page @(12.91,3.8,12.78,3.8) $true
    Label $page 13.25 2.05 0.65 0.18 "256 bit" $black 4.8 $true | Out-Null

    Box $page 15.35 4.55 1.05 0.8 "256 bit`n并行输入" $red $white 5.3 $true | Out-Null
    Line $page @(13.25,2.25,15.15,4.15) $true $false $red 0.9
    Sine $page 15.35 3.0 0.95 0.6 $red
    Label $page 15.35 2.35 1.3 0.22 "模拟正弦输出" $red 5.5 $true | Out-Null

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
