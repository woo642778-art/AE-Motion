# AE Motion 2.0+ 통합 제품·엔진 로드맵

작성일: 2026-07-13  
기준 버전: v2.0.1 Beta 13  
문서 목적: Host Extension 안정화 이후, AE Motion을 장기적으로 전문 모바일 편집·합성 플랫폼으로 발전시키기 위한 통합 설계 기준

---

## 문서 개정 기록

- v4: Tutorials, 커스텀 이펙트 패키지, 3D·파티클, 전문 Matte, Asset Library, 반사·굴절·물리, AI Model Manager, Composite Workspace, AI Beat Edit, AE Project Bridge 요구사항을 통합했다.
- v5: 다음 안정화 릴리스를 `v2.0.1 — Preset Studio Navigation & Apply Pipeline Stabilization`으로 지정했다. Preset Studio의 돌아가기 동작, 미저장 변경 보호, Apply Preset 대상 선택·호환성 검사·미리보기·원자적 적용·롤백·진단을 추가했다.
- v6: 실제 기기 검증 결과를 반영해 v2.0의 확인된 문제를 `Preset Studio 돌아가기 버튼 부재`와 `Apply Preset 영역의 비정상 동작` 두 건으로 한정했다. 그 외 v2.0 기능은 정상 동작으로 기록하고, v2.0.1에서 관련 없는 기능을 재설계하지 않도록 범위를 잠갔다.
- v7: v2.0.1 Beta 13 패키징 상태를 반영하고, 다음 릴리스를 `v2.0.2 — Native UI Integration, Feature Placement & Visual Polish`로 지정했다. 신규 기능을 Extensions & Scripts에 집중시키지 않는 배치 원칙, Alight Motion 시각 언어 정렬, 빈 배경·검은 미완성 영역·empty state 정리를 추가했다.
- 별도 메모의 4번 항목은 요청에 따라 이번 개정에서 제외했다.
- 기존 v2.0 BCC 검색·카테고리 수정 기록은 실제 구현 상태이므로 유지한다.

---


## 0. 핵심 결론

AE Motion의 장기 경쟁력은 효과 개수보다 다음 기반에서 결정된다.

1. **프로젝트가 절대 쉽게 손상되지 않는 신뢰성**
2. **모든 속성이 같은 방식으로 키프레임화되는 통합 애니메이션 엔진**
3. **프록시·캐시·렌더 큐·메모리 예산을 포함한 모바일 성능 구조**
4. **트래킹·마스크·매트·채널·알파가 서로 연결되는 합성 구조**
5. **사용자 프리셋·템플릿·플러그인 생태계**
6. **전문 출력·색관리·오디오·텍스트·데스크톱 교환**
7. **맵·시간·벡터를 입력받는 범용 고급 이펙트 엔진**

대표 제품 기능은 다음 세 가지로 유지한다.

- **Professional Velocity**
- **Universal Tracking**
- **Object Matte Studio**

다만 이 세 기능보다 먼저 또는 동시에 준비해야 할 기반은 다음이다.

- Project Schema
- Autosave·History·Recovery
- Unified Property System
- Render Graph
- Proxy·Cache
- Track Matte·Alpha Pipeline
- Render Queue
- Diagnostics·Project Doctor

AI 기능이나 화려한 이펙트가 이 기반보다 먼저 대규모로 들어가면, 기능은 많지만 장시간 실제 프로젝트에 사용할 수 없는 앱이 된다.

---

## 1. 제품 구조

현재 AE Motion은 Alight Motion 내부에 주입되는 **Host Extension**이다. 이 구조는 기존 앱을 확장하는 데 유리하지만, Alight Motion의 private 타임라인·프로젝트 모델을 안정적으로 통제할 수 없다.

따라서 제품을 두 계층으로 나눈다.

### 1.1 Host Extension

현재 Alight Motion 내부에서 작동한다.

- Add Effects 확장
- BCC 검색과 메타데이터 보정
- Speed Remap Studio
- Person Cutout Studio
- Depth Map Studio
- Dead Frame Cleaner
- 프리셋 제작·가져오기·내보내기
- 리소스 허브
- 외부 렌더 도구
- 진단 로그
- AI Upscale·Repair 같은 독립형 처리 도구

Host Extension에서는 Alight Motion 프로젝트 데이터베이스를 추측해서 직접 수정하지 않는다. 가능한 작업은 별도 렌더 결과 생성, 안전한 UI 확장, 프리셋 관리, 리소스 접근, 진단에 한정한다.

### 1.2 AE Motion Studio Core

자체 프로젝트 파일과 렌더링 엔진을 가진 독립 편집 계층이다.

- 타임라인
- 레이어·트랙·노드
- 모든 속성의 키프레임
- 속도 리매핑
- 트래킹 데이터
- Null·Parenting
- Adjustment Layer
- Pre-compose
- Track Matte·Blend Mode·Channel
- 전문 텍스트
- 색관리·색보정·Scopes
- 오디오 믹서
- 자막·대본 편집
- 렌더 큐
- 2.5D·3D 모델
- 프로젝트 패키지
- 플러그인 SDK
- 데스크톱 교환

### 1.3 공통 포맷

Host Extension과 Studio Core는 다음 형식을 공유한다.

- `PresetDocument`
- `AnimatableProperty`
- `KeyframeCurve`
- `DependencyManifest`
- `TrackingData`
- `MaskDocument`
- `RenderJob`
- `EffectDescriptor`
- `ColorPipelineDescriptor`
- `ProjectPackageManifest`
- `EffectPackageManifest`
- `AssetDescriptor`
- `TutorialPackageManifest`
- `AIModelDescriptor`
- `RenderPassDescriptor`

---

## 2. 현재 상태

| 기능 | 상태 | 처리 |
|---|---|---|
| Speed Remap Studio | 부분 구현 | 별도 영상 렌더 방식 유지. Studio Core에서 직접 타임라인 속도 리매핑 구현 |
| 속도 그래프 | 부분 구현 | v2.2에서 범용 그래프 엔진으로 교체 |
| Person Cutout | 부분 구현 | v2.4 Object Matte의 초기 기반으로 사용 |
| Selection Tracking | 부분 구현 | v2.4 범용 TrackingData로 마이그레이션 |
| Dead Frame Cleaner | 구현됨 | Optical Flow·Repair 파이프라인과 연결 |
| Depth Map Studio | 부분 구현 | v3.0에서 실제 Core ML depth 모델로 교체 |
| Render 100% 충돌 수정 | 구현됨 | 회귀 테스트 유지 |
| 렌더 취소·중복 방지·임시 파일 정리 | v1.9.2 구현 | 공통 Task Scheduler로 확장 |
| BCC 검색 별칭 | v1.9.2 구현 | 실제 기기 검증 후 완료 처리 |
| Add Effects: Move/Transform 카테고리 누락 | v2.0 Beta 12 패키징 수정 | 실제 기기 카테고리·검색 검증 필요 |
| Add Effects: Distortion/Warp 카테고리 누락 | v2.0 Beta 12 패키징 수정 | 실제 기기 카테고리·검색 검증 필요 |
| Extensions 지연 표시 개선 | v1.9.2 구현 | 실제 기기 검증 후 완료 처리 |
| 사용자 프리셋 플랫폼 | v2.0 Beta 12 구현 | 실제 기기 전체 워크플로 검증 후 완료 처리 |
| 프로젝트 복구·프록시·캐시 | 미구현 | v2.1 |
| Null·Parenting·Pre-compose | 미구현 | v2.3 |
| Track Matte·Blend Mode·Channel | 미구현 | v2.3 |
| 전문 텍스트·템플릿 | 미구현 | v2.5 |
| 색관리·Scopes | 미구현 | v2.6 |
| 오디오 믹서·자막 | 미구현 | v2.7 |
| 렌더 큐·포맷·교환 | 미구현 | v2.8 |
| 전문 작업 공간·성능 분석기 | 미구현 | v2.9 |
| AI Upscale·Noise Reduction | 미구현 | v3.0 |
| 범용 고급 이펙트 엔진 | 미구현 | v3.1~v3.2 |
| Visual Expression·2.5D | 미구현 | v3.3 |
| Paint·Vector·3D 모델 | 미구현 | v3.4 |
| Market·SDK·Remix | 미구현 | v4.0 |
| Asset Library·Smart Asset | 미구현 | v2.10 |
| Project Tutorials·Learn Hub | 미구현 | v2.10 기반, v4.2 커뮤니티 확장 |
| 3D Particle·Render Pass | 미구현 | v3.5 |
| Reflection·Refraction·Physics | 미구현 | v3.6 |
| AI Model Manager | 미구현 | v3.0 |
| AE Project Bridge | 미구현 | v2.8 교환 기반, v4.3 고급 호환 |

---

# 3. 릴리스 로드맵

## v2.0 — Preset Platform, Macro Controls & Resource Hub

### 목표

현재 정적인 Presets 화면을 실제로 제작·편집·검증·적용·공유할 수 있는 플랫폼으로 교체한다. 이후 모든 기능이 같은 프리셋 포맷을 사용하도록 기반을 확정한다.

### 공개 스키마

XML 기반 `PresetDocument 1.0`을 사용한다.

필수 메타데이터:

- preset ID
- 이름
- 설명
- 제작자
- 생성·수정 시각
- 스키마 버전
- 최소 앱 버전
- 대상 도구·효과
- 카테고리
- 태그
- 즐겨찾기 상태
- 미리보기 이미지
- 필요한 폰트
- 필요한 효과
- 필요한 미디어
- 필요한 AI 모델
- 지원 해상도·프레임레이트
- 지원 색심도
- 호환되지 않는 기능
- 라이선스와 출처

### 프리셋 타입

- Effect Preset
- Motion Preset
- Velocity Preset
- Graph Preset
- Color Preset
- Text Animation Preset
- Transition Preset
- Effect Group Preset
- Audio Reactive Preset
- Editable Template
- Edit Recipe

### 제작기

사용자가 다음 파라미터를 UI에서 자유롭게 생성한다.

- Number
- Integer
- Toggle
- Enum
- Color
- Text
- Angle
- Point
- Size
- Rectangle
- Gradient
- Curve
- Keyframes
- Layer Reference
- Mask Reference
- External Map Reference
- Audio Band Reference
- Seed
- Quality Level

### 관리 기능

- Import
- Export
- Duplicate
- Rename
- Delete
- Tags
- Favorites
- Search
- Sort
- Collections
- 최근 사용
- 사용 횟수
- 호환성 경고
- 손상된 프리셋 격리
- 알 수 없는 필드 보존
- 스키마 마이그레이션
- 프리셋 차이 비교

### Macro Controls

복잡한 효과 내부 파라미터를 몇 개의 매크로로 노출한다.

예시 `Cinematic Shake`:

- Strength
- Speed
- Impact
- Blur
- Seed

모드:

- **Easy:** 매크로만 표시
- **Advanced:** 내부 효과·곡선·매핑 공개

매크로는 한 파라미터를 여러 속성에 연결하고, 범위 매핑·반전·곡선·Clamp를 지원한다.

### 실제 적용 어댑터

v2.0에서는 다음 세 종류 이상을 실제로 적용한다.

- Speed Remap preset
- Easing/Graph preset
- Shake/Motion preset
- Color preset
- Text preset

### Editable Template 기반

- 제작자가 노출할 속성 선택
- 문구·색상·미디어 교체 허용 범위 설정
- 편집 불가 속성 잠금
- Responsive Time
- 인트로·아웃트로 보호 구간
- 중앙 반복·늘이기 구간
- Smart Replace용 미디어 슬롯
- 폰트·효과·해상도 의존성 검사

### Resource Hub

- DaFont 바로가기
- 폰트별 라이선스 확인 안내
- Keyframe/편집 리소스 링크
- 자주 쓰는 도구 즐겨찾기
- 링크 카테고리
- 안전한 외부 브라우저 전환
- 오프라인 설명 카드
- 링크 오류 신고

### Add Effects 카테고리 무결성 수정

