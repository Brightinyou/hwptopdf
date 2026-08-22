# Third-party licenses

hwptopdf's own source code is licensed under PolyForm Noncommercial 1.0.0
(see `LICENSE`) — free for personal/noncommercial use, commercial use
prohibited.

**This tool bundles no third-party code.** It is written entirely in Windows
PowerShell and uses only components already present on Windows (.NET Framework
4.x, Windows Forms). There is no NuGet package, no vendored binary, and no
downloaded library in this folder.

Two third-party pieces are nevertheless involved at runtime, and both are
described below.

## Hancom Office Hangul (한/글) — proprietary, not distributed

This tool has **no conversion engine of its own.** It drives the copy of
Hangul already installed on the user's PC through its COM automation
interface (`HWPFrame.HwpObject`), and Hangul performs the actual PDF export.

- Nothing from Hancom Office is copied, bundled, or redistributed here.
- The user must hold their own valid license for Hangul.
- Only the documented automation interface is called. No Hancom code or type
  library is included, so there is no license conflict.
- Without Hangul installed, this tool does nothing — by design.

The application window and desktop shortcut use this project's own icon
(`app.ico`), drawn for this tool. No Hancom icon, wordmark, or other brand
asset is used or redistributed.

## Hancom automation security module — downloaded, not redistributed

`FilePathCheckerModuleExample.dll` suppresses the security-approval popup that
Hangul otherwise shows every time an automation client touches a file.

- **Not included in this folder.** `install.ps1` downloads it at install time
  from Hancom's official distribution and verifies its SHA256 before use:
  - Source page: <https://developer.hancom.com/hwpautomation>
  - File: `보안모듈(Automation).zip` from Hancom's official GitHub
    organization, <https://github.com/hancom-io/devcenter-archive>
  - Verified SHA256 of the DLL:
    `9AC5B97C47AC8AED1E8BCA27A3EEF39411361D8F68C262509F0C40A8F9D21BB6`
  - Installed to `%USERPROFILE%\Tools\HancomAutomation\` and registered under
    `HKCU\Software\HNC\HwpAutomation\Modules`.
- **License:** Hancom publishes this module as sample code for its automation
  developers. The distributed archive states no license terms and carries no
  license file. Because the terms are unstated, this project **does not
  redistribute the DLL** — each installation fetches it from Hancom directly,
  so it reaches the user under whatever terms Hancom offers it.
- **What it does:** its only exported function, `IsAccessiblePath()`, returns
  `TRUE` unconditionally. The archive ships the C++ source, which confirms
  this; it performs no network access and no file manipulation. In effect it
  turns off Hangul's file-access confirmation prompt, which is required for
  unattended batch conversion.
- The DLL is unsigned. It is Hancom's own published sample, but it carries no
  Authenticode signature, and this project cannot prove byte-for-byte that the
  published DLL was built from the published source. The SHA256 check above
  pins the exact file that was reviewed.
- Removing it: `설치.bat -Uninstall` deletes both the file and the registry
  entries, restoring Hangul's default prompt behavior.

## Nothing else

No fonts, images, icons, sample documents, or code from any other party are
included in this folder. The PDF page-count check is implemented directly
against the PDF file format using .NET's built-in `DeflateStream`; no PDF
library is used.
