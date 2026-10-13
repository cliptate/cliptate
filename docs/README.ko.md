<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate 아이콘" />
  <h1>Cliptate</h1>
  <p><strong>Mac 오디오·비디오 크리에이터를 위한 온디바이스 AI 워크스페이스</strong></p>

  <p>
    <a href="https://github.com/cliptate/cliptate/releases"><img alt="GitHub Releases에서 다운로드" src="https://img.shields.io/badge/GitHub%20Releases-다운로드-0066cc?logo=github&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="로컬 음성 처리" src="https://img.shields.io/badge/처리방식-로컬%20음성-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">웹사이트</a> ·
    <a href="https://cliptate.github.io#features">기능</a> ·
    <a href="https://cliptate.github.io#voice">음성 및 TTS</a> ·
    <a href="https://github.com/cliptate/cliptate/releases">다운로드</a>
  </p>

  <p>
    <a href="../README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate는 음성을 편집 가능한 텍스트, 자막, 러프 컷으로 바꾸는 네이티브 macOS 앱입니다. Apple Silicon Mac에서 모델을 실행하여 녹음 전사, 다른 앱으로 받아쓰기, 무음 구간 제거, 음성 합성을 할 수 있습니다.

**GitHub 다운로드 버전은 무료입니다.** 모든 모델과 Pro 기능을 구독이나 구매 없이 사용할 수 있습니다. 선택적 온라인 AI 기능은 직접 설정한 서비스를 사용합니다.

![Cliptate AI 컷 작업 공간 (한국어)](../assets/screenshots/home.ko.jpg)

중앙 가져오기 영역에 동영상을 끌어 놓거나 클릭하여 파일을 선택하세요. 여러 동영상을 한 번에 가져올 수 있습니다. 왼쪽 사이드바에서 기능을 전환하고 하단에서 언제든 **무료 접근**과 **설정**을 열 수 있습니다.

인터페이스는 영어, 중국어 간체, 일본어, 한국어, 독일어를 지원하며 **설정 → 언어**에서 표시 언어를 변경할 수 있습니다.