v2.0의 기능 추가보다 먼저 다음 기존 카테고리 표시 오류를 릴리스 차단 버그로 처리한다.

- `Move/Transform` 카테고리에 등록된 효과가 목록에 나타나지 않는 현상
- `Distortion/Warp` 카테고리에 등록된 효과가 목록에 나타나지 않는 현상

수정 범위:

- 원본 효과 XML의 `category`, `tags`, effect ID를 변경 전·후로 비교
- Alight Motion이 실제로 인식하는 내부 카테고리 키와 표시 이름을 분리해 매핑
- `/`, 공백, 대소문자, 복수형, 이전 카테고리 이름에 대한 정규화
- `Move`, `Transform`, `Move/Transform`을 동일 검색 그룹으로 처리
- `Distortion`, `Warp`, `Distort`, `Distortion/Warp`를 동일 검색 그룹으로 처리
- 사용자 효과와 내장 효과가 같은 카테고리에 함께 노출되도록 병합
- Extensions 인덱스 프록시가 원본 카테고리 index path를 잘못 이동시키지 않는지 검증
- 카테고리를 열었을 때 effect count가 0이면 진단 로그에 다음을 기록
  - 원본 category 문자열
  - 정규화된 category key
  - 검색 인덱스 등록 여부
  - 필터 전·후 효과 수
  - 중복 ID 또는 파싱 실패 파일
- 알 수 없는 카테고리를 무조건 다른 카테고리로 이동시키지 않고 `Other/Imported` fallback 제공
- XML 정규화 스크립트는 두 번 실행해도 추가 변경이 생기지 않는 멱등성을 유지
- 검색 결과와 카테고리 탐색 결과가 동일한 effect ID 집합을 반환하도록 통합 인덱스 사용

회귀 테스트:

1. Add Effects에서 `Move/Transform`을 열었을 때 해당 효과가 표시된다.
2. Add Effects에서 `Distortion/Warp`를 열었을 때 해당 효과가 표시된다.
3. `Move`, `Transform`, `Distortion`, `Distort`, `Warp` 검색으로 같은 효과를 찾을 수 있다.
4. `BCC`, `BBC`, `BorisFX`, `Continuum` 검색 수정이 유지된다.
5. Repeat, Favorites, Recent, Extensions 카테고리의 index path가 밀리지 않는다.
6. 빈 카테고리, 중복 효과, 잘못된 XML이 있어도 Add Effects가 종료되지 않는다.
7. 앱 재실행 후에도 카테고리 결과가 동일하다.

### 완료 조건

- `Move/Transform` 카테고리의 효과가 정상 표시되고 검색 결과와 일치
- `Distortion/Warp` 카테고리의 효과가 정상 표시되고 검색 결과와 일치
- 카테고리 정규화 후 Repeat·Favorites·Recent·Extensions의 index path 회귀 없음
- UI만으로 프리셋 생성 가능
- Export→Import 후 값·곡선·의존성이 동일
- 깨진 XML로 앱이 종료되지 않음
- 최소 3개 실제 도구에 프리셋 적용
- 매크로와 Advanced 설정이 양방향으로 동기화
- 이전 버전 프리셋이 마이그레이션됨

### 제외

- 온라인 마켓
- 결제
- 네이티브 플러그인 실행
- Alight Motion private 타임라인 직접 수정
- 전체 프로젝트 공유

---

## v2.0.1 — Preset Studio Navigation & Apply Pipeline Stabilization

### 목표

v2.0 Beta 12의 실제 기기 검증에서 확인된 문제는 다음 두 건뿐이다.

1. Preset Studio에 명확한 돌아가기 버튼이 없음
2. `Apply Preset` 영역의 버튼·화면·적용 동작이 비정상적임

이 두 항목만 수정한다. 사용자가 별도로 문제를 보고하지 않은 v2.0 기능은 정상 동작으로 간주하며, v2.0.1에서 구조를 바꾸거나 다시 구현하지 않는다. 관련 기능은 수정으로 인한 회귀가 없는지만 확인한다.

### 확정된 수정 범위

수정 대상:

- Preset Studio의 Back·Close navigation
- `Apply Preset` 화면 구성
- Apply 버튼의 action 연결
- preset 선택 상태
- 지원 도구 adapter 선택
- 실제 설정값 전달
- 적용 완료 후 UI 갱신
- 적용 실패 시 오류 표시

수정 대상이 아닌 항목:

- Add Effects 카테고리
- BCC 검색
- Extensions 표시 시점
- Render & Return
- 렌더 취소·메모리 제한·임시 파일 정리
- Preset XML Import·Export
- Duplicate·Rename·Tags·Favorites
- Resource Hub
- DaFont·Keyfla.me 링크
- Speed Remap·Depth·Cutout·Dead Frame의 기존 렌더 동작

위 항목들은 현재 정상으로 확인되었으므로, v2.0.1에서는 기능 변경 없이 smoke test와 회귀 테스트만 수행한다.

### 돌아가기 버튼과 화면 계층

모든 Preset Studio 화면 왼쪽 상단에 시스템 규칙을 따르는 명확한 Back 또는 Close 버튼을 제공한다.

화면별 동작:

- Preset 상세·편집 화면 → Preset 목록
- Macro 편집 화면 → Preset 편집 화면
- Apply Preview·Diff 화면 → 이전 Preset 상세 화면
- Import 검토 화면 → Preset 목록
- Preset Studio 루트 화면 → `Extensions & Scripts`
- 모달로 표시된 화면 → 현재 모달만 닫기
- Navigation Controller로 표시된 화면 → 한 단계만 pop

구현 규칙:

- 같은 버튼이 여러 화면을 한꺼번에 dismiss하지 않도록 현재 presentation context를 판별한다.
- 화면을 닫은 뒤 Preset 목록의 검색어, 필터, 정렬, 스크롤 위치, 선택 항목을 복원한다.
- navigation stack에 동일 화면이 중복으로 쌓이지 않게 한다.
- 안전 영역, Dynamic Type, VoiceOver label, 충분한 터치 영역을 적용한다.
- 가능한 화면에서는 iOS edge-swipe back 제스처를 지원하되, 커브·슬라이더 편집 제스처와 충돌하지 않게 한다.

### 미저장 변경 보호

편집 중 Back 또는 Close를 누르면 변경 상태를 검사한다.

선택지:

- **Save & Go Back**
- **Discard Changes**
- **Cancel**

규칙:

- 실제 변경이 없으면 확인창 없이 즉시 돌아간다.
- 저장 실패 시 화면을 닫지 않고 오류 원인을 표시한다.
- Import 중 생성된 임시 파일은 취소·실패 시 제거한다.
- 앱이 background로 이동하거나 메모리 경고를 받아도 편집 초안을 임시 복구 파일로 보존한다.
- 비정상 종료 후 Preset Studio를 다시 열면 복구 가능한 초안을 제안한다.

### Apply Preset 검토 원칙

아래 항목은 모두 실제 버그로 확정된 목록이 아니다. `Apply Preset`이 이상하게 보이거나 작동하는 정확한 원인을 찾기 위한 점검 순서다. 코드와 기기 동작으로 확인된 원인만 수정하며, 정상인 부분은 유지한다.

### Apply Preset 파이프라인 재설계

`Apply Preset`을 단일 버튼 콜백으로 처리하지 않고 다음 단계로 분리한다.

```text
Select Target
→ Resolve Adapter
→ Validate Compatibility
→ Resolve Dependencies
→ Build Change Set
→ Preview Differences
→ Atomic Commit
→ Refresh Target UI
→ Record Result
```

#### 1. Select Target

- 현재 열려 있는 도구를 우선 대상 후보로 제시한다.
- 지원 대상이 여러 개면 사용자가 명시적으로 선택한다.
- 대상이 없으면 Apply 버튼을 비활성화하고 `Open Compatible Tool`을 제공한다.
- Speed Remap preset을 Color Palette에 적용하는 것처럼 타입이 다른 적용을 허용하지 않는다.
- 마지막으로 사용한 대상은 편의 기능으로만 기억하며 자동 확정하지 않는다.

지원 어댑터:

- Speed Remap
- Easing Curve
- Camera Shake
- Color Palette

#### 2. Resolve Adapter

각 프리셋은 명시적 `PresetTarget`과 adapter ID를 가진다.

- 프리셋 target과 실제 도구 target이 일치해야 한다.
- adapter가 없으면 유사 어댑터로 조용히 대체하지 않는다.
- 지원하지 않는 preset type은 `Unsupported in this version`으로 표시한다.
- adapter version이 맞지 않으면 migration 가능 여부를 검사한다.
- 동일 target의 여러 adapter가 발견되면 우선순위를 추측하지 않고 오류로 처리한다.

#### 3. Validate Compatibility

Apply 전에 다음을 검사한다.

- schema version
- minimum app version
- target tool
- parameter type
- required parameter
- numeric range
- enum case
- color format
- curve domain
- keyframe time range
- macro binding
- required effect
- required font
- required media
- required AI model

처리 원칙:

- 누락된 선택 파라미터는 명시된 default 사용
- 누락된 필수 파라미터는 적용 차단
- 알 수 없는 확장 필드는 보존하되 실행에는 사용하지 않음
- 범위를 벗어난 값은 사용자 동의 없이 자동 Clamp하지 않음
- Clamp가 허용된 필드만 수정값을 Preview에 표시
- 적용 불가능한 의존성은 정확한 파일·효과·폰트 이름과 함께 표시

#### 4. Build Change Set

현재 도구 설정과 프리셋 값을 비교해 변경 목록을 만든다.

각 항목:

- property ID
- 기존 값
- 적용 예정 값
- 값의 출처
- macro에 의해 계산된 값
- Clamp 또는 migration 여부
- 적용 가능 여부
- 경고

현재 설정을 직접 변경하기 전에 immutable snapshot을 생성한다.

#### 5. Preview Differences

Apply 직전에 다음을 표시한다.

- 변경되는 값
- 유지되는 값
- 무시되는 값과 이유
- 누락 의존성
- migration 결과
- macro 계산 결과
- 예상 적용 대상
- 대상 도구 이름

버튼:

- **Apply**
- **Apply & Close**
- **Cancel**

변경점이 하나도 없으면 Apply를 실행하지 않고 `No Changes`를 표시한다.

#### 6. Atomic Commit과 Rollback

- 모든 변경을 하나의 transaction으로 적용한다.
- 중간 단계에서 하나라도 실패하면 전체를 이전 snapshot으로 되돌린다.
- UI에 일부 값만 적용된 반쪽 상태를 허용하지 않는다.
- Apply 중 버튼을 반복해서 눌러도 작업은 한 번만 실행한다.
- 적용 성공 후 Undo 가능한 단일 작업으로 기록한다.
- 적용 실패 후 대상 도구를 다시 열 필요 없이 즉시 재시도할 수 있게 한다.

#### 7. Target UI Refresh

적용 성공 후 다음이 실제로 갱신되어야 한다.

- 슬라이더
- 텍스트 값
- 선택 메뉴
- 그래프
- 미리보기
- 렌더 예상 시간
- 현재 preset 표시
- dirty state
- Undo history

데이터 모델만 바뀌고 화면은 이전 값을 보여주는 상태를 허용하지 않는다.

### 도구별 적용 검토

#### Speed Remap

- speed point 시간 정렬
- 중복 시간 keyframe 병합 규칙
- 0배속·음수 속도 허용 여부
- reverse segment
- curve handle
- pitch preserve
- audio mode
- source duration 밖 keyframe 차단
- 프리셋 적용 후 그래프 재계산

#### Easing Curve

- curve domain을 0...1로 정규화
- 시작점 `(0,0)`과 끝점 `(1,1)` 검증
- handle overshoot 허용 정책
- non-monotonic curve 경고
- 기존 그래프와 교체·병합 선택
- Apply 후 preview animation 갱신

#### Camera Shake

- amplitude
- frequency
- rotation
- scale
- blur
- seed
- duration
- coordinate space
- random seed 재현성
- 현재 설정에 Add 또는 Replace 선택
- 프레임레이트 변경 시 주파수 일관성

