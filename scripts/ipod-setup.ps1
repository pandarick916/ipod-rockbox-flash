<#
.SYNOPSIS
    iPod Classic 一把梭部署工具 —— 自动识别设备、合并安装 Rockbox、引导手动装 bootloader

.DESCRIPTION
    这个脚本解决四件最容易出错的事：
      1. 分清哪个盘符才是数据盘（G: 是 192MB 固件分区，H: 才是 74GB 数据盘）
      2. 把 Rockbox 系统文件正确合并到 .rockbox 目录
      3. 把主题一并装上，并检测它是否支持中文
      4. 调用命令行工具 mks5lboot64.exe 自动刷写引导程序（不用碰 Rockbox Utility）

    整个过程你只需要做两件事：双击脚本、按住两个键 12 秒。

.PARAMETER SourceMusic
    可选。拷歌源目录。指定后会把这个目录下的所有音频文件复制到 iPod 的 Music 文件夹。

.PARAMETER FirmwareZip
    可选。Rockbox 固件 zip 路径。不指定会自动查找。

.PARAMETER ThemeZip
    可选。主题 zip 路径。不指定会自动查找，找到多个会让你选。

.PARAMETER DryRun
    只做检查和预演，不写入任何文件。建议第一次先跑这个。

.EXAMPLE
    .\ipod-setup.ps1 -DryRun
    预演模式：看看脚本会往哪个盘、写什么东西，但不动手。

.EXAMPLE
    .\ipod-setup.ps1
    正式部署。

.EXAMPLE
    .\ipod-setup.ps1 -SourceMusic "D:\我的音乐"
    部署完成后顺便把音乐拷进去。
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceMusic = "",
    [string]$FirmwareZip = "",
    [string]$ThemeZip    = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============ 输出样式 ============
function Say-Step($n, $text) {
    Write-Host ""
    Write-Host "  [$n] $text" -ForegroundColor Cyan
}
function Say-Ok($text)   { Write-Host "      [OK] $text"   -ForegroundColor Green }
function Say-Warn($text) { Write-Host "      [!]  $text"   -ForegroundColor Yellow }
function Say-Err($text)  { Write-Host "      [X]  $text"   -ForegroundColor Red }
function Say-Info($text) { Write-Host "           $text"   -ForegroundColor DarkGray }
function Say-Key($text)  { Write-Host "           $text"   -ForegroundColor White }

function Stop-Here($msg) {
    Write-Host ""
    Write-Host "  ==================================================" -ForegroundColor Red
    Write-Host "   已停止：$msg" -ForegroundColor Red
    Write-Host "  ==================================================" -ForegroundColor Red
    Write-Host ""
    Read-Host "  按回车退出"
    exit 1
}

# ============ 横幅 ============
Clear-Host
Write-Host ""
Write-Host "  ========================================================" -ForegroundColor DarkCyan
Write-Host "     iPod Classic 一把梭部署工具" -ForegroundColor White
Write-Host "     自动识别设备 / 合并安装系统 / 引导装引导程序" -ForegroundColor DarkGray
Write-Host "  ========================================================" -ForegroundColor DarkCyan

if ($DryRun) {
    Write-Host ""
    Write-Host "     >>> 预演模式：只看不写 <<<" -ForegroundColor Yellow
}

# ============ 1. 环境检查 ============
Say-Step "1/5" "检查运行环境"

$psv = $PSVersionTable.PSVersion
if ($psv.Major -lt 5) { Stop-Here "PowerShell 版本太老（$psv），需要 5.1 或更高" }
Say-Ok "PowerShell $psv"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Say-Ok "以管理员身份运行" } else { Say-Info "普通权限运行（够用，不需要管理员）" }

# ============ 2. 定位文件 ============
Say-Step "2/5" "查找需要的文件"

# 判断一个 zip 是不是真正的 Rockbox 包：里面必须含 .rockbox 目录
function Test-ZipHasRockbox($zipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $hit = $z.Entries | Where-Object { $_.FullName -like '.rockbox/*' } | Select-Object -First 1
            return [bool]$hit
        } finally { $z.Dispose() }
    } catch { return $false }
}

