<#
  HWP → PDF 변환 공통 로직
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
  ------------------------------------------------------------------
  gui.ps1(화면)과 convert.ps1(명령줄)이 이 파일을 함께 씁니다.
  이 파일만 단독으로 실행하면 아무 일도 하지 않습니다.

  주의: 반드시 UTF-8 (BOM 포함) 으로 저장할 것.
#>

# 경로 문자열 정리 — Explorer의 "경로로 복사"는 따옴표를 붙여준다.
function Clean-PathText {
    param([string]$Text)
    if (-not $Text) { return "" }
    $t = $Text.Trim().Trim('"').Trim("'").Trim()
    # 끝의 역슬래시는 떼되, 드라이브 루트("C:\")는 그대로 둔다
    if ($t.Length -gt 3 -and $t.EndsWith('\')) { $t = $t.TrimEnd('\') }
    return $t
}

# PDF의 실제 페이지 수를 센다.
# 한글이 만드는 PDF는 페이지 정보가 FlateDecode 스트림 안에 압축돼 있으므로
# 스트림을 풀어서 /Type /Page 를 센다. (압축 때문에 raw 검색으로는 0이 나온다)
function Get-PdfPageCount {
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $enc = [System.Text.Encoding]::GetEncoding(28591)   # Latin1: 바이트 1:1 보존
        $txt = $enc.GetString($bytes)
        $sb = New-Object System.Text.StringBuilder

        $idx = 0
        while ($true) {
            $s = $txt.IndexOf('stream', $idx)
            if ($s -lt 0) { break }
            $from = $s + 6
            if ($from -lt $txt.Length -and $txt[$from] -eq "`r") { $from++ }
            if ($from -lt $txt.Length -and $txt[$from] -eq "`n") { $from++ }
            $e = $txt.IndexOf('endstream', $from)
            if ($e -lt 0) { break }
            $len = $e - $from
            $idx = $e + 9
            if ($len -le 2) { continue }
            try {
                # zlib 헤더 2바이트를 건너뛰고 raw deflate 로 푼다
                $ms = New-Object System.IO.MemoryStream(, $bytes[($from + 2)..($from + $len - 1)])
                $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $out = New-Object System.IO.MemoryStream
                $ds.CopyTo($out)
                $ds.Dispose(); $ms.Dispose()
                [void]$sb.Append($enc.GetString($out.ToArray()))
                $out.Dispose()
            } catch { }   # 이미지 등 다른 필터 스트림은 실패해도 무시
        }
        return ([regex]::Matches($sb.ToString(), '/Type\s*/Page(?![s])')).Count
    } catch {
        return -1
    }
}

# 출력 폴더 이름 규칙 — 각 폴더 안에 "<그 폴더 이름>_변환PDF" 를 만든다.
#
# 왜 이렇게 하는가:
#   상위 폴더를 지정하든 하위 폴더를 지정하든 결과가 항상 같은 자리에 생긴다.
#   (상위에서 한 번, 하위에서 한 번 돌려도 같은 PDF가 두 군데 생기지 않는다)
#   예)  2026년 당회보고\2026년 당회보고_변환PDF\
#        2026년 당회보고\회의록\회의록_변환PDF\
function Get-PdfFolderSuffix { return '_변환PDF' }

function Get-PdfFolderFor {
    param([string]$Dir)
    $leaf = Split-Path $Dir -Leaf
    if (-not $leaf) { $leaf = ($Dir -replace '[\\/:]', '') }   # 드라이브 루트 등
    if (-not $leaf) { $leaf = 'PDF' }
    return Join-Path $Dir ($leaf + (Get-PdfFolderSuffix))
}

# 이미 출력 폴더 안에 있는 파일인지 — 재실행 시 결과물을 다시 훑지 않도록.
function Test-IsInPdfFolder {
    param([string]$Path)
    $suffix = Get-PdfFolderSuffix
    foreach ($seg in ($Path -split '\\')) {
        if ($seg -and $seg.EndsWith($suffix)) { return $true }
    }
    return $false
}

# 대상(폴더/파일)을 (원본, 출력PDF) 쌍의 목록으로 펼친다.
function Get-HwpJobs {
    param(
        [string[]]$Targets,
        [string]$OutDir,
        # 켜면 PDF를 원본과 같은 폴더에 바로 만든다(하위 폴더를 만들지 않음)
        [switch]$SameFolder
    )
    $jobs = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[string]
    $outRoot = $null   # 기록 파일을 두고 [결과 폴더 열기]가 여는 대표 폴더

    foreach ($t in $Targets) {
        $t = Clean-PathText $t
        if (-not $t) { continue }
        if (-not (Test-Path -LiteralPath $t)) { $skipped.Add("찾을 수 없음: $t"); continue }

        $item = Get-Item -LiteralPath $t

        if ($item.PSIsContainer) {
            if (-not $outRoot) {
                $outRoot = if ($OutDir) { $OutDir }
                           elseif ($SameFolder) { $item.FullName }
                           else { Get-PdfFolderFor $item.FullName }
            }

            $files = Get-ChildItem -LiteralPath $item.FullName -File -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in '.hwp', '.hwpx' } |
                     Where-Object { -not (Test-IsInPdfFolder $_.FullName) } |
                     Sort-Object FullName

            foreach ($f in $files) {
                $rel = $f.DirectoryName.Substring($item.FullName.Length).TrimStart('\')
                if ($OutDir) {
                    # -OutDir 로 한곳에 모을 때는 이름 충돌을 막기 위해 하위 구조를 유지한다
                    $dir = if ($rel) { Join-Path $OutDir $rel } else { $OutDir }
                } elseif ($SameFolder) {
                    # 원본이 있는 폴더에 그대로 만든다
                    $dir = $f.DirectoryName
                } else {
                    # 기본: 각 파일이 있는 폴더 안에 "<그 폴더 이름>_변환PDF" 를 만든다
                    $dir = Get-PdfFolderFor $f.DirectoryName
                }
                $jobs.Add([PSCustomObject]@{
                    Src    = $f.FullName
                    Pdf    = Join-Path $dir ($f.BaseName + '.pdf')
                    Name   = $f.Name
                    Folder = if ($rel) { $rel } else { '.' }
                })
            }
        }
        elseif ($item.Extension -in '.hwp', '.hwpx') {
            $dir = if ($OutDir) { $OutDir }
                   elseif ($SameFolder) { $item.DirectoryName }
                   else { Get-PdfFolderFor $item.DirectoryName }
            if (-not $outRoot) { $outRoot = $dir }
            $jobs.Add([PSCustomObject]@{
                Src    = $item.FullName
                Pdf    = Join-Path $dir ($item.BaseName + '.pdf')
                Name   = $item.Name
                Folder = '.'
            })
        }
        else {
            $skipped.Add("HWP/HWPX 아님: $($item.Name)")
        }
    }

    # 주의: 반드시 배열(.ToArray())로 돌려줄 것.
    # 이 환경의 Windows PowerShell 5.1은 제네릭 List에 @()를 씌우면
    # "Argument types do not match" 예외를 낸다. 호출부에서 @($r.Jobs)를
    # 쓰다가 터졌던 실제 사례가 있다.
    return [PSCustomObject]@{ Jobs = $jobs.ToArray(); Skipped = $skipped.ToArray(); OutRoot = $outRoot }
}

# 쓸 수 있는 PDF 프린터 이름을 찾는다.
#
# 쪽수가 안 맞을 때 가상 인쇄로 다시 뽑기 위해 필요하다. 한컴 PDF 프린터가
# 있으면 그것을, 없으면 Windows 기본 제공 프린터를 쓴다.
function Get-PdfPrinterName {
    $names = @()
    try { $names = @(Get-Printer -ErrorAction Stop | Select-Object -ExpandProperty Name) }
    catch {
        try { $names = @(Get-CimInstance Win32_Printer -ErrorAction Stop | Select-Object -ExpandProperty Name) } catch { }
    }
    foreach ($want in 'Hancom PDF', 'Microsoft Print to PDF') {
        if ($names -contains $want) { return $want }
    }
    return $null
}

# 한글 세션 열기 — COM 연결 + 보안 모듈 등록 + 창 숨기기
function New-HwpSession {
    $hwp = New-Object -ComObject HWPFrame.HwpObject
    # 보안 승인 팝업 억제 (설치.bat 으로 모듈을 등록해 두어야 실제로 동작)
    $secured = $false
    try { $secured = [bool]$hwp.RegisterModule("FilePathCheckDLL", "FilePathCheckerModuleExample") } catch { }
    # 파일마다 한글 창이 깜빡이지 않도록 숨긴다
    try { $hwp.XHwpWindows.Item(0).Visible = $false } catch { }
    # 모아 찍기 문서를 다시 뽑을 때 쓸 PDF 프린터
    return [PSCustomObject]@{ Hwp = $hwp; Secured = $secured; PdfPrinter = (Get-PdfPrinterName) }
}

function Close-HwpSession {
    param($Session)
    if (-not $Session) { return }
    try { $Session.Hwp.Quit() } catch { }
    try { [Runtime.InteropServices.Marshal]::ReleaseComObject($Session.Hwp) | Out-Null } catch { }
}

# 한글 COM 연결이 아직 살아 있는지 확인한다.
#
# 특정 문서에서 한글이 죽으면(RPC_E_SERVERFAULT 0x80010105 등) 그 뒤의 파일이
# 전부 연쇄로 실패한다. 실패가 났을 때 이걸로 확인해서, 죽었으면 세션을 새로
# 열고 남은 파일을 계속 처리한다.
function Test-HwpSessionAlive {
    param($Session)
    if (-not $Session) { return $false }
    try { $null = $Session.Hwp.Version; return $true } catch { return $false }
}

# 가상 인쇄로 PDF 만들기 (열려 있는 문서 대상).
#
# SaveAs 와 달리 인쇄 파라미터를 직접 넘기므로, 문서에 저장된 모아 찍기
# 설정을 무시하고 한 장에 한 쪽씩 뽑을 수 있다.
function Invoke-PrintToPdf {
    param($Hwp, [string]$Pdf, [string]$PrinterName)
    try {
        if (Test-Path -LiteralPath $Pdf) { Remove-Item -LiteralPath $Pdf -Force -ErrorAction SilentlyContinue }
        $act = $Hwp.CreateAction("PrintToPDFEx")
        $ps = $Hwp.HParameterSet.HPrint
        $null = $act.GetDefault($ps.HSet)
        $ps.PrinterName = $PrinterName
        $ps.PrintMethod = 0        # 모아 찍기 해제
        $ps.PrintToFile = 1
        $ps.filename = $Pdf
        $ok = $act.Execute($ps.HSet)
        if (-not $ok) { return $false }
        # 인쇄가 파일로 떨어질 때까지 잠깐 기다린다
        for ($i = 0; $i -lt 40; $i++) {
            if ((Test-Path -LiteralPath $Pdf) -and (Get-Item -LiteralPath $Pdf).Length -gt 0) { return $true }
            Start-Sleep -Milliseconds 250
        }
        return (Test-Path -LiteralPath $Pdf)
    } catch { return $false }
}

# 원본과 PDF의 쪽수가 다를 때, 왜 그런지 짚어 준다.
#
# 가장 흔한 원인은 '모아 찍기'다. 문서에 2쪽·4쪽 모아 찍기가 켜져 있으면
# 8쪽짜리가 4쪽·2쪽 PDF로 나온다. 내용이 빠진 게 아니라 한 장에 여러 쪽을
# 앉힌 것이므로, 잘림(일부만 저장)과 구분해서 알려 줘야 한다.
function Get-MismatchReason {
    param([int]$SrcPages, [int]$PdfPages, [int]$Layout = 0)

    if ($PdfPages -le 0 -or $SrcPages -le 0) {
        return "원본 ${SrcPages}쪽 / PDF ${PdfPages}쪽"
    }

    # 한글의 모아 찍기 선택지. 작은 값부터 검사해야 과하게 추정하지 않는다.
    foreach ($n in 2, 3, 4, 6, 8, 9, 16) {
        if ($PdfPages -eq [math]::Ceiling($SrcPages / $n)) {
            return "모아찍기 ${n}쪽 추정 (원본 ${SrcPages}쪽 → PDF ${PdfPages}쪽). 내용 누락은 아닙니다"
        }
    }

    if ($PdfPages -lt $SrcPages) {
        $tail = if ($Layout -ne 0) { " (문서의 모아찍기 설정 PageLayout=$Layout)" } else { "" }
        return "원본 ${SrcPages}쪽 / PDF ${PdfPages}쪽 — 일부만 저장됐을 수 있습니다$tail"
    }

    return "원본 ${SrcPages}쪽 / PDF ${PdfPages}쪽 — PDF 쪽수가 더 많습니다"
}

# 파일 하나 변환.
# 반환: Status = skip | ok | warn | fail
function Convert-OneHwp {
    param(
        $Session,
        $Job,
        [switch]$Force,
        [switch]$Verify
    )

    $r = [PSCustomObject]@{
        Status = 'fail'; SrcPages = 0; PdfPages = 0; Size = 0; Message = ''; Layout = 0; Fixed = $false
    }

    if ((-not $Force) -and (Test-Path -LiteralPath $Job.Pdf)) {
        $r.Status = 'skip'
        $r.Message = '이미 PDF가 있음'
        return $r
    }

    $dir = Split-Path $Job.Pdf -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $hwp = $Session.Hwp
    try {
        # -Force 로 다시 만들 때 한글이 덮어쓰기 확인창을 띄우고 멈추는 것을 막는다.
        # 지우는 대상은 출력 PDF이며, 원본 HWP는 절대 건드리지 않는다.
        if ($Force -and (Test-Path -LiteralPath $Job.Pdf)) {
            try { Remove-Item -LiteralPath $Job.Pdf -Force } catch { }
        }

        if (-not $hwp.Open($Job.Src, "", "forceopen:true")) { throw "파일을 열지 못했습니다" }

        # 문서가 열려 있는 동안 원본 페이지 수를 읽어둔다 (검증용)
        if ($Verify) {
            try { $r.SrcPages = [int]$hwp.PageCount } catch { $r.SrcPages = 0 }
            # 문서에 저장된 '인쇄 방식'(PrintMethod)을 같이 읽어둔다.
            # 0이 아니면 모아 찍기가 켜져 있다는 뜻이고, 그러면 SaveAs 로 뽑은
            # PDF의 쪽수가 원본보다 적게 나온다. (실측: PrintMethod=4 인 2쪽
            # 문서가 1쪽 PDF로 나왔고, 두 문서의 인쇄 설정 중 다른 값은 이것뿐이었다)
            try {
                $act = $hwp.CreateAction("Print")
                $pset = $hwp.HParameterSet.HPrint
                $null = $act.GetDefault($pset.HSet)
                $r.Layout = [int]$pset.PrintMethod
            } catch { $r.Layout = 0 }
        }

        $saved = $hwp.SaveAs($Job.Pdf, "PDF", "")

        if (-not $saved -or -not (Test-Path -LiteralPath $Job.Pdf)) {
            try { $null = $hwp.Run("FileClose") } catch { }
            throw "PDF가 생성되지 않았습니다"
        }

        $r.Size = (Get-Item -LiteralPath $Job.Pdf).Length
        if ($r.Size -eq 0) {
            try { $null = $hwp.Run("FileClose") } catch { }
            throw "PDF가 0바이트입니다"
        }

        # 쪽수 대조. 안 맞으면 가상 인쇄로 한 번 더 시도한다.
        if ($Verify -and $r.SrcPages -gt 0) {
            $r.PdfPages = Get-PdfPageCount $Job.Pdf

            if ($r.PdfPages -gt 0 -and $r.PdfPages -ne $r.SrcPages -and $Session.PdfPrinter) {
                # SaveAs 는 문서에 저장된 모아 찍기 설정을 그대로 물려받는다.
                # PrintToPDFEx 는 우리가 파라미터를 직접 넘기므로 PrintMethod=0 으로
                # 강제해 한 장에 한 쪽씩 뽑을 수 있다. (문서는 아직 열려 있다)
                $retry = Invoke-PrintToPdf -Hwp $hwp -Pdf $Job.Pdf -PrinterName $Session.PdfPrinter
                if ($retry) {
                    $again = Get-PdfPageCount $Job.Pdf
                    if ($again -eq $r.SrcPages) {
                        $r.PdfPages = $again
                        $r.Size = (Get-Item -LiteralPath $Job.Pdf).Length
                        $r.Fixed = $true
                    } else {
                        $r.PdfPages = $again
                    }
                }
            }

            if ($r.PdfPages -gt 0 -and $r.PdfPages -ne $r.SrcPages) {
                try { $null = $hwp.Run("FileClose") } catch { }
                $r.Status = 'warn'
                $r.Message = Get-MismatchReason -SrcPages $r.SrcPages -PdfPages $r.PdfPages -Layout $r.Layout
                return $r
            }
        }

        try { $null = $hwp.Run("FileClose") } catch { }
        $r.Status = 'ok'
        if ($r.Fixed) { $r.Message = "모아찍기가 켜져 있어 가상 인쇄로 다시 뽑았습니다" }
        return $r
    }
    catch {
        try { $null = $hwp.Run("FileClose") } catch { }
        $r.Status = 'fail'
        $r.Message = $_.Exception.Message
        return $r
    }
}

# ─────────────────────────────────────────────── 설정 저장
#
# 프로그램 폴더(Program Files 등)는 쓰기 권한이 없을 수 있으므로
# 사용자별 폴더에 둔다.
function Get-SettingsPath {
    $dir = Join-Path $env:APPDATA 'hwptopdf'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Join-Path $dir 'settings.json')
}