#### Color Palette

- 색상 문자열 파싱
- 색공간 메타데이터
- alpha
- 색상 개수
- 기존 팔레트 Replace·Append 선택
- 중복 색상 처리
- Display P3→현재 작업 색공간 변환 경고
- 적용 후 swatch와 preview 갱신

### Macro 적용 검토

- macro 계산은 항상 저장된 base parameter에서 시작한다.
- 슬라이더를 왕복해도 값이 누적 변형되지 않아야 한다.
- Easy→Advanced 전환 시 실제 계산된 값을 표시한다.
- Advanced 값을 직접 수정하면 macro 상태를 재계산하거나 `Custom`으로 표시한다.
- 하나의 parameter에 여러 macro가 연결된 경우 계산 순서를 명시한다.
- NaN, Infinity, divide-by-zero를 적용 전에 차단한다.
- 범위 매핑·반전·curve·Clamp 순서를 스키마에 고정한다.

### Import 후 Apply 검증

- Export한 프리셋을 다시 Import한 뒤 동일한 결과를 생성해야 한다.
- migration된 프리셋은 원본과 변경점을 표시한다.
- Quarantine에서 복구된 프리셋은 적용 전 전체 검증을 다시 수행한다.
- 같은 preset ID가 있으면 Replace·Keep Both·Cancel을 선택한다.
- `Keep Both`는 새 UUID를 생성하되 원본 provenance를 기록한다.

### 진단 로그

Apply 한 번마다 다음을 기록한다.

- preset ID·schema version
- preset type
- target tool
- selected adapter·adapter version
- validation result
- dependency result
- change count
- ignored field count
- migrated field count
- apply start·end time
- success·rollback
- UI refresh result
- 오류 단계와 메시지

민감한 사용자 텍스트·파일 내용은 기본 로그에 포함하지 않는다.

### 회귀 테스트

확인된 두 문제에 대한 필수 테스트:

1. Preset Studio 루트에서 Back을 누르면 `Extensions & Scripts`로 돌아간다.
2. 편집·상세·Apply 화면에서 Back을 누르면 정확히 한 단계만 이동한다.
3. Apply 버튼이 현재 선택된 프리셋과 대상 도구에 연결된다.
4. Speed Remap, Easing Curve, Camera Shake, Color Palette에서 각각 실제 값이 적용된다.
5. Apply 후 슬라이더·그래프·팔레트·미리보기가 즉시 갱신된다.
6. 지원되지 않는 대상에서는 명확한 오류가 표시되고 값은 바뀌지 않는다.
7. Apply 버튼을 빠르게 여러 번 눌러도 중복 적용되지 않는다.
8. 적용 실패 시 이전 값이 유지된다.

기존에 정상 동작한 v2.0 기능의 smoke test:

9. Preset 생성·Import·Export가 기존과 동일하게 작동한다.
10. Duplicate·Rename·Tags·Favorites가 기존과 동일하게 작동한다.
11. Resource Hub 링크가 기존과 동일하게 작동한다.
12. Move/Transform, Distortion/Warp, BCC 검색 결과가 유지된다.
13. v1.9.2 렌더 안정화 기능에 회귀가 없다.

### 완료 조건

- Preset Studio에서 명확한 Back·Close 버튼으로 이전 화면에 복귀
- `Apply Preset` UI의 버튼·대상 표시·상태 표시가 일관됨
- 지원 네 adapter에서 프리셋 값이 실제 도구에 정확히 반영됨
- Apply 후 대상 UI가 즉시 갱신됨
- 실패 시 기존 설정이 유지되고 원인이 표시됨
- 기존에 정상 동작한 v2.0 기능에 회귀 없음
- 실제 iPhone에서 네 adapter를 반복 적용해 강제 종료 0회

### 제외

- 새로운 preset type 추가
- 온라인 preset market
- Alight Motion private timeline 직접 수정
- 범용 키프레임 시스템
- AI preset
- 플러그인 SDK

---

## v2.0.2 — Native UI Integration, Feature Placement & Visual Polish

### 목표

AE Motion 기능이 Alight Motion 위에 별도로 붙은 도구 모음처럼 보이지 않게 한다. 신규 기능을 `Extensions & Scripts`에 일괄 수용하는 구조를 중단하고, 기능의 작업 맥락에 맞는 위치로 분산한다. 동시에 AE Motion 화면의 색상·간격·컨트롤·전환·empty state를 Alight Motion의 시각 언어에 맞춰 정리한다.

이 릴리스의 핵심은 새로운 편집 기능 추가가 아니라 다음 세 가지다.

1. **기능 배치 아키텍처 재정의**
2. **Alight Motion 스타일 UI 통합**
3. **빈 화면·검은 여백·미완성 상태 제거**

### 제품 원칙: Extensions & Scripts는 허브이지 모든 기능의 수납장이 아니다

`Extensions & Scripts`는 다음 용도로 제한한다.

- 독립형 유틸리티
- 파일 Import·Export
- 진단과 복구
- Preset·Resource 관리
- 실험적 기능
- 작업 맥락이 없는 전역 도구
- 고급 사용자를 위한 전체 기능 디렉터리

다음 기능은 기본적으로 해당 작업 위치에 배치한다.

| 기능 유형 | 기본 배치 위치 |
|---|---|
| 타임라인 편집 | 타임라인 왼쪽 도구 영역 또는 상단 툴바 |
| 선택 레이어 대상 기능 | 레이어 컨텍스트 메뉴·레이어 속성·Inspector |
| 뷰어 조작 | Viewer 상단 또는 오버레이 도구 |
| 효과 관련 기능 | Add Effects 또는 효과 상세 화면 |
| 속도·그래프 | 속도 메뉴, Graph Editor 진입점 |
| 트래킹·마스크 | Mask·Tracking 관련 컨텍스트 영역 |
| 색보정 | Color·Adjustment 관련 진입점 |
| 오디오 | Audio 도구 및 클립 오디오 메뉴 |
| 프로젝트 전역 기능 | 프로젝트 메뉴 또는 상단 More 메뉴 |
| 독립 변환·복구 유틸리티 | Extensions & Scripts |

### 기능 배치 결정 규칙

신규 기능마다 다음 순서로 배치 위치를 결정한다.

1. 현재 선택 대상이 필요한가?
2. 타임라인, Viewer, Layer, Effect 중 어디와 가장 직접적으로 연결되는가?
3. 사용자가 해당 작업을 수행하는 순간 자연스럽게 찾을 위치는 어디인가?
4. 상시 노출이 필요한가, 컨텍스트가 있을 때만 표시해야 하는가?
5. 기존 Alight Motion 버튼과 충돌하거나 화면을 가리지 않는가?
6. 기기 크기·가로세로 모드·Dynamic Type에서 공간이 유지되는가?
7. 안전하게 hook할 수 없는 영역이면 무리하게 삽입하지 않고 fallback 메뉴를 제공하는가?

### v2.0.2 우선 배치 변경

- Preset Studio:
  - Extensions & Scripts 진입점 유지
  - 각 지원 도구 내부에 `Presets` 또는 preset 아이콘 추가
  - 현재 도구와 호환되는 preset만 표시
- Speed Remap:
  - 타임라인 또는 속도 관련 메뉴에 직접 진입점 제공
- Easing Curve:
  - 그래프·키프레임 관련 화면에서 직접 진입
- Camera Shake:
  - 선택 레이어의 Motion·Transform 컨텍스트에서 진입
- Color Palette:
  - 색상 선택기·Color 관련 화면에서 진입
- Cutout·Depth·Tracking:
  - 선택 미디어가 있을 때 레이어 도구 또는 Viewer 도구로 노출
- Dead Frame Cleaner:
  - 클립 진단·복구 컨텍스트 메뉴에 배치
- Diagnostics·Resource Hub:
  - Extensions & Scripts에 유지

동일 기능은 필요할 경우 두 곳에 진입점을 가질 수 있지만, 실제 상태와 controller는 하나를 사용한다. 중복 화면·중복 데이터 저장소를 만들지 않는다.

### Alight Motion 스타일 정렬

#### 시각 토큰

직접 고정한 색상값을 최소화하고 가능한 범위에서 시스템·호스트 앱의 실제 값을 관찰해 사용한다.

- 배경색
- secondary background
- grouped surface
- separator
- primary·secondary text
- accent
- destructive
- disabled
- selected state
- corner radius
- border thickness
- row height
- toolbar height
- horizontal margin
- section spacing

호스트 값을 안전하게 읽을 수 없으면 iOS semantic color와 보수적인 fallback을 사용한다.

#### 구성 요소

- Navigation bar
- Toolbar
- Segmented control
- List row
- Section header
- Card
- Slider
- Toggle
- Text field
- Numeric input
- Color swatch
- Bottom action bar
- Progress overlay
- Error banner
- Empty state
- Confirmation sheet

모든 신규 화면은 공통 `AEMotionTheme`과 component factory를 사용한다. 각 화면에서 임의로 색상·radius·shadow를 만들지 않는다.

#### 아이콘과 텍스트

- 가능한 경우 SF Symbols 또는 호스트 앱과 유사한 선 굵기의 아이콘 사용
- 아이콘과 텍스트의 baseline 정렬
- 과도한 emoji·색상 아이콘 사용 금지
- 버튼 문구 길이와 언어별 레이아웃 검증
- Dynamic Type 지원
- VoiceOver label·hint
- 최소 터치 영역 유지

#### 모션과 전환

- 화면 push·pop·sheet 전환을 iOS 기본 동작과 맞춤
- 불필요한 spring·과도한 fade 금지
- 로딩 중 레이아웃 점프 방지
- 긴 작업은 blocking spinner 대신 진행률·취소 제공
- 작업 완료 후 toast 또는 짧은 상태 피드백 제공

### Extensions & Scripts 화면 재설계

현재처럼 배경이 비어 보이거나 기능 카드만 떠 있는 느낌을 제거한다.

구성:

- 명확한 navigation bar와 title
- 배경 전체를 채우는 grouped surface
- `Recent`, `Editing`, `AI & Analysis`, `Presets`, `Resources`, `Diagnostics` 섹션
- 기능이 없는 섹션은 숨김
- 검색 결과 없음·로딩·오류 상태 각각의 empty state
- 짧은 설명과 일관된 icon
- 마지막 row 아래 남는 공간도 배경 surface가 이어지도록 처리
- safe area와 tab bar·home indicator까지 배경 연결
- 화면 회전·Split View에서 검은 영역이 생기지 않게 constraints 재검증

### Add Effects 검은 화면·미완성 영역 수정

가능한 원인을 분리해 검증한다.

- collection view background가 nil 또는 clear
- parent view와 child collection view의 background 불일치
- synthetic section 삽입 후 supplementary view 누락
- content size가 화면보다 작을 때 남는 영역 미처리
- 추천 strip을 숨긴 후 해당 frame이 빈 공간으로 남음
- category 전환 중 loading view 제거 시점 문제
- safe area·bottom inset·keyboard inset 오류
- trait 변경 또는 dark mode 시 색상 갱신 누락
- 재사용 cell이 투명 상태로 남음

수정 기준:

- root view, collection view, background view가 같은 semantic surface를 사용
- 빈 카테고리는 검은 화면 대신 icon·설명·검색 제안 표시
- 로딩 중 skeleton 또는 progress 표시
- 오류 상태는 재시도 버튼 제공
- recommendation 영역을 숨기면 layout constraint 자체를 접음
- synthetic Extensions section의 header·footer·background를 원본 section과 일치
- 스크롤 바깥 overscroll 영역도 동일 배경색 유지
- 앱 재진입, 회전, 키보드, 검색 취소 후에도 배경 일관성 유지

### 화면 밀도와 정보 구조

