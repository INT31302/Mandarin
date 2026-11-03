# Mandarin

이미지, 동영상, 오디오와 PDF를 Mac에서 변환하고 다루는 로컬 파일 도구입니다. 파일을 끌어다 놓고 원형 메뉴에서 원하는 작업을 선택합니다.

![Mandarin 파일 변환 화면](docs/images/main.jpg)

파일을 끌어다 놓고 변환 작업을 시작하는 기본 화면입니다.

## 주요 기능

- 이미지, 동영상, 오디오, PDF의 지원 형식 간 변환과 동영상에서 오디오 추출
- 이미지 자르기 및 메타데이터 확인, PDF 페이지 작업과 병합
- 클릭하거나 Shift, Command, Control 키를 사용해 커서 위치에 원형 메뉴 표시
- 변환 파일 저장 위치와 이미지 품질 설정

출력 가능한 형식은 파일 종류와 macOS에서 제공하는 인코더에 따라 달라집니다. 애니메이션·다중 페이지 이미지의 편집 도구에는 제한이 있습니다. 파일 처리는 Mac에서 이루어집니다.

## 요구 사항 및 실행

- macOS 27 이상으로 설정된 프로젝트와 해당 SDK를 지원하는 Xcode

```sh
git clone https://github.com/INT31302/Mandarin.git
cd Mandarin
open Mandarin.xcodeproj
```

Xcode에서 **Mandarin** 스킴과 My Mac을 선택해 실행하세요. 파일을 앱에 놓은 뒤 표시되는 메뉴에서 형식이나 도구를 선택합니다.

## 프로젝트 구성

- `Mandarin/`: SwiftUI 인터페이스, 변환 엔진 및 파일 도구
- `Mandarin.xcodeproj/`: Xcode 프로젝트와 공유 스킴
- `Validation/`, `tests/`: 파일 도구 및 원형 메뉴 관련 검증 코드
