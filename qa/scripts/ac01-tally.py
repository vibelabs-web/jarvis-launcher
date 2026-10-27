"""AC-01 집계: 작가님이 직접 누른 핫키 기록을 진단 로그에서 센다(화면 자동화 없음).
마지막 app.launched 이후 줄만 본다. 사용: python3 -I qa/scripts/ac01-tally.py [--out DIR]
"""
import re, sys, pathlib, datetime

root = pathlib.Path(__file__).resolve().parents[2]
log = (root / ".local-data/diagnostics.log").read_text(encoding="utf-8").splitlines()
start = max(i for i, l in enumerate(log) if " app.launched " in l)
lines = log[start:]

cycles, cur = [], None
for l in lines:
    ts = l.split(" ", 1)[0]
    if " hotkey.pressed visible=false" in l:
        cur = {"pressed_at": ts, "shown": False, "inside": None, "focus": None, "screen": None, "closed": False}
        cycles.append(cur)
    elif " panel.show " in l and cur and not cur["shown"]:
        cur["shown"] = True
        m = re.search(r"screen=(-?\d+)", l); cur["screen"] = m.group(1) if m else "?"
        m = re.search(r"insideVisibleFrame=(\w+)", l); cur["inside"] = m.group(1) if m else "?"
    elif " panel.focus " in l and cur and cur["focus"] is None:
        cur["focus"] = "textInputFocused=true" in l
    elif " hotkey.pressed visible=true" in l and cur:
        cur["close_by"] = "hotkey"
    elif " panel.hide" in l and cur and cur["shown"] and not cur["closed"]:
        cur["closed"] = True
        cur.setdefault("close_by", "esc/x/other")

def ok(c):
    return c["shown"] and c["focus"] is True and c["closed"] and c.get("close_by") == "hotkey"

def status(c, last):
    if ok(c): return "PASS"
    if last and c["shown"] and c["focus"] is not False and not c["closed"]: return "진행 중(아직 열려 있음)"
    return "FAIL"

n_ok = sum(ok(c) for c in cycles)
n_fail = sum(status(c, i == len(cycles) - 1) == "FAIL" for i, c in enumerate(cycles))
target = 30
verdict = "FAIL" if n_fail else ("PASS" if n_ok >= target else "부분 증거")
out = [f"# AC-01 수동 핫키 집계 ({datetime.datetime.now().isoformat(timespec='seconds')})",
       f"집계 범위: 진단 로그의 마지막 app.launched 이후 ({lines[0].split(' ',1)[0]}) — 작가님 수동 입력만, 키 이벤트 주입 없음",
       f"열기 시도(핫키 눌러 열림 요청): {len(cycles)}회",
       f"정상 사이클(열림 + 텍스트 입력 포커스 + 두 번째 핫키로 닫힘): {n_ok}회 / 목표 {target}회",
       f"실패 사이클: {n_fail}회",
       f"판정: {verdict}" + (f" (부족분 {target - n_ok}회)" if n_ok < target else ""),
       "", "| # | 눌린 시각(UTC) | 열림 | 화면 | 사용영역 안 | 입력 포커스 | 닫힘 방법 | 결과 |", "|---|---|---|---|---|---|---|---|"]
for i, c in enumerate(cycles, 1):
    out.append(f"| {i} | {c['pressed_at']} | {c['shown']} | {c['screen']} | {c['inside']} | {c['focus']} | "
               f"{c.get('close_by','열린 채')} | {status(c, i == len(cycles))} |")
out += ["", "참고: 키 충돌 안내는 등록 실패 시 메뉴바 아이콘·설정에 표시(이번 실행은 hotkey.register ok=true)."]
text = "\n".join(out) + "\n"
dest = root / "qa/evidence/AC-01"
dest.mkdir(parents=True, exist_ok=True)
f = dest / f"manual-hotkey-tally-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.md"
f.write_text(text, encoding="utf-8")
print(text); print("saved:", f.relative_to(root))
