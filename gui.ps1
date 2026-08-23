<#
  HWP → PDF 일괄 변환기 (화면)
  ------------------------------------------------------------------
  Copyright (c) 2026 Brightinyou
  PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
  ------------------------------------------------------------------
  변환 과정과 결과를 창 안에서 보여줍니다. 끝나도 창은 닫히지 않고
  최종 리포트를 보여주며, 결과 폴더를 바로 열 수 있습니다.

  실행: hwptopdf.vbs (콘솔 창 없이 실행) 또는 명령줄변환.bat
  변환 로직은 core.ps1 에 있습니다.

  주의: 반드시 UTF-8 (BOM 포함) 으로 저장할 것.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Targets
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'core.ps1')

$APP_NAME    = 'hwptopdf'
$APP_VERSION = '1.1'
$APP_DESC    = '한글 문서 PDF 일괄 변환'
$APP_AUTHOR  = 'Brightinyou'
$APP_YEAR    = '2026'
$APP_LICENSE = 'PolyForm Noncommercial License 1.0.0'
$APP_URL     = 'https://github.com/Brightinyou/hwptopdf'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# hwptopdf.vbs 는 콘솔이 보이지 않도록 프로세스를 SW_HIDE 상태로 띄운다.
# WinForms 창이 그 상태를 물려받아 "떠 있지만 보이지 않는" 창이 되므로,
# 창이 만들어진 뒤 명시적으로 보이게 만들어야 한다.
Add-Type -Namespace HwpPdf -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
"@

# ─────────────────────────────────────────────── 상태
$script:jobs      = @()
$script:running   = $false
$script:cancel    = $false
$script:outRoot   = $null
$script:logPath   = $null
$script:done      = $false

$FONT   = New-Object System.Drawing.Font("맑은 고딕", 9)
$FONTB  = New-Object System.Drawing.Font("맑은 고딕", 9, [System.Drawing.FontStyle]::Bold)
$FONTM  = New-Object System.Drawing.Font("Consolas", 9)

$C_OK   = [System.Drawing.Color]::FromArgb(27, 122, 62)
$C_SKIP = [System.Drawing.Color]::FromArgb(120, 120, 120)
$C_WARN = [System.Drawing.Color]::FromArgb(150, 99, 26)
$C_FAIL = [System.Drawing.Color]::FromArgb(176, 37, 37)
$C_BUSY = [System.Drawing.Color]::FromArgb(26, 95, 166)

# ─────────────────────────────────────────────── 화면
$form = New-Object System.Windows.Forms.Form
$form.Text = "$APP_NAME $APP_VERSION — $APP_DESC"
$form.ClientSize = New-Object System.Drawing.Size(940, 664)
$form.StartPosition = 'CenterScreen'
$form.Font = $FONT
$form.MinimumSize = New-Object System.Drawing.Size(760, 560)
$form.AllowDrop = $true

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "변환할 폴더 — 경로를 붙여넣거나(Ctrl+V), 창에 폴더를 끌어다 놓으세요."
$lblPath.Location = New-Object System.Drawing.Point(14, 14)
$lblPath.Size = New-Object System.Drawing.Size(700, 20)

$tbPath = New-Object System.Windows.Forms.TextBox
$tbPath.Location = New-Object System.Drawing.Point(14, 36)
$tbPath.Size = New-Object System.Drawing.Size(690, 25)
$tbPath.Anchor = 'Top,Left,Right'

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "찾아보기..."
$btnBrowse.Location = New-Object System.Drawing.Point(712, 35)
$btnBrowse.Size = New-Object System.Drawing.Size(100, 27)
$btnBrowse.Anchor = 'Top,Right'

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "파일 찾기"
$btnScan.Location = New-Object System.Drawing.Point(820, 35)
$btnScan.Size = New-Object System.Drawing.Size(106, 27)
$btnScan.Anchor = 'Top,Right'

$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = "이미 만들어진 PDF도 다시 변환"
$chkForce.Location = New-Object System.Drawing.Point(14, 70)
$chkForce.Size = New-Object System.Drawing.Size(230, 24)

# 원본과 PDF의 페이지 수 대조는 항상 수행한다 (끌 수 없음).
# 잘린 PDF를 놓치면 뒤늦게 발견하기 어려워서 선택지로 두지 않았다.

