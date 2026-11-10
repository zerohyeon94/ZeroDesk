# ZeroDesk

iOS/iPadOS 18 이상에서 실행하는 SwiftUI 앱입니다.

## Xcode에서 실행

`ZeroDesk.xcodeproj`가 Git에 포함되어 있어 저장소를 받은 뒤 바로 Xcode에서 열 수 있습니다. 최초 실행에는 XcodeGen 설치가 필요하지 않습니다.

```sh
# 저장소 루트에서 프로젝트 열기
open ZeroDesk.xcodeproj
```

Xcode 상단에서 `ZeroDesk` scheme과 iPhone 또는 iPad 시뮬레이터를 선택한 뒤 `⌘R`로 실행합니다. 앱 진입점은 `ZeroDesk/ZeroDeskApp.swift`입니다.

실제 기기에서 실행할 때는 `Signing & Capabilities`의 Team을 본인 계정으로 설정합니다.

## 프로젝트 설정 변경

프로젝트는 `project.yml`을 기준으로 XcodeGen이 생성합니다. 설정을 변경할 때는 `project.yml`을 수정한 뒤 아래 명령을 실행하고, 생성된 `ZeroDesk.xcodeproj` 변경도 함께 커밋합니다. 개인별 Xcode 설정인 `xcuserdata`와 `*.xcuserstate`는 Git에서 제외됩니다.

```sh
# XcodeGen이 없다면 먼저 설치
brew install xcodegen

xcodegen generate
```
