# Competition Exam Rescue — Live Demo Script (Phase T7)

Audience: Top-10 competition jury, on-device, live, no slide deck.
Total runtime target: **30 seconds**. Extended cut: **90 seconds**.
Everything below is a physical, on-device action. Nothing in this script is
simulated, pre-recorded, or backed by hidden data manipulation.

---

## 1. Preconditions (run once, before the jury session)

| # | Check | Command / action | Pass criterion |
|---|-------|------------------|----------------|
| P1 | Device unlocked, screen timeout ≥ 2 min, brightness ≥ 70% | Device settings | Screen stays on for the whole demo |
| P2 | USB debugging on, `adb devices` shows the device | `adb devices` | One device listed as `device` |
| P3 | App installed from a T7 debug build | `flutter build apk --debug --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com …` then `adb install -r app-debug.apk` | `install` reports `Success` |
| P3b | Build defines present | — | `API_BASE_URL` **must** be passed or every AI/backend call fails with `Backend URL is not configured…` |
| P4 | Signed in as the demo student | Launch app | Lands on **Today**, not the login screen |
| P5 | Active rescue session exists | Look at Today | `EXAM RESCUE` card visible with a future exam |
| P6 | Backend reachable (Render cold start) | `curl https://ekthikana-api-x473.onrender.com/api/health` | HTTP 200 (warm it up 60 s before the session) |
| P7 | Wi-Fi/cellular stable, battery ≥ 60% | Device status | No low-battery / offline banner on Today |
| P8 | App language English, Study mode active | Today app bar | `Today` heading, 5 Study tabs at the bottom |
| P9 | At least one rescue quiz task is still incomplete | Plan tab | A `Take Quiz` button is visible |
| P10 | Logcat recording started (for evidence) | `adb logcat -c && adb logcat -v time > demo_logcat.txt` | File grows while you interact |
| P11 | AI quiz quota available | `AI usage` screen or backend quota | Fewer than **3** quiz generations used this month — the app blocks with `AI Quiz limit reached. You have used all 3 quiz generations this month…` |
| P12 | Warm app already running | Launch once before the jury session | Cold start measures **~10 s** (`am start -W` → `WaitTime: 10342`), warm resume is ~2 s |

If **P5** fails: run the 30-second *creation* variant in §4 instead.

---

## 2. The 30-second run-of-show

Read the "Say" column out loud while performing the "Do" column. Times are
cumulative and are the acceptance budget for the rehearsal.

| t | Do (finger action) | Screen must show | Say |
|---|--------------------|------------------|-----|
| 0 s | Launch / tap **Today** | `EXAM RESCUE` badge, exam title, `3 days left` | "Gochano sees my exam is in three days and puts my rescue plan on the first screen." |
| 4 s | Read the numbers, then tap **Continue Rescue** | `2 of 4 rescue tasks completed`, `50%`, `120 min planned today` | "Two of four tasks done, 120 minutes planned for today — all read from real tasks." |
| 8 s | Land on **Plan**; point at the banner | `Exam Rescue: Optical Fiber Midterm`, `2 days remaining · Active Plan`, `+ New Plan` | "Plan shows the same live session — same listener, not a second copy of my data." |
| 12 s | Point at a rescue quiz row, tap **Take Quiz** | Quiz Generator opens with the task's topic pre-filled (`Comprehensive Mock Quiz`) | "The plan knows the quiz task's topic and hands it straight to the generator." |
| 14 s | Tap **Select** → tap a document → tap **Select (1)** | Material chip appears; the confirm button reads `Select (1)` | "Source material is chosen explicitly — the count is always visible." |
| 17 s | Set **Number of Questions** to `5`, tap **Generate Quiz** | `Generating…`, then the interactive questions | "Five questions keeps the AI response inside the model's output budget." |
| 22 s | Answer all 5, tap **Submit Quiz** | Result screen with score, topic bars in 0–100 %, `Result saved` | "Topic mastery is a percentage, the same unit the backend weak-topic engine uses." |
| 24 s | Return to **Plan** | The same row now shows a `Completed` badge (and leaves *Due this day*) | "Saving the result marks the task done and the UI reflects it immediately." |
| 27 s | Tap **Today** | Progress on the rescue card has increased | "No refresh button — the progress stream updated by itself." |
| 30 s | End on **Today** | Card, Today's tasks, and the overdue badge (if any) | "One session, three surfaces, one listener." |

### 30-second acceptance (all must be true, no exceptions)

> All numbers in the table are **live**: the day pill, `x of y rescue tasks`
> and `50%` come from the current session and today's date — never hardcode
> them in your speech. Example from the T7 capture: the run crossed midnight,
> so `2 days left` became `1 day left` and the card recomputed its day's task
> set without a refresh.

- [ ] No red error banner, no `Unable to load tasks`, no infinite skeleton
- [ ] No overflow / `RenderFlex` exception toast, nothing clipped at the edges
- [ ] No `FirebaseException`, `SocketException`, or unhandled Dart exception in logcat
- [ ] Progress numbers on Today and Plan agree at the end
- [ ] Nothing on screen claims a completion that did not happen

