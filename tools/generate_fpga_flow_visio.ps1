param(
    [string]$OutPath = "D:\FPGA\ku5P\ad9173-x\output\figures\fpga_main_control_flow.vsdx",
    [string]$PngPath = "D:\FPGA\ku5P\ad9173-x\output\figures\fpga_main_control_flow_visio.png",
    [switch]$NoPreview
)

$ErrorActionPreference = "Stop"

function Log-Step([string]$message) {
    Write-Output "$(Get-Date -Format HH:mm:ss) $message"
}

function Set-Cell($shape, [string]$cell, [string]$formula) {
    try { $shape.CellsU($cell).FormulaU = $formula } catch {}
}

function Set-TextStyle($shape, [double]$pt = 9, [bool]$bold = $false, [string]$color = "RGB(17,17,17)") {
    Set-Cell $shape "Char.Size" "$pt pt"
    Set-Cell $shape "Char.Style" ($(if ($bold) { "1" } else { "0" }))
    Set-Cell $shape "Char.Color" $color
    Set-Cell $shape "Para.HorzAlign" "1"
    Set-Cell $shape "VerticalAlign" "1"
    Set-Cell $shape "TxtWidth" "Width"
}

function Size-Shape($s, [double]$w, [double]$h) {
    Set-Cell $s "Width" "$w in"
    Set-Cell $s "Height" "$h in"
}

function Add-Box($page, $master, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill, [double]$pt = 9, [bool]$bold = $true) {
    if ($master) {
        $s = $page.Drop($master, $x, $y)
        Size-Shape $s $w $h
    } else {
        $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    }
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "1.1 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-Cell $s "Rounding" "0.04 in"
    Set-TextStyle $s $pt $bold
    return $s
}

function Add-Diamond($page, $master, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$line, [string]$fill, [double]$pt = 9) {
    if ($master) {
        $s = $page.Drop($master, $x, $y)
        Size-Shape $s $w $h
    } else {
        $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
        Set-Cell $s "Angle" "45 deg"
    }
    $s.Text = $text
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "1.1 pt"
    Set-Cell $s "FillForegnd" $fill
    Set-TextStyle $s $pt $true
    return $s
}

function Add-DashedRegion($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$line) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = ""
    Set-Cell $s "FillPattern" "0"
    Set-Cell $s "LineColor" $line
    Set-Cell $s "LineWeight" "0.9 pt"
    Set-Cell $s "LinePattern" "2"
    Set-Cell $s "Rounding" "0.06 in"
    return $s
}

function Add-Text($page, [double]$x, [double]$y, [double]$w, [double]$h, [string]$text, [string]$color, [double]$pt = 9, [bool]$bold = $true) {
    $s = $page.DrawRectangle($x - $w / 2, $y - $h / 2, $x + $w / 2, $y + $h / 2)
    $s.Text = $text
    Set-Cell $s "LinePattern" "0"
    Set-Cell $s "FillPattern" "0"
    Set-TextStyle $s $pt $bold $color
    return $s
}