- 한 화면에 주요 CTA는 하나
- secondary action은 toolbar 또는 context menu
- destructive action은 별도 확인
- 설명문은 짧게 유지하고 상세 도움말은 info 화면으로 이동
- 중요 파라미터를 위에, 고급 설정은 disclosure section에 배치
- 빈 공간을 무조건 카드로 채우지 않고 정렬과 그룹으로 안정감 제공
- iPhone mini부터 iPad까지 동일 hierarchy 유지

### 안전한 UIKit 통합

- private class 이름 하나에만 의존하지 않고 class·selector·outlet 존재 여부 검사
- 삽입 대상 view controller의 생명주기를 확인한 뒤 한 번만 설치
- 이미 설치된 버튼·section을 중복 삽입하지 않음
- host layout constraint를 직접 삭제하지 않음
- hook 실패 시 원본 UI를 그대로 유지
- 신규 버튼이 원본 gesture·scroll·keyboard 동작을 가로채지 않음
- 가로 모드·iPad·Split View에서 숨김 또는 compact fallback 제공
- 진단 로그에 placement target, success, fallback, duplicate prevention 기록

### 회귀 테스트

1. Extensions & Scripts의 모든 화면 영역이 동일한 배경으로 채워진다.
2. 기능이 없거나 검색 결과가 없을 때 검은 화면 대신 empty state가 표시된다.
3. Add Effects의 상단·하단·overscroll 영역에 검은 미완성 영역이 없다.
4. 추천 strip 숨김 후 빈 frame이 남지 않는다.
5. 신규 contextual 버튼이 원본 Alight Motion 버튼을 가리지 않는다.
6. 같은 화면을 반복 진입해도 버튼이 중복 생성되지 않는다.
7. iPhone 소형 화면, 대형 화면, iPad에서 layout이 깨지지 않는다.
8. 세로·가로 회전 후 배경과 constraints가 유지된다.
9. Dynamic Type와 VoiceOver에서 핵심 기능을 사용할 수 있다.
10. Preset Studio, Speed Remap, Easing, Shake, Color의 기존 기능에 회귀가 없다.
11. Move/Transform, Distortion/Warp, BCC 검색에 회귀가 없다.
12. 렌더 완료·취소·메모리 처리에 회귀가 없다.

### 완료 조건

- 신규 기능 배치 검토표와 실제 placement가 일치
- Extensions & Scripts에 불필요한 신규 기능 집중 없음
- 주요 도구를 작업 맥락에서 직접 진입 가능
- 모든 AE Motion 화면이 공통 theme component를 사용
- 빈 화면·검은 여백·투명 background 결함 0건
- 원본 Alight Motion UI와 시각적 충돌 최소화
- hook 실패 시 원본 앱 동작 유지
- 실제 iPhone과 iPad에서 스크린샷 기반 UI 검수 통과

### 제외

- Alight Motion private 프로젝트 DB 직접 수정
- 원본 앱의 기존 버튼 제거 또는 재배치
- 기능 자체의 대규모 엔진 변경
- v2.1 Project Schema·Autosave·Proxy 구현
- 온라인 market·plugin SDK

---

## v2.1 — Project Reliability, History, Proxy, Cache & Recovery

### 목표

전문 작업에서 가장 중요한 “프로젝트가 날아가지 않는다”는 신뢰를 만든다. Studio Core의 기반 릴리스다.

### Project Schema

- Project
- Sequence
- Track
- Layer
- Clip
- Effect
- Property
- Keyframe
- Mask
- Matte
- Media Reference
- Cache Reference
- Color Pipeline
- Audio Bus
- Render Setting

모든 구조에 schema version과 migration rule을 포함한다.

### 자동 저장과 복구

- 변경 작업마다 비파괴 command log
- 주기적 snapshot
- 1분·5분·10분 전 복구
- 앱 강제 종료 후 정확한 타임라인 복원
- write-ahead journal
- atomic save
- 저장 중 앱 종료 대응
- 안전 모드 열기
- 문제 효과·레이어만 비활성화
- 프로젝트 복제 Branch
- 저장 공간 부족 사전 경고
- 누락 미디어·폰트·효과 표시
- 손상된 캐시 자동 폐기
- autosave retention 정책

### History Timeline

- Undo·Redo
- 시각적 작업 이력
- 특정 상태로 이동
- 중요 상태 북마크
- 상태 이름 지정
- 브랜치 비교
- 되돌리기 전 복제
- 대규모 작업 묶음
- command-level diff

### Proxy·Cache

- Adaptive Preview 1/2·1/4·1/8
- Smart Proxy
- Effect Cache
- Background Render
- Cache Indicator
- Smart Invalidation
- External Cache
- 프록시와 원본 자동 재연결
- 원본 오프라인 편집
- 캐시 예산
- LRU 정리
- 재생 중 동적 품질 전환

### 성능 모드

- Battery Saver
- Balanced
- Maximum Quality
- Background Export
- Thermal Protection

열 상태·메모리 압박이 높아지면 다음을 단계적으로 조정한다.

- Preview resolution
- Optical Flow quality
- Particle count
- Depth inference frequency
- Effect sample count
- Cache prefetch
- Background jobs

### Project Doctor

- 누락 파일
- 누락 폰트
- 호환되지 않는 효과
- 손상 프레임
- 과도한 캐시
- 고비용 효과
- 색공간 불일치
- 오디오 클리핑
- 렌더 실패 이력
- 자동 최적화 권고
- 안전 복제 후 수리

### 완료 조건

- 강제 종료 후 프로젝트 상태 복구
- 동일 프로젝트 100회 저장·열기
- 저장 중 종료 테스트
- 누락 미디어 상태에서 안전하게 열기
- 캐시 삭제 후 재생성
- 외장 저장소 연결 해제 대응
- 프로젝트 마이그레이션 테스트 통과

---

## v2.2 — Unified Animation Core, Gesture Recording & Professional Velocity

### 목표

모든 숫자·색상·좌표 속성에 동일한 키프레임·곡선·시간 매핑을 제공한다.

### 핵심 모델

- PropertyID
- AnimatableProperty
- Keyframe
- KeyframeValue
- BezierHandle
- CurveSegment
- KeyframeCurve
- InterpolationMode
- ExtrapolationMode
- TimeMapping
- PropertyBinding
- AnimationPreset

### Graph Editor

- Value Graph
- Speed Graph
- 두 손가락 확대·축소
- 다중 선택
- 복사·붙여넣기
- 간격 균등 배치
- Snap
- 핸들 각도·길이 잠금
- Overshoot
- Bounce
- Elastic
- Back
- Hold
- Linear
- Auto Bezier
- 그래프 프리셋 재사용
- Motion Cleanup
- 키프레임 값 직접 입력
- 영역 확대
- 미니맵

### Gesture Recording

- 손가락 이동을 Position으로 기록
- 회전을 Rotation으로 기록
- Pinch를 Scale로 기록
- 두 손 동시 입력
- 실시간 Auto Keyframe
- 샘플링 빈도 선택
- 흔들림 제거
- 곡선 단순화
- Bezier fitting
- 시작·끝 정렬
- Loop 생성
- 기록 후 Motion Cleanup

### Professional Velocity

- 현재 Studio Core 타임라인 클립에 직접 적용
- Speed keyframe
- Time remap keyframe
- Freeze frame
- Reverse segment
- Hold
- Ramp
- Montage
- 구간별 정방향·역방향
- Frame Blending
- Optical Flow interface
- 오디오 분리
- Pitch Preserve
- BPM 연동
- Proxy 분석과 Full render 분리
- Dead Frame Cleaner 연결
- 장면 전환에서 flow reset
- 속도 변화 지점 자동 마커

### 햅틱

- Keyframe
- Beat marker
- Cut point
- Clip edge
- Graph tangent lock
- Frame exact position

### 완료 조건

- 모든 기본 숫자 속성에서 동일한 keyframe API 사용
- Speed Graph와 Value Graph 왕복 시 데이터 손실 없음
- Gesture Recording을 60fps 입력에서도 안정적으로 단순화
- Reverse·Freeze·오디오 유지 조합 테스트
- 24·30·60fps에서 시간 정확도 유지

---

## v2.3 — Composition Foundation, Track Matte, Blend & Channel Pipeline

### 목표

AE급 합성의 기반인 레이어 관계·매트·알파·채널·비파괴 그룹 구조를 구현한다.

### Null·Parenting

- Null Object
- Pick Whip
- 위치·회전·크기 상속
- 속성별 상속 해제
- 부모 변경 시 world transform 유지
- 여러 레이어 자동 연결
- TrackingData→Null
- Camera controller Null
- 기본 IK prototype

### Adjustment·Effect Group

- Adjustment Layer
- 범위 지정
- Effect Group
- 그룹 강도
- Enable·Disable
- 순서 변경
- 그룹 마스크
- Before·After
- Preset 저장
- Macro 연결
- nested group

### Group·Pre-compose

- Group: 타임라인 정리
- Pre-compose: 독립 내부 타임라인
- Linked Composition
- 모든 인스턴스 동시 수정
- 인스턴스별 override
- collapse transform 정책
- duration·frame rate 관리
- 원본 위치 유지·이동 선택

### Blend Modes

최소 지원:

- Normal
- Add
- Screen
- Multiply
- Overlay
- Soft Light
- Hard Light
- Difference
- Exclusion
- Color Dodge
- Color Burn
- Hue
- Saturation
- Color
- Luminosity

### Track Matte

- Alpha Matte
- Alpha Inverted Matte
- Luma Matte
- Luma Inverted Matte
- Difference Matte
- Holdout Matte
- Garbage Matte
- Set Matte
- Channel Matte
- 모든 레이어를 matte source로 선택
- 하나의 matte를 여러 레이어가 공유
- matte source visibility 유지
- source·target 크기와 좌표계 자동 정렬
- RGB·Luma·Alpha·개별 채널 선택
- matte invert
- matte blur
- contrast
- levels
- expand·contract
- feather
- fill holes
- edge noise cleanup
- temporal edge stabilization
- 합집합·교집합·차집합
- matte stack
- depth matte
- normal·motion vector·object ID auxiliary matte
- 3D 오브젝트와 2D 영상 사이 holdout
- matte 결과를 재사용 가능한 `MaskDocument`로 저장

### Channel·Alpha

- RGB channel view
- Alpha view
- Channel swap
- Add·Subtract·Intersect alpha
- Straight·Premultiplied
- Unmult
- Premult correction
- Luma to alpha
- Color range to alpha
- Depth·Normal·Motion Vector pass
- auxiliary output routing

### 완료 조건

- matte source와 대상 레이어 순서에 제한 없음
- Difference·Holdout·Set·Channel Matte가 동일한 matte graph를 사용
- 여러 matte boolean 연산과 temporal cleanup 결과가 프레임 간 안정적
- premultiplied edge halo 테스트 통과
- Adjustment Layer 캐시 무효화가 하위 레이어 수정 범위에만 적용
- Pre-compose round-trip 데이터 손실 없음

---

## v2.4 — Universal Tracking, Stabilization & Object Matte Studio

### 목표

추적 데이터를 독립 자산으로 저장하고 어느 속성에도 연결한다.

### TrackingData

- position
- scale
- rotation
- perspective corners
- confidence
- occlusion
- lost state
- correction keyframe
- coordinate space
- reference frame
- source resolution
- tracker version

### 1차 트래커

- Point Tracker
- Mask Tracker
- Face Landmark Tracker
- Stabilize

### 2차 트래커

- Planar Tracker
- Camera Tracker

### 연결 대상

- layer transform
- text position
- glow center
- lens flare center
- blur center
- particle emitter
- mask
- null
- power window
- stabilization target
- Visual Expression
- effect map position

### Object Matte

- 사람
- 얼굴
- 의상
- 머리카락
- 차량
- 하늘
- 사용자 지정 사물
- 탭 선택
- Keep·Remove 브러시
- Box·Lasso
- 앞뒤 프레임 전파
- 신뢰도 낮은 프레임 표시
- re-anchor
- Refine Edge
- Feather
- Choke
- Decontaminate Color
- Temporal Stabilization
- Freeze·Cache
- Alpha output
- Mask conversion
- Separate layer conversion
- Apple Pencil pressure