---

## 3. The 90-second extended cut (only if the jury asks "show me more")

| t | Action | Expected |
|---|--------|----------|
| 30–38 s | Tap **Workspace** → point at the `Exam Rescue` row | `Exam in <N> day(s) · View plan` (live count) |
| 38–46 s | Tap it → jumps to **Plan** banner | Same session title, `+ New Plan` |
| 46–54 s | Tap `+ New Plan` → setup sheet | Title field, exam-date chips, `2h 0m` daily budget, `0 of 3 selected` |
| 54–62 s | Type a title, pick a date, tap **Generate Rescue Plan…** | Loading label `Generating Rescue Plan…` (dismiss is blocked during generation) |
| 62–72 s | Preview screen | Day-by-day list, badges, the `General subject-based plan` / fallback transparency label where applicable, **Apply** |
| 72–80 s | Apply → back on Plan | Success message, new rescue tasks appear in Today's schedule |
| 80–86 s | Toggle **Language** to বাংলা | Today hero reads `পরীক্ষা উদ্ধার`, `৩ দিন বাকি`, CTA `উদ্ধার চালিয়ে যান` |
| 86–90 s | Toggle back to English, end on Today | Everything returns to English, no rebuild flash |

---

## 4. 30-second "no active session" variant (P5 failed)

| t | Do | Screen must show |
|---|----|------------------|
| 0 s | Today | No rescue card; ordinary Today's tasks list |
| 4 s | Workspace | `Exam Rescue` with `Exam close? Build a quick rescue plan.` |
| 8 s | Tap it → Plan | `Exam Rescue` / `Exam close? Build a focused rescue plan.` / `Build Plan` |
| 14 s | Tap `Build Plan` | Setup sheet opens, all fields usable |
| 20 s | Cancel | Returns to Plan, no error state left behind |
| 26 s | Home/Today | Still normal — nothing was created by just opening the sheet |

---

## 5. Bangla (bilingual) proof — 15 seconds, optional but rewarded

| Surface | English | Bangla (must match exactly) |
|---------|---------|-----------------------------|
| Today hero eyebrow | `EXAM RESCUE` | `পরীক্ষা উদ্ধার` |
| Today hero days pill | `3 days left` / `Exam Today` | `৩ দিন বাকি` / `পরীক্ষা আজ` |
| Today hero CTA | `Continue Rescue` | `উদ্ধার চালিয়ে যান` |
| Setup sheet title | `Exam Rescue` | `এক্সাম রেসকিউ` |
| Plan banner | `Exam Rescue` | `পরীক্ষা উদ্ধার` |
| Quiz CTA on a rescue row | `Take Quiz` | `কুইজ দিন` |

> **Known, intentional wording variance:** the setup sheet and the preview
> screen title are `এক্সাম রেসকিউ`, while the Today hero, Workspace tile and
> Plan banner use `পরীক্ষা উদ্ধার`. Both are pinned by regression tests
> (`exam_rescue_flow_test.dart`, `exam_rescue_active_experience_test.dart`);
> do not "unify" one into the other — it will fail the suite.

---

## 6. Demo checklist (complete during rehearsal, keep the signed copy)

### Build & static gates
- [ ] `flutter analyze lib/` → `No issues found!`
- [ ] `dart format` on every T7-touched file → 0 changed
- [ ] `git diff --check` → exit 0, no output
- [ ] `flutter build apk --debug` → √ built
- [ ] `flutter build apk --release` → √ built
- [ ] `flutter build appbundle --release` → √ built

### Automated test gates
- [ ] Rescue batch (models + flow + persistence + active experience + home mode + overdue + shell + quiz integration) → **141 passed**
- [ ] `test/exam_rescue_active_experience_test.dart` → **23 passed**
- [ ] `test/exam_rescue_flow_test.dart` → **23 passed**
- [ ] `test/exam_rescue_quiz_integration_test.dart` → **18 passed** (incl. the two T7 MCQ-scoring tests)
- [ ] `backend/tests/test_ai_exam_rescue.py` → **21 passed**
- [ ] Full Flutter suite compared against the HEAD baseline → no new failures

### Live device gates
- [ ] App launches to Today without a red banner
- [ ] Active rescue card renders on Today (EN and BN)
- [ ] Workspace tile shows the live days-remaining subtitle and jumps to Plan
- [ ] Plan banner shows the session title and `+ New Plan`
- [ ] Setup → generate → preview → apply creates real tasks
- [ ] `Take Quiz` → result → task shows `Completed`; Today progress increases
- [ ] Restart the app: the session and progress come back (no data loss)
- [ ] Airplane mode: Today/Plan degrade gracefully with a friendly message, no crash
- [ ] Logcat captured end-to-end with no `E/AndroidRuntime`, no unhandled Dart exception

---

## 7. Backup artifacts (use when live demo cannot run)

Already captured in `docs/device_smoke_artifacts/` from earlier phases:

