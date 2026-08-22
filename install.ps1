<#
  한글 자동화 보안 승인 모듈 설치기
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
  (이 스크립트가 내려받는 한컴 보안 모듈은 이 라이선스의 적용 대상이
   아닙니다. THIRD-PARTY-LICENSES.md 참조)
  ------------------------------------------------------------------
  한글 자동화는 파일에 접근할 때마다 보안 승인 팝업을 띄웁니다.
  한컴이 공식 배포하는 보안 승인 모듈을 등록하면 그 팝업이 사라집니다.

  이 스크립트가 하는 일
    1. 한글(한컴오피스) 설치 여부 확인
    2. 한컴 공식 배포처에서 보안모듈(Automation).zip 내려받기
    3. 내려받은 DLL의 SHA256 지문을 대조 (위변조 확인)
    4. %USERPROFILE%\Tools\HancomAutomation\ 에 설치
    5. HKCU 레지스트리에 등록 (관리자 권한 불필요)
    6. 실제로 로드되는지 검증

  되돌리기:  설치.ps1 -Uninstall

  주의: 이 파일은 반드시 UTF-8 (BOM 포함) 으로 저장해야 합니다.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# 한컴 공식 배포처 (developer.hancom.com/hwpautomation 에서 링크하는 한컴 공식 GitHub)
$ZipUrl = 'https://github.com/hancom-io/devcenter-archive/raw/main/hwp-automation/%EB%B3%B4%EC%95%88%EB%AA%A8%EB%93%88(Automation).zip'

# 2026-08-22 기준 정품 DLL의 지문. 내려받은 파일이 이것과 다르면 설치를 중단한다.
$ExpectedSha256 = '9AC5B97C47AC8AED1E8BCA27A3EEF39411361D8F68C262509F0C40A8F9D21BB6'

$DllName   = 'FilePathCheckerModuleExample.dll'
$ModuleKey = 'FilePathCheckerModuleExample'
$InstallDir = Join-Path $env:USERPROFILE 'Tools\HancomAutomation'
$DllPath    = Join-Path $InstallDir $DllName
$RegKeys    = @(
    'HKCU:\Software\HNC\HwpAutomation\Modules',
    'HKCU:\Software\HNC\HwpCtrl\Modules'
)

