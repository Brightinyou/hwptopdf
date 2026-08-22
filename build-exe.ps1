<#
  hwptopdf.exe 빌드
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
  ------------------------------------------------------------------
  Windows 에 기본 포함된 .NET Framework 의 C# 컴파일러만 씁니다.
  NuGet·외부 라이브러리가 필요 없습니다.

      powershell -ExecutionPolicy Bypass -File build-exe.ps1

  주의: 반드시 UTF-8 (BOM 포함) 으로 저장할 것.
#>
[CmdletBinding()]
param([string]$Output = 'hwptopdf.exe')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Push-Location $root
try {
    $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    if (-not (Test-Path $fw)) { $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319' }

    $csc = Join-Path $fw 'csc.exe'
    if (-not (Test-Path $csc)) { throw "csc.exe 를 찾을 수 없습니다: $csc  (.NET Framework 4.x 필요)" }

    # PowerShell 호스팅용 어셈블리 (GAC). exe 안에서 스크립트를 직접 돌리기 위해 필요하다.
    $smaDir = Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation'
    $sma = Get-ChildItem $smaDir -Recurse -Filter 'System.Management.Automation.dll' -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $sma) { throw "System.Management.Automation.dll 을 찾을 수 없습니다 (Windows PowerShell 필요)" }

    $args = @(
        '/nologo'
        '/target:winexe'          # 콘솔 창 없음
        '/codepage:65001'         # 소스가 UTF-8
        '/optimize+'
        '/win32icon:app.ico'
        "/out:$Output"
        "/reference:$(Join-Path $fw 'System.dll')"
        "/reference:$(Join-Path $fw 'System.Windows.Forms.dll')"
        "/reference:$(Join-Path $fw 'System.Drawing.dll')"
        "/reference:$($sma.FullName)"
        'launcher.cs'
    )

    Write-Host "빌드 중: $Output ..."
    & $csc $args
    if ($LASTEXITCODE -ne 0) { throw "컴파일 실패 (종료 코드 $LASTEXITCODE)" }

    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Resolve-Path $Output).Path)
    $kb = [math]::Round((Get-Item $Output).Length / 1KB, 1)
    Write-Host ("완료: {0}  ({1} {2}, {3} KB)" -f $Output, $info.ProductName, $info.FileVersion, $kb) -ForegroundColor Green
}
finally {
    Pop-Location
}
