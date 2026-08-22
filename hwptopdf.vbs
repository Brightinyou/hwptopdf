' ------------------------------------------------------------------
'  HWP -> PDF converter (GUI launcher)
'  Starts gui.ps1 with no console window at all.
'  Drag a folder onto this file, or just double-click it.
'  ASCII-only on purpose.
' ------------------------------------------------------------------
Option Explicit

Dim sh, fso, here, ps1, cmd, i

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = fso.BuildPath(here, "gui.ps1")

If Not fso.FileExists(ps1) Then
    MsgBox "gui.ps1 not found in:" & vbCrLf & here, vbCritical, "hwptopdf"
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & ps1 & """"

' pass dropped files / folders through
For i = 0 To WScript.Arguments.Count - 1
    cmd = cmd & " """ & WScript.Arguments(i) & """"
Next

' 0 = hidden window, False = do not wait
sh.Run cmd, 0, False