# PDF를 어디에 만들지 — 둘 중 하나만 고르는 것이므로 라디오 버튼으로 둔다.
$sameFolderPref = [bool](Get-AppSettings)['SameFolder']

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = "PDF 위치:"
$lblOut.Location = New-Object System.Drawing.Point(258, 73)
$lblOut.Size = New-Object System.Drawing.Size(64, 20)

$rdoSub = New-Object System.Windows.Forms.RadioButton
$rdoSub.Text = "하위 폴더에 만들기 ([폴더이름]_변환PDF)"
$rdoSub.Location = New-Object System.Drawing.Point(324, 70)
$rdoSub.Size = New-Object System.Drawing.Size(268, 24)
$rdoSub.Checked = (-not $sameFolderPref)

$rdoSame = New-Object System.Windows.Forms.RadioButton
$rdoSame.Text = "원본과 같은 폴더에 만들기"
$rdoSame.Location = New-Object System.Drawing.Point(600, 70)
$rdoSame.Size = New-Object System.Drawing.Size(190, 24)
$rdoSame.Checked = $sameFolderPref

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(14, 100)
$lv.Size = New-Object System.Drawing.Size(912, 330)
$lv.Anchor = 'Top,Left,Right,Bottom'
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.GridLines = $false
$lv.HideSelection = $false
[void]$lv.Columns.Add("파일", 400)
[void]$lv.Columns.Add("위치", 170)
[void]$lv.Columns.Add("상태", 110)
[void]$lv.Columns.Add("쪽", 70)
[void]$lv.Columns.Add("크기", 90)
[void]$lv.Columns.Add("비고", 150)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(14, 440)
$bar.Size = New-Object System.Drawing.Size(912, 16)
$bar.Anchor = 'Left,Right,Bottom'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "폴더를 지정한 뒤 [파일 찾기]를 누르세요."
$lblStatus.Location = New-Object System.Drawing.Point(14, 462)
$lblStatus.Size = New-Object System.Drawing.Size(912, 20)
$lblStatus.Anchor = 'Left,Right,Bottom'

$tbReport = New-Object System.Windows.Forms.TextBox
$tbReport.Location = New-Object System.Drawing.Point(14, 486)
$tbReport.Size = New-Object System.Drawing.Size(912, 128)
$tbReport.Anchor = 'Left,Right,Bottom'
$tbReport.Multiline = $true
$tbReport.ReadOnly = $true
$tbReport.ScrollBars = 'Vertical'
$tbReport.Font = $FONTM
$tbReport.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "변환 시작"
$btnStart.Location = New-Object System.Drawing.Point(14, 622)
$btnStart.Size = New-Object System.Drawing.Size(120, 30)
$btnStart.Anchor = 'Left,Bottom'
$btnStart.Font = $FONTB
$btnStart.Enabled = $false

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "중단"
$btnStop.Location = New-Object System.Drawing.Point(140, 622)
$btnStop.Size = New-Object System.Drawing.Size(84, 30)
$btnStop.Anchor = 'Left,Bottom'
$btnStop.Enabled = $false

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "결과 폴더 열기"
$btnOpen.Location = New-Object System.Drawing.Point(560, 622)
$btnOpen.Size = New-Object System.Drawing.Size(130, 30)
$btnOpen.Anchor = 'Right,Bottom'
$btnOpen.Enabled = $false

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = "기록 열기"
$btnLog.Location = New-Object System.Drawing.Point(696, 622)
$btnLog.Size = New-Object System.Drawing.Size(110, 30)
$btnLog.Anchor = 'Right,Bottom'
$btnLog.Enabled = $false

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "닫기"
$btnClose.Location = New-Object System.Drawing.Point(812, 622)
$btnClose.Size = New-Object System.Drawing.Size(114, 30)
$btnClose.Anchor = 'Right,Bottom'

# 정보(크레딧) — 버전·제작자·라이선스와 문서 바로가기
$btnAbout = New-Object System.Windows.Forms.Button
$btnAbout.Text = "정보"
$btnAbout.Location = New-Object System.Drawing.Point(232, 622)
$btnAbout.Size = New-Object System.Drawing.Size(64, 30)
$btnAbout.Anchor = 'Left,Bottom'

$form.Controls.AddRange(@(
    $lblPath, $tbPath, $btnBrowse, $btnScan, $chkForce, $lblOut, $rdoSub, $rdoSame,
    $lv, $bar, $lblStatus, $tbReport,
    $btnStart, $btnStop, $btnAbout, $btnOpen, $btnLog, $btnClose
))

