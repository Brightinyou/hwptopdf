<div align="center">

# hwptopdf

**한글 문서(HWP·HWPX)를 폴더 단위로 PDF 일괄 변환하는 Windows 도구**

<sub>Batch-convert Hangul (HWP/HWPX) documents to PDF on Windows, folder by folder,
with automatic page-count verification. Requires Hancom Office Hangul.</sub>

[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey.svg)
![Version](https://img.shields.io/badge/version-1.1-green.svg)

</div>

---

## 무엇이 다른가

한글을 자동화해 PDF로 저장하는 도구는 이미 여럿 있습니다. 이 도구는 **여러 폴더에 흩어진
문서를 반복해서 정리하는 상황**에 맞춰 만들었습니다.

| | |
|---|---|
| **폴더별 출력** | HWP가 있는 각 폴더 안에 `[폴더이름]_변환PDF` 를 만듭니다. 상위에서 돌리든 하위에서 돌리든 결과가 늘 같은 자리에 생겨, **같은 PDF가 여러 곳에 중복 생성되지 않습니다.** |
| **쪽수 검증 + 자동 보정** | 변환할 때마다 원본 HWP의 쪽수와 PDF의 실제 쪽수를 대조합니다. 안 맞으면 **모아 찍기 때문인지 판단해 PDF 프린터로 다시 뽑아 바로잡습니다.** 그래도 안 맞으면 `확인필요`로 표시하고 이유를 알려줍니다. |
| **출력 위치 선택** | [PDF 위치] 에서 폴더별 `_변환PDF` 하위 폴더 / 원본과 같은 폴더 중 선택. 선택은 기억됩니다. |
| **여러 번 돌려도 안전** | 이미 PDF가 있으면 건너뜁니다. 중간에 끊겨도 다시 실행하면 이어서 합니다. |
| **기록** | 무엇을 변환했는지 `변환로그_*.txt` 로 남깁니다. |
| **보안 팝업 해결** | 한글 자동화의 보안 승인 팝업을 없애는 한컴 공식 모듈을, 지문(SHA256)을 대조해 설치해 줍니다. |

### 왜 쪽수를 검증하나

한글 자동화의 `SaveAs ... "PDF"` 는 **문서에 저장된 인쇄 설정을 그대로 물려받습니다.**
문서에 모아 찍기(`PrintMethod` ≠ 0)가 켜져 있으면 2쪽짜리가 1쪽 PDF로, 40쪽짜리가
20쪽으로 조용히 나옵니다. 인쇄 범위가 문서 전체가 아니면 일부만 저장되기도 합니다.

이 도구는 매번 쪽수를 대조해 그런 경우를 잡아내고, **`PrintToPDFEx` 에 `PrintMethod=0`
을 직접 넘겨 다시 뽑는 방식으로 자동 보정합니다.** `PrintToPDFEx` 는 파라미터를 우리가
넘기므로 문서의 설정을 물려받지 않습니다. 이때 PDF 프린터(`Hancom PDF` 또는
`Microsoft Print to PDF`) 중 하나가 필요하며, 없으면 보정하지 못하고 `확인필요`로
알려 주면서 설치 방법을 안내합니다.

## 요구 사항

- Windows 10 / 11
- **한컴오피스 한글 2010 SE 이상** — 이 도구에는 변환 엔진이 없고, 설치된 한글을 자동화로
  조종합니다. 그래서 표·서식이 원본 그대로 나옵니다.
- HWPX 변환은 한글 2020 이상
- .NET Framework 4.x (Windows에 기본 포함)

> 한글이 없는 PC, MS Office·LibreOffice만 있는 PC에서는 동작하지 않습니다.

## 설치

1. 이 저장소를 내려받아 아무 폴더에나 둡니다. (`C:\Program Files\hwptopdf\` 도 괜찮습니다)
2. `설치.bat` 을 한 번 실행합니다 — 한글 보안 승인 팝업을 없애는 한컴 공식 모듈을
   내려받아 등록합니다. **관리자 권한이 필요 없습니다.**
3. `hwptopdf.exe` 를 실행합니다.

되돌리려면 `설치.bat -Uninstall`.

## 사용법

`hwptopdf.exe` 에 폴더를 끌어다 놓거나, 실행 후 경로를 붙여넣고 `[파일 찾기]` → `[변환 시작]`.

```
2026년 회의\
  ├ 1월 회의.hwp
  ├ 2026년 회의_변환PDF\
  │    ├ 1월 회의.pdf
  │    └ 변환로그_20260822_114016.txt
  └ 회의결과\
       ├ 5월.hwp
       └ 회의결과_변환PDF\
            └ 5월.pdf
```

### 명령줄

```bat
convert.ps1 "폴더경로"
convert.ps1 "폴더경로" -Force              :: 이미 있는 PDF도 다시 만들기
convert.ps1 "폴더경로" -OutDir "다른폴더"   :: PDF를 한곳에 모으기
convert.ps1 "폴더경로" -SameFolder         :: PDF를 원본과 같은 폴더에
convert.ps1 "폴더경로" -NoVerify           :: 쪽수 대조 생략
```

종료 코드: `0` 정상 / `1` 대상 없음 / `2` 한글 없음 / `3` 실패 있음

자세한 내용은 [사용법.txt](사용법.txt) 를 보세요.

## 소스 빌드

Windows에 기본 포함된 C# 컴파일러만 씁니다. **NuGet·외부 라이브러리가 필요 없습니다.**

```bat
powershell -ExecutionPolicy Bypass -File build-exe.ps1
```

`hwptopdf.exe` 는 `gui.ps1` 을 콘솔 창 없이 띄우는 실행기일 뿐이고, 실제 기능은 모두
PowerShell 쪽에 있습니다.

| 파일 | 역할 |
|---|---|
| `core.ps1` | 변환 로직 (앱·명령줄 공용) |
| `gui.ps1` | 앱 화면 (WinForms) |
| `convert.ps1` | 명령줄판 |
| `install.ps1` | 보안 승인 모듈 설치 |
| `launcher.cs` | `hwptopdf.exe` 소스 |

## 개인정보

**변환은 전부 이 PC 안에서 이루어집니다.** 문서가 외부로 전송되지 않습니다.
인터넷을 쓰는 곳은 `install.ps1` 이 한컴 공식 배포처에서 보안 모듈을 내려받는
한 번뿐입니다.

## 라이선스

[PolyForm Noncommercial License 1.0.0](LICENSE) © 2026 Brightinyou

개인·비상업 용도로 자유롭게 사용·복제·수정·배포할 수 있습니다.
교회, 학교, 공공기관, 비영리단체의 사용은 허용된 용도입니다.
상업적 이용은 저작자의 서면 동의가 필요합니다.

한글(한컴오피스)과 한컴 보안 승인 모듈은 이 라이선스의 적용 대상이 아닙니다 —
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) 를 보세요.

## 면책

"있는 그대로(as-is)" 제공되며 무결성을 보증하지 않습니다. 원본 HWP는 열고 닫기만 하지만,
중요한 자료는 변환 전 백업을 권합니다. 쪽수 대조는 보조 장치이며, 중요한 문서는 최종본을
직접 열어 확인하세요.
