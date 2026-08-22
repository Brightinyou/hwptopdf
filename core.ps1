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
        [string]$OutDir
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
                $outRoot = if ($OutDir) { $OutDir } else { Get-PdfFolderFor $item.FullName }
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
            $dir = if ($OutDir) { $OutDir } else { Get-PdfFolderFor $item.DirectoryName }
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

# 한글 세션 열기 — COM 연결 + 보안 모듈 등록 + 창 숨기기
function New-HwpSession {
    $hwp = New-Object -ComObject HWPFrame.HwpObject
    # 보안 승인 팝업 억제 (설치.bat 으로 모듈을 등록해 두어야 실제로 동작)
    $secured = $false
    try { $secured = [bool]$hwp.RegisterModule("FilePathCheckDLL", "FilePathCheckerModuleExample") } catch { }
    # 파일마다 한글 창이 깜빡이지 않도록 숨긴다
    try { $hwp.XHwpWindows.Item(0).Visible = $false } catch { }
    return [PSCustomObject]@{ Hwp = $hwp; Secured = $secured }
}

function Close-HwpSession {
    param($Session)
    if (-not $Session) { return }
    try { $Session.Hwp.Quit() } catch { }
    try { [Runtime.InteropServices.Marshal]::ReleaseComObject($Session.Hwp) | Out-Null } catch { }
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
        Status = 'fail'; SrcPages = 0; PdfPages = 0; Size = 0; Message = ''
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
        if ($Verify) { try { $r.SrcPages = [int]$hwp.PageCount } catch { $r.SrcPages = 0 } }

        $saved = $hwp.SaveAs($Job.Pdf, "PDF", "")
        try { $null = $hwp.Run("FileClose") } catch { }

        if (-not $saved -or -not (Test-Path -LiteralPath $Job.Pdf)) { throw "PDF가 생성되지 않았습니다" }

        $r.Size = (Get-Item -LiteralPath $Job.Pdf).Length
        if ($r.Size -eq 0) { throw "PDF가 0바이트입니다" }

        # 페이지 수 대조 — 한글에 남은 인쇄 범위 설정 때문에 일부만 저장되는 경우를 잡는다
        if ($Verify -and $r.SrcPages -gt 0) {
            $r.PdfPages = Get-PdfPageCount $Job.Pdf
            if ($r.PdfPages -gt 0 -and $r.PdfPages -ne $r.SrcPages) {
                $r.Status = 'warn'
                $r.Message = "원본 $($r.SrcPages)쪽 / PDF $($r.PdfPages)쪽"
                return $r
            }
        }

        $r.Status = 'ok'
        return $r
    }
    catch {
        try { $null = $hwp.Run("FileClose") } catch { }
        $r.Status = 'fail'
        $r.Message = $_.Exception.Message
        return $r
    }
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
