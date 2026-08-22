// hwptopdf — 실행기(launcher)
// ------------------------------------------------------------------
// Copyright (c) 2026 Brightinyou
// PolyForm Noncommercial License 1.0.0 — 같은 폴더의 LICENSE 참조
// ------------------------------------------------------------------
// 같은 폴더의 gui.ps1 을 "이 프로세스 안에서" 실행한다.
//
// 왜 powershell.exe 를 따로 띄우지 않는가:
//   외부 프로세스로 띄우면 창의 주인이 powershell.exe 가 되어, 작업표시줄과
//   작업 관리자에 PowerShell 로 표시된다. PowerShell 런스페이스를 이 exe 안에
//   만들고 UseCurrentThread 로 현재 STA 스레드에서 돌리면, 스크립트가 만든
//   WinForms 창이 hwptopdf.exe 소유가 되어 아이콘·이름이 제대로 나온다.
//
// 실제 기능은 전부 PowerShell 쪽(core.ps1 / gui.ps1)에 있다.
// 빌드: build-exe.ps1 (Windows 기본 포함 csc.exe + GAC 의 자동화 어셈블리)

using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
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
                "이 프로그램은 같은 폴더의 스크립트를 실행합니다.\n" +
                "폴더를 통째로 옮겨 주세요.\n\n" + dir,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // 스크립트를 경로로 호출해야 $PSScriptRoot 가 제대로 잡힌다.
        // 작은따옴표 문자열이므로 경로 안의 ' 만 이스케이프한다.
        string bootstrap =
            "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue\r\n" +
            "& '" + script.Replace("'", "''") + "' @args";

        try
        {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                // 핵심: 현재 스레드에서 실행해야 창이 이 프로세스 소유가 된다
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();

                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(bootstrap);
                    foreach (string a in args) { ps.AddArgument(a); }

                    ps.Invoke();

                    if (ps.Streams.Error.Count > 0)
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (ErrorRecord e in ps.Streams.Error)
                        {
                            sb.AppendLine(e.ToString());
                            if (e.InvocationInfo != null && e.InvocationInfo.ScriptLineNumber > 0)
                            {
                                sb.AppendLine("  (줄 " + e.InvocationInfo.ScriptLineNumber + ")");
                            }
                            sb.AppendLine();
                        }
                        MessageBox.Show(
                            "실행 중 오류가 발생했습니다.\n\n" + Shorten(sb.ToString(), 1500),
                            AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 3;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "실행에 실패했습니다.\n\n" + ex.Message,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        return 0;
    }

    static string Shorten(string s, int max)
    {
        if (s == null) { return ""; }
        s = s.Trim();
        return s.Length <= max ? s : s.Substring(0, max) + "\n...";
    }
}