| Beat | Backup file |
|------|-------------|
| Login / entry | `login_dev.png` |
| Today baseline (no session) | `00_baseline.png`, `today_tab.png` |
| Setup sheet | `setup_sheet.png`, `setup_filled.png`, `setup_scrolled.png` |
| Generation loading | `gen_loading.png`, `ready_to_gen.png` |
| Preview + item removal | `01_preview.png`, `02_item_removed.png`, `preview_scroll.png` |
| Apply + plan tasks | `03_apply_success.png`, `04_plan_tasks.png`, `today_after_apply.png` |
| Today active rescue | `13_today_active_rescue.png` |
| Workspace discovery | `14_workspace_exam_rescue.png`, `workspace_more.png` |
| Plan active banner | `15_plan_active_rescue.png` |
| Take quiz | `16_take_quiz.png`, `quiz_generator.png` |
| Quiz result | `17_quiz_result.png` |
| Task marked completed | `18_quiz_task_completed.png` |
| Today progress updated | `19_today_after_quiz.png` |
| Persistence after restart | `09_after_restart.png`, `20_after_restart_active_rescue.png` |
| Bangla surfaces | `11_bangla_today.png`, `12_bangla_plan.png`, `21_bangla_active_rescue.png` |
| Logcat | `t6_5_logcat.txt` (older run), plus the logcat captured in §1 P10 for T7 |

### Captured in the T7 physical device run (`docs/device_smoke_artifacts/`)

| Beat | T7 file |
|------|---------|
| Cold launch / login screen | `T7_00_launch.png`, `T7_01_login.png` |
| Today active rescue card (EN) | `T7_01_today_en.png`, `T7_12_today_final.png` |
| Plan active banner + tasks | `T7_02_plan_en.png`, `T7_06_plan_after_quiz.png` |
| Workspace discovery tile | `T7_03_workspace_en.png` |
| Quiz generator + material picker | `T7_04_take_quiz.png`, `T7_04c_material_selected.png`, `T7_10b_material_selected.png` |
| 5-question selection | `T7_05f_count5.png`, `T7_10c_count5.png` |
| Interactive quiz | `T7_04g_q1_answered.png`, `T7_05g_quiz_complete.png` |
| Result screen (`Result saved`, progress message) | `T7_05_result_screen.png` |
| Today progress after quiz | `T7_07_today_progress.png` |
| Bangla Today | `T7_08_today_bn.png` |
| Persistence after force-stop + relaunch | `T7_09_restart.png` |
| AI quota limit (honest block) | `T7_11_ai_quota_limit.png` |
| Raw-JSON fallback (10-question truncation) | `T7_05_raw_or_quiz.png`, `T7_05b_ai_response.png` |
| Missing `API_BASE_URL` message | `T7_10d_state.png` |
| Cold start measurement | `T7_12_cold_start_today.png` |
| Full logcat for the run | `T7_logcat.txt` (21 MB, no `E/AndroidRuntime`, no `FATAL EXCEPTION`, no `ANR in`) |

---

## 8. Known failure modes and the honest recovery

| Symptom | Cause | Recovery (say it, do not hide it) |
|---------|-------|-----------------------------------|
| First AI call takes ~30 s or fails | Render cold start / daily quota | "Backend is on a free tier and cold-starts; retry once, and the UI shows the daily-limit message." |
| `AI Quiz limit reached. You have used all 3 quiz generations this month…` | Monthly AI quiz quota (3) | "The limit is real and shown verbatim — there is no silent bypass. Rehearse with a free quota or reset it on the 1st." |
| `Backend URL is not configured. Run Flutter with --dart-define=API_BASE_URL=…` | Debug build missing the define | "Build with `--dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com`; never bake it into source." |
| `AI Response` card shows raw JSON, no questions | 10+ question responses exceed the provider's `max_tokens` (1600) and the JSON is truncated | "Pick 5 questions; the raw output is shown honestly instead of a fake success. Backend cap fix is tracked separately." |
| `No internet connection…` banner | Device offline | "This is the dedicated network message, shown instead of a fake success." |
| Session absent on Today | No exam within range, or exam already past | "Expired sessions are filtered out on purpose; here is how you create a new one (§4)." |
| `Take Quiz` shows a snackbar about material | Rescue quiz without a linked material | "The row tells the student to pick material instead of opening an empty quiz." |
| Progress did not move | Save failed | "The failure surfaces as an error; we never show 'completed' when the write failed." |

---

## 9. Rehearsal script (three runs minimum before the session)

1. **Run A (cold):** kill the app, clear nothing, launch, do §2. Record time.
2. **Run B (warm):** immediately repeat §2. Record time — must be ≤ 30 s.
3. **Run C (adversarial):** enable airplane mode mid-run; confirm §8 row 2 appears and the app survives; then re-run §2 online.
4. Save `T7_logcat.txt` from run B (the fastest) as the evidence log.

Rehearsal acceptance: three consecutive runs with **zero** red banners, zero
overflow exceptions, and total elapsed ≤ 30 s for §2.