### 완료 조건

- 추적 결과를 최소 5개 속성 유형에 연결
- 가림 후 재등장 처리
- 보정 키프레임 삽입
- matte freeze와 unfreeze 일관성
- 알파 영상 출력과 마스크 변환 일치

---

## v2.5 — Professional Text, Editable Templates & Vector Typography

### 목표

모바일 편집에서 가장 자주 쓰는 텍스트를 AE급 애니메이션 엔진으로 만든다.

### Text Engine

- 문자별 Position·Scale·Rotation·Opacity
- 단어별·줄별·임의 순서
- Range Selector
- Tracking·Leading animation
- Path text
- Circular text
- Vertical writing
- 한글 자모 단위 애니메이션
- 음절 조립·분해
- Variable Font axes
- text warp
- 3D extrusion
- karaoke syllable highlight
- typewriter
- text to shape
- text to particles
- SVG conversion

### Selector

- Start·End·Offset
- Amount
- Shape
- Ease High·Low
- Randomize
- Based On: Character·Word·Line·Syllable·Jamo
- Seed
- expression input

### Editable Template

- 노출 속성 지정
- 미디어 교체 슬롯
- 폰트 제한
- 색상 제한
- Responsive Time
- Intro·Outro protected region
- Looping middle
- duration rules
- aspect-ratio adaptation
- Smart Replace
- safe-zone constraints

### Motion Search

자연어 또는 구조 검색:

- “빠르게 확대 후 흔들림”
- “글자별 아래에서 튀어오름”
- “후렴에 맞춰 단어 강조”

프리셋 이름을 몰라도 동작 설명으로 검색한다.

### 완료 조건

- 한글 자모 분해·재조합이 Unicode normalization과 충돌하지 않음
- Responsive Time에서 intro·outro 길이 유지
- 템플릿 미디어 교체 후 구도 유지
- variable font 축 keyframe 지원

---

## v2.6 — Professional Color, HDR, Log, Color Management & Scopes

### 목표

색보정 도구뿐 아니라 입력부터 표시·합성·출력까지 일관된 색관리 파이프라인을 만든다.

### Color Management

- Rec.709
- Display P3
- Rec.2020
- SDR
- HDR10
- HLG
- Apple Log
- S-Log
- C-Log
- V-Log
- Log auto-detection
- Log→Rec.709
- 8·10·16·32-bit
- Linear Light
- ACES
- OpenColorIO
- HDR→SDR Tone Mapping
- gamut warning
- dithering
- banding reduction
- display color management

기본 모드는 메타데이터 자동 인식이며, 수동 설정은 전문가 모드에서만 노출한다.

### Color Stack

- Exposure
- Offset
- Lift
- Gamma
- Gain
- Temperature
- Tint
- Contrast
- Pivot
- Saturation
- Curves
- Hue vs Hue
- Hue vs Saturation
- Hue vs Luminance
- Luma vs Saturation
- Color Range Qualifier
- LUT Import
- CDL
- Before·After

### Color Nodes

- Serial
- Parallel
- Layer Mixer
- Mask Input
- Group Input·Output
- bypass
- node cache
- node version

### Power Window

- Circle
- Rectangle
- Pen
- Gradient
- Feather
- Inside·Outside
- Tracking
- matte cleanup

### Scopes

- Histogram
- Waveform
- RGB Parade
- Vectorscope
- Skin Tone Line
- HDR scale
- clipping indicator

### Reference Color Match

- temperature
- tint
- contrast
- black depth
- highlight rolloff
- palette
- saturation
- skin protection
- user-adjustable result

### 비교 뷰

- Before·After
- vertical·horizontal wipe
- flicker compare
- reference image
- synchronized reference video
- palette extraction
- RGB·exposure probe
- brightness·temperature difference
- Onion Skin
- Difference View

### 완료 조건

- SDR/HDR 왕복 tone mapping 검증
- Display P3와 Rec.709 출력 차이 표시
- scope 값이 렌더 결과와 일치
- straight/premult alpha에서 linear-light 합성 검증

---

## v2.7 — Audio Studio, Beat Intelligence, Captions & Transcript Editing

### 목표

작은 DAW 수준의 오디오 편집과 자막·대본 기반 편집을 통합한다.

### Audio Mixer

- track volume
- pan
- mute·solo
- buses
- sends
- automation
- sample-accurate editing
- waveform
- clip gain
- fades
- crossfade

### Effects

- Parametric EQ
- Compressor
- Limiter
- Noise Gate
- De-esser
- Reverb
- Delay
- Voice Isolation
- Hum Removal
- Audio Ducking
- Sidechain
- Loudness Meter
- LUFS normalization
- Noise Removal

### Stem·Music Intelligence

- vocal removal
- vocal isolation
- drums
- bass
- instruments
- instrumental generation
- chorus detection
- music length extension
- music length reduction
- pitch independent BPM
- BPM independent pitch
- structure-aware remix

### Beat Map

- BPM
- Beat
- Downbeat
- tempo changes
- Kick
- Snare
- Hi-hat
- Bass
- Vocal onset
- Major Accent
- Minor Accent
- Drop
- Build-up
- Chorus
- Verse
- Bridge
- Phrase
- Silence
- music energy
- emotion change
- strength
- confidence
- 사용자 보정 마커
- 분석 모델·버전 기록

### Audio Binding

- overall amplitude
- low
- mid
- high
- custom frequency
- attack
- release
- smoothing
- bake to keyframes

### AI Beat Edit·자동 규칙

자동 편집 스타일:

- Beat Cut
- Velocity Edit
- Zoom Edit
- Shake Edit
- Flash Edit
- Manga Impact
- Glitch Edit
- Cinematic Edit
- Smooth Edit

규칙 입력:

- strong beat→cut
- snare→flash
- bass→scale
- high→chromatic aberration
- pre-drop slowdown
- drop velocity preset
- vocal onset→text or character emphasis
- phrase boundary→scene transition
- silence→hold or contrast

사용자 제어:

- 컷 빈도
- 강한 비트만 사용
- 효과 강도
- 동일 효과 반복 방지
- 장면 최소 길이
- 인물 장면 우선
- 구간별 편집 스타일
- 마커 신뢰도
- 자동 결과를 일반 키프레임·컷으로 Bake
- 자동 생성 전 별도 프로젝트 snapshot

### Captions·Transcript

- speech recognition
- speaker diarization
- sentence segmentation
- silence·mistake detection
- transcript delete→video ripple delete
- word search
- Korean spelling correction
- translation subtitle
- translated dubbing
- SRT
- VTT
- ASS
- bulk style
- word highlight
- keyword effect trigger

### 완료 조건

- sample-accurate audio edit
- LUFS meter 검증
- transcript 편집과 타임라인 동기화
- stem separation 실패 시 원본 보존
- 자막 export round-trip

---

## v2.8 — Render Queue, Professional Output, External Storage & Desktop Interchange

### 목표

“내보내기 버튼 하나”가 아니라 복수 작업·복구·전문 포맷을 지원하는 출력 시스템을 만든다.

### Render Queue

- 여러 프로젝트 일괄 렌더
- 여러 해상도 동시 출력
- 여러 출력 구간
- YouTube·Instagram·TikTok presets
- background render
- completion notification
- pause
- resume
- retry from failure
- expected file size
- per-frame error detection
- automatic upload hook
- video·audio·alpha separate output
- checksum
- render report
- frame manifest

### 출력 포맷

- H.264
- H.265·HEVC
- ProRes
- ProRes 4444
- AV1
- PNG sequence
- EXR sequence
- GIF
- WebP
- WAV
- FLAC
- AAC
- SRT
- VTT
- ASS

이미지 시퀀스는 완료 프레임부터 재개 가능하게 한다.

### 외장 저장소

- 외장 SSD 프로젝트
- 외장 미디어 직접 편집
- 외장 프록시·캐시
- 연결 해제 안전 처리
- 재연결
- read-only mode
- bandwidth test

### 데스크톱 교환

- FCPXML
- OTIO
- EDL
- AAF
- LUT
- CDL
- SVG
- PSD layer import
- Premiere·Final Cut·DaVinci용 타임라인
- 폴더형 프로젝트 저장
- 누락 효과 대체
- 호환되지 않는 효과만 baked render로 교체
- media relink report
- Composition·해상도·프레임레이트·레이어 순서를 보존하는 중립 교환 모델
- Position·Rotation·Scale·Opacity·기본 keyframe·Bezier curve 교환
- Mask·Blend Mode·Track Matte·Parenting·Null·Pre-compose 호환성 필드
- Camera·Light·3D pass를 보존할 수 있는 확장 메타데이터
- 완전 호환·부분 호환·bake 필요·지원 불가 상태 분류
- 누락 폰트·미디어·효과 호환성 보고서
- 데스크톱 브리지 도구가 읽을 수 있는 공개 프로젝트 폴더 구조

직접 `.aep` 파일을 완전하게 파싱하는 기능은 이 릴리스의 완료 조건으로 두지 않는다. v2.8에서는 공개 교환 포맷과 AE Motion Bridge용 중립 모델을 완성하고, 고급 AE 프로젝트 호환은 v4.3에서 별도 브리지·변환기로 구현한다.

### 완료 조건

- 4K 장시간 렌더 재개
- 이미지 시퀀스 실패 프레임만 재렌더
- 외장 SSD 분리 후 프로젝트 손상 없음
- OTIO/FCPXML 기본 컷·속도·오디오 왕복 검증

---

## v2.9 — Professional Workspace, Project Diagnostics & Mobile Interaction

### 목표

작은 화면에서도 초보자와 전문가가 같은 프로젝트 구조를 사용하며, 성능 문제를 스스로 분석할 수 있게 한다.

### 앱 전역 탭

- Home
- Projects
- Tools
- Presets
- Templates
- Assets
- Resources
- Tutorials

### 전문 작업 공간

- Edit — 컷 편집과 타임라인
- Motion — 키프레임과 그래프
- Composite — 레이어·노드·매트·채널 합성
- 3D — 모델·카메라·조명·파티클
- Color — 색관리·색보정·Scopes
- Audio — 믹싱·Beat Map·자막
- Deliver — Render Queue·출력

Composite Workspace:

- 레이어 기반 합성
- 노드 기반 합성
- 레이어와 노드 표현 전환
- Pre-compose
- Adjustment Layer
- Track Matte
- Blend Mode
- Channel Operations
- 2D·3D 레이어 혼합
- Depth 기반 합성
- Render Pass 입력
- 여러 Viewer 동시 표시
- 원본·Matte·Depth·Normal·최종 결과 전환
- 효과 적용 순서 변경
- 그룹·폴더
- Effect Macro 제작
- 데이터 연결 상태 시각화

연결 예시:

```text
AI Depth Map → Depth Blur → Fog Depth → Particle Collision → Color Grade
Audio Bass → Glow Strength → Camera Shake → Particle Emission
```

### Viewer

- Preview Quality 25·50·75·100%
- Adaptive
- Proxy·Full
- Original·Processed
- RGB·Alpha
- 2D·Depth
- Side-by-side
- Split Wipe
- Viewer A·B
- Grid
- Safe Area
- Guides
- Reference pin
- Onion Skin
- Difference

### 모바일 입력

- 두 손 조작
- Apple Pencil
- pressure brush
- hover support where available
- 키프레임 햅틱
- keyboard shortcut
- gesture conflict prevention
- left-hand playhead + right-hand parameter
- long task restoration

### Performance Profiler

- layer render time
- effect GPU time
- CPU time
- memory
- cache
- frame drop
- thermal state
- decode bottleneck
- expensive effect warning
- low-quality preview substitute
- automatic Project Optimization

### Frame Inspector

특정 프레임에서 다음을 표시한다.

- 적용 효과
- 마스크
- 매트
- 속성 값
- keyframe source
- color transform
- audio event
- cache state
- render dependency
- auxiliary passes

### Effect Explanation

