param(
    [string]$OutPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow_editable_v4.vsdx",
    [string]$PngPath = "D:\FPGA\ku5P\ad9173-x\output\figures\dds_jesd_flow_editable_v4.png",
    [switch]$NoPreview
)

$ErrorActionPreference = "Stop"

function Set-Cell($shape, [string]$cell, [string]$formula) {
    try { $shape.CellsU($cell).FormulaU = $formula } catch {}
}

function Apply-Text($shape, [double]$pt, [bool]$bold = $false, [string]$color = "RGB(20,20,20)") {
    Set-Cell $shape "Char.Size" "$pt pt"
    Set-Cell $shape "Char.Style" ($(if ($bold) { "1" } else { "0" }))
    Set-Cell $shape "Char.Color" $color
    Set-Cell $shape "Para.HorzAlign" "1"
    Set-Cell $shape "VerticalAlign" "1"
    Set-Cell $shape "TxtWidth" "Width"
    if ($script:FontId -ne $null) { Set-Cell $shape "Char.Font" "$script:FontId" }
}

function Box($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill, [double]$pt = 7, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "Rounding" "0.025 in"
    Apply-Text $s $pt $bold
    return $s
}

function Region($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$line, [string]$fill) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = ""
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "LinePattern" "2"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "FillTransparency" "12%"
    Set-Cell $s "Rounding" "0.035 in"
    return $s
}

function Label($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$color, [double]$pt = 7, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LinePattern" "0"
    Set-Cell $s "FillPattern" "0"
    Apply-Text $s $pt $bold $color
    return $s
}

