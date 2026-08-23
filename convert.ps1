<#
  HWP / HWPX → PDF 일괄 변환기 (명령줄판)
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
  ------------------------------------------------------------------
  화면으로 쓰시려면 hwptopdf.vbs 를 실행하세요. 이 파일은 자동화·배치용입니다.
  변환 로직은 core.ps1 에 있습니다.

  사용법
    convert.ps1 "폴더경로"
    convert.ps1 "폴더경로" -Force              이미 있는 PDF도 다시 만들기
    convert.ps1 "폴더경로" -OutDir "다른폴더"   PDF를 지정한 곳에 모으기
    convert.ps1 "폴더경로" -NoVerify           페이지 수 대조 생략 (조금 빠름)

  종료 코드: 0 정상 / 1 대상 없음 / 2 한글 없음 / 3 실패 있음

  주의: 아래 매개변수 선언에서 $Targets 에 Position = 0 을 반드시 유지할 것.
        빼면 넘긴 경로가 -OutDir 로 잘못 바인딩된다.

  주의: 반드시 UTF-8 (BOM 포함) 으로 저장할 것.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Targets,

    [Parameter()][switch]$Force,
    [Parameter()][string]$OutDir,
    [Parameter()][switch]$NoVerify,
    # PDF를 원본과 같은 폴더에 만든다 (하위 폴더를 만들지 않음)
    [Parameter()][switch]$SameFolder
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'core.ps1')

function Say { param([string]$T, [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

if (-not $Targets -or $Targets.Count -eq 0) {
    Say "변환할 폴더를 지정하세요.  예)  convert.ps1 `"D:\문서폴더`"" 'Yellow'
    Say "화면으로 쓰시려면 hwptopdf.vbs 를 실행하세요." 'DarkGray'
    exit 1
}

if (-not [Type]::GetTypeFromProgID('HWPFrame.HwpObject')) {
    Say "한글(한컴오피스)이 설치되어 있지 않습니다." 'Red'
    exit 2
}

$r = Get-HwpJobs -Targets $Targets -OutDir $OutDir -SameFolder:$SameFolder
$jobs = @($r.Jobs)
foreach ($s in $r.Skipped) { Say "제외 — $s" 'Yellow' }

if ($jobs.Count -eq 0) {
    Say "변환할 HWP/HWPX 파일이 없습니다." 'Yellow'
    exit 1
}

Say ""
Say ("─" * 60) 'DarkGray'
Say " HWP → PDF 변환   대상 $($jobs.Count)개" 'Cyan'
Say ("─" * 60) 'DarkGray'

$session = New-HwpSession
if (-not $session.Secured) {
    Say " (보안 승인 모듈 미등록 — 한글 팝업이 뜰 수 있습니다. 설치.bat 실행)" 'DarkGray'
}

$ok = 0; $skip = 0; $warn = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
$n = 0

foreach ($j in $jobs) {
    $n++
    $prefix = "[{0}/{1}]" -f $n, $jobs.Count
    Write-Host "$prefix $($j.Name) ... " -NoNewline

    $res = Convert-OneHwp -Session $session -Job $j -Force:$Force -Verify:(-not $NoVerify)

    switch ($res.Status) {
        'ok'   {
            $ok++
            $kb = [math]::Round($res.Size / 1KB)
            if ($res.SrcPages -gt 0) { Say "완료 ($($res.SrcPages)쪽, ${kb}KB)" 'Green' }
            else { Say "완료 (${kb}KB)" 'Green' }
            $lines.Add("OK    $($j.Src)")
        }
        'skip' { $skip++; Say "건너뜀" 'DarkGray'; $lines.Add("SKIP  $($j.Src)") }
        'warn' {
            $warn++
            Say "확인 필요 — $($res.Message)" 'Yellow'
            Say "           $($j.Src)" 'DarkGray'
            # 나중에 어느 파일인지 찾을 수 있도록 전체 경로를 남긴다
            $lines.Add("WARN  $($j.Src)")
            $lines.Add("        $($res.Message)")
        }
        default {
            $fail++
            Say "실패 — $($res.Message)" 'Red'
            Say "       $($j.Src)" 'DarkGray'
            $lines.Add("FAIL  $($j.Src)")
            $lines.Add("        $($res.Message)")

            # 한글이 죽으면(RPC_E_SERVERFAULT 등) 뒤 파일이 모두 연쇄로 실패한다.
            if (-not (Test-HwpSessionAlive $session)) {
                Say "       한글 연결이 끊겨 다시 연결합니다..." 'Yellow'
                Close-HwpSession $session
                $session = $null
                try {
                    $session = New-HwpSession
                    $lines.Add("        (한글 연결이 끊겨 재연결함)")
                } catch {
                    Say "       다시 연결하지 못했습니다. 중단합니다." 'Red'
                    $lines.Add("        (한글 재연결 실패 — 중단)")
                    break
                }
            }
        }
    }
}

Close-HwpSession $session

$outRoot = $r.OutRoot
$logPath = Write-ConvertLog -OutRoot $outRoot -Targets $Targets -Lines $lines.ToArray() -Ok $ok -Skip $skip -Warn $warn -Fail $fail

Say ("─" * 60) 'DarkGray'
Say (" 완료 {0}   건너뜀 {1}   확인필요 {2}   실패 {3}" -f $ok, $skip, $warn, $fail) 'Cyan'
if ($warn -gt 0) {
    Say ""
    Say " '확인필요'는 원본과 PDF의 쪽수가 다른 경우입니다." 'Yellow'
    Say " 한글에서 해당 문서의 [파일]-[인쇄] 범위를 '문서 전체'로 바꾼 뒤" 'Yellow'
    Say " -Force 로 다시 변환하세요." 'Yellow'
}
if ($logPath) { Say ""; Say " 기록: $logPath" 'DarkGray' }
Say ""

if ($fail -gt 0) { exit 3 }
exit 0