[시작하기](#시작하기) · [기능](#기능) · [명령줄](#명령줄) · [개인정보와 모델](#개인정보와-모델) · [소스 빌드](#소스에서-빌드)

## 시작하기

### 다운로드 및 설치

1. [GitHub Releases](https://github.com/cliptate/cliptate/releases/latest)에서 `Cliptate.dmg`를 다운로드합니다. 매일 생성되는 빌드는 [Nightly 사전 릴리스](https://github.com/cliptate/cliptate/releases/tag/nightly)에서 받을 수 있습니다.
2. DMG를 열고 **Cliptate.app**을 **응용 프로그램** 폴더로 드래그한 뒤 실행합니다.
3. **모델(Models)** 페이지에서 첫 전사 또는 음성 합성에 필요한 모델을 다운로드합니다.

릴리스 패키지는 Developer ID 서명과 Apple 공증을 거치며 SHA-256 체크섬 파일도 제공합니다. [설치 및 검증 가이드](development.md#dmg-packages-and-ci-downloads)를 참고하세요. 직접 다운로드 버전은 [앱 내 업데이트](updates.md)를 지원합니다.

### 시스템 요구 사항

| 요구 사항 | 설명 |
| --- | --- |
| Mac | Apple Silicon(M1 이상) |
| 시스템 | macOS 15 Sequoia 이상 |
| 저장 공간과 메모리 | 선택한 모델에 따라 다릅니다. 모델 페이지에서 크기를 확인하세요 |
| 네트워크 | 최초 모델 다운로드 및 선택적 온라인 서비스에 필요 |

### 첫 작업

- **녹음 또는 영상:** **AI Cut**에서 파일을 가져오고 전사 모델과 언어를 선택합니다. 텍스트와 무음 구간 편집을 검토한 뒤 내보냅니다.
- **실시간 받아쓰기:** **Voice To Text**에서 모델과 단축키를 설정하고 마이크 접근을 허용합니다. 직접 다운로드 버전은 손쉬운 사용 권한으로 다른 앱에 텍스트를 입력하며, 클립보드 붙여넣기도 사용할 수 있습니다.
- **음성 합성:** TTS 모델을 선택하고 텍스트를 입력한 뒤, 해당 모델이 지원하는 프리셋 음성, 참조 오디오 또는 음성 설명을 지정합니다.

## 기능

| 작업 | 가능한 기능 |
| --- | --- |
| **오프라인 전사** | Parakeet, Qwen3 ASR, FireRed, Cohere 모델로 오디오와 영상을 일괄 전사합니다. 언어와 하드웨어에 맞는 엔진을 선택하세요. |
| **음성 받아쓰기** | 스트리밍 전사, 사용자 정의 사전, 설정 가능한 받아쓰기 단축키. |
| **AI Cut** | 음성 활동 감지(VAD)로 무음 구간을 감지하고, 구간을 검토하여 러프 컷을 내보냅니다. |
| **화자 표시** | 지원하는 전사 파이프라인에서 Sortformer로 화자를 구분합니다. Silero VAD는 음성을 감지하지만 화자를 식별하지 않습니다. |
| **음성 합성** | Qwen3 TTS로 프리셋 음성, 음성 복제, 감정·스타일 지정, 음성 디자인을 사용합니다. 설정 항목은 모델에 따라 다릅니다. |
| **교정과 번역** | 선택적 온라인 AI 서비스로 텍스트 교정과 키워드 강조를 수행하고, Apple 번역으로 지원하는 언어 쌍의 자막을 번역합니다. |
| **명령줄** | 스크립트나 AI 에이전트에서 파일 전사, WAV 음성 생성, 사용자 정의 사전 관리를 수행합니다. |

## 내보내기

| 출력 | 형식과 용도 |
| --- | --- |
| 편집 타임라인 | Final Cut Pro용 **FCPXML** |
| 자막과 전사문 | 앱에서 **SRT**, 스타일이 있는 **ASS**, 타임스탬프가 있는 **TXT** |
| 영상 | **MP4**, **MOV**, **M4V** 및 선택적 자막 삽입 |
| 오디오 | **M4A**, **WAV** |
| CLI 전사 | **Text**, **JSON**, **Markdown**, **SRT**, **VTT** |

자막과 렌더링한 미디어는 각 편집기의 형식 지원에 따라 DaVinci Resolve, Adobe Premiere Pro 등에서 사용할 수 있습니다. FCPXML은 Final Cut Pro 타임라인용입니다.

## 명령줄

직접 다운로드 버전에는 CLI가 포함됩니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 **설정 → 명령줄(Settings → Command Line)**에서 복사한 설치 명령을 터미널에서 실행하세요. [CLI 가이드](cli.md)에 따라 `~/.local/bin`을 셸의 `PATH`에 추가합니다.

```bash
cliptate transcribe interview.mp4 --format srt --output interview.srt
cliptate transcribe recording.wav --format json --download
cliptate tts --text "Cliptate에 오신 것을 환영합니다." --output speech.wav --download
cliptate dictionary add "Cliptate" "MLX"
```

CLI는 앱에서 선택한 모델과 설정을 사용하며, 필요하면 앱을 백그라운드에서 실행합니다. `--download`는 없는 모델의 다운로드를 허용합니다. CLI 전사는 로컬 파일을 입력받으며 프로젝트나 기록을 생성하지 않습니다. 일괄 출력, 모델 지정, 스크립트 사용 방법은 `cliptate --help` 또는 [전체 명령 참조](cli.md)를 확인하세요.

## 개인정보와 모델

- **로컬 음성 처리:** 전사, VAD, 화자 분리, TTS 추론은 Mac에서 실행됩니다. 다운로드한 음성 모델은 오프라인에서 사용할 수 있습니다.
- **선택적 온라인 AI:** 교정과 키워드 추출은 설정한 서비스에 텍스트를 전송합니다. 오프라인 음성 작업에서는 이 기능을 꺼 주세요.
- **번역:** Apple 번역에 필요한 언어 리소스를 다운로드해야 할 수 있습니다. 사용 가능 여부는 언어 쌍에 따라 다릅니다.
- **모델 저장:** 가중치는 별도로 다운로드합니다. 직접 다운로드 버전은 `~/.cache/huggingface/hub` 캐시를 재사용할 수 있습니다. [캐시 설명](development.md#shared-model-cache)을 참고하세요.
- **라이선스:** 앱은 [MIT 라이선스](../LICENSE)를 따릅니다. 모델 가중치와 의존성에는 각각의 라이선스가 적용됩니다. [타사 라이선스](../THIRD_PARTY_NOTICES.md)를 확인하세요.

## 소스에서 빌드

Apple Silicon, macOS 15+, **Xcode 26+(Swift 6.2+)**가 필요합니다. Xcode 테스트 타깃은 macOS 15.5+가 필요합니다.

```bash
git clone https://github.com/cliptate/cliptate.git
cd cliptate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLIPTATE_APP_STORE=NO
swift build
swift test
./scripts/run.sh
```

SwiftPM은 라이브러리와 CLI를 빌드하고 단위 테스트를 실행합니다. `./scripts/run.sh`는 Xcode 앱 **Cliptate Dev.app**을 빌드하고 실행하며, 개발용 설정과 데이터를 별도로 사용합니다. 실행 없이 빌드하려면 `./scripts/build-and-run.sh build`를 사용하세요.

`CLIPTATE_APP_STORE=NO`는 CLI와 손쉬운 사용 기반 받아쓰기를 포함하는 무료 직접 배포 채널을 선택합니다. 기본 소스 빌드는 App Store 기능 제한과 구독 동작을 유지하며, 결제에는 별도의 로컬 설정이 필요합니다. 서명, 모델 캐시, 배포 설정은 [개발 가이드](development.md)를 참고하세요.

## 기여 및 도움말

버그와 기능 요청은 [GitHub Issues](https://github.com/cliptate/cliptate/issues)에 등록하세요. macOS 버전, 앱 버전, 선택한 모델, 재현 단계를 포함하고 개인 녹음이나 인증 정보는 공개하지 마세요.

- [기여 가이드](../CONTRIBUTING.md) — 개발 절차, 검증, 커밋 규칙
- [아키텍처](architecture/README.md) — 코드 구조와 런타임 경계
- [릴리스 노트](release-notes/README.md#version-archive) — 버전 기록
- [보안 정책](../SECURITY.md) — 취약점 보고
- [웹사이트](https://cliptate.github.io) — 제품 소개