# 아이콘 — 이 도구 자체 아이콘. 어느 회사의 자산도 쓰지 않는다.
try {
    $icoPath = Join-Path $PSScriptRoot 'app.ico'
    if (Test-Path $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
} catch { }

# ─────────────────────────────────────────────── 동작

function Add-Report {
    param([string]$Text)
    $tbReport.AppendText($Text + "`r`n")
    $tbReport.SelectionStart = $tbReport.TextLength
    $tbReport.ScrollToCaret()
}

function Set-Status { param([string]$Text) $lblStatus.Text = $Text }

# 정보 창 — 버전·제작자·라이선스 + 문서 바로 열기
function Show-About {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "정보"
    $dlg.ClientSize = New-Object System.Drawing.Size(430, 268)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.Font = $FONT
    try { $dlg.Icon = $form.Icon } catch { }

    # 아이콘
    try {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image = ([System.Drawing.Icon]::new((Join-Path $PSScriptRoot 'app.ico'), 64, 64)).ToBitmap()
        $pic.SizeMode = 'Zoom'
        $pic.Location = New-Object System.Drawing.Point(24, 24)
        $pic.Size = New-Object System.Drawing.Size(64, 64)
        $dlg.Controls.Add($pic)
    } catch { }

    $t1 = New-Object System.Windows.Forms.Label
    $t1.Text = "$APP_NAME $APP_VERSION"
    $t1.Font = New-Object System.Drawing.Font("맑은 고딕", 14, [System.Drawing.FontStyle]::Bold)
    $t1.Location = New-Object System.Drawing.Point(104, 24)
    $t1.Size = New-Object System.Drawing.Size(300, 30)

    $t2 = New-Object System.Windows.Forms.Label
    $t2.Text = $APP_DESC
    $t2.Location = New-Object System.Drawing.Point(106, 56)
    $t2.Size = New-Object System.Drawing.Size(300, 20)
    $t2.ForeColor = [System.Drawing.Color]::Gray

    $t3 = New-Object System.Windows.Forms.Label
    $t3.Text = "© $APP_YEAR $APP_AUTHOR`r`n$APP_LICENSE`r`n개인·비상업 용도로 자유롭게 사용할 수 있습니다."
    $t3.Location = New-Object System.Drawing.Point(24, 104)
    $t3.Size = New-Object System.Drawing.Size(384, 60)

    $dlg.Controls.AddRange(@($t1, $t2, $t3))

    # 문서 열기 버튼들
    $files = @(
        @{ T = "사용법";     F = '사용법.txt' },
        @{ T = "라이선스";   F = 'LICENSE' },
        @{ T = "고지";       F = 'THIRD-PARTY-LICENSES.md' }
    )
    $x = 24
    foreach ($f in $files) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $f.T
        $b.Location = New-Object System.Drawing.Point($x, 176)
        $b.Size = New-Object System.Drawing.Size(88, 28)
        $target = Join-Path $PSScriptRoot $f.F
        $b.Add_Click({
            if (Test-Path -LiteralPath $target) { Start-Process notepad.exe -ArgumentList ('"' + $target + '"') }
            else { [System.Windows.Forms.MessageBox]::Show($dlg, "파일을 찾을 수 없습니다:`n$target", "없음", 'OK', 'Warning') | Out-Null }
        }.GetNewClosure())
        $dlg.Controls.Add($b)
        $x += 96
    }

    $bWeb = New-Object System.Windows.Forms.Button
    $bWeb.Text = "GitHub"
    $bWeb.Location = New-Object System.Drawing.Point(312, 176)
    $bWeb.Size = New-Object System.Drawing.Size(94, 28)
    $bWeb.Add_Click({ Start-Process $APP_URL })
    $dlg.Controls.Add($bWeb)

    $bOk = New-Object System.Windows.Forms.Button
    $bOk.Text = "닫기"
    $bOk.Location = New-Object System.Drawing.Point(312, 218)
    $bOk.Size = New-Object System.Drawing.Size(94, 30)
    $bOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($bOk)
    $dlg.AcceptButton = $bOk
    $dlg.CancelButton = $bOk

    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

function Do-Scan {
    $p = Clean-PathText $tbPath.Text
    if (-not $p) {
        [System.Windows.Forms.MessageBox]::Show($form, "변환할 폴더 경로를 입력하세요.", "경로 없음", 'OK', 'Information') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $p)) {
        [System.Windows.Forms.MessageBox]::Show($form,
            "이 경로를 찾을 수 없습니다:`n`n$p`n`n오타이거나, 네트워크 폴더에 연결되어 있지 않을 수 있습니다.",
            "경로를 찾을 수 없음", 'OK', 'Warning') | Out-Null
        return
    }

    $tbPath.Text = $p
    $btnScan.Enabled = $false; $btnStart.Enabled = $false; $btnBrowse.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        Set-Status "폴더를 훑는 중... (하위 폴더까지 찾습니다)"
        $form.Refresh()

        $r = Get-HwpJobs -Targets @($p) -SameFolder:$rdoSame.Checked
        $script:jobs = @($r.Jobs)

        # 결과 폴더(기록이 저장되고 [결과 폴더 열기]가 여는 곳)
        $script:outRoot = $r.OutRoot
        $script:logPath = $null
        $script:done = $false
        $btnLog.Enabled = $false
        $btnOpen.Enabled = ($script:outRoot -and (Test-Path -LiteralPath $script:outRoot))

        $lv.Items.Clear()
        $tbReport.Clear()

        $n = $script:jobs.Count
        if ($n -gt 0) {
            Set-Status ("{0}개를 찾았습니다. 목록을 만드는 중..." -f $n)
            $form.Refresh()

            # 목록은 통째로 한 번에 넣는다.
            # 하나씩 Add 하면 항목마다 다시 그리느라 2배 이상 느리다.
            $arr = New-Object 'System.Windows.Forms.ListViewItem[]' $n
            for ($i = 0; $i -lt $n; $i++) {
                $j = $script:jobs[$i]
                $folder = if ($j.Folder) { $j.Folder } else { '.' }
                $arr[$i] = New-Object System.Windows.Forms.ListViewItem `
                             -ArgumentList (, [string[]]@($j.Name, $folder, '대기', '', '', ''))
            }
            $lv.BeginUpdate()
            $lv.Items.AddRange($arr)
            $lv.EndUpdate()
        }

        $bar.Value = 0
        $bar.Maximum = [Math]::Max(1, $n)

        foreach ($s in $r.Skipped) { Add-Report "제외 - $s" }

        if ($n -eq 0) {
            Set-Status "이 폴더에 HWP/HWPX 파일이 없습니다."
            $btnStart.Enabled = $false
        } else {
            # "이미 PDF 있음"은 파일마다 Test-Path 하지 않는다.
            # 출력 폴더를 폴더당 한 번씩만 훑어 대조한다(네트워크 왕복 횟수가 파일 수에
            # 비례하지 않도록). 파일이 많을수록 차이가 커진다.
            $have = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $dirs = $script:jobs | ForEach-Object { Split-Path $_.Pdf -Parent } | Sort-Object -Unique
            foreach ($dir in $dirs) {
                if (Test-Path -LiteralPath $dir) {
                    foreach ($f in [System.IO.Directory]::EnumerateFiles($dir, '*.pdf')) { [void]$have.Add($f) }
                }
            }
            $already = 0
            foreach ($j in $script:jobs) { if ($have.Contains($j.Pdf)) { $already++ } }

            Set-Status ("HWP/HWPX {0}개를 찾았습니다. (이미 PDF가 있어 건너뛸 파일 {1}개)  [변환 시작]을 누르세요." -f $n, $already)
            $btnStart.Enabled = $true
        }
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnScan.Enabled = $true; $btnBrowse.Enabled = $true
    }
}

function Do-Convert {
    if ($script:running -or $script:jobs.Count -eq 0) { return }

    $force  = $chkForce.Checked
    $verify = $true   # 페이지 수 대조는 항상 수행

    $script:running = $true
    $script:cancel = $false
    $script:done = $false
    $btnStart.Enabled = $false; $btnScan.Enabled = $false; $btnBrowse.Enabled = $false
    $chkForce.Enabled = $false; $tbPath.Enabled = $false
    $rdoSub.Enabled = $false; $rdoSame.Enabled = $false
    $btnStop.Enabled = $true
    $tbReport.Clear()
    $bar.Value = 0

    $session = $null
    $pdfPrinter = $null
    $ok = 0; $skip = 0; $warn = 0; $fail = 0
    $lines = New-Object System.Collections.Generic.List[string]
    $started = Get-Date

    try {
        Set-Status "한글에 연결하는 중..."
        $form.Refresh()
        $session = New-HwpSession
        if (-not $session.Secured) {
            Add-Report "안내 - 보안 승인 모듈이 등록되어 있지 않습니다. 한글 팝업이 뜰 수 있습니다. (설치.bat 실행)"
        }
        $pdfPrinter = $session.PdfPrinter
        if ($session.PdfPrinter) {
            Add-Report "안내 - 모아찍기가 켜진 문서는 '$($session.PdfPrinter)' 로 다시 뽑아 한 쪽씩 저장합니다."
        } else {
            Add-Report "주의 - 쓸 수 있는 PDF 프린터가 없어, 모아찍기가 켜진 문서를 바로잡을 수 없습니다."
            Add-Report "       (아래 [정보] 버튼 옆 안내 참고 — Hancom PDF 또는 Microsoft Print to PDF 필요)"
        }

        for ($i = 0; $i -lt $script:jobs.Count; $i++) {
            if ($script:cancel) { break }

            $j = $script:jobs[$i]
            $it = $lv.Items[$i]
            $it.SubItems[2].Text = "변환 중"
            $it.ForeColor = $C_BUSY
            $it.EnsureVisible()
            Set-Status ("변환 중 ({0}/{1})  {2}" -f ($i + 1), $script:jobs.Count, $j.Name)
            [System.Windows.Forms.Application]::DoEvents()

            $r = Convert-OneHwp -Session $session -Job $j -Force:$force -Verify:$verify

            switch ($r.Status) {
                'ok' {
                    $ok++
                    $it.SubItems[2].Text = "완료"; $it.ForeColor = $C_OK
                    if ($r.SrcPages -gt 0) { $it.SubItems[3].Text = "$($r.SrcPages)" }
                    $it.SubItems[4].Text = Format-Size $r.Size
                    $lines.Add("OK    $($j.Src)")
                }
                'skip' {
                    $skip++
                    $it.SubItems[2].Text = "건너뜀"; $it.ForeColor = $C_SKIP
                    $it.SubItems[5].Text = "이미 PDF 있음"
                    $lines.Add("SKIP  $($j.Src)")
                }
                'warn' {
                    $warn++
                    $it.SubItems[2].Text = "확인필요"; $it.ForeColor = $C_WARN
                    $it.SubItems[3].Text = "$($r.SrcPages)→$($r.PdfPages)"
                    $it.SubItems[4].Text = Format-Size $r.Size
                    $it.SubItems[5].Text = $r.Message
                    # 나중에 어느 파일인지 찾을 수 있도록 전체 경로를 남긴다
                    $lines.Add("WARN  $($j.Src)")
                    $lines.Add("        $($r.Message)")
                    Add-Report "확인필요 - $($r.Message)"
                    Add-Report "           $($j.Src)"
                }
                default {
                    $fail++
                    $it.SubItems[2].Text = "실패"; $it.ForeColor = $C_FAIL
                    $it.SubItems[5].Text = $r.Message
                    $lines.Add("FAIL  $($j.Src)")
                    $lines.Add("        $($r.Message)")
                    Add-Report "실패 - $($r.Message)"
                    Add-Report "       $($j.Src)"

                    # 한글이 죽은 경우(RPC_E_SERVERFAULT 등) 뒤 파일이 모두 연쇄로
                    # 실패한다. 연결이 끊겼으면 새로 열고 계속한다.
                    if (-not (Test-HwpSessionAlive $session)) {
                        Add-Report "       한글 연결이 끊겨 다시 연결합니다..."
                        Set-Status "한글 연결이 끊겨 다시 연결하는 중..."
                        [System.Windows.Forms.Application]::DoEvents()
                        Close-HwpSession $session
                        $session = $null
                        try {
                            $session = New-HwpSession
                            $lines.Add("        (한글 연결이 끊겨 재연결함)")
                        } catch {
                            Add-Report "       다시 연결하지 못했습니다. 여기서 중단합니다."
                            $lines.Add("        (한글 재연결 실패 — 중단)")
                            break
                        }
                    }
                }
            }

            $bar.Value = $i + 1
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch {
        Add-Report "오류 - $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($form,
            "한글 연결에 실패했습니다.`n`n$($_.Exception.Message)", "오류", 'OK', 'Error') | Out-Null
    }
    finally {
        Close-HwpSession $session

        $elapsed = (Get-Date) - $started
        $total = $ok + $skip + $warn + $fail

        $script:logPath = Write-ConvertLog -OutRoot $script:outRoot -Targets @($tbPath.Text) `
                            -Lines $lines.ToArray() -Ok $ok -Skip $skip -Warn $warn -Fail $fail

        # ── 최종 리포트 ──
        $sep = "─" * 62
        Add-Report $sep
        if ($script:cancel) { Add-Report "  중단됨 — $total / $($script:jobs.Count) 개까지 처리" }
        else                { Add-Report "  변환 완료" }
        Add-Report $sep
        Add-Report ("  완료      {0,4} 개" -f $ok)
        Add-Report ("  건너뜀    {0,4} 개   (이미 PDF가 있어 그대로 둠)" -f $skip)
        Add-Report ("  확인필요  {0,4} 개   (원본과 PDF의 쪽수가 다름)" -f $warn)
        Add-Report ("  실패      {0,4} 개" -f $fail)
        Add-Report $sep
        Add-Report ("  걸린 시간 : {0}분 {1}초" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds)
        Add-Report ("  저장 위치 : {0}" -f $script:outRoot)
        if ($script:logPath) { Add-Report ("  기록 파일 : {0}" -f (Split-Path $script:logPath -Leaf)) }
        if ($warn -gt 0 -and -not $pdfPrinter) {
            [System.Windows.Forms.MessageBox]::Show($form,
                "쪽수가 맞지 않는 파일이 $warn 개 있습니다.`n`n" +
                "문서에 '모아 찍기'가 켜져 있으면 한 장에 여러 쪽이 들어가 이렇게 됩니다.`n" +
                "이 프로그램은 그런 경우 PDF 프린터로 다시 뽑아 바로잡는데,`n" +
                "지금 이 PC에는 쓸 수 있는 PDF 프린터가 없습니다.`n`n" +
                "다음 중 하나를 설치하면 자동으로 해결됩니다.`n`n" +
                "  · Hancom PDF  — 한컴오피스 설치 시 함께 제공됩니다.`n" +
                "    한컴오피스 설치 관리자에서 다시 설치하거나,`n" +
                "    한글 설치 폴더의 HancomPDF\SetupDriver.exe 를 실행하세요.`n`n" +
                "  · Microsoft Print to PDF — Windows 기본 기능입니다.`n" +
                "    [설정] → [Bluetooth 및 장치] → [프린터 및 스캐너] 에서 추가하거나,`n" +
                "    [Windows 기능 켜기/끄기] 에서 켤 수 있습니다.",
                "PDF 프린터가 없습니다", 'OK', 'Information') | Out-Null
        }

        if ($warn -gt 0) {
            Add-Report ""
            Add-Report "  [확인필요] 원본과 PDF의 쪽수가 다른 경우입니다. 두 가지로 갈립니다."
            Add-Report ""
            Add-Report "  · '모아찍기 N쪽 추정' — 문서에 모아 찍기가 켜져 있어 한 장에 여러 쪽이"
            Add-Report "    들어간 것입니다. 내용은 다 있으니 그대로 두셔도 됩니다."
            Add-Report "    한 쪽씩 나오게 하려면 한글에서 그 문서를 열어 [파일]-[인쇄]의"
            Add-Report "    '모아 찍기'를 끄고 저장한 뒤, 위 '다시 변환'을 켜고 다시 실행하세요."
            Add-Report ""
            Add-Report "  · '일부만 저장됐을 수 있습니다' — 인쇄 범위가 문서 전체가 아닐 수"
            Add-Report "    있습니다. [파일]-[인쇄] 범위를 '문서 전체'로 바꾼 뒤 다시 변환하세요."
        }

        $script:running = $false
        $script:done = $true
        $btnStart.Enabled = $true; $btnScan.Enabled = $true; $btnBrowse.Enabled = $true
        $chkForce.Enabled = $true; $tbPath.Enabled = $true
        $rdoSub.Enabled = $true; $rdoSame.Enabled = $true
        $btnStop.Enabled = $false
        $btnOpen.Enabled = ($script:outRoot -and (Test-Path -LiteralPath $script:outRoot))
        $btnLog.Enabled = ($null -ne $script:logPath)

        if ($script:cancel) { Set-Status "중단했습니다. 결과는 아래 리포트를 보세요." }
        else { Set-Status ("끝났습니다 — 완료 {0} / 건너뜀 {1} / 확인필요 {2} / 실패 {3}" -f $ok, $skip, $warn, $fail) }

        $form.Activate()
    }
}

# ─────────────────────────────────────────────── 이벤트

$btnBrowse.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "HWP 파일이 있는 폴더를 선택하세요."
    $d.ShowNewFolderButton = $false
    $cur = Clean-PathText $tbPath.Text
    if ($cur -and (Test-Path -LiteralPath $cur -PathType Container)) { $d.SelectedPath = $cur }
    if ($d.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $tbPath.Text = $d.SelectedPath
        Do-Scan
    }
})

