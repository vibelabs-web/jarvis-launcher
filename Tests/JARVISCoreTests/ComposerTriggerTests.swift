import Foundation
import Testing
@testable import JARVISCore

@Suite("한 화면 컴포저: @·/ 트리거")
struct ComposerTriggerTests {
    func at(_ s: String) -> ActiveTrigger? { TriggerParser.active(in: s, caretUTF16: (s as NSString).length) }

    @Test("@로 프로젝트, /로 스킬")
    func basic() {
        #expect(at("@") == ActiveTrigger(kind: .project, query: "", range: NSRange(location: 0, length: 1)))
        #expect(at("매출 필터 고쳐줘 @sal")?.query == "sal")
        #expect(at("매출 필터 고쳐줘 @sal")?.kind == .project)
        #expect(at("/jl-ec")?.kind == .skill)
        #expect(at("리뷰해줘 /vibelabs-sdlc:sdlc")?.query == "vibelabs-sdlc:sdlc")
        #expect(at("@고객관")?.query == "고객관")
    }

    @Test("이메일·경로·문장 중간은 트리거 아님")
    func notTriggers() {
        #expect(at("a@b.com") == nil)
        #expect(at("~/notes/books") == nil)
        #expect(at("/Users/me") == nil)
        #expect(at("src/main") == nil)
        #expect(at("매출 필터 ") == nil)
        #expect(at("") == nil)
        #expect(at("@a@b") == nil)
    }

    @Test("커서가 중간에 있으면 커서 앞 낱말만 본다")
    func caretInMiddle() {
        let s = "앞 @crm 뒤"
        let caret = ("앞 @crm" as NSString).length
        #expect(TriggerParser.active(in: s, caretUTF16: caret)?.query == "crm")
        #expect(TriggerParser.active(in: s, caretUTF16: (s as NSString).length) == nil)
    }

    @Test("선택하면 토큰과 뒤 공백 하나를 지운다(본문은 그대로)")
    func removeToken() {
        let s = "날짜 필터 고쳐줘 @sal 오늘 안에"
        let caret = ("날짜 필터 고쳐줘 @sal" as NSString).length
        let t = TriggerParser.active(in: s, caretUTF16: caret)!
        let (out, newCaret) = TriggerParser.removing(t, from: s)
        #expect(out == "날짜 필터 고쳐줘 오늘 안에")
        #expect(newCaret == ("날짜 필터 고쳐줘 " as NSString).length)
        let t2 = at("/jl-echo")!
        #expect(TriggerParser.removing(t2, from: "/jl-echo").text == "")
    }

    @Test("전송 문자열: 스킬 접두 + 본문")
    func outgoing() {
        #expect(ComposerSession.outgoing(text: "  고쳐줘\n", skillInvocation: nil) == "고쳐줘")
        #expect(ComposerSession.outgoing(text: "src 폴더만", skillInvocation: "/review") == "/review src 폴더만")
        #expect(ComposerSession.outgoing(text: "  ", skillInvocation: "/jl-echo") == "/jl-echo")
    }

    @Test("설정 파일에 lastProjectID가 없어도 읽힌다")
    func prefsCompat() throws {
        let old = #"{"useLLM": false, "defaultParentFolder": "/x"}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
        #expect(p.lastProjectID == nil && p.useLLM == false && p.defaultParentFolder == "/x")
    }
}