function Get-AppSettings {
    $defaults = @{ SameFolder = $false }
    try {
        $p = Get-SettingsPath
        if (Test-Path -LiteralPath $p) {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($defaults.Keys)) {
                if ($null -ne $j.$k) { $defaults[$k] = [bool]$j.$k }
            }
        }
    } catch { }
    return $defaults
}

function Save-AppSettings {
    param([hashtable]$Settings)
    try {
        ($Settings | ConvertTo-Json) | Out-File -LiteralPath (Get-SettingsPath) -Encoding utf8
    } catch { }
}

# 변환 기록 파일 저장. 저장한 경로를 반환한다.
function Write-ConvertLog {
    param(
        [string]$OutRoot,
        [string[]]$Targets,
        [string[]]$Lines,
        [int]$Ok, [int]$Skip, [int]$Warn, [int]$Fail
    )
    try {
        if (-not $OutRoot) { return $null }
        # 대표 폴더에 변환된 파일이 없어도(하위 폴더에만 있는 경우) 기록은 남긴다
        if (-not (Test-Path -LiteralPath $OutRoot)) {
            New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
        }
        $path = Join-Path $OutRoot ("변환로그_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")
        $header = @(
            "HWP → PDF 변환 기록",
            "일시 : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            "대상 : " + ($Targets -join ', '),
            "결과 : 완료 $Ok / 건너뜀 $Skip / 확인필요 $Warn / 실패 $Fail",
            ("-" * 60)
        )
        ($header + $Lines) | Out-File -LiteralPath $path -Encoding utf8
        return $path
    } catch { return $null }
}
