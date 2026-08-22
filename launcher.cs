// hwptopdf — 실행기(launcher)
// ------------------------------------------------------------------
// Copyright (c) 2026 Brightinyou
// PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
// ------------------------------------------------------------------
// 하는 일은 하나뿐이다. 같은 폴더의 gui.ps1 을 콘솔 창 없이 실행한다.
// 실제 기능은 전부 PowerShell 쪽(core.ps1 / gui.ps1)에 있다.
//
// 왜 exe 가 필요한가:
//   .vbs 로 띄우면 탐색기에서 스크립트 아이콘으로 보이고 프로그램처럼
//   느껴지지 않는다. exe 로 감싸면 아이콘·버전 정보가 제대로 붙는다.
//
// 빌드: build-exe.ps1 (Windows 에 기본 포함된 csc.exe 만 사용, 외부 의존 없음)

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("hwptopdf")]
[assembly: AssemblyProduct("hwptopdf")]
[assembly: AssemblyDescription("한글 문서 PDF 일괄 변환")]
[assembly: AssemblyCompany("Brightinyou")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Brightinyou")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Launcher
{
    const string AppName = "hwptopdf";

    [STAThread]
    static int Main(string[] args)
    {
        string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string script = Path.Combine(dir, "gui.ps1");

        if (!File.Exists(script))
        {
            MessageBox.Show(
                "gui.ps1 을 찾을 수 없습니다.\n\n" +
                "이 exe 는 같은 폴더의 스크립트를 실행합니다.\n" +
                "폴더를 통째로 옮겨 주세요.\n\n" + dir,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        StringBuilder sb = new StringBuilder();
        sb.Append("-NoProfile -ExecutionPolicy Bypass -STA -File \"").Append(script).Append("\"");
        // 끌어다 놓은 폴더·파일 경로를 그대로 넘긴다
        foreach (string a in args)
        {
            sb.Append(" \"").Append(a).Append("\"");
        }

        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", sb.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;              // 콘솔 창을 띄우지 않는다
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        psi.WorkingDirectory = dir;

        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "실행에 실패했습니다.\n\nWindows PowerShell 을 찾을 수 없거나 차단되었을 수 있습니다.\n\n" + ex.Message,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        return 0;
    }
}