$btnScan.Add_Click({ Do-Scan })

# 출력 위치 선택은 기억해 둔다. 바꾸면 목록도 다시 만든다.
# 둘 중 하나만 처리하면 된다 — 다른 쪽을 눌러도 이 이벤트가 함께 발생한다.
$rdoSame.Add_CheckedChanged({
    Save-AppSettings @{ SameFolder = [bool]$rdoSame.Checked }
    if (-not $script:running -and $script:jobs.Count -gt 0) { Do-Scan }
})
$btnStart.Add_Click({ Do-Convert })
$btnStop.Add_Click({ $script:cancel = $true; Set-Status "중단하는 중... 현재 파일까지만 끝냅니다." })

$btnOpen.Add_Click({
    if ($script:outRoot -and (Test-Path -LiteralPath $script:outRoot)) {
        Start-Process explorer.exe -ArgumentList ('"' + $script:outRoot + '"')
    }
})

$btnLog.Add_Click({
    if ($script:logPath -and (Test-Path -LiteralPath $script:logPath)) {
        Start-Process notepad.exe -ArgumentList ('"' + $script:logPath + '"')
    }
})

$btnAbout.Add_Click({ Show-About })
$btnClose.Add_Click({ $form.Close() })

# Enter 로 파일 찾기
$tbPath.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Do-Scan
    }
})

