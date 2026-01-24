# SwiftMTP

<div align="center">

<img src="../SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**네이티브 macOS Android MTP 파일 전송 도구**

[![Swift Version](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)

</div>

---

**🌍 언어:** [English](../README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

---

## ✨ 기능

| 기능 | 설명 |
|------|------|
| 🔌 **자동 장치 감지** | 연결된 Android 장치를 자동 감지 |
| 📁 **파일 브라우징** | 장치 파일 시스템을 원활하게 탐색 |
| ⬇️ **파일 다운로드** | 단일 및 일괄 파일 다운로드 지원 |
| ⬆️ **파일 업로드** | 버튼 선택 및 드래그 앤 드롭 파일 업로드 지원 |
| 💾 **대용량 파일 지원** | 4GB 이상 파일 전송 지원 |
| 📦 **일괄 작업** | 파일 일괄 선택 및 처리 |
| 🎨 **모던 UI** | 아름다운 SwiftUI 인터페이스 |
| 📊 **저장소 정보** | 장치 저장소 사용량 표시 |
| 🌍 **다국어 지원** | 간체 중국어, 영어, 일본어, 한국어, 러시아어, 프랑스어, 독일어 지원, 시스템 언어 따름 |

## 📸 앱 스크린샷
![SwiftMTP Logo](cap_2025-12-24%2005.29.36.png)

## 🚀 빠른 시작

### 요구사항

| 의존성 | 버전 |
|------------|---------|
| macOS | 26.0+ (이상) |
| Xcode | 26.0+ |
| Homebrew | 최신 버전 |

### 의존성 설치

```bash
brew install go
```

> 📝 **참고**: libusb-1.0은 애플리케이션에 번들되어 있으므로 수동 설치가 필요하지 않습니다.

### 빌드 및 실행

```bash
# 리포지토리 클론
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# Go 브리지 레이어 빌드
./Scripts/build_kalam.sh

# Xcode에서 열어 실행
open SwiftMTP.xcodeproj
```

> 📝 **참고**: 프로젝트 구성 파일은 버전 관리에 커밋되었습니다. 클론 후 Xcode에서 프로젝트를 열기만 하면 추가 설정 없이 바로 빌드할 수 있습니다.

> 💡 **팁**: Android 장치를 연결한 후 장치에서 **파일 전송 (MTP)** 모드를 선택하여 사용을 시작하세요.

### 설치 패키지 생성

```bash
# 간단한 패키징(개발자 인증서 불필요)
./Scripts/create_dmg_simple.sh

# 완전한 패키징(개발자 인증서 필요)
./Scripts/create_dmg.sh
```

DMG 파일은 `build/` 디렉토리에 생성됩니다.

## 📖 사용자 가이드

### 장치 연결

1. USB를 통해 Android 장치를 Mac에 연결
2. 장치에서 **파일 전송 (MTP)** 모드 선택
3. SwiftMTP가 자동으로 장치를 감지하여 표시

### 파일 작업

| 작업 | 방법 |
|-----------|--------|
| 파일 탐색 | 폴더를 더블 클릭하여 이동, 빵 부스레기 탐색으로 돌아가기 |
| 파일 다운로드 | 파일을 마우스 오른쪽 버튼으로 클릭 → **다운로드** |
| 일괄 다운로드 | 파일을 여러 개 선택 → 마우스 오른쪽 버튼 클릭 → **선택한 파일 다운로드** |
| 파일 업로드 | 도구 모음의 **파일 업로드** 버튼 클릭 또는 파일을 창으로 드래그 앤 드롭 |
| 드래그 앤 드롭 업로드 | 파일을 파일 브라우저 창으로 드래그하여 업로드 |

### 언어 설정

1. **설정** 창 열기（⌘ + ,）
2. **일반** 탭에서 언어 선택
3. 사용 가능한 언어:
   - **시스템 기본값** - macOS 시스템 언어 따름
   - **English** - 영어 인터페이스
   - **中文** - 간체 중국어 인터페이스
   - **日本語** - 일본어 인터페이스
   - **한국어** - 한국어 인터페이스
   - **Русский** - 러시아어 인터페이스
   - **Français** - 프랑스어 인터페이스
   - **Deutsch** - 독일어 인터페이스
4. 앱 내 인터페이스는 즉시 언어가 업데이트됩니다
5. **메뉴 모음 및 파일 선택기**는 앱 재시작이 필요하며 시스템이 즉시 재시작을 안내합니다

## 🏗️ 프로젝트 아키텍처

```
SwiftMTP/
├── Native/                         # Go 브리지 레이어 (Kalam Kernel)
│   ├── kalam_bridge.go            # 메인 브리지 구현 (CGO)
│   ├── libkalam.h                 # C 헤더 (Swift 브리지)
│   ├── go.mod / go.sum            # Go 모듈 의존성
│   └── vendor/                    # Go 의존성 (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # Go 동적 라이브러리 빌드
│   ├── create_dmg.sh              # DMG 패키징 스크립트
│   ├── create_dmg_simple.sh       # 간단한 패키징
│   ├── generate_icons.sh          # 아이콘 생성 스크립트
│   ├── run_tests.sh               # 테스트 실행 스크립트
│   └── SwiftMTP/                  # 리소스 스크립트
│       └── App/Assets.xcassets/   # 앱 아이콘 리소스
├── SwiftMTP/                      # Swift 애플리케이션
│   ├── App/                       # 앱 진입점
│   │   ├── SwiftMTPApp.swift      # 앱 진입점
│   │   ├── Info.plist             # 앱 구성
│   │   ├── Assets.xcassets/       # 에셋 번들(아이콘)
│   │   └── Resources/             # 앱 리소스
│   │       └── SwiftMTP_Logo.svg  # 앱 로고
│   ├── Models/                    # 데이터 모델
│   │   ├── Device.swift           # 장치 모델
│   │   ├── FileItem.swift         # 파일 모델
│   │   ├── TransferTask.swift     # 전송 작업 모델
│   │   └── AppLanguage.swift      # 언어 모델
│   ├── Services/                  # 서비스 레이어
│   │   ├── MTP/                   # MTP 서비스
│   │   │   ├── DeviceManager.swift    # 장치 관리
│   │   │   ├── FileSystemManager.swift# 파일 시스템
│   │   │   └── FileTransferManager.swift # 전송 관리
│   │   ├── LanguageManager.swift  # 언어 관리자
│   │   └── LocalizationManager.swift # 현지화 관리자
│   ├── Views/                     # SwiftUI 뷰
│   │   ├── MainWindowView.swift   # 메인 창
│   │   ├── DeviceListView.swift   # 장치 목록
│   │   ├── FileBrowserView.swift  # 파일 브라우저
│   │   ├── FileTransferView.swift # 전송 뷰
│   │   ├── SettingsView.swift     # 설정 창
│   │   └── Components/            # 재사용 가능한 컴포넌트
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # 리소스 파일
│   │   ├── Kalam.bundle/          # Go 동적 라이브러리 번들
│   │   │   └── Contents/MacOS/Kalam
│   │   ├── Base.lproj/            # 기본 언어 팩(영어)
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # 영어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # 간체 중국어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # 일본어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ko.lproj/              # 한국어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ru.lproj/              # 러시아어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── fr.lproj/              # 프랑스어 언어 팩
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── de.lproj/              # 독일어 언어 팩
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Go 동적 라이브러리
│   ├── libkalam.h                 # C 헤더 파일
│   └── SwiftMTP-Bridging-Header.h # Swift-C 브리지 헤더
├── SwiftMTPTests/                 # Swift 단위 테스트
│   ├── AppLanguageTests.swift
│   ├── DeviceTests.swift
│   ├── FileBrowserViewTests.swift
│   ├── FileItemTests.swift
│   ├── FileSystemManagerTests.swift
│   ├── FileTransferManagerTests.swift
│   ├── LanguageManagerTests.swift
│   ├── SwiftMTPTests.swift
│   └── TransferTaskTests.swift
├── docs/                          # 프로젝트 문서
│   ├── sequence-diagrams.md       # 시퀀스 다이어그램 문서
│   ├── TESTING.md                 # 테스트 문서
│   └── WIKI.md                    # 프로젝트 Wiki
├── build/                         # 빌드 출력 디렉토리
├── .github/workflows/             # GitHub Actions
│   └── test.yml                   # CI 테스트 구성
└── SwiftMTP.xcodeproj/            # Xcode 프로젝트
```

### 기술 스택

- **언어**: Swift 6+, Go 1.22+
- **UI 프레임워크**: SwiftUI
- **MTP 라이브러리**: go-mtpx (libusb-1.0 기반)
- **아키텍처 패턴**: MVVM
- **브리지 방법**: CGO
- **국제화**: Swift 현지화 프레임워크 (NSLocalizedString)

## ⚠️ 알려진 제한사항

1. USB 장치에 액세스하려면 샌드박스를 비활성화해야 합니다
2. 전송 속도는 MTP 프로토콜 제한을 받습니다
3. 현재 단일 파일 업로드만 지원합니다(폴더 업로드 미지원)
4. Swift 단위 테스트가 불완전하고 추가 개발이 필요합니다
5. Liquid Glass UI 구현이 불완전하고 버그가 있어 수정이 필요합니다
6. 코드베이스 개선을 도와줄 많은 기여자를 환영합니다

## 🔧 문제 해결

### 장치가 감지되지 않음

```
✓ 장치가 MTP 모드인지 확인
✓ USB 케이블을 분리했다가 다시 연결해 보세요
✓ 앱 재시작
✓ USB 케이블이 데이터 전송을 지원하는지 확인
```

### 빌드 오류

```bash
# Go 브리지 레이어 재빌드
./Scripts/build_kalam.sh

# 정리 후 재빌드
xcodebuild clean
xcodebuild
```

## 🤝 기여

Issue와 Pull Request를 환영합니다!

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 라이선스가 부여됩니다 - 자세한 내용은 [LICENSE](../LICENSE) 파일을 참조하세요.

---

<div align="center">

**이 프로젝트가 도움이 되셨다면 ⭐ Star로 응원해 주세요!**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>