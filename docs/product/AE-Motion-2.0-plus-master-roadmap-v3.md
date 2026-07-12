# AE Motion 2.0+ 통합 제품·엔진 로드맵

작성일: 2026-07-12  
기준 버전: v1.9.2 Beta 11  
문서 목적: Host Extension 안정화 이후, AE Motion을 장기적으로 전문 모바일 편집·합성 플랫폼으로 발전시키기 위한 통합 설계 기준

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
| Add Effects: Move/Transform 카테고리 누락 | 확인된 버그 | v2.0 릴리스 차단 항목으로 수정 |
| Add Effects: Distortion/Warp 카테고리 누락 | 확인된 버그 | v2.0 릴리스 차단 항목으로 수정 |
| Extensions 지연 표시 개선 | v1.9.2 구현 | 실제 기기 검증 후 완료 처리 |
| 사용자 프리셋 플랫폼 | 미구현 | v2.0 |
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
- Alpha Inverted
- Luma Matte
- Luma Inverted
- 모든 레이어를 matte source로 선택
- 하나의 matte를 여러 레이어가 공유
- matte source visibility 유지
- matte blur
- levels
- expand·contract
- feather
- matte stack
- depth matte
- normal·motion vector auxiliary matte

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
- tempo changes
- Kick
- Snare
- Hi-hat
- Bass
- Vocal onset
- Drop
- strength
- confidence

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

### 자동 규칙

- strong beat→cut
- snare→flash
- bass→scale
- high→chromatic aberration
- pre-drop slowdown
- drop velocity preset

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

### 완료 조건

- 4K 장시간 렌더 재개
- 이미지 시퀀스 실패 프레임만 재렌더
- 외장 SSD 분리 후 프로젝트 손상 없음
- OTIO/FCPXML 기본 컷·속도·오디오 왕복 검증

---

## v2.9 — Professional Workspace, Project Diagnostics & Mobile Interaction

### 목표

작은 화면에서도 초보자와 전문가가 같은 프로젝트 구조를 사용하며, 성능 문제를 스스로 분석할 수 있게 한다.

### 탭

- Home
- Projects
- Tools
- Presets
- Templates
- Resources
- Tutorials

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
- 성능 분석 수치와 실제 병목 일치
- 긴 작업 중 앱 background→foreground 복귀
- 제스처 충돌 회귀 테스트

---

## v3.0 — AI Media Engine

### 목표

Depth·Upscale·Noise Reduction·Optical Flow·Repair·Object Removal을 공통 Core ML 실행 계층으로 통합한다.

### 공통 런타임

- model registry
- download
- version
- checksum
- Neural Engine·GPU·CPU
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
- materials
- textures
- HDRI
- animation playback
- imported camera
- imported light
- shadow
- reflection
- depth relation
- Depth Map
- Normal Map
- Object ID
- video texture

모바일에서는 완전한 모델링이 아니라 가져오기·배치·합성을 우선한다.

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

### Plugin 단계

#### Effect Builder

코딩 없이 기존 효과·맵·곡선을 연결한다.

#### Shader Editor

- Metal Shading Language 기반
- 제한된 입력·출력
- 선언형 파라미터
- preview
- compile diagnostics

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
10. **Plugin Sandbox**
11. **Schema Migration**
12. **Diagnostics Event Log**

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

# 10. v2.0 구현 직전 확정 항목

v2.0에서 반드시 먼저 설계할 타입:

```text
PresetDocument
PresetParameter
PresetMacro
PresetTarget
AnimatableProperty
KeyframeCurve
DependencyManifest
CompatibilityRule
PresetValidationResult
PresetApplicationAdapter
```

v2.0 구현 원칙:

1. UI만 만든 가짜 프리셋을 만들지 않는다.
2. 최소 3개 실제 도구에 적용한다.
3. Import·Export round-trip을 자동 테스트한다.
4. 손상된 XML은 격리하고 복구 가능한 부분은 보존한다.
5. 모든 값에 버전과 타입을 명시한다.
6. 폰트·효과·미디어 의존성을 가져오기 전에 검사한다.
7. 매크로는 Advanced 파라미터와 양방향으로 동기화한다.
8. 이후 Animation Core·Text·Color·Audio preset이 같은 문서를 사용하게 한다.
9. Alight Motion private 프로젝트 구조 직접 수정은 v2.0 범위에서 제외한다.
10. v2.0 완료 후 v2.1 Project Reliability 기반을 먼저 구현한다.

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
- 기능이 많아져도 초보 모드와 고급 모드가 동일한 프로젝트 구조를 공유한다.

**Critical Priority:** v2.0 프리셋 플랫폼 이후에는 화려한 AI 기능보다 `프로젝트 복구 + 프록시·캐시 + 통합 애니메이션 엔진 + 트랙 매트·알파 처리 + 전문 출력`을 우선한다. 고급 이펙트는 `Time Displacement + Vector Field Warp + Procedural Texture`를 범용 엔진으로 먼저 만들고, Heat Distortion·Liquid Warp·Impact Wave·Scan Transition 같은 결과는 프리셋으로 제공한다.