- 효과가 바꾸는 영역 시각화
- 입력·출력 비교
- 파라미터 영향 애니메이션
- 성능 비용
- 추천 사용법
- 조합 가능한 맵·매트
- 품질 모드 차이

### 완료 조건

- 초보 모드·고급 모드 간 프로젝트 데이터 동일
- Edit·Motion·Composite·3D·Color·Audio·Deliver 전환 시 선택·playhead 상태 유지
- 레이어와 노드 표현이 동일 Render Graph를 가리키며 왕복 시 데이터 손실 없음
- AI·Audio·Tracking·Render Pass 데이터를 속성·효과 입력에 연결 가능
- 성능 분석 수치와 실제 병목 일치
- 긴 작업 중 앱 background→foreground 복귀
- 제스처 충돌 회귀 테스트

---

## v2.10 — Asset Library, Smart Assets & Tutorial Foundation

### 목표

텍스처·오버레이·사운드·폰트·LUT·3D 모델을 앱 안에서 검색하고 바로 사용하는 자산 계층을 만들고, 이후 커뮤니티형 Project Tutorials가 사용할 학습 패키지 형식을 준비한다.

### Asset Library

자산 카테고리:

- Film Burn
- Light Leak
- Dust
- Scratch
- Grain
- Smoke
- Fog
- Fire
- Sparks
- Water
- Glass
- Grunge
- Paper
- Ink
- Manga Texture
- Halftone
- HUD
- Lens Dirt
- Bokeh
- Particles
- Sound Effects
- 3D Models
- HDRI
- Materials
- LUT
- Fonts
- Transitions

관리 기능:

- 검색
- 즉시 미리보기
- 타임라인·Viewer 드래그 추가
- 권장 Blend Mode 자동 제안
- 화면 비율·크기 자동 맞춤
- 장면 색상·밝기 Match
- 오프라인 다운로드
- 즐겨찾기
- 최근 사용
- 컬렉션
- 사용하지 않는 자산 정리
- 라이선스·출처·제작자 표시
- checksum과 버전 관리
- 누락 자산 재연결
- 외장 저장소 위치 선택

### Smart Asset

단순 미디어 파일과 별도로 조절 가능한 자산을 제공한다.

예시 `Smart Smoke`:

- direction
- density
- speed
- color
- distortion
- mask
- depth
- camera motion response
- light response
- loop region
- quality level

Smart Asset은 내부적으로 미디어·효과·매크로·의존성을 가진 `AssetDescriptor`와 `PresetDocument` 조합으로 저장한다.

### Tutorial Foundation

- `TutorialPackageManifest`
- 완성 영상
- 단계별 설명
- 타임라인 시간 범위 연결
- 사용 효과·폰트·자산·모델 자동 목록
- 연습용 프로젝트
- 단계별 snapshot
- `이 효과 사용하기`
- `이 장면 열어보기`
- `내 미디어로 교체`
- 단계 적용 전후 비교
- 난이도·분야·필수 기술 태그
- 로컬 북마크·학습 진행률

v2.10에서는 로컬·검증된 패키지 재생과 학습 기능만 구현한다. 사용자 업로드, 제작자 인증, 신고·검수, 공개 커뮤니티는 v4.2에서 확장한다.

### 완료 조건

- 설치된 자산을 검색·미리보기·추가 가능
- 자산 라이선스와 의존성이 프로젝트 패키지에 기록
- Smart Asset 매크로 변경이 내부 구성에 반영
- Tutorial 단계와 타임라인 구간이 정확히 동기화
- 누락·손상 자산이 있어도 프로젝트와 튜토리얼을 안전하게 열 수 있음

---

## v3.0 — AI Media Engine

### 목표

Depth·Upscale·Noise Reduction·Optical Flow·Repair·Object Removal을 공통 Core ML 실행 계층으로 통합한다.

### AI Model Manager·공통 런타임

- installed model list
- model category
- model size
- quality tier
- expected speed
- on-device·server processing policy
- lightweight·high-quality variant
- model registry
- download
- update
- uninstall
- version
- checksum
- author·license
- supported operators
- input·output schema validation
- maximum model size
- Neural Engine·GPU·CPU
- sandboxed execution boundary
- time limit
- memory limit
- tiled inference
- memory estimate
- minimum-device tier
- preview inference
- final inference
- progress
- cancel
- resume
- cache
- temporal chunk
- thermal adaptation
- failure isolation
- verified-model publishing status

기본 모델 카테고리:

- background removal
- person·object segmentation
- face tracking
- depth
- optical flow
- frame interpolation
- upscale
- denoise
- face restoration
- stabilization
- color restoration
- style transfer
- lip sync
- captions
- stem separation
- auto reframe

AI 결과는 가능한 한 완성 영상을 강제로 적용하지 않고 다음 auxiliary data로 출력한다.

- Alpha Matte
- Depth Map
- Normal Map
- Motion Vector
- Object ID
- Segmentation Map
- Clean Plate
- Upscaled Frame
- Confidence Map

### Depth

- 실제 monocular depth model
- keyframe inference
- temporal stabilization
- Original·Depth·Split
- Near/Far invert
- Focus
- DOF
- Fog
- Parallax
- depth cache
- depth pass export

### Upscale

- General 2×
- General 4×
- Anime 2×
- Anime 4×
- Game Footage
- face detail protection
- compression artifact reduction
- original/upscaled slider

### Noise·Repair

- spatial noise reduction
- temporal noise reduction
- deblock
- deband
- ringing removal
- moiré removal
- chroma repair
- dead pixel
- dust·scratch
- rolling shutter
- frame jitter
- compression detail recovery

### Optical Flow

- Frame Blending
- Flow Interpolation
- scene cut detection
- occlusion
- confidence
- bad frame display
- Dead Frame Cleaner integration

### Content-Aware Removal

- remove brush
- mask tracker
- temporal fill
- reference frame
- failed-frame marker
- manual correction
- clone source
- edge blending

### Smart Replace·Style DNA

- subject replacement with framing preservation
- motion·color·cut rhythm analysis
- style preset generation
- template slot adaptation

### 완료 조건

- 모델 실패가 프로젝트 손상으로 이어지지 않음
- 저사양 기기에서 proxy 분석
- 4K tiled inference
- temporal seam 검사
- AI 결과와 원본 비교·복구

---

## v3.1 — Advanced Temporal, Warp & Procedural Effects Core

### 목표

단발성 필터를 늘리는 대신 시간·벡터·외부 맵을 공유하는 범용 GPU 엔진을 만든다.

### 공통 Effect Contract

모든 고급 이펙트는 가능한 범위에서 다음을 지원한다.

- Mix·Opacity
- Mask Input
- External Map Input
- Channel Selection
- Edge Mode
- Coordinate Space
- Seed
- Temporal Coherence
- Preview·Final Quality
- 16·32-bit
- Linear-light
- Straight·Premult alpha
- auxiliary output
- GPU capability metadata
- memory estimate
- cache policy
- tile support
- deterministic render

### Time Displacement Pro

픽셀별로 서로 다른 시간의 프레임을 참조한다.

필수 파라미터:

- Time Range
- Neutral Point
- Map Channel
- Time Direction
- Temporal Interpolation
- Edge Time Mode
- Map Blur
- Time Quantization
- Temporal Jitter
- Preserve Subject
- External Map
- Reset at cut

활용:

- 충격파 시간 전파
- 액체형 시간 왜곡
- 스캔 전환
- 신체 부위 지연
- 노이즈 기반 시간 붕괴

### Vector Field Warp

R/G 또는 생성된 vector field를 X/Y 흐름으로 사용한다.

- X·Y Strength
- Curl
- Divergence
- Advection Steps
- Viscosity
- Center
- Rotation
- Flow Speed
- Turbulence Scale
- Detail
- Edge Mode
- Map Resolution
- Layer·Screen·World
- Touch-drawn field
- Vector Output input

### Optical Compensation Pro

- Reverse Lens Distortion
- Fisheye Expand
- Fisheye Contract
- Rectilinear
- Spherical
- Stereographic
- Anamorphic
- Panini
- Field of View
- View Center
- Anamorphic Ratio
- Overscan
- Curvature
- Perspective Preserve
- Radial Falloff
- Center Lock
- Crop Compensation

### Temporal Feedback

이전 출력 결과를 현재 입력에 재귀적으로 섞는다.

- Feedback Amount
- Decay
- Feedback Frames
- per-iteration transform
- hue·saturation·luminance shift
- bright·dark gating
- Alpha Decay
- Detail Decay
- Edge Mode
- Mask
- Reset Frame
- directional feedback
- blend mode
- random-access cache checkpoint

### Slit Scan·Time Slice

- Horizontal
- Vertical
- Radial
- Spiral
- Grid
- Angular
- Path
- Depth-based
- Time Range
- Direction
- Width
- Spacing
- Curve
- Repeat
- Reverse
- Center
- Time Easing

### Procedural Texture Lab

- Curl Noise
- FBM
- Voronoi
- Reaction Diffusion
- Turbulence
- Caustics
- Ink Flow
- Cloud Volume
- Electric Field
- Marble
- Paper Fiber
- Film Dust
- Cracks
- Fluid Marble

공통 출력:

- Color
- Alpha
- Vector
- Normal
- Height

공통 파라미터:

- Scale
- Detail
- Roughness
- Lacunarity
- Evolution
- Seed
- Loop Duration
- Distortion
- Tileable
- Contrast
- Color Ramp

### SDF Morphology

- Distance Field
- Smooth Union
- Smooth Subtract
- Contour Lines
- Blob Morph
- Edge Waves
- Grow·Shrink
- Bevel
- liquid text
- alpha-to-SDF cache

### 완료 조건

- 모든 엔진이 외부 맵을 공유
- 랜덤 시드로 결과 재현
- temporal effect의 임의 프레임 탐색 캐시
- Preview와 Final 결과 구조적 일치
- 32-bit linear-light 경로 검증

---

## v3.2 — Advanced Glitch, Keying, Relight, Film & Repair Effects

### Pixel Sort Pro

정렬 기준:

- Luminance
- Hue
- Saturation
- R·G·B
- Alpha
- Edge Strength
- Custom Map
- Color Distance

방향:

- Horizontal
- Vertical
- Radial
- Circular
- Spiral
- Vector Field
- Mask Path
- Optical Flow
- Brush Direction

파라미터:

- Threshold Min·Max
- Segment Length
- Sort Order
- Gap
- Sampling
- Temporal Stability
- Seed
- Edge Protection

### Datamosh Studio

- I-frame Drop
- Motion Vector Hold
- Vector Exaggeration
- Vector Rotation
- Macroblock Corruption
- Packet Loss
- Reference Frame Swap
- Motion Vector Injection
- Two-clip Mosh
- Block Size
- Vector Strength
- Persistence
- I-frame Interval
- Damage Probability
- Damage Region
- Direction Bias
- Color Plane Damage
- Seed
- Freeze Vector
- Scene Reset

### Keyer·Edge Repair Suite

모듈:

- Screen Keyer
- Difference Keyer
- Spill Suppressor
- Matte Cleaner
- Edge Decontaminate
- Light Wrap
- Edge Temporal Stabilizer

Matte Cleaner:

- Black·White Clip
- Despot Black·White
- Erode·Dilate
- Open·Close
- Fill Holes
- Edge Contrast
- Feather
- Chatter Reduction
- Temporal Consistency
- Hair Detail
- Translucency Protection

### Surface Relight

입력:

- luminance-derived normal
- alpha-derived surface
- external Normal
- external Depth

파라미터:

- Light Position
- Light Type
- Height Scale
- Smoothness
- Roughness
- Specular
- Metallic
- Ambient
- Rim
- Shadow Depth
- Normal Blur
- Edge Preserve
- Light Color
- Multiple Lights

### Film Response

- Density Curve
- Halation
- luminance-aware grain
- channel-specific grain
- Gate Weave
- Exposure Flicker
- layer misregistration
- Dirt
- Dust
- Scratch
- Bleach
- Highlight Compression
- Black Lift
- edge exposure variation
- Match Grain
- Remove Grain

