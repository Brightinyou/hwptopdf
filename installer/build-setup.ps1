<#
  hwptopdf 설치 프로그램 빌드
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 저장소의 LICENSE 참조
  ------------------------------------------------------------------
  하는 일
    1. hwptopdf.exe 를 먼저 빌드 (build-exe.ps1)
    2. 배포에 들어갈 파일만 staging\ 으로 모음 (.git 등 제외)
    3. Inno Setup(ISCC.exe)으로 dist\hwptopdf-1.0-setup.exe 생성

      powershell -ExecutionPolicy Bypass -File installer\build-setup.ps1

  주의: 반드시 UTF-8 (BOM 포함) 으로 저장할 것.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent

# ── 1. exe 빌드 ─────────────────────────────────
Write-Host "[1/3] hwptopdf.exe 빌드..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build-exe.ps1')
if ($LASTEXITCODE -ne 0) { throw "exe 빌드 실패" }

# ── 2. staging ──────────────────────────────────
Write-Host "[2/3] 배포 파일 모으는 중..." -ForegroundColor Cyan
$stage = Join-Path $here 'staging'
if ([System.IO.Directory]::Exists($stage)) { [System.IO.Directory]::Delete($stage, $true) }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 설치본에 들어갈 파일. 새 파일을 추가하면 여기에도 넣을 것.
$files = @(
    'hwptopdf.exe', 'hwptopdf.vbs', 'app.ico',
    'gui.ps1', 'core.ps1', 'convert.ps1', 'install.ps1',
    'launcher.cs', 'build-exe.ps1',
    '명령줄변환.bat', '설치.bat',
    '사용법.txt', 'LICENSE', 'THIRD-PARTY-LICENSES.md', 'README.md'
)
foreach ($f in $files) {
    $src = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $src)) { throw "빠진 파일: $f" }
    [System.IO.File]::Copy($src, (Join-Path $stage $f), $true)
}
Write-Host ("      {0}개 파일" -f $files.Count)

# ── 3. ISCC ─────────────────────────────────────
Write-Host "[3/3] 설치 프로그램 컴파일..." -ForegroundColor Cyan
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
    throw "ISCC.exe 를 찾을 수 없습니다: $iscc`nInno Setup 6 을 설치하세요: https://jrsoftware.org/isdl.php"
}

& $iscc (Join-Path $here 'hwptopdf.iss')
if ($LASTEXITCODE -ne 0) { throw "설치 프로그램 컴파일 실패 (종료 코드 $LASTEXITCODE)" }

$out = Get-ChildItem (Join-Path $root 'dist') -Filter '*-setup.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ""
Write-Host ("완료: {0}  ({1:N0} KB)" -f $out.FullName, ($out.Length / 1KB)) -ForegroundColor Green
Write-Host ("SHA256: " + (Get-FileHash $out.FullName -Algorithm SHA256).Hash) -ForegroundColor DarkGray