function Find-FileUpward($pattern, $startDir) {
    $dir = $startDir
    for ($i = 0; $i -lt 4; $i++) {
        if (-not $dir) { break }
        # 每一层都先看目录本身，再看它的 files 子目录
        # （下载的东西通常堆在 第三期_iPod刷机\files 里）
        foreach ($probe in @($dir, (Join-Path $dir 'files'), (Join-Path $dir 'assets'))) {
            if (-not (Test-Path $probe)) { continue }
            $hits = Get-ChildItem -Path $probe -Filter $pattern -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '*manual*' -and $_.Name -notlike '*Press_Kit*' -and $_.Name -notlike '*Utility*' } |
                    Sort-Object LastWriteTime -Descending
            foreach ($h in $hits) {
                if (Test-ZipHasRockbox $h.FullName) { return $h.FullName }
            }
        }
        $dir = Split-Path -Parent $dir
    }
    return $null
}

# 固件
if (-not $FirmwareZip) {
    $FirmwareZip = Find-FileUpward "rockbox-ipod6g*.zip" $Script:Root
}
if (-not $FirmwareZip -or -not (Test-Path $FirmwareZip)) {
    Stop-Here "找不到 Rockbox 固件 zip（rockbox-ipod6g*.zip）。请把它放在工具目录或上一级目录。"
}
Say-Ok "固件：$(Split-Path -Leaf $FirmwareZip)"
Say-Info "完整路径 $FirmwareZip"

# 主题（可选）
if (-not $ThemeZip) {
    $candidates = @()
    $up1 = Split-Path -Parent $Script:Root
    $searchDirs = @($Script:Root, $up1,
                    (Join-Path $Script:Root 'files'),
                    (Join-Path $up1 'files'),
                    (Join-Path $Script:Root 'assets'),
                    (Join-Path $up1 'assets'))
    foreach ($d in $searchDirs) {
        if (-not $d -or -not (Test-Path $d)) { continue }
        $candidates += Get-ChildItem -Path $d -Filter "*.zip" -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notlike "rockbox-ipod6g*" -and
                $_.Name -notlike "*Press_Kit*" -and
                $_.Name -notlike "*manual*" -and
                $_.Name -notlike "*Utility*" -and
                (Test-ZipHasRockbox $_.FullName)
            }
    }
    $candidates = $candidates | Sort-Object Name -Unique

    if ($candidates.Count -eq 1) {
        $ThemeZip = $candidates[0].FullName
    } elseif ($candidates.Count -gt 1) {
        Write-Host ""
        Say-Info "找到多个可能的主题包，请选择（回车跳过主题）："
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Say-Key ("  {0}. {1}" -f ($i + 1), $candidates[$i].Name)
        }
        $pick = Read-Host "  输入编号"
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $candidates.Count) {
            $ThemeZip = $candidates[[int]$pick - 1].FullName
        }
    }
}

if ($ThemeZip -and (Test-Path $ThemeZip)) {
    Say-Ok "主题：$(Split-Path -Leaf $ThemeZip)"
} else {
    $ThemeZip = $null
    Say-Info "没指定主题，只装系统（主题以后随时能加）"
}

# ============ 3. 识别 iPod ============
Say-Step "3/5" "查找连接的 iPod"

Say-Info "扫描可移动磁盘..."
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue)

if ($drives.Count -eq 0) {
    Stop-Here "没有检测到任何可移动磁盘。请确认：数据线插好、iPod 已开机、优先用机箱后置 USB 2.0 口。"
}

$targets  = @()
$rejected = @()

foreach ($d in $drives) {
    $letter  = $d.DeviceID
    $root    = "$letter\"
    $sizeGB  = if ($d.Size) { [math]::Round($d.Size / 1GB, 1) } else { 0 }
    $fs      = $d.FileSystem
    $label   = $d.VolumeName

    $hasIpodControl = Test-Path (Join-Path $root "iPod_Control") -ErrorAction SilentlyContinue
    $hasRockbox     = Test-Path (Join-Path $root ".rockbox")     -ErrorAction SilentlyContinue

    Write-Host ""
    Say-Key "$letter  $label   ${sizeGB}GB   $fs"
    if ($hasIpodControl) { Say-Info "  发现 iPod_Control 目录 → 这是苹果原系统的数据分区" }
    if ($hasRockbox)     { Say-Info "  发现 .rockbox 目录 → 已经装过 Rockbox" }

    # 判定规则
    $isIpod = $hasIpodControl -or $hasRockbox
    $isFat  = $fs -in @('FAT32','FAT','FAT16')
    $bigEnough = $sizeGB -ge 10
    $isFirmwarePartition = $sizeGB -lt 1

    if ($isFirmwarePartition) {
        $rejected += "$letter (${sizeGB}GB) —— 这是固件分区，跳过"
        Say-Warn "跳过：容量太小，是苹果固件分区，不是数据盘"
        continue
    }
    if ($isIpod -and $isFat -and $bigEnough) {
        $targets += [pscustomobject]@{
            Letter = $letter
            Root   = $root
            SizeGB = $sizeGB
            Label  = $label
            HasRB  = $hasRockbox
        }
        Say-Ok "认定为 iPod 数据分区"
    } else {
        $rejected += "$letter (${sizeGB}GB) —— 不像 iPod 数据分区"
        Say-Warn "跳过：不像 iPod 数据分区（需要 FAT32 且大于 10GB）"
    }
}

