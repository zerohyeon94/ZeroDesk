# ZeroDesk

iOS/iPadOS 18 이상에서 실행하는 SwiftUI 앱입니다.

## Xcode에서 실행

Xcode 프로젝트는 `project.yml`을 기준으로 XcodeGen이 생성합니다. `ZeroDesk.xcodeproj`는 Git에 포함되지 않으므로 저장소를 처음 받은 뒤 생성해야 합니다.

```sh
# XcodeGen이 없다면 먼저 설치
brew install xcodegen

# 저장소 루트에서 프로젝트 생성 후 열기
xcodegen generate
open ZeroDesk.xcodeproj
```

Xcode 상단에서 `ZeroDesk` scheme과 iPhone 또는 iPad 시뮬레이터를 선택한 뒤 `⌘R`로 실행합니다. 앱 진입점은 `ZeroDesk/ZeroDeskApp.swift`입니다.

실제 기기에서 실행할 때는 `Signing & Capabilities`의 Team을 본인 계정으로 설정합니다. 프로젝트 설정을 변경할 때는 `project.yml`을 수정한 뒤 `xcodegen generate`를 다시 실행합니다.