function Say { param([string]$T, [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

Say ""
Say "───────────────────────────────────────────────" 'DarkGray'
Say " 한글 자동화 보안 승인 모듈 설치" 'Cyan'
Say "───────────────────────────────────────────────" 'DarkGray'

# ── 되돌리기 ─────────────────────────────────────
if ($Uninstall) {
    foreach ($k in $RegKeys) {
        if (Test-Path $k) {
            try {
                Remove-ItemProperty -Path $k -Name $ModuleKey -ErrorAction Stop
                Say " 레지스트리 삭제: $k" 'Green'
            } catch { Say " 레지스트리에 등록되어 있지 않음: $k" 'DarkGray' }
        }
    }
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
        Say " 폴더 삭제: $InstallDir" 'Green'
    }
    Say ""
    Say " 되돌리기 완료. 이제 보안 승인 팝업이 다시 나타납니다." 'Cyan'
    Say ""
    exit 0
}

# ── 1. 한글 설치 확인 ────────────────────────────
if (-not [Type]::GetTypeFromProgID('HWPFrame.HwpObject')) {
    Say ""
    Say " 한글(한컴오피스)이 설치되어 있지 않습니다." 'Red'
    Say " 이 모듈은 한글이 있어야 의미가 있습니다. 한글을 먼저 설치하세요." 'Red'
    Say ""
    exit 2
}
Say " [1/5] 한글 설치 확인 — OK" 'Green'

# ── 2. 이미 설치돼 있는지 확인 ───────────────────
$already = $false
if (Test-Path $DllPath) {
    $h = (Get-FileHash $DllPath -Algorithm SHA256).Hash
    $regOk = $true
    foreach ($k in $RegKeys) {
        $v = (Get-ItemProperty -Path $k -Name $ModuleKey -ErrorAction SilentlyContinue).$ModuleKey
        if ($v -ne $DllPath) { $regOk = $false }
    }
    if ($h -eq $ExpectedSha256 -and $regOk) { $already = $true }
}

if ($already) {
    Say " [2/5] 이미 설치되어 있습니다 — 내려받기를 건너뜁니다." 'DarkGray'
} else {
    # ── 내려받기 ─────────────────────────────────
    Say " [2/5] 한컴 공식 배포처에서 내려받는 중..." 'Gray'
    $tmp = Join-Path $env:TEMP ("hancom_secmod_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'secmod.zip'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
    } catch {
        Say ""
        Say " 내려받기에 실패했습니다: $($_.Exception.Message)" 'Red'
        Say " 인터넷 연결을 확인하거나, 아래 주소에서 직접 받아" 'Red'
        Say " $DllName 을 $InstallDir 에 두고 이 스크립트를 다시 실행하세요." 'Red'
        Say " $ZipUrl" 'DarkGray'
        Say ""
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        exit 3
    }

    # ── 3. 압축 해제 + 지문 대조 ─────────────────
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ext = Join-Path $tmp 'x'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $ext)

    $found = Get-ChildItem $ext -Recurse -File -Filter $DllName | Select-Object -First 1
    if (-not $found) {
        Say " 내려받은 압축 파일 안에 $DllName 이 없습니다. 설치를 중단합니다." 'Red'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        exit 4
    }

    $sha = (Get-FileHash $found.FullName -Algorithm SHA256).Hash
    if ($sha -ne $ExpectedSha256) {
        Say ""
        Say " 파일 지문이 예상과 다릅니다. 안전을 위해 설치를 중단합니다." 'Red'
        Say "   예상: $ExpectedSha256" 'DarkGray'
        Say "   실제: $sha" 'DarkGray'
        Say " 한컴이 파일을 갱신했을 수도 있고, 내려받기가 변조됐을 수도 있습니다." 'Yellow'
        Say " 확인 전에는 설치하지 마세요." 'Yellow'
        Say ""
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        exit 5
    }
    Say " [3/5] 파일 지문 대조 — OK" 'Green'

    # ── 4. 설치 ──────────────────────────────────
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -LiteralPath $found.FullName -Destination $DllPath -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Say " [4/5] 설치 — $DllPath" 'Green'
}

# ── 5. 레지스트리 등록 ───────────────────────────
foreach ($k in $RegKeys) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    New-ItemProperty -Path $k -Name $ModuleKey -Value $DllPath -PropertyType String -Force | Out-Null
}
Say " [5/5] 레지스트리 등록 — HKCU\Software\HNC\{HwpAutomation,HwpCtrl}\Modules" 'Green'

# ── 검증 ─────────────────────────────────────────
Say ""
Say " 검증 중..." 'Gray'
$ok = $false
try {
    $hwp = New-Object -ComObject HWPFrame.HwpObject
    $ok = [bool]$hwp.RegisterModule("FilePathCheckDLL", $ModuleKey)
    try { $hwp.Quit() } catch { }
    try { [Runtime.InteropServices.Marshal]::ReleaseComObject($hwp) | Out-Null } catch { }
} catch {
    Say " 한글 연결에 실패했습니다: $($_.Exception.Message)" 'Red'
}

Say ""
if ($ok) {
    Say "───────────────────────────────────────────────" 'DarkGray'
    Say " 설치 완료 — 보안 승인 팝업이 더 이상 뜨지 않습니다." 'Green'
    Say "───────────────────────────────────────────────" 'DarkGray'
    Say ""
    Say " 이 모듈은 한글이 '이 파일에 접근해도 되냐'고 물을 때" 'DarkGray'
    Say " 무조건 '예'라고 답합니다. 즉 파일 접근 확인 절차를 끕니다." 'DarkGray'
    Say " 출처가 불분명한 스크립트를 한글 자동화로 돌리지 마세요." 'DarkGray'
    Say ""
    Say " 되돌리려면:  설치.bat 을 -Uninstall 로 실행" 'DarkGray'
    Say ""
    exit 0
} else {
    Say " 등록은 했지만 한글이 모듈을 읽지 못했습니다." 'Yellow'
    Say " 한글이 실행 중이면 완전히 종료한 뒤 다시 시도해 보세요." 'Yellow'
    Say ""
    exit 6
}