### Print·Manga Stylizer

- CMYK Halftone
- Manga Screentone
- Cross Hatching
- Ink Outline
- Speed Lines
- Posterized Shading
- Palette Quantization
- Dither
- Misregistration
- Paper Absorption
- Ink Bleed
- Dot Shape
- Angle
- Frequency
- per-channel angle
- dot growth curve
- perspective
- temporal lock

### Footage Repair Suite

AI Media Engine과 연결하며 수동 효과 형태도 제공한다.

- Deflicker
- Deband
- Deblock
- Ringing Removal
- Moiré Removal
- Chroma Noise Repair
- Dead Pixel Repair
- Dust·Scratch Removal
- Rolling Shutter Repair
- Frame Jitter Repair
- Compression Detail Recovery

### Frequency Separation

- Separation Radius
- Low Gain
- High Gain
- Detail Threshold
- Skin Range
- Edge Protection
- Texture Equalizer
- High-frequency tint removal
- Multi-band mode

### 완료 조건

- keyer edge temporal stability
- datamosh deterministic seed
- pixel sort temporal coherence
- film grain brightness·channel dependence
- repair effect가 원본 디테일을 과도하게 제거하지 않음

---

## v3.3 — Visual Expressions, Motion Preset Composer & 2.5D

### Visual Expression

노드:

- Audio Amplitude
- Frequency Band
- Time
- Sine
- Noise
- Random
- Add
- Multiply
- Divide
- Clamp
- Map Range
- Tracker Position
- Layer Transform
- Distance
- Delay
- Spring
- Sample Image
- Depth
- Beat Event
- Velocity
- Output Property

기능:

- block UI
- advanced text expression
- type checking
- cycle detection
- preview
- bake to keyframes
- variable inspector
- reusable expression preset

### Motion Preset Composer

예시:

`Scale Overshoot + Rotation Shake + Blur Decay + RGB Split`

지원:

- effect sequence
- property binding
- time offset
- intensity scale
- seed
- preview
- macro controls
- dependency manifest
- share package

### Velocity-Aware Effects

- translation speed→Directional Blur
- stop impulse→Shake
- acceleration→RGB Split
- angular speed→Motion Trail
- zoom speed→Radial Blur

### 2.5D

- Z axis
- 3D rotation
- perspective camera
- camera null
- DOF
- lights
- shadows
- billboard
- 3D text
- camera shake preset
- 2D·3D split view

### 완료 조건

- 순환 참조 안전 차단
- expression bake 재현성
- camera projection 일관성
- Null·Parenting과 3D transform 연결

---

## v3.4 — Paint, Vector, 3D Import & Effect Lens

### Paint

- frame paint
- Clone Stamp
- Healing Brush
- Eraser
- animated stroke
- smoothing
- pressure
- speed-based width
- onion skin
- paint cache

### Vector

- Pen Tool
- Boolean operations
- Trim Paths
- Repeater
- Gradient Mesh
- shape to mask
- shape to particle path
- text to shape

### 3D Import

- GLB
- GLTF
- OBJ
- USDZ
- static mesh
- skeletal character
- model animation
- materials
- textures
- transparent material
- metal·glass material
- HDRI
- animation playback
- animation range·speed
- imported camera
- imported light
- shadow
- reflection
- collision bounds
- particle emission surface
- depth relation
- Depth Map
- Normal Map
- Object ID
- Motion Vector
- video texture

조작:

- 3D Gizmo
- world·local coordinates
- camera view
- focal length
- DOF
- duplicate
- parent·child
- group

모바일에서는 완전한 조형 모델링보다 가져오기·배치·애니메이션·영상 합성을 우선한다.

### Effect Lens

- 촬영 전 효과 preview
- LUT
- mask guide
- tracking guide
- depth preview
- performance-limited live effects

### 완료 조건

- Apple Pencil stroke latency
- frame paint 복구
- vector boolean 안정성
- 3D asset memory budget
- unsupported material fallback

---

## v3.5 — 3D Motion Graphics, Particles & Render Pass Workspace

### 목표

Cinema 4D·Blender 전체를 복제하지 않고 영상 합성에 필요한 3D 모션그래픽·파티클·렌더 패스를 모바일에 맞게 제공한다.

### Scene 구조

- Scene Hierarchy
- Object List
- Camera
- Light
- Material
- Empty
- Null
- Particle Emitter
- Force Field
- Text Object
- Shape Object
- Imported Model

### 기본 모델링·모디파이어

- Cube
- Sphere
- Plane
- Cylinder
- Torus
- Text Extrusion
- Bevel
- Bend
- Twist
- Taper
- Array
- Boolean
- Subdivision
- Displacement

### 애니메이션·Constraint

- transform
- morph
- material animation
- camera animation
- light animation
- path animation
- Look At
- Follow Path
- Parent
- Offset
- Loop
- Procedural Animation

### Particle Engine

- 2D·3D particles
- image·text·model particle
- point·line·plane·model surface emitter
- velocity·direction
- gravity
- wind
- vortex
- turbulence field
- collision
- life
- color·size over life
- connection lines
- trails
- physically responsive light
- particle as light
- Depth Map collision
- Motion Vector output
- object·mask·audio·beat driven emission

### Render Pass

- Beauty
- Alpha
- Depth
- Normal
- Object ID
- Motion Vector
- Shadow
- Reflection
- Emission
- Ambient Occlusion

각 pass는 2D Composite Workspace의 matte·effect map·color node 입력으로 다시 연결할 수 있어야 한다.

### 완료 조건

- 동일 3D 장면에서 Preview·Final transform 일치
- particle deterministic seed
- render pass와 Beauty의 frame alignment 일치
- 3D asset memory budget 초과 시 proxy mesh·texture fallback
- 2D matte와 3D depth occlusion 조합 검증

---

## v3.6 — Material, Reflection, Refraction & Mobile Physics

### 목표

평면 영상·텍스트·3D 오브젝트에 일관된 재질·반사·굴절을 적용하고, 영상 모션그래픽에 필요한 제한된 물리 시뮬레이션을 제공한다.

### Material

- Base Color
- Roughness
- Metallic
- Emission
- Opacity
- Normal Map
- Displacement Map
- Reflection
- Refraction
- Subsurface
- Texture Mapping
- Video Texture
- material animation

### Reflection

- horizontal·vertical
- floor reflection
- mirror
- curved reflection
- scene reflection
- environment map
- blur
- distortion
- intensity
- tint
- distance falloff
- Fresnel
- rough reflection

### Refraction·Glass

- glass
- water
- ice
- gel
- crystal
- convex lens
- concave lens
- prism
- chromatic dispersion
- map-driven refraction
- thickness
- index of refraction
- roughness
- internal reflection
- absorption
- caustic approximation

### Physics

- gravity
- collision
- friction
- restitution
- wind
- torque
- rigid body
- soft constraint
- simplified cloth
- rope·hair chain
- fracture prototype
- particle collision
- gyroscope-driven gravity
- simulation bake
- deterministic seed
- cache
- reset frame

실시간 Preview에서는 단순화된 solver를 사용하고 Final에서는 고정 timestep과 더 높은 iteration을 사용한다.

### 완료 조건

- Fresnel·IOR·roughness가 색관리·linear-light 경로에서 계산
- reflection·refraction auxiliary pass 출력
- physics bake 후 재생 결과가 동일
- 기기 자이로 입력을 일반 keyframe으로 Bake 가능
- 복잡한 시뮬레이션 실패 시 프로젝트 손상 없이 비활성화

---

## v4.0 — Ecosystem, Project Package, Plugin SDK & Remix

### Preset Market

- Effect
- Motion
- Graph
- Color
- Text
- Transition
- Template
- Expression
- Shader
- 제작자
- 버전 호환성
- 의존성 검사
- 리뷰·신고
- 샌드박스
- 라이선스

### Project Package

- video
- image
- audio
- font
- preset
- LUT
- AI model reference
- original 제외
- proxy only
- missing relink
- license metadata
- migration
- checksum

### Remix

- 영상만 공개
- 효과 목록 공개
- 프리셋 공개
- 전체 프로젝트 공개
- remix 허용
- 원작자 표시
- dependency resolution

### Effect Package·Plugin 단계

전용 패키지 확장자 예시: `.fxpack`

```text
CinematicWarp.fxpack
├── manifest.xml
├── graph/
├── shader/
├── preview.mp4
├── icon.png
├── presets/
└── documentation/
```

`EffectPackageManifest`:

- effect ID·name·author·version
- category·tags
- minimum app version
- parameters and ranges
- keyframe capability
- video·mask·map input count
- auxiliary output
- GPU·CPU path
- quality tiers
- supported resolution·bit depth·color space
- memory·performance tier
- permissions
- package signature
- license

설치·관리:

- Files import
- URL install
- QR install
- preview before installation
- dependency·permission·performance review
- compatibility block
- update
- creator signature·trust
- individual package disable
- export
- package collection
- rollback

#### Preset

기존 효과 설정 조합. 일반 사용자 대상이며 v2.0 `PresetDocument`를 사용한다.

#### Effect Builder

코딩 없이 기존 효과·맵·곡선·매크로를 연결한다.

#### Shader Editor

- Metal Shading Language 기반
- 제한된 입력·출력
- 선언형 파라미터
- preview
- compile diagnostics
- resource limit
- no arbitrary filesystem or network access

#### Native Plugin SDK

- tracking
- AI
- render plugin
- 별도 프로세스 또는 제한된 sandbox
- CPU·GPU·memory budget
- permission
- timeout
- crash isolation
- minimum app version
- signed package

### Edit Recipe

완성 영상의 효과 순서·매크로·곡선·타이밍을 레시피로 저장하고 다른 영상에 적용한다.

### 완료 조건

- 악성·손상 플러그인으로 앱 본체 종료 방지
- package dependency 검사
- 프로젝트 공유 시 저작권 미디어 제외
- remix attribution 보존

---

## v4.1 — Capture, External Devices & Multicam Research

- in-app camera
- real-time LUT
- focus peaking
- zebra
- waveform
- audio level
- guides
- timecode
- clap sync
- external microphone
- external storage recording
- multi-iPhone/iPad monitoring
- multicam sync research
- recording→project automatic organization

이 릴리스는 핵심 편집 엔진과 프로젝트 신뢰성이 충분히 성숙한 이후 진행한다.

---

## v4.2 — Learn Hub, Project Tutorials & Community Breakdown

### 목표

완성 영상·튜토리얼·실제 프로젝트 구조를 연결하는 학습 커뮤니티를 구축한다.

### 기능

- 사용자 완성 영상 업로드
- 영상·텍스트·단계별 튜토리얼
- 사용한 효과·폰트·자산·모델 자동 표시
- 타임라인 구간과 설명 연결
- 연습 프로젝트·프록시 프로젝트
- 설정을 프리셋으로 배포
- 초급·중급·고급
- AMV·Motion Graphics·VFX·Color·3D 분류
- bookmark
- learning progress
- creator verification
- malicious package scanning
- report·moderation

학습 UX:

- `이 효과 사용하기`
- `이 장면 열어보기`
- `내 미디어로 교체`
- `한 단계씩 재생`
- 단계별 Before·After
- 사용 기술 목록
- 결과 비교
- Remix
- attribution

### 완료 조건

- 튜토리얼 패키지와 프로젝트 버전 호환성 검사
- 악성·손상 파일 격리
- 공개 범위·리믹스 권한 보존
- 사용자의 원본 미디어가 동의 없이 공유되지 않음
- 단계 재생이 원본 프로젝트 history와 일치

---

## v4.3 — AE Project Bridge & Compatibility Environment

### 목표

AE Motion의 중립 프로젝트 모델과 데스크톱 브리지 도구를 통해 AE 계열 프로젝트의 구조를 최대한 보존하고, 지원하지 않는 항목은 명확히 보고·대체·bake한다.

### 가져오기 대상