if ($targets.Count -eq 0) {
    Write-Host ""
    Say-Err "没找到符合条件的 iPod 数据分区。"
    Say-Info "常见原因："
    Say-Info "  · iPod 还没进到 Rockbox 系统的 USB 模式"
    Say-Info "  · 数据线不支持传输（只能用充电线不行）"
    Say-Info "  · 插在 USB 3.0 口上，换机箱后置 USB 2.0 试试"
    Stop-Here "未找到目标设备"
}

if ($targets.Count -gt 1) {
    Write-Host ""
    Say-Warn "找到多个候选设备，请选择："
    for ($i = 0; $i -lt $targets.Count; $i++) {
        Say-Key ("  {0}. {1}  {2}  {3}GB" -f ($i+1), $targets[$i].Letter, $targets[$i].Label, $targets[$i].SizeGB)
    }
    $pick = Read-Host "  输入编号"
    if ($pick -notmatch '^\d+$') { Stop-Here "输入无效" }
    $target = $targets[[int]$pick - 1]
} else {
    $target = $targets[0]
}

# ============ 4. 确认 ============
Say-Step "4/5" "确认部署内容"

Write-Host ""
Say-Key "  目标设备    $($target.Letter)  $($target.Label)"
Say-Key "  可用容量    $($target.SizeGB) GB"
Write-Host ""
Say-Key "  将要写入    $($target.Root).rockbox\  （与现有内容合并，不删除）"
if ($ThemeZip) { Say-Key "  同时安装    $(Split-Path -Leaf $ThemeZip)" }
Write-Host ""
if ($target.HasRB) {
    Say-Warn "这个设备已经有 .rockbox 目录，系统文件会被覆盖更新"
}

Say-Info "不会碰的东西：你的歌、苹果原厂系统、那个 192MB 固件分区"

if ($DryRun) {
    Write-Host ""
    Write-Host "  --------------------------------------------------" -ForegroundColor Yellow
    Write-Host "   预演结束。没有写入任何文件。" -ForegroundColor Yellow
    Write-Host "   确认无误后，去掉 -DryRun 再跑一次就是真装。" -ForegroundColor Yellow
    Write-Host "  --------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  按回车退出"
    exit 0
}

Write-Host ""
Write-Host "  3 秒后自动开始部署，要取消请按 Ctrl+C" -ForegroundColor Yellow
for ($i = 3; $i -ge 1; $i--) {
    Write-Host "    $i ..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
}
Write-Host ""
Say-Ok "开始"

# ============ 5. 部署 ============
Say-Step "5/5" "部署文件"

