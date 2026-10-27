import Foundation
import Testing

/// `swift run JARVISCoreTestRunner` — Swift Testing 진입점(CLT 환경용)
@main
struct RunnerMain {
    static func main() async {
        let code: CInt = await Testing.__swiftPMEntryPoint()
        exit(code)
    }
}
