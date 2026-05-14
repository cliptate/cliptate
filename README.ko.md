<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate 아이콘" />
  <h1>Cliptate</h1>
  <p><strong>Mac 오디오·비디오 크리에이터를 위한 온디바이스 AI 워크스페이스</strong></p>

  <p>
    <a href="https://apps.apple.com/"><img alt="App Store에서 다운로드" src="https://img.shields.io/badge/App%20Store-다운로드-0066cc?logo=apple&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="100% 로컬 처리" src="https://img.shields.io/badge/처리방식-100%25%20로컬-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">웹사이트</a> ·
    <a href="https://cliptate.github.io#features">기능</a> ·
    <a href="https://cliptate.github.io#voice">음성 및 TTS</a> ·
    <a href="https://apps.apple.com/">다운로드</a>
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate는 오디오·비디오 제작에서 가장 시간이 많이 걸리는 작업들을 완전히 로컬에서 동작하는 하나의 연속된 워크플로우로 통합한 네이티브 macOS 앱입니다. 클라우드 업로드, API 키, 네트워크 대기 없이 모든 모델이 Mac에서 실행됩니다.

---

## 기능

### 🎙 음성 받아쓰기 — 말하는 대로 입력

실시간 스트리밍 음성-텍스트 변환을 입력기처럼 사용할 수 있습니다. 글로벌 키보드 단축키로 어느 앱에서든 호출하면 말하는 즉시 편집 가능한 텍스트가 생성됩니다.

- 최소 지연의 스트리밍 실시간 전사
- 다중 화자 자동 식별 및 레이블링
- 전문 용어 정확도 향상을 위한 사용자 정의 어휘 사전
- 어디서든 호출하거나 일시 중지할 수 있는 글로벌 단축키

### 📝 오프라인 전사

오디오·비디오 파일을 완전히 온디바이스에서 일괄 전사합니다. 여러 ASR 엔진(Parakeet, Qwen3, FireRed ASR)과 Apple Silicon 최적화 MLX 추론으로 서버에 오디오를 전송하지 않고도 정확한 자막을 생성합니다.

### ✂️ 스마트 침묵 제거

VAD 기반 무음 감지로 팟캐스트, 인터뷰, 강의 녹음의 불필요한 침묵을 자동으로 식별하고 일괄 제거합니다. 러프 컷이 납품 가능한 상태에 훨씬 빠르게 도달합니다.

### 👥 화자 분리

녹음에서 여러 화자를 자동으로 식별하고 레이블을 붙입니다. Sortformer와 Silero VAD 모델이 온디바이스에서 실행되어 인터뷰, 패널, 회의록에 화자 정보가 포함된 구조화된 전사문을 생성합니다.

### 🔊 TTS 음성 합성 — 네 가지 모드

| 모드 | 설명 |
|---|---|
| **프리셋 음성** | 내장 다국어 음성 라이브러리, 즉시 사용 가능 |
| **음성 클론** | 참조 오디오를 업로드하여 화자의 음색과 리듬 재현 |
| **감정 제어** | 텍스트 프롬프트로 지정된 화자의 감정과 스타일 조정 |
| **음성 디자인** | 텍스트로 음성 특성을 기술하여 완전히 독창적인 페르소나 합성 |

모든 TTS 추론은 MLX를 통해 온디바이스에서 실행됩니다. 오디오 데이터는 클라우드로 전송되지 않습니다.

### 🌐 AI 교정 및 번역

문맥 기반 전사문 교정 후 온디바이스 또는 Apple 번역을 통한 다국어 출력. 도구 전환 없이 글로벌 시청자를 위한 콘텐츠를 제작할 수 있습니다.

### ⭐ 하이라이트 감지

녹음에서 가장 중요한 문장과 주목할 만한 순간을 자동으로 찾아 타임라인에 표시합니다. 편집 및 게시 작업이 더 빠르게 진행됩니다.

---

## 내보내기 형식

Cliptate는 이미 사용 중인 툴로 직접 내보냅니다:

| 형식 | 용도 |
|---|---|
| **FCPXML** | Final Cut Pro 타임라인 프로젝트 교환 |
| **SRT** | 범용 자막 배포 |
| **ASS** | 위치 및 스타일 정보가 포함된 자막 |
| **VTT** | 브라우저 및 스트리밍 플랫폼용 웹 자막 |

**Final Cut Pro**, **DaVinci Resolve**, **Adobe Premiere Pro** 호환.

---

## 개인정보 보호 및 보안

- **클라우드 업로드 없음** — 오디오, 비디오, 전사문은 절대 Mac 밖으로 나가지 않습니다
- **API 키 불필요** — 모든 모델은 앱에 포함되거나 첫 사용 시 다운로드됩니다
- **네트워크 독립** — 모델 캐시 후 완전 오프라인 동작
- 민감하거나 기밀적이며 규정 준수가 필요한 콘텐츠에 적합합니다

---

## 시스템 요구 사항

| | |
|---|---|
| **플랫폼** | macOS 14 Sonoma 이상 |
| **아키텍처** | Apple Silicon(M1 이상) 권장 |
| **저장 공간** | 모델 선택에 따라 다름 (전체 모델 세트: 2–8 GB) |

---

## 기술 스택

Cliptate는 Swift로 완전히 구축되어 Apple 네이티브 프레임워크 위에서 실행됩니다:

- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Apple Silicon 최적화 ML 프레임워크(ASR 및 TTS 추론)
- **[AudioKit](https://github.com/AudioKit/AudioKit)** — 오디오 처리 및 파형 렌더링
- **[mlx-audio-swift](https://github.com/ml-explore/mlx-audio-swift)** — VAD, ASR, TTS 모델 통합
- **Apple Translation** — 온디바이스 다국어 번역
- **KeyboardShortcuts** — 글로벌 단축키 관리
- **RevenueCat** — 구독 및 페이월 관리
- **SwiftAssRenderer** — ASS 자막 렌더링

---

## 활용 사례

**팟캐스터 및 인터뷰어** — 침묵 제거, 자막 생성, 게시 가능한 구간 표시를 앱 내에서 완결.

**Vlog 및 숏폼 크리에이터** — 말하는 장면 편집을 더 부드럽게 만들고, 페이싱과 표현에 집중.

**강의 제작자 및 회의 기록자** — 음성 받아쓰기나 일괄 전사로 수 시간의 녹음을 검색·번역·납품 가능한 텍스트 자산으로 변환.

**다국어 콘텐츠 팀** — 음성 클론, 전사문 번역, 더빙 버전 생성을 Mac 한 대로 완성.

---

## 링크

- **웹사이트:** [cliptate.github.io](https://cliptate.github.io)
- **App Store:** [Cliptate 다운로드](https://apps.apple.com/)
- **문의 및 피드백:** [GitHub Issues](https://github.com/cliptate/cliptate.github.io/issues)

---

<div align="center">
  <sub>개인정보 보호, 속도, 전문적인 출력을 중시하는 크리에이터를 위해 만들었습니다.</sub>
</div>
