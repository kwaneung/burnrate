# 🐱 BurnRate: macOS Status Bar App Specification

`BurnRate`는 개발자와 AI 사용자가 실시간으로 AI API 사용량 및 비용을 모니터링할 수 있도록 돕는 **macOS 네이티브 상태바(Status Bar) 앱**입니다. 

메뉴바에 상주하며, 클릭 시 미니 대시보드를 띄워 연동된 AI 서비스들의 사용량 통계를 시각화합니다. 사용자가 설정한 예산 대비 소진율에 따라 상태바 아이콘의 캐릭터 상태가 역동적으로 변화합니다.

---

## 📌 1. 핵심 기획 요약

*   **형태**: macOS 네이티브 상태바 앱 (100% SwiftUI - macOS 13+ `MenuBarExtra` 사용)
*   **패키지 구조**: Swift Package Manager (SPM) 단일 실행 바이너리 패키지
*   **핵심 기능**:
    *   **상태바 상주**: Dock에 나타나지 않고 macOS 상단 메뉴바에만 표시되는 백그라운드 에이전트.
    *   **실시간 애니메이션**: 자금 소진율(Burn Rate)에 따라 캐릭터(고양이)가 뛰거나 땀 흘리고, 결국 불타는 시각적 효과 제공.
    *   **통합 대시보드 Window**: 클릭 시 각 AI 서비스별 토큰 사용량, 총 누적 요금, 잔여 예산 통계를 원형 게이지와 리스트로 직관적 시각화.
    *   **다중 AI 연동 설정**: 다양한 AI 서비스들의 API 키 등록 또는 로그인을 통해 다중 계정의 실시간 사용량을 한곳에서 확인.
*   **첫 번째 연동 타겟**: **Antigravity CLI (Agentic AI Coding Assistant)**

---

## ⚙️ 2. 시스템 아키텍처 및 연동 개념

```mermaid
graph TD
    A[사용자 macOS 환경] -->|상태바 상주| B(BurnRate macOS App)
    B -->|MenuBarExtra Window| C[SwiftUI Dashboard View]
    B -->|설정 화면| D[SwiftUI Settings View]
    
    %% 연동 대상들
    D -->|1. Antigravity 연동| E[Local Log Monitor]
    F[Antigravity CLI / Agent] -->|사용량 기록| G[(Local Log / JSON)]
    E -->|실시간 파일 모니터링| G
    E -->|데이터 파싱| B
    
    %% 클라우드 API
    D -->|2. Cloud API 연동| H[OpenAI / Anthropic / Gemini Cloud API]
```

### 2.1 연동 개념
*   **로컬 에이전트 연동**: Antigravity CLI 등 로컬에서 실행되는 AI 에이전트의 로그(JSON 등)를 감시하여 사용량과 비용을 실시간 반영합니다.
*   **클라우드 API 연동**: OpenAI, Anthropic 등 주요 AI 서비스의 API 키나 사용자 계정을 등록하여 사용량 API를 직접 호출하거나 통합적으로 모니터링할 수 있도록 확장해 나갑니다.

---

## 🛠️ 3. 빌드, 실행 및 배포 (SPM & Homebrew)

### 3.1 로컬 빌드 및 실행
별도의 Xcode GUI 프로그램 설치 및 실행 없이 터미널에서 다음 한 줄로 빌드와 동시에 실행할 수 있습니다.
```bash
swift run
```

### 3.2 링커를 통한 Info.plist 내장 구조
macOS에서 일반 CLI 실행 파일이 백그라운드 에이전트(`LSUIElement`)로 인식되게 하기 위하여, `Package.swift` 내부에서 링커 플래그 `-sectcreate __TEXT __info_plist` 설정을 통해 빌드 시점에 실행 파일(Executable) 자체에 `Info.plist`가 내장되도록 구성되어 있습니다. 
따라서 별도의 `.app` 패키징 없이 단일 바이너리 상태로도 완벽하게 백그라운드 메뉴바 앱으로 구동됩니다.

### 3.3 Homebrew Package (Formula) 배포 설계
이 앱은 단일 실행 파일로 컴파일되므로, 향후 Homebrew Formula로 배포 시 매우 간편하게 배포할 수 있습니다.
*   **Formula 빌드 커맨드 예시**:
    ```ruby
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/burnrate"
    ```
*   사용자가 `brew install burnrate`를 설치하고 `burnrate`를 실행하면 즉시 백그라운드 메뉴바 앱으로 동작하게 됩니다.
