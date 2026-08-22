; hwptopdf 설치 프로그램
; ------------------------------------------------------------------
; Copyright (c) 2026 Brightinyou
; PolyForm Noncommercial License 1.0.0 — 저장소의 LICENSE 참조
; ------------------------------------------------------------------
; 빌드: build-setup.ps1 (staging 폴더를 만든 뒤 ISCC로 컴파일)
;
; 관리자 권한을 요구하지 않는다(PrivilegesRequired=lowest).
; 이 프로그램은 자기 폴더에 아무것도 쓰지 않고, 한글 보안 승인 모듈도
; 사용자별(HKCU) 설정이라 관리자 권한이 필요 없다.

#define AppName    "hwptopdf"
#define AppVersion "1.0"
#define AppPub     "Brightinyou"
#define AppUrl     "https://github.com/Brightinyou/hwptopdf"

[Setup]
AppId={{CCDA65BE-3322-42C6-BDB3-447686A6E2BE}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPub}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={localappdata}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=staging\LICENSE
InfoAfterFile=staging\사용법.txt
OutputDir=..\dist
OutputBaseFilename=hwptopdf-{#AppVersion}-setup
SetupIconFile=staging\app.ico
UninstallDisplayIcon={app}\hwptopdf.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
PrivilegesRequired=lowest

[Languages]
Name: "korean";  MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로 가기 만들기"; GroupDescription: "추가 작업:"
Name: "secmodule";   Description: "한글 보안 승인 모듈 등록 (권장 — 변환할 때마다 뜨는 팝업을 없앱니다)"; GroupDescription: "추가 작업:"

[Files]
; staging 폴더를 통째로 넣는다.
; 파일을 하나씩 나열하면 새 파일이 추가됐을 때 조용히 빠지므로 와일드카드로 둔다.
Source: "staging\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";            Filename: "{app}\hwptopdf.exe"; WorkingDir: "{app}"
Name: "{group}\사용법";                 Filename: "{app}\사용법.txt"
Name: "{group}\{#AppName} 제거";        Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}";      Filename: "{app}\hwptopdf.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; 한글 보안 승인 모듈 등록 — 한컴 공식 배포처에서 내려받아 지문 대조 후 설치한다.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"""; \
  StatusMsg: "한글 보안 승인 모듈을 등록하는 중..."; \
  Flags: runhidden waituntilterminated; Tasks: secmodule

Filename: "{app}\hwptopdf.exe"; Description: "{#AppName} 실행"; \
  WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

; [UninstallRun] 을 일부러 두지 않는다.
;
; 제거할 때 보안 승인 모듈 등록까지 지우도록 만들었다가 테스트에서 문제를 발견했다.
; 그 모듈은 이 프로그램 전용이 아니라 한글 자동화 전반에 적용되는 사용자 설정이라,
; 다른 도구나 스크립트가 쓰고 있을 수 있다. 프로그램 하나를 지웠다고 조용히
; 없애 버리면 곤란하다.
;
; 모듈까지 지우고 싶으면 제거 전에 직접 실행:  설치.bat -Uninstall