function Line($page, [double[]]$pts, [bool]$arrow = $true, [bool]$dash = $false, [string]$color = "RGB(20,20,20)", [double]$weight = 0.9) {
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

function Oval($page, [double]$x, [double]$y, [double]$rx, [double]$ry, [string]$text, [string]$line, [string]$fill, [double]$pt = 7) {
    $s = $page.DrawOval($x - $rx, $y - $ry, $x + $rx, $y + $ry)
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "FillForegnd" $fill
    Apply-Text $s $pt $true
    return $s
}

function Sine($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$color) {
    $px = $x - $w/2
    $py = $y
    for ($i=1; $i -le 40; $i++) {
        $nx = $x - $w/2 + $w*$i/40
        $ny = $y + [Math]::Sin(2*[Math]::PI*$i/40) * $h/2
        $s = $page.DrawLine($px, $py, $nx, $ny)
        Set-Cell $s "LineColor" $color
        Set-Cell $s "LineWeight" "1.2 pt"
        $px = $nx; $py = $ny
    }
}

$visio = New-Object -ComObject Visio.Application
$visio.Visible = $false
try {
    $doc = $visio.Documents.Add("")
    $script:FontId = $null
    foreach ($fontName in @("Microsoft YaHei","微软雅黑","SimHei","宋体")) {
        try {
            $script:FontId = $doc.Fonts.Item($fontName).ID
            break
        } catch {}
    }

    $page = $visio.ActivePage
    $page.Name = "DDS-JESD204C 数据通路"
    $page.PageSheet.CellsU("PageWidth").FormulaU = "15.8 in"
    $page.PageSheet.CellsU("PageHeight").FormulaU = "6.0 in"
    $page.PageSheet.CellsU("PrintPageOrientation").FormulaU = "2"

    $blue="RGB(45,105,180)"; $purple="RGB(105,70,180)"; $green="RGB(35,130,65)"
    $orange="RGB(230,116,20)"; $red="RGB(220,45,45)"; $black="RGB(20,20,20)"
    $fb="RGB(240,246,255)"; $fp="RGB(247,243,255)"; $fg="RGB(241,250,244)"
    $fo="RGB(255,247,236)"; $fr="RGB(255,242,242)"; $white="RGB(255,255,255)"

    # Function regions, compact and close to the reference proportions.
    Region $page 1.05 3.1 1.95 5.45 $blue $fb | Out-Null
    Region $page 3.75 3.1 3.35 5.45 $purple $fp | Out-Null
    Region $page 6.82 3.25 1.95 5.05 $green $fg | Out-Null
    Region $page 8.65 3.25 1.4 5.05 $orange $fo | Out-Null
    Region $page 10.25 3.25 1.55 5.05 $red $fr | Out-Null
    Region $page 11.75 3.25 1.2 5.05 $red $fr | Out-Null
    Region $page 13.55 3.25 2.25 5.05 $red $fr | Out-Null

    Label $page 1.05 5.65 1.55 0.22 "频率配置（软件侧）" $blue 8.0 $true | Out-Null
    Label $page 3.75 5.65 2.95 0.22 "相位累加与并行相位生成（pattern_gen_256.v）" $purple 7.0 $true | Out-Null
    Label $page 6.82 5.65 1.55 0.30 "4 路 DDS 封装模块`n(dds48_phase_to_sine_quad.v)" $green 6.7 $true | Out-Null
    Label $page 8.65 5.65 1.1 0.30 "幅度控制`n(pattern_gen_256.v)" $orange 6.5 $true | Out-Null
    Label $page 10.25 5.65 1.25 0.30 "四通道并行打包`n(pattern_gen_256.v)" $red 6.4 $true | Out-Null
    Label $page 11.75 5.65 0.9 0.30 "JESD204C`nTX IP" $red 7.0 $true | Out-Null
    Label $page 13.55 5.65 1.2 0.22 "AD9173 DAC" $red 7.5 $true | Out-Null

    # Frequency config.
    Box $page 1.05 5.05 0.55 0.45 "上位机`n或 MicroBlaze" $blue $white 5.6 $true | Out-Null
    Label $page 1.05 4.55 1.35 0.18 "下发目标频率 f_out" $blue 6.0 $true | Out-Null
    Box $page 1.05 4.05 1.45 0.52 "软件计算 FTW（48 bit）`nFTW = f_out / f_s × 2^48" $blue $white 5.9 $true | Out-Null
    Box $page 1.05 3.25 1.45 0.52 "写入 FPGA 寄存器`nftw[47:0]" $blue $white 6.0 $true | Out-Null
    Box $page 1.05 1.35 1.55 1.2 "设计参数示例`nJESD 工作时钟：245.76 MHz`n并行因子：4（4 采样点/clk）`nDDS 等效采样率：983.04 MSPS`n相位宽度：48 bit`n幅度格式：Q1.15 unsigned`n采样位宽：16 bit" $blue $white 4.9 $false | Out-Null
    Line $page @(1.05,4.83,1.05,4.31) $true $false $blue
    Line $page @(1.05,3.79,1.05,3.51) $true $false $blue

    # Phase generator.
    Box $page 2.9 4.45 1.25 0.9 "48 bit 相位累加器`n每个 DAC 通道独立`nphase_reg[47:0]" $purple $white 5.6 $true | Out-Null
    Oval $page 2.9 3.48 0.21 0.21 "+" $purple $white 8.0 | Out-Null
    Box $page 2.9 2.85 1.0 0.4 "+ 4×FTW" $purple $white 6.2 $true | Out-Null
    Line $page @(1.78,3.25,2.25,3.25,2.25,4.45,2.28,4.45) $true
    Label $page 2.02 4.05 0.55 0.16 "FTW[47:0]" $black 5.0 $false | Out-Null
    Line $page @(2.9,4.0,2.9,3.69) $true
    Line $page @(2.9,3.27,2.9,3.05) $true
    Line $page @(3.4,2.85,3.62,2.85,3.62,4.45,3.52,4.45) $true

    Box $page 4.75 5.0 1.95 0.42 "同一 JESD 时钟周期内`n并行生成 4 个相位值" $purple $white 5.6 $true | Out-Null
    $phaseY = @(4.45,4.0,3.55,3.1)
    $phaseText = @("phase_0 = phase","phase_1 = phase + 1×FTW","phase_2 = phase + 2×FTW","phase_3 = phase + 3×FTW")
    for ($i=0; $i -lt 4; $i++) {
        Box $page 4.75 $phaseY[$i] 1.9 0.32 $phaseText[$i] $purple $white 5.7 $true | Out-Null
        Label $page 5.82 $phaseY[$i] 0.5 0.14 ("phase_{0}[47:0]" -f $i) $black 4.5 $false | Out-Null
    }
    Box $page 4.75 2.35 1.9 0.46 "周期结束后，相位状态更新`nphase_next = phase + 4×FTW" $purple $white 5.2 $true | Out-Null
    Label $page 3.75 0.55 3.0 0.32 "每个 DAC 通道维护独立的 48 bit 相位累加器`n实现 4 倍并行采样：245.76 MHz → 983.04 MSPS 等效采样率" $purple 5.3 $true | Out-Null
    Line $page @(3.52,4.45,3.8,4.45) $true

    # DDS rows.
    $rows = @(4.65,3.95,3.25,2.55)
    for ($i=0; $i -lt 4; $i++) {
        Box $page 6.18 $rows[$i] 0.55 0.42 "相位高`n16 bit`n[47:32]" $green $white 4.6 $true | Out-Null
        Box $page 7.05 $rows[$i] 0.98 0.48 "Xilinx DDS Compiler IP`ndds_phase_to_sine`n相位 → 正弦" $green $white 4.45 $true | Out-Null
        Line $page @(5.72,$phaseY[$i],5.9,$phaseY[$i],5.9,$rows[$i],5.9,$rows[$i]) $false
        Line $page @(5.9,$rows[$i],5.91,$rows[$i]) $true
        Line $page @(6.46,$rows[$i],6.56,$rows[$i]) $true
        Label $page 7.72 ($rows[$i]+0.11) 0.38 0.14 ("S{0}[15:0]" -f $i) $black 4.5 $false | Out-Null
        Line $page @(7.54,$rows[$i],8.0,$rows[$i]) $true
    }
    Box $page 6.82 1.05 1.65 0.62 "dds_phase_to_sine 为 Xilinx DDS Compiler IP`n使用相位查表（LUT）或 CORDIC 完成正弦量化`n每周期生成 4 路并行 16 bit 正弦采样" $green $white 4.55 $false | Out-Null

    # Amplitude control.
    Oval $page 8.65 5.0 0.26 0.26 "Q1.15`nscale" $orange $white 4.8 | Out-Null
    for ($i=0; $i -lt 4; $i++) {
        Oval $page 8.65 $rows[$i] 0.19 0.19 "×" $orange $white 7.0 | Out-Null
        Line $page @(8.2,$rows[$i],8.46,$rows[$i]) $true
        Line $page @(8.65,4.74,8.65,($rows[$i]+0.19)) $true $true
        Line $page @(8.84,$rows[$i],9.32,$rows[$i]) $true
        Label $page 9.08 ($rows[$i]+0.13) 0.42 0.16 "16 bit`n缩放输出" $black 4.2 $false | Out-Null
    }
    Box $page 8.65 0.92 1.05 0.55 "scale：unsigned Q1.15`n0x0000 = 静音`n0x7FFF = 满幅输出" $orange $white 4.6 $false | Out-Null

    # Packing, with four visible n=0..3 sample cells.
    $dac = @("DAC0","DAC1","DAC2","DAC3")
    for ($i=0; $i -lt 4; $i++) {
        Label $page 9.65 ($rows[$i]+0.12) 0.34 0.15 $dac[$i] $black 4.6 $true | Out-Null
        Line $page @(9.32,$rows[$i],9.58,$rows[$i]) $true
        $baseX = 9.92
        for ($j=0; $j -lt 4; $j++) {
            Box $page ($baseX + 0.25*$j) $rows[$i] 0.25 0.34 ("n={0}" -f $j) $red $white 5.1 $true | Out-Null
        }
    }
    Box $page 11.05 3.6 0.68 0.75 "256 bit`n并行数据`n4 Ch ×`n4 采样 ×`n16 bit" $red $white 4.7 $true | Out-Null
    $mergeY = @(3.93,3.72,3.51,3.30)
    for ($i=0; $i -lt 4; $i++) {
        Line $page @(10.67,$rows[$i],10.85,$mergeY[$i]) $false
        Line $page @(10.85,$mergeY[$i],11.05,$mergeY[$i]) $true
    }

    # JESD and DAC.
    Box $page 11.75 4.85 0.9 0.72 "高速串行发送" $red $white 5.8 $true | Out-Null
    Box $page 11.75 3.25 0.95 0.9 "JESD 数据映射`n(tx_mapper.v)`n数据打包与`n字节重排" $red $white 4.8 $true | Out-Null
    Line $page @(11.75,4.49,11.75,3.70) $true $false $red 1.0
    Line $page @(11.75,2.80,11.75,2.10) $true $false $red 1.0
    Line $page @(11.39,3.6,11.27,3.6) $true
    Label $page 11.75 1.92 0.6 0.16 "256 bit" $black 4.8 $true | Out-Null

    Box $page 13.55 4.38 1.05 0.72 "256 bit`n并行输入" $red $white 5.2 $true | Out-Null
    Line $page @(11.75,2.10,13.35,4.00) $true $false $red 0.9
    Sine $page 13.55 3.0 0.95 0.62 $red
    Label $page 13.55 2.35 1.2 0.2 "模拟正弦输出" $red 5.5 $true | Out-Null

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