# 창 전체에 폴더를 끌어다 놓기
$form.Add_DragEnter({
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop) -and -not $script:running) {
        $_.Effect = 'Copy'
    }
})
$form.Add_DragDrop({
    if ($script:running) { return }
    $paths = @($_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
    if ($paths.Count -gt 0) { $tbPath.Text = $paths[0]; Do-Scan }
})

# 변환 중에는 창을 닫지 못하게 한다
$form.Add_FormClosing({
    if ($script:running) {
        $r = [System.Windows.Forms.MessageBox]::Show($form,
            "변환이 진행 중입니다. 중단하고 닫을까요?", "변환 중",
            'YesNo', 'Question')
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { $script:cancel = $true }
        $_.Cancel = $true
    }
})

$form.Add_Shown({
    # SW_SHOW(5) 로 강제로 보이게 한 뒤 앞으로 가져온다 (위 주석 참고)
    try {
        [void][HwpPdf.Win]::ShowWindow($form.Handle, 5)
        [void][HwpPdf.Win]::SetForegroundWindow($form.Handle)
    } catch { }
    $form.Activate()

    # 한글 설치 확인
    if (-not [Type]::GetTypeFromProgID('HWPFrame.HwpObject')) {
        [System.Windows.Forms.MessageBox]::Show($form,
            "한글(한컴오피스)이 설치되어 있지 않습니다.`n`n이 프로그램은 설치된 한글을 이용해 변환합니다.",
            "한글을 찾을 수 없음", 'OK', 'Error') | Out-Null
        $btnScan.Enabled = $false
        return
    }

    # 인자로 폴더를 받았으면 바로 채우고 찾는다
    if ($Targets -and $Targets.Count -gt 0) {
        $tbPath.Text = Clean-PathText $Targets[0]
        Do-Scan
    } else {
        # 클립보드에 폴더 경로가 있으면 미리 채워둔다
        try {
            $clip = Clean-PathText ([System.Windows.Forms.Clipboard]::GetText())
            if ($clip -and (Test-Path -LiteralPath $clip -PathType Container)) {
                $tbPath.Text = $clip
                Set-Status "클립보드의 경로를 넣었습니다. [파일 찾기]를 누르세요."
            }
        } catch { }
        $tbPath.Focus()
    }
})

[void]$form.ShowDialog()