function Expand-ZipTo($zipPath, $destRoot) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $total = $zip.Entries.Count
        $done  = 0
        foreach ($entry in $zip.Entries) {
            $done++
            $rel  = $entry.FullName -replace '/', '\'
            $dest = Join-Path $destRoot $rel

            if ($entry.Name -eq '') {
                if (-not (Test-Path $dest)) {
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                }
            } else {
                $parent = Split-Path -Parent $dest
                if (-not (Test-Path $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
            }

            if ($total -gt 0) {
                $pct = [int](($done / $total) * 100)
                Write-Progress -Activity "解压 $(Split-Path -Leaf $zipPath)" `
                               -Status "$done / $total" -PercentComplete $pct
            }
        }
    } finally {
        $zip.Dispose()
        Write-Progress -Activity "解压" -Completed
    }
}

try {
    Write-Host ""
    Say-Info "解压系统文件到 $($target.Root).rockbox ..."
    Expand-ZipTo $FirmwareZip $target.Root
    Say-Ok "系统文件完成"

    if ($ThemeZip) {
        Write-Host ""
        Say-Info "解压主题到 $($target.Root).rockbox ..."
        Expand-ZipTo $ThemeZip $target.Root
        Say-Ok "主题完成"
    }

    # ============================================================
    # 中文化：找字体 → 换主题字形 → 写配置
    #
    # 为什么不能只改 config.cfg 里的 font:
    #   cfg 的 font: 只管「菜单/文件浏览器」这一层。
    #   主题播放屏的字体是在 .wps / .sbs 里用 %Fl(id,xxx.fnt) 写死的。
    #   只改 cfg，播放屏的中文歌名照样是方块。
    #
    # 为什么不改 .wps 里的字体名：
    #   sbs 里有 %ss(0,2,%St(font)) 判断字体名头两位是不是 22/24，
    #   改了名会切到另一套排版分支。所以：保留文件名，只换文件内容。
    #
    # 为什么中文只有 16px：
    #   Rockbox 官方字体包里的中文字体最大就是 16px
    #   （16-WenQangYi-Unibit / 16-GNU-Unifont），没有 22px。
    #   League Spartan 22px 的位置换成 16px 中文字形，字会矮 6px，
    #   但主题所有坐标不变、不会错位、不会截断。
    # ============================================================
    Write-Host ""
    Say-Info "处理中文显示..."
    $rbDir    = Join-Path $target.Root ".rockbox"
    $fontDir  = Join-Path $rbDir "fonts"
    $themeDir = Join-Path $rbDir "themes"

    # ---- 1. 找一个带中文字形的字体（优先大字号） ----
    # 分级依据：文件名里带 CJK 的最可靠（作者明确标注过的）；
    # 其次是思源黑体；再其次是 Unifont / 文泉驿 / Sazanami / 明朝这类已知含中文的点阵字体。
    # 同一级里按字号从大到小——中文字号越大，越接近主题原本的设计。
    # 绝不按"文件体积最大"来猜：主题自带的 22-LeagueSpartan-Bold 有 2.8MB，
    # 比多数中文字体还大，认错了会把整个主题换成英文。
    $cjFont = $null
    $cjPx   = 0
    if (Test-Path $fontDir) {
        $ranked = @()
        foreach ($f in @(Get-ChildItem -Path $fontDir -Filter '*.fnt' -File -ErrorAction SilentlyContinue)) {
            $px   = 0
            if ($f.Name -match '^(\d+)') { $px = [int]$Matches[1] }
            $tier = 99
            if     ($f.Name -match 'CJK')    { $tier = 1 }
            elseif ($f.Name -match 'SourceHan') { $tier = 2 }
            elseif ($f.Name -match 'Unifont|WenQangYi|WenQuanYi|Sazanami|Mincho|Song') { $tier = 3 }
            if ($tier -eq 99) { continue }
            $ranked += [pscustomobject]@{ Path = $f.FullName; Tier = $tier; Px = $px }
        }
        $ranked = @($ranked | Sort-Object Tier, @{Expression={$_.Px}; Descending=$true})
        if ($ranked.Count -gt 0) {
            $cjFont = $ranked[0].Path
            $cjPx   = $ranked[0].Px
        }
    }

    if (-not $cjFont) {
        Say-Warn "没找到任何带中文字形的字体"
        Say-Info "原因：Rockbox 基础固件包里只带 2 个英文字体，中文字体在单独的字体包里"
        Say-Info "补法（二选一）："
        Say-Info "  · 用 Rockbox Utility 勾上 Fonts 再装一次（它自动下字体包）"
        Say-Info "  · 或把 fonts.zip 解压进 设备\.rockbox\fonts\"
        Say-Info "补完之后重跑一次脚本，会自动完成中文化"
    } else {
        $leaf = Split-Path $cjFont -Leaf
        $kb   = [math]::Round((Get-Item -LiteralPath $cjFont).Length / 1KB)
        Say-Ok "中文字体：$leaf  (${kb} KB, ${cjPx}px)"
        if ($cjPx -ge 18) {
            Say-Info "这台机器有 ${cjPx}px 中文，主题原本 22px，字号损失很小"
        } elseif ($cjPx -ge 16) {
            Say-Info "目前最大 ${cjPx}px 中文，歌名会比主题原设计小一圈"
        } else {
            Say-Warn "目前最大只有 ${cjPx}px 中文，歌名会明显变小"
        }
    }

    # ---- 2. 定位这次装的主题 ----
    $themeCfg = $null
    if ($ThemeZip -and (Test-Path $themeDir)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $ThemeZip))
        $guess = Join-Path $themeDir "$stem.cfg"
        if (Test-Path $guess) {
            $themeCfg = $guess
        } else {
            $allCfg = @(Get-ChildItem -Path $themeDir -Filter '*.cfg' -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notin @('rockbox_default_icons.cfg','rockbox_failsafe.cfg') })
            if ($allCfg.Count -eq 1) { $themeCfg = $allCfg[0].FullName }
        }
    }

    # ---- 3. 把这个主题引用的英文字体，就地换成中文字形 ----
    $swapped = 0
    if ($themeCfg -and $cjFont) {
        $themeLabel = Split-Path $themeCfg -Leaf
        Say-Info "主题 $themeLabel 用的是纯英文字体，正在换字形（文件名不动，只换内容）"

        $refs = New-Object System.Collections.Generic.List[string]

        # 3a. cfg 里的 font:（全局 UI 字体）
        foreach ($l in @(Get-Content -LiteralPath $themeCfg -ErrorAction SilentlyContinue)) {
            if ($l -match '^\s*font\s*:\s*(.+)$') {
                $n = Split-Path $Matches[1].Trim() -Leaf
                if ($n -and -not $refs.Contains($n)) { $refs.Add($n) }
            }
        }

        # 3b. wps / sbs 里的 %Fl(编号, 字体文件名)
        foreach ($l in @(Get-Content -LiteralPath $themeCfg -ErrorAction SilentlyContinue)) {
            if ($l -notmatch '^\s*(wps|sbs)\s*:\s*(.+)$') { continue }
            $rel  = $Matches[2].Trim() -replace '^/\.rockbox/', '' -replace '/', '\'
            $skin = Join-Path $rbDir $rel
            if (-not (Test-Path $skin)) { continue }
            $txt = Get-Content -LiteralPath $skin -Raw -ErrorAction SilentlyContinue
            if (-not $txt) { continue }
            foreach ($m in [regex]::Matches($txt, '%Fl\(\s*\d+\s*,\s*([^,\)]+)\s*[,\)]')) {
                $n = $m.Groups[1].Value.Trim()
                if ($n -notlike '*.fnt') { continue }      # 排除 .fnticons 图标字体
                if (-not $refs.Contains($n)) { $refs.Add($n) }
            }
        }

        if ($refs.Count -eq 0) {
            Say-Info "这个主题没有引用外部字体（或字体已内置），不需要处理"
        }

        $srcName = Split-Path $cjFont -Leaf
        foreach ($n in $refs) {
            if ($n -match '\.fnticons$') { continue }
            $dst = Join-Path $fontDir $n
            if ($n -eq $srcName) { Say-Ok "$n —— 本身就是中文字体"; continue }
            if (-not (Test-Path $dst)) {
                Say-Info "$n —— 设备上没有这个文件，跳过"
                continue
            }
            $bak = "$dst.orig-en"
            if (-not (Test-Path $bak)) {
                Copy-Item -LiteralPath $dst -Destination $bak -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -LiteralPath $cjFont -Destination $dst -Force
            $swapped++
            Say-Ok "$n  →  换成中文字形"
        }

        if ($swapped -gt 0) {
            Write-Host ""
            Say-Info "原英文字体已备份为 同名.orig-en，想恢复英文就把 .orig-en 去掉再覆盖回去"
            Say-Info "代价说明：中文字体没有 22px 那么大，歌名会比原设计矮约 6px"
            Say-Info "         但坐标、图标、进度条、封面位置全部不变，不会错位"
        }
    } elseif ($themeCfg -and -not $cjFont) {
        Say-Warn "有主题但没中文字体，主题保持英文原样（中文会是方块）"
    }

    # ---- 4. 写 config.cfg：开机直接进这个主题 + 中文 ----
    if (Test-Path $rbDir) {
        $cfgPath = Join-Path $rbDir "config.cfg"

        # 先记下现有的 codepage。中文歌的 ID3 标签靠它解码，
        # 这台机器上已经是可用的值，沿用比自己猜一个安全。
        $codepageLine = $null
        if (Test-Path $cfgPath) {
            $cpHit = @(Get-Content -LiteralPath $cfgPath -ErrorAction SilentlyContinue) |
                     Where-Object { $_ -match '^\s*default codepage\s*:' } |
                     Select-Object -First 1
            if ($cpHit) { $codepageLine = $cpHit.Trim() }
        }

        if (Test-Path $cfgPath) {
            Copy-Item $cfgPath "$cfgPath.bak" -Force -ErrorAction SilentlyContinue
            Say-Info "原有设置已备份为 config.cfg.bak"
        }

        # 有主题 → 以主题的 cfg 为底稿（这样开机就是主题本身，不用再去设置里点一遍）
        $base = @()
        if ($themeCfg) { $base = @(Get-Content -LiteralPath $themeCfg -ErrorAction SilentlyContinue) }

        # 干掉旧的语言/代码页行，其余（含 font: 和所有主题设置）原样保留
        $kept = @($base | Where-Object { $_ -notmatch '^\s*(lang|default codepage)\s*:' })

        $out = New-Object System.Collections.Generic.List[string]
        $out.Add('# generated by one-click installer')
        $out.Add('lang: /.rockbox/langs/chinese-simp.lng')
        if ((-not $themeCfg) -and $cjFont) {
            $out.Add("font: /.rockbox/fonts/$(Split-Path $cjFont -Leaf)")
        }
        # 注意：config.cfg 要按 ASCII 写出，注释行只能用英文，
        # 否则中文会被 -Encoding ASCII 写成问号。
        if ($codepageLine) {
            $out.Add($codepageLine)
            Say-Info "沿用现有代码页设置：$codepageLine"
        } else {
            $out.Add('# Uncomment the next line if old MP3 tags show garbled text')
            $out.Add('# default codepage: GB2312')
        }
        foreach ($l in $kept) { $out.Add($l) }

        try {
            $out | Out-File -FilePath $cfgPath -Encoding ASCII -Force
            if ($themeCfg) {
                Say-Ok "配置写入完成：开机即是 $(Split-Path $themeCfg -Leaf) + 中文界面"
            } else {
                Say-Ok "配置写入完成：开机即是中文界面"
            }
        } catch {
            Say-Warn "配置写入失败（不影响刷机，开机后手动设一下语言和字体）"
        }
    }


    # 可选：拷歌
    if ($SourceMusic) {
        Write-Host ""
        if (-not (Test-Path $SourceMusic)) {
            Say-Warn "拷歌目录不存在，跳过：$SourceMusic"
        } else {
            $musicDir = Join-Path $target.Root "Music"
            if (-not (Test-Path $musicDir)) { New-Item -ItemType Directory -Path $musicDir -Force | Out-Null }
            Say-Info "开始拷歌：$SourceMusic  →  $musicDir"
            Say-Warn "这一步可能很久（几 GB 要几十分钟），中途别拔线"
            $exts = @('*.flac','*.mp3','*.m4a','*.aac','*.ogg','*.opus','*.wav','*.aiff','*.alac','*.wma','*.ape','*.wv','*.mpc','*.tta')
            $files = @()
            foreach ($e in $exts) {
                $files += Get-ChildItem -Path $SourceMusic -Filter $e -File -Recurse -ErrorAction SilentlyContinue
            }
            if ($files.Count -eq 0) {
                Say-Warn "源目录里没找到音频文件"
            } else {
                $n = 0
                foreach ($f in $files) {
                    $n++
                    Copy-Item $f.FullName -Destination $musicDir -Force -ErrorAction SilentlyContinue
                    if ($n % 20 -eq 0 -or $n -eq $files.Count) {
                        $pct = [int](($n / $files.Count) * 100)
                        Write-Progress -Activity "拷歌" -Status "$n / $($files.Count)" -PercentComplete $pct
                    }
                }
                Write-Progress -Activity "拷歌" -Completed
                Say-Ok "拷完 $($files.Count) 个文件"
                Say-Info "注意：都放在 Music 根目录，没有保留原来的文件夹结构"
            }
        }
    }

} catch {
    Write-Host ""
    Say-Err "部署过程中出错：$($_.Exception.Message)"
    Say-Info "已写入的文件不会造成损坏，重新跑一次即可覆盖。"
    Stop-Here "部署失败"
}

# ============ 收尾：装引导程序 ============
Say-Step "收尾" "安装引导程序"

$killList = @('iPodService', 'iTunesHelper', 'AppleMobileDeviceService')
$killed = 0
foreach ($procName in $killList) {
    $p = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($p) {
        $p | Stop-Process -Force -ErrorAction SilentlyContinue
        $killed++
        Say-Ok "已关闭 $procName"
    }
}
if ($killed -eq 0) { Say-Info "没有需要关闭的 iTunes 进程" }

$binDir   = Join-Path $Script:Root "bin"
$mkExe    = Join-Path $binDir "mks5lboot64.exe"
$blFile   = Join-Path $binDir "bootloader-ipod6g.ipod"
$cliReady = (Test-Path $mkExe) -and (Test-Path $blFile)

# ---- 预检引导文件：型号标识 + ROM 载荷尺寸 ----
# 依据 mks5lboot 源码 mkdfu.c：
#   1) load_file() 校验文件第 5-8 字节的型号标识，必须是 "ip6g"，否则 abort
#   2) ROM 载荷上限 = 128KiB - IM3INFO_SZ(0x50) - CERT_SIZE(700) = 130292 字节
if ($cliReady) {
    try {
        $blBytes = [System.IO.File]::ReadAllBytes($blFile)
        $blLen   = $blBytes.Length
        $blTag   = -join ($blBytes[4..7] | ForEach-Object { [char]$_ })
        $romLimit = 128 * 1024 - 0x50 - 700

        if ($blTag -ne 'ip6g') {
            Say-Err "引导文件型号不对：读到 '$blTag'，应为 'ip6g'"
            Say-Info "这不是 6 代的引导文件，强行写入会被工具拒绝。已切到手动路径。"
            $cliReady = $false
        } elseif ($blLen -gt $romLimit) {
            Say-Err "引导文件过大：$blLen 字节，ROM 上限 $romLimit 字节"
            Say-Info "超出部分写不进 NOR，设备会拒绝。已切到手动路径。"
            $cliReady = $false
        } else {
            Say-Ok "引导文件校验通过：型号 ip6g / $blLen 字节 / 余量 $($romLimit - $blLen) 字节"
        }
    } catch {
        Say-Warn "读不了引导文件，切到手动路径"
        $cliReady = $false
    }
}

function Show-ManualBootloaderGuide {
    Write-Host ""
    Write-Host "  --------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "   手动装引导程序（3 个动作）" -ForegroundColor Yellow
    Write-Host "  --------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   1. Rockbox Utility 里：只勾 Bootloader，点 Install" -ForegroundColor White
    Write-Host "   2. 日志提示按键时：按住 MENU + 中间圆键，按到屏幕全黑" -ForegroundColor White
    Write-Host "      继续按住，等日志说松手再松" -ForegroundColor White
    Write-Host "   3. 拔线，按住 SELECT+MENU 5-8 秒重启" -ForegroundColor White
    Write-Host ""
    Say-Info "日志报 'Could not remount the device' 是正常的："
    Say-Info "只要出现过 'DFU transfer completed'，就已经写进去了。"
    Write-Host ""
}

# ---- 检测设备是否已经装好并正常工作（避免把新版引导降级成旧版）----
$existingCfg  = Join-Path $target.Root ".rockbox\config.cfg"
$existingFw   = Join-Path $target.Root ".rockbox\rockbox.ipod"
$alreadyWorks = $false

if ((Test-Path $existingFw) -and (Test-Path $existingCfg)) {
    try {
        if ((Get-Item -LiteralPath $existingCfg).Length -gt 20) { $alreadyWorks = $true }
    } catch { }
}

if ($alreadyWorks) {
    Write-Host ""
    Write-Host "  ========================================================" -ForegroundColor Yellow
    Write-Host "   这台机器已经装好了" -ForegroundColor Yellow
    Write-Host "  ========================================================" -ForegroundColor Yellow
    Write-Host ""
    Say-Ok "检测到系统文件和配置文件都在，说明引导程序正常工作"
    Write-Host ""
    Say-Info "bin 里的引导文件是官方当前版本（2017-03-22 发布，至今未更新）"
    Say-Info "你机器上装的应该就是同一个文件。除非换了硬盘或引导坏了，不需要重装"
    Write-Host ""
    $ans = Read-Host "  真要覆盖引导程序吗？输入 YES 才继续，直接回车跳过"
    if ($ans -ne 'YES') {
        Write-Host ""
        Say-Ok "已跳过引导安装，你的机器保持原样"
        Write-Host ""
        Say-Info "想用最新引导的话：浏览器打开下面这个地址，等页面验证过再点下载"
        Say-Info "  https://download.rockbox.org/bootloader/ipod/"
        Say-Info "下好之后替换 工具/bin/bootloader-ipod6g.ipod，脚本会自动校验型号和尺寸"
        Write-Host ""
        Read-Host "  按回车退出"
        exit 0
    }
    Write-Host ""
    Say-Warn "已确认覆盖，继续"
}

if (-not $cliReady) {
    Write-Host ""
    Say-Warn "没找到命令行刷写工具（bin 目录里的 mks5lboot64.exe / bootloader-ipod6g.ipod）"
    Say-Info "走手动路径"

    $rbuExe = $null
    foreach ($r in @($Script:Root, (Split-Path -Parent $Script:Root))) {
        if (-not $r) { continue }
        $hit = Get-ChildItem -Path $r -Filter "RockboxUtility.exe" -File -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $rbuExe = $hit.FullName; break }
    }
    if ($rbuExe) {
        $go = Read-Host "  现在帮你打开 Rockbox Utility？（Y 打开，其它键跳过）"
        if ($go -match '^[Yy]$') {
            try { Start-Process -FilePath $rbuExe; Say-Ok "已启动" }
            catch { Say-Warn "启动失败，请手动双击：$rbuExe" }
        }
    }
    Show-ManualBootloaderGuide
    Read-Host "  按回车退出"
    exit 0
}

# ---- 走命令行全自动路径 ----
Say-Ok "找到命令行工具，可以自动刷引导"
Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Cyan
Write-Host "   接下来只做一件事：按住两个键" -ForegroundColor White
Write-Host "  ========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "   按住  MENU 键 + 中间圆键" -ForegroundColor Yellow
Write-Host "   数到 12 秒，屏幕会彻底黑掉（这是正常的）" -ForegroundColor Yellow
Write-Host "   黑屏后继续按住 2 秒再松手" -ForegroundColor Yellow
Write-Host ""
Say-Info "脚本会在倒计时结束后自动开始扫描，最多等 60 秒"
Write-Host ""
Write-Host "   现在把手指放在 MENU 键和中间圆键上，准备按" -ForegroundColor Yellow
Write-Host ""
for ($c = 5; $c -ge 1; $c--) {
    Write-Host ("    {0} ..." -f $c) -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host "   开始！按住那两个键，数到 12" -ForegroundColor Green
Write-Host ""
Say-Info "正在等待设备进入 DFU 模式..."

$found = $false
$waitLoops = 75
for ($i = 1; $i -le $waitLoops; $i++) {
    & $mkExe --dfuscan *> $null
    if ($LASTEXITCODE -eq 0) { $found = $true; break }
    if ($i % 5 -eq 0) {
        Write-Host ("    等待中... {0}/{1}" -f $i, $waitLoops) -ForegroundColor DarkGray
    }
    Start-Sleep -Milliseconds 800
}

if (-not $found) {
    Write-Host ""
    Say-Err "60 秒内没检测到设备进入 DFU 模式"
    Write-Host ""
    Say-Info "常见的三个原因："
    Say-Info "  1. 按的时间不够（要按住 12 秒，不是 5 秒）"
    Say-Info "  2. 按的顺序不对（先按住 MENU，再按圆键）"
    Say-Info "  3. 数据线只能充电，不能传数据"
    Write-Host ""
    Say-Info "可以重新跑一次脚本，也可以用 Rockbox Utility 手动装"
    Show-ManualBootloaderGuide
    Read-Host "  按回车退出"
    exit 1
}

Say-Ok "检测到设备！开始写入引导程序..."
Write-Host ""
Say-Info "这一过程约 5–10 秒，别拔线"

& $mkExe --bl-inst $blFile

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  ========================================================" -ForegroundColor Green
    Write-Host "   引导程序安装成功" -ForegroundColor Green
    Write-Host "  ========================================================" -ForegroundColor Green
    Write-Host ""
    Say-Info "设备会自己重启并响一声（两种音调）"
    Write-Host ""
    Write-Host "   最后两个动作：" -ForegroundColor White
    Write-Host "   ① 拔掉数据线" -ForegroundColor White
    Write-Host "   ② 如果没自动重启，按住 SELECT+MENU 5–8 秒" -ForegroundColor White
    Write-Host ""
    Say-Info "屏幕出现 Rockbox 画面 = 成功"
} else {
    Write-Host ""
    Say-Err "写入失败（退出码 $LASTEXITCODE）"
    Write-Host ""
    Say-Info "可能的提示音含义："
    Say-Info "  单声低音 330Hz = 写入失败，可以重试"
    Say-Info "  三声低音 = 引导区需要 iTunes 恢复（概率很低）"
    Write-Host ""
    Say-Info "可以重新跑脚本再试一次，或者用 Rockbox Utility 手动装"
    Show-ManualBootloaderGuide
}

Write-Host ""
Read-Host "  按回车退出"
