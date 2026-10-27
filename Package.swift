// swift-tools-version: 6.0
import PackageDescription

let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLib = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "JARVISLauncher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JARVISLauncher", targets: ["JARVISLauncher"]),
    ],
    targets: [
        .target(name: "JARVISCore", swiftSettings: [.unsafeFlags(["-enable-testing"])]),
        .executableTarget(name: "JARVISLauncher", dependencies: ["JARVISCore"]),
        // 실제 Orca 대상 E2E(화면 없음). 자신이 만든 테스트 터미널에만 보낸다: `swift run JARVISE2E`
        .executableTarget(name: "JARVISE2E", dependencies: ["JARVISCore"]),
        // 받아쓰기 예비 벤치마크(앱과 같은 WhisperCLIRecognizer 경로): `swift run JARVISBench`
        .executableTarget(name: "JARVISBench", dependencies: ["JARVISCore"]),
        // Xcode가 없으면 xctest 러너가 없어 `swift test`가 테스트를 실행하지 않는다(CLT 한계, ADR-3).
        // 그래서 Swift Testing 진입점을 직접 부르는 실행 타깃으로 돌린다: `swift run JARVISCoreTestRunner`
        .executableTarget(
            name: "JARVISCoreTestRunner",
            dependencies: ["JARVISCore"],
            path: "Tests/JARVISCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks, "-enable-testing"])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing",
                                           "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                                           "-Xlinker", "-rpath", "-Xlinker", cltLib])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