- Composition
- resolution
- frame rate
- layer order
- video·image
- text
- transform
- keyframes
- Bezier curve
- masks
- Blend Mode
- Track Matte
- Parenting
- Null
- Camera
- Light
- basic effects
- Pre-compose

### 비호환 처리

- equivalent effect conversion
- layer-only baked render
- preserve but disable
- missing dependency list
- replacement recommendation
- manual remap
- original parameter payload preservation

### Compatibility Report

- fully compatible layers
- partially compatible layers
- bake required
- unsupported effects
- missing fonts
- missing media
- changed color space
- changed expression
- changed 3D material

### 내보내기

- original media
- proxy-only option
- font list
- effect settings
- mattes
- markers
- Beat Map
- audio analysis
- 3D passes
- unsupported effect pre-render
- path relink manifest

직접 `.aep` 포맷 처리가 안정적이지 않거나 법적·기술적 제약이 있으면, 데스크톱 AE용 Bridge 플러그인이 프로젝트를 공개 중립 패키지로 변환하는 방식을 우선한다.

### 완료 조건

- Compatibility Report가 실제 변환 결과와 일치
- 지원되지 않는 항목이 조용히 삭제되지 않음
- 원본 파라미터 payload 보존
- round-trip 가능한 항목과 bake 항목 명확히 분리
- 누락 폰트·미디어 재연결

---

# 4. 독창적 기능 배치

| 기능 | 버전 | 설명 |
|---|---|---|
| Edit Recipe | v2.0→v4.0 | 프리셋으로 시작해 생태계 패키지로 확장 |
| Motion Search | v2.5 | 자연어로 동작 검색 |
| Effect Lens | v3.4 | 촬영 전 실시간 효과 |
| Gesture Recording | v2.2 | 터치 움직임을 키프레임으로 기록 |
| Style DNA | v3.0 | 색·모션·컷 속도를 분석해 스타일 생성 |
| Smart Replace | v2.5→v3.0 | 템플릿 미디어 교체 후 구도 유지 |
| Motion Cleanup | v2.2 | 수동 키프레임을 부드러운 곡선으로 정리 |
| Effect Explanation | v2.9 | 효과의 작동과 비용을 시각화 |
| Project Doctor | v2.1 | 누락·손상·성능 문제 진단 |
| Frame Inspector | v2.9 | 특정 프레임의 전체 의존성 표시 |
| Smart Asset Library | v2.10 | 소재를 매크로·깊이·조명 반응이 있는 편집 가능한 자산으로 제공 |
| Learn Hub | v2.10→v4.2 | 로컬 학습 패키지에서 커뮤니티 Project Breakdown으로 확장 |
| AI Model Manager | v3.0 | 모델 품질·속도·기기 요구사항·출력을 관리 |
| 3D Particle Workspace | v3.5 | 2D·3D·Depth·Beat 데이터를 파티클에 연결 |
| Material Simulation | v3.6 | 반사·굴절·유리·물리를 공통 재질 시스템으로 제공 |
| AE Project Bridge | v2.8→v4.3 | 중립 교환 모델에서 고급 호환·보고서로 확장 |

---

# 5. 기반 기술 구현 순서

기능 버전과 별개로 다음 기반은 선행되어야 한다.

1. **Project Schema**
2. **Autosave Journal**
3. **Unified Property System**
4. **Render Graph**
5. **Track Matte·Alpha Pipeline**
6. **Cache Graph**
7. **Task Scheduler**
8. **Color Pipeline**
9. **Audio Graph**
10. **Asset Registry**
11. **AI Model Registry**
12. **Render Pass Graph**
13. **Plugin Sandbox**
14. **Schema Migration**
15. **Diagnostics Event Log**

---

# 6. 공통 UX 원칙

## Progressive Disclosure

- 기본 모드: 핵심 매크로와 추천 설정
- 고급 모드: 전체 파라미터·그래프·맵·채널
- 같은 프로젝트 구조를 사용하며 모드 전환 시 데이터 손실 없음

## Direct Manipulation

- Viewer에서 직접 위치·크기·회전
- Gesture Recording
- Brush·Lasso
- Viewer probe
- 실시간 feedback

## Error Prevention

- 파괴적 작업 전 자동 snapshot
- 호환되지 않는 기능 표시
- 예상 메모리·시간·파일 크기
- 렌더 전 누락 의존성 검사
- 실패 시 안전 fallback

## Discoverability

- 검색
- Effect Explanation
- 예시 preview
- parameter animation demo
- 관련 프리셋
- 관련 리소스
- Motion Search

## Mobile Precision

- 햅틱
- 확대 편집
- 두 손 조작
- Apple Pencil
- 숫자 직접 입력
- frame exact snapping
- gesture conflict management

---

# 7. 공통 성능·정밀도 계약

각 효과·도구는 다음 메타데이터를 제공한다.

- GPU accelerated
- CPU fallback
- Neural Engine
- bit depth
- linear-light support
- HDR support
- multi-frame dependency
- random-access cost
- cacheable
- tileable
- memory estimate
- preview substitution
- minimum device tier
- auxiliary output
- alpha mode
- deterministic seed

품질 모드:

- Draft
- Preview
- High
- Final

앱은 열 상태·메모리 압박·배터리에 따라 Preview만 자동 조정하고, Final 결과 설정은 임의로 낮추지 않는다.

---

# 8. 우선순위 재정렬

| 우선순위 | 영역 | 이유 |
|---:|---|---|
| 1 | 프로젝트 복구·Autosave | 작업 신뢰성 |
| 2 | Unified Property·Graph | 모든 모션 기능의 기반 |
| 3 | Proxy·Cache·Task Scheduler | 모바일 성능 기반 |
| 4 | Professional Velocity | 핵심 사용자 수요 |
| 5 | Track Matte·Alpha·Blend | 고급 합성 기반 |
| 6 | Universal Tracking | 효과 연결성 |
| 7 | Object Matte | 전문 합성 |
| 8 | Text·Template | 대중 사용성 |
| 9 | Render Queue·Professional Output | 실제 프로젝트 완결성 |
| 10 | Color Management·Scopes | 전문성 |
| 11 | Audio·Captions | 일반 사용자 확장 |
| 12 | Advanced Map/Temporal Effects | 차별화 |
| 13 | AI Media Engine | 높은 가치지만 높은 비용 |
| 14 | Visual Expression·2.5D | 장기 차별화 |
| 15 | Plugin·Market·Remix | 생태계 |
| 16 | Asset Library·Smart Asset | 반복 작업과 소재 접근성 |
| 17 | Learn Hub·Project Tutorials | 학습·유입·커뮤니티 |
| 18 | 3D Particle·Material·Physics | 장기 시각적 차별화 |
| 19 | AE Project Bridge | 전문 사용자 교환 |

v2.0이 이미 다음 릴리스로 확정되었으므로 프리셋 플랫폼부터 구현하되, v2.0 내부 데이터 모델은 v2.1~v3.x 기반과 호환되게 만든다.

---

# 9. 릴리스 품질 기준

모든 릴리스는 다음을 통과해야 한다.

## 안정성

- 핵심 플로우 강제 종료 0회
- 동일 작업 20회 반복
- 취소 후 UI 복구
- 실패 후 임시 파일 정리
- 저메모리 경고
- thermal state
- background→foreground
- 저장 중 종료
- 외장 저장소 분리

## 미디어

- 3초·30초·3분
- 720p·1080p·4K
- 24·30·60fps
- 세로·가로·정사각형
- Photos·Files
- H.264·HEVC
- SDR·HDR
- variable frame rate
- 알파 영상

## 데이터

- 잘못된 XML
- 알 수 없는 필드
- 이전 스키마
- 누락 폰트
- 누락 미디어
- 손상 캐시
- 플러그인 오류
- 프로젝트 migration

## 렌더

- Preview와 Final 비교
- frame checksum
- resume
- image sequence
- color match
- audio sync
- alpha edge
- deterministic seed

## 진단

- 공유 가능한 로그
- crash-free fallback
- 단계별 진행률
- 실패 원인
- 기기 정보
- 모델·효과 버전
- 메모리·열 상태

---

# 10. v2.0 구현 상태와 다음 게이트

v2.0 Beta 12에 포함된 항목:

- XML Preset schema 1.0
- typed parameter
- curve·macro·dependency·compatibility
- create·edit·import·export
- duplicate·rename·delete
- tags·favorites·search
- validation·migration·quarantine
- Speed Remap·Easing·Camera Shake·Color Palette adapter
- DaFont·Keyfla.me Resource Hub
- Move/Transform category packaging restoration
- Distortion/Warp category packaging restoration
- BCC search aliases

완료 판정 전 필요한 실제 기기 검증:

1. Move/Transform·Distortion/Warp 카테고리 표시
2. 검색 결과와 카테고리 effect ID 일치
3. Preset export→delete→import round-trip
4. macro Easy·Advanced 양방향 동기화
5. 손상 XML quarantine
6. 네 application adapter 실제 반영
7. Resource Hub 외부 링크
8. v1.9.2 렌더 안정화 회귀 없음

v2.1 착수 전 고정할 공통 타입:

```text
ProjectDocument
ProjectCommand
ProjectSnapshot
MediaReference
CacheReference
PresetDocument
AnimatableProperty
KeyframeCurve
DependencyManifest
CompatibilityRule
RenderJob
AssetDescriptor
TutorialPackageManifest
AIModelDescriptor
RenderPassDescriptor
```

다음 구현 우선순위:

1. v2.0 기기 검증과 발견 버그 수정
2. v2.1 Project Reliability·Autosave·Proxy·Cache
3. v2.2 Unified Animation Core·Professional Velocity
4. v2.3 Matte·Alpha·Blend·Composition
5. v2.4 Universal Tracking·Object Matte

---

# 11. 최종 제품 기준

AE Motion이 단순한 모바일 효과 앱을 넘어 전문 도구로 인정받으려면 다음 조건을 만족해야 한다.

- 프로젝트 복구를 신뢰할 수 있다.
- 4K·HDR·다중 효과 프로젝트를 프록시로 편집할 수 있다.
- 모든 속성에 같은 키프레임·그래프가 적용된다.
- 트래킹 결과를 어떤 속성에도 연결할 수 있다.
- 매트·알파·채널·색공간이 정확하다.
- 텍스트·오디오·자막·출력이 독립적인 전문 영역을 가진다.
- 모바일 터치·햅틱·Pencil을 PC 마우스 대체가 아닌 장점으로 사용한다.
- 프리셋과 플러그인이 버전·의존성·안전성을 가진다.
- 고급 효과는 외부 맵·시간·벡터·auxiliary pass로 조합된다.
- Asset Library의 소재는 라이선스·버전·의존성이 명확하며 Smart Asset으로 재사용된다.
- AI 모델은 품질·속도·기기 요구사항을 표시하고 Matte·Depth·Vector 같은 조합 가능한 데이터를 출력한다.
- Tutorials는 완성 영상뿐 아니라 단계·프로젝트·프리셋·자산과 연결된다.
- 3D 장면은 Beauty뿐 아니라 Depth·Normal·Object ID·Motion Vector pass를 2D 합성에 제공한다.
- 데스크톱 호환에서 지원하지 않는 데이터는 삭제하지 않고 보고·보존·bake한다.
- 기능이 많아져도 초보 모드와 고급 모드가 동일한 프로젝트 구조를 공유한다.

**Critical Priority:** v2.0 프리셋 플랫폼의 기기 검증 이후에는 `프로젝트 복구 + 프록시·캐시 + 통합 애니메이션 엔진 + 전문 Matte·알파 처리 + Composite Workspace + 전문 출력`을 우선한다. 그 기반 위에서 `AI Beat Edit + Smart Asset Library + 커스텀 이펙트 패키지`를 사용자 체감 기능으로 확장한다. 고급 이펙트는 `Time Displacement + Vector Field Warp + Procedural Texture`를 범용 엔진으로 먼저 만들고, Heat Distortion·Liquid Warp·Impact Wave·Scan Transition 같은 결과는 프리셋으로 제공한다.
