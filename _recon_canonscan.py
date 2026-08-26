"""
PART 2 reconciliation — scan Flutter lib + backend for canonical FINAL-scope features
that may not yet be catalogued in audit.json.

Searches:
- chat / chatEnabled / chat messages / group chat
- Focus timer / focusTimer / study session timing
- Streak / daily streak / consecutive days
- DOC / DOCX upload + handling
- Offline download / offline cache / reopen after restart / remove offline copy
- Monthly Available Money / Remaining Money / Available Money
- Study time tracking / completed-task stats
"""
import os
import re
from pathlib import Path

ROOT = Path(r"D:\EkThikana_Full_Production_Starter")
LIB = ROOT / "flutter_app" / "lib"
BACKEND = ROOT / "backend" / "app"

patterns = {
    "chat":        r"\bchat\b|chatEnabled|message\s*=|sendMessage|GroupChat|group_chat",
    "focus_timer": r"FocusTimer|focusTimer|focus_timer|focus_session|pomodoro|Pomodoro|StudyTimer|studyTimer",
    "streak":      r"[Ss]treak|consecutive|daysInRow",
    "doc_upload":  r"\.docx?[\"'\)]|\bDOC\b|\bDOCX\b|allowed.*docx|accept.*docx|docx.*pdf",
    "offline":     r"OfflineDownload|offline_mode|offlineCache|savedOffline|isOffline|removeOffline|offline.*reopen|cacheMaterial",
    "money_terms": r"[Mm]onthlyAvailable|monthly_money|availableMoney|remainingMoney|totalSpent|monthlyLimit|monthlyBudget",
    "task_stats":  r"completedCount|completedTaskCount|taskStats|study_time|studyTime|totalMinutes",
}

def scan(root, label):
    print(f"=== {label} ({root}) ===")
    files = list(root.rglob("*.dart")) + list(root.rglob("*.py"))
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for label2, pat in patterns.items():
            for m in re.finditer(pat, text):
                line = text[: m.start()].count("\n") + 1
                snippet = m.group(0)
                rel = f.relative_to(ROOT)
                print(f"  [{label2}] {rel}:{line}  match='{snippet}'")
    print()

scan(LIB, "flutter_app/lib")
scan(BACKEND, "backend/app")
print("=== summary ===")
print("If any of the canonical features above appear in code, they must be catalogued.")
print("If none appear, they are genuine MISSING in the active codebase.")