function Add-Line($page, [double[]]$pts, [bool]$arrow = $true, [bool]$dash = $false) {
    $made = @()
    for ($i = 0; $i -lt ($pts.Length - 2); $i += 2) {
        $x1 = $pts[$i]; $y1 = $pts[$i + 1]; $x2 = $pts[$i + 2]; $y2 = $pts[$i + 3]
        $s = $page.DrawLine($x1, $y1, $x2, $y2)
        Set-Cell $s "LineColor" "RGB(17,17,17)"
        Set-Cell $s "LineWeight" "1.1 pt"
        if ($dash) { Set-Cell $s "LinePattern" "2" }
        if ($arrow -and $i -ge ($pts.Length - 4)) {
            Set-Cell $s "EndArrow" "4"
            Set-Cell $s "EndArrowSize" "2"
        }
        $made += $s
    }
    return $made
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
    Log-Step "Creating Visio document"
    $doc = $visio.Documents.Add("")
    $page = $visio.ActivePage
    $stencil = $visio.Documents.OpenEx("BASFLO_U.VSSX", 64)
    $processMaster = $stencil.Masters.ItemU("Process")
    $decisionMaster = $stencil.Masters.ItemU("Decision")
    $page.Name = "FPGA 主控制流程"
    $page.PageSheet.CellsU("PageWidth").FormulaU = "11.7 in"
    $page.PageSheet.CellsU("PageHeight").FormulaU = "18.5 in"
    $page.PageSheet.CellsU("PrintPageOrientation").FormulaU = "2"
    $page.PageSheet.CellsU("DrawingScale").FormulaU = "1 in"
    $page.PageSheet.CellsU("PageScale").FormulaU = "1 in"

    $blue = "RGB(0,109,255)"
    $green = "RGB(23,139,50)"
    $orange = "RGB(255,122,0)"
    $purple = "RGB(134,80,230)"
    $red = "RGB(240,24,24)"
    $black = "RGB(34,34,34)"
    $fillBlue = "RGB(243,248,255)"
    $fillGreen = "RGB(243,251,245)"
    $fillOrange = "RGB(255,247,236)"
    $fillPurple = "RGB(247,242,255)"
    $fillRed = "RGB(255,242,242)"
    $fillWhite = "RGB(255,255,255)"

    Log-Step "Drawing title and initialization flow"
    Add-Text $page 5.85 18.15 5.0 0.35 "FPGA 主控制流程图" $black 18 $true | Out-Null

    Add-Box $page $processMaster 5.85 17.6 3.6 0.45 "FPGA 上电/复位" $black $fillWhite 10 $true | Out-Null
    Add-Line $page @(5.85,17.38,5.85,17.12) | Out-Null
    Add-Box $page $processMaster 5.85 16.85 4.35 0.85 "时钟与复位管理`n系统时钟、JESD 时钟、以太网时钟`n与各模块复位释放" $blue $fillBlue 8.5 $true | Out-Null
    Add-Line $page @(5.85,16.43,5.85,16.16) | Out-Null

    Add-DashedRegion $page 5.55 15.0 5.65 3.45 $blue | Out-Null
    Add-Text $page 2.9 15.0 0.35 1.35 "外设初始化流程" $blue 9 $true | Out-Null
    Add-Box $page $processMaster 5.55 16.0 3.65 0.38 "HMC7044 时钟芯片初始化" $blue $fillBlue 9 $true | Out-Null
    Add-Line $page @(5.55,15.81,5.55,15.55) | Out-Null
    Add-Box $page $processMaster 5.55 15.35 3.65 0.38 "AD9173 DAC 初始化" $blue $fillBlue 9 $true | Out-Null
    Add-Line $page @(5.55,15.16,5.55,14.9) | Out-Null
    Add-Box $page $processMaster 5.55 14.7 3.65 0.38 "JESD204C TX 链路初始化" $blue $fillBlue 9 $true | Out-Null
    Add-Line $page @(5.55,14.51,5.55,14.25) | Out-Null
    Add-Box $page $processMaster 5.55 14.05 3.65 0.38 "链路状态检测" $blue $fillBlue 9 $true | Out-Null
    Add-Line $page @(5.55,13.86,5.55,13.58) | Out-Null
    Add-Diamond $page $decisionMaster 5.55 13.28 2.55 0.8 "初始化成功？" $blue $fillBlue 9 | Out-Null
    Add-Box $page $processMaster 9.55 13.35 2.0 0.6 "初始化失败`n保持等待或重试" $blue $fillBlue 8.5 $true | Out-Null
    Add-Line $page @(6.82,13.28,8.55,13.28) | Out-Null
    Add-Text $page 7.18 13.42 0.25 0.2 "否" $black 8 $true | Out-Null
    Add-Line $page @(9.55,13.65,9.55,16.05,7.38,16.05) | Out-Null
    Add-Line $page @(5.55,12.88,5.55,12.55) | Out-Null
    Add-Text $page 5.75 12.76 0.25 0.2 "是" $black 8 $true | Out-Null
    Add-Box $page $processMaster 5.85 12.32 4.15 0.6 "等待配置与运行控制`n系统就绪态" $blue $fillBlue 8.7 $true | Out-Null

    Log-Step "Drawing UDP and MicroBlaze branches"
    Add-Line $page @(5.85,12.02,5.85,11.65,3.15,11.65,3.15,11.35) | Out-Null
    Add-Line $page @(5.85,11.65,9.2,11.65,9.2,11.35) | Out-Null

    Add-DashedRegion $page 3.25 8.8 6.2 5.1 $green | Out-Null
    Add-Text $page 3.25 11.12 2.2 0.25 "UDP 配置接收路径" $green 10 $true | Out-Null
    Add-Box $page $processMaster 3.25 10.65 2.7 0.52 "RGMII 接收以太网`nUDP 数据包" $green $fillGreen 8.5 $true | Out-Null
    Add-Line $page @(3.25,10.39,3.25,10.15) | Out-Null
    Add-Box $page $processMaster 3.25 9.95 2.2 0.38 "解析 K5WG 协议帧" $green $fillGreen 8.7 $true | Out-Null
    Add-Line $page @(3.25,9.76,3.25,9.52) | Out-Null
    Add-Diamond $page $decisionMaster 3.25 9.25 2.0 0.62 "判断帧类型" $green $fillGreen 8.7 | Out-Null

    Add-Line $page @(3.25,8.94,3.25,8.68,1.35,8.68,1.35,8.42) | Out-Null
    Add-Line $page @(3.25,8.94,3.25,8.42) | Out-Null
    Add-Line $page @(3.25,8.68,5.35,8.68,5.35,8.42) | Out-Null
    Add-Text $page 1.35 8.55 1.0 0.2 "CONFIG 帧" $green 8 $true | Out-Null
    Add-Text $page 3.25 8.55 0.9 0.2 "DATA 帧" $green 8 $true | Out-Null
    Add-Text $page 5.35 8.55 1.0 0.2 "COMMIT 帧" $green 8 $true | Out-Null
    Add-Box $page $processMaster 1.35 8.18 2.1 0.42 "解析 K5DC 配置数据" $green $fillGreen 8 $true | Out-Null
    Add-Line $page @(1.35,7.97,1.35,7.72) | Out-Null
    Add-Box $page $processMaster 1.35 7.15 2.1 1.15 "更新系统参数：`n• DDS FTW`n• 幅度 scale`n• 通道使能`n• 输出路径`n• 继电器衰减 / 工作模式" $green $fillGreen 7.7 $false | Out-Null

    Add-Box $page $processMaster 3.25 8.18 1.65 0.42 "根据 sample offset" $green $fillGreen 8 $true | Out-Null
    Add-Line $page @(3.25,7.97,3.25,7.72) | Out-Null
    Add-Box $page $processMaster 3.25 7.45 1.65 0.55 "将波形数据写入`nwaveform RAM" $green $fillGreen 8 $true | Out-Null
    Add-Line $page @(3.25,7.18,3.25,6.95) | Out-Null
    Add-Box $page $processMaster 3.25 6.7 1.65 0.5 "更新写入指针与`n状态信息" $green $fillGreen 8 $true | Out-Null

    Add-Box $page $processMaster 5.35 8.12 1.75 0.62 "确认波形数据`n写入完成" $green $fillGreen 8 $true | Out-Null
    Add-Line $page @(5.35,7.81,5.35,7.55) | Out-Null
    Add-Box $page $processMaster 5.35 7.25 1.75 0.62 "切换到`nRAM 波形播放状态" $green $fillGreen 8 $true | Out-Null

    Add-DashedRegion $page 9.05 8.78 4.0 4.85 $orange | Out-Null
    Add-Text $page 9.05 11.12 2.65 0.25 "MicroBlaze 慢速控制路径" $orange 10 $true | Out-Null
    Add-Box $page $processMaster 9.05 10.58 3.1 0.35 "MicroBlaze 控制寄存器访问" $orange $fillOrange 8.5 $true | Out-Null
    Add-Line $page @(9.05,10.4,9.05,10.02) | Out-Null
    Add-Box $page $processMaster 9.05 9.35 3.1 1.15 "写入默认/运行参数：`n• DDS 默认参数（FTW、相位等）`n• 幅度 / scale`n• RF 开关`n• 数字衰减器 / DAC profile" $orange $fillOrange 7.8 $false | Out-Null
    Add-Line $page @(9.05,8.78,9.05,8.42) | Out-Null
    Add-Box $page $processMaster 9.05 8.0 3.1 0.78 "触发操作：`n• 参数更新   • 相位复位等" $orange $fillOrange 8 $true | Out-Null
    Add-Line $page @(9.05,7.61,9.05,7.25) | Out-Null
    Add-Box $page $processMaster 9.05 7.08 3.1 0.34 "参数同步到相关模块" $orange $fillOrange 8 $true | Out-Null

    Log-Step "Drawing mode selection and waveform generation"
    Add-Line $page @(1.35,6.58,1.35,5.98,4.55,5.98) $true $true | Out-Null
    Add-Line $page @(3.25,6.45,3.25,5.98) $false $true | Out-Null
    Add-Line $page @(5.35,6.94,5.35,5.98) $false $true | Out-Null
    Add-Line $page @(9.05,6.91,9.05,5.98,7.15,5.98) | Out-Null
    Add-Diamond $page $decisionMaster 5.85 5.98 2.65 1.02 "输出模式选择`n当前工作模式" $purple $fillPurple 8.7 | Out-Null

    Add-Line $page @(5.85,5.47,5.85,5.15,3.7,5.15,3.7,4.95) | Out-Null
    Add-Line $page @(5.85,5.47,5.85,4.95) | Out-Null
    Add-Line $page @(5.85,5.15,8.0,5.15,8.0,4.95) | Out-Null
    Add-Box $page $processMaster 3.7 4.45 2.05 0.95 "DDS 单音模式`nDDS 相位累加器`n正弦查表生成" $purple $fillPurple 8.2 $true | Out-Null
    Add-Box $page $processMaster 5.85 4.45 2.05 0.95 "RAM 任意波形`n模式`n从 waveform RAM`n循环读取采样数据" $purple $fillPurple 8.0 $true | Out-Null
    Add-Box $page $processMaster 8.0 4.45 2.2 0.95 "片内 NCO / 调试`n模式`n运行时控制参数`n更新 AD9173 相关配置" $purple $fillPurple 8.0 $true | Out-Null
    Add-Line $page @(3.7,3.98,3.7,3.72,5.85,3.72) $false | Out-Null
    Add-Line $page @(5.85,3.98,5.85,3.72) $false | Out-Null
    Add-Line $page @(8.0,3.98,8.0,3.72,5.85,3.72) $false | Out-Null
    Add-Line $page @(5.85,3.72,5.85,3.55) | Out-Null
    Add-Box $page $processMaster 5.85 3.28 4.2 0.55 "通道映射 / 幅度控制 / 同步处理`n增益、相位、时延校正、通道映射等" $purple $fillPurple 8.5 $true | Out-Null
    Add-Line $page @(5.85,3.0,5.85,2.7) | Out-Null
    Add-Box $page $processMaster 5.85 2.4 4.8 0.6 "JESD204C TX 发送链路`n8B/10B 编码、Scrambling、Lane 对齐等" $red $fillRed 8.5 $true | Out-Null
    Add-Line $page @(8.25,2.4,9.45,2.4) | Out-Null
    Add-Diamond $page $decisionMaster 10.05 2.4 1.3 0.75 "链路就绪？" $red $fillWhite 8 | Out-Null
    Add-Line $page @(10.7,2.4,11.25,2.4,11.25,12.0,7.9,12.0) | Out-Null
    Add-Text $page 10.95 2.55 0.25 0.2 "否" $black 8 $true | Out-Null
    Add-Line $page @(10.05,2.03,10.05,1.75,5.85,1.75,5.85,1.55) | Out-Null
    Add-Text $page 10.28 1.9 0.25 0.2 "是" $black 8 $true | Out-Null
    Add-Box $page $processMaster 5.85 1.32 4.2 0.42 "输出到 AD9173 DAC" $red $fillRed 9.5 $true | Out-Null

    Add-Box $page $processMaster 5.85 0.45 11.15 0.35 "初始化流程    UDP 数据路径    MicroBlaze 控制路径    DDS/RAM 波形生成    JESD 输出路径    → 流程方向" $black $fillWhite 7.5 $false | Out-Null

    Log-Step "Saving VSDX"
    if (Test-Path $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
    $doc.SaveAs($OutPath)
    if (!$NoPreview -and $PngPath) {
        Log-Step "Exporting PNG preview"
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
