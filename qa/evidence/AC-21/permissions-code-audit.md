# AC-21 권한 최소화 — 코드 점검 2026-10-27T19:44:10+09:00
## 권한 요청 API 사용 위치 (grep)
- AXIsProcessTrusted: 0건 
- CGRequestScreenCaptureAccess: 0건 
- CGPreflightScreenCaptureAccess: 0건 
- SCShareableContent: 0건 
- CGEventPost: 0건 
- CGEventTapCreate: 0건 
- requestAccess: 1건     Sources/JARVISLauncher/Audio/MicRecorder.swift:21:        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
- FullDiskAccess: 0건 

## Info.plist 권한 문구
	<key>NSMicrophoneUsageDescription</key>
	<string>받아쓰기 버튼을 누를 때만 마이크를 사용합니다. 음성은 이 Mac 안에서만 처리하고 저장하지 않습니다.</string>

해석: 마이크(AVCaptureDevice.requestAccess)만 받아쓰기 버튼 동작 시 요청. 전역 핫키는 Carbon RegisterEventHotKey(접근성 불필요). 접근성·화면기록·전체디스크 API 사용 0건.
미확인: 마이크 '거부' 상태에서의 실제 동작(UI 수동 확인 필요).
