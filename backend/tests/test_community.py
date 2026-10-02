"""Phase 7 — Ziku Learning Community tests.

Covers the new ``/api/community`` surface (Question Bank, Learning Points,
Exam Challenges), the Ziku Moderator + group quizzes on ``/api/groups``,
the spec 7.7 group ``kind``/``category`` fields and the family-link
architecture. Everything runs against the real FastAPI app through the
shared ``client`` fixture (FakeFirestore + FakeAuth); AI seams are
monkeypatched so no test ever needs a provider key.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import AsyncMock

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _seed_group(db, group_id="grp-p7", *, owner="p7-owner", members=None,
                name="Physics HSC 2027"):
    members = members or [owner]
    db.seed(
        "groups",
        group_id,
        {
            "name": name,
            "description": "Physics board prep",
            "ownerId": owner,
            "adminIds": [owner],
            "memberIds": members,
            "category": "hsc",
            "kind": "study",
            "chatEnabled": True,
        },
    )
    return group_id


def _seed_post(db, post_id, **overrides):
    data = {
        "kind": "question",
        "title": "What is the lens formula?",
        "body": "1/f = 1/v - 1/u?",
        "category": "hsc",
        "groupId": "",
        "groupName": "",
        "authorId": "p7-asker",
        "authorName": "Asker",
        "subject": "Physics",
        "chapter": "Optics",
        "status": "active",
        "answerCount": 0,
        "usefulCount": 0,
        "usefulBy": [],
        "acceptedAnswerId": "",
        "attachments": [],
        "createdAtIso": "2026-10-01T10:00:00+00:00",
    }
    data.update(overrides)
    db.seed("community_posts", post_id, data)
    return post_id


def _seed_answer(db, post_id, answer_id, **overrides):
    data = {
        "postId": post_id,
        "authorId": "p7-answerer",
        "authorName": "Answerer",
        "body": "Use the lens formula with sign conventions.",
        "accepted": False,
        "helpful": False,
        "createdAtIso": "2026-10-01T11:00:00+00:00",
    }
    data.update(overrides)
    db.seed(f"community_posts/{post_id}/answers", answer_id, data)
    return answer_id


def _seed_exam(db, uid="p7-challenger", exam_id="ex-p7", *, count=3):
    db.seed(
        f"users/{uid}/exams",
        exam_id,
        {
            "examId": exam_id,
            "title": "Physics PT 1",
            "subject": "Physics",
            "questionCount": count,
            "timeLimitMinutes": 20,
        },
    )
    for i in range(count):
        db.seed(
            f"users/{uid}/exams/{exam_id}/exam_questions",
            str(i),
            {
                "index": i,
                "question": f"Question {i + 1}: light behaves as?",
                "type": "mcq",
                "options": ["wave", "particle", "both", "none"],
                "correct": "C",
                "explanation": "Wave-particle duality.",
                "topic": "Optics",
                "marks": 1.0,
                "difficulty": "medium",
                "needsReview": False,
            },
        )
    return exam_id


def _ai_json(payload: dict):
    async def _fake(uid, prompt, feature=None):
        return json.dumps(payload)
    return _fake


# ---------------------------------------------------------------------------
# Learning posts (spec 7.3 / 7.5)
# ---------------------------------------------------------------------------

def test_create_question_post_ai_tags_subject_and_chapter(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import community_service as community

    uid = "p7-student"
    seed_profile(fake_db, uid, name="Rahim")
    monkeypatch.setattr(
        community,
        "_ai",
        _ai_json({"subject": "Physics", "chapter": "Optics", "isDuplicate": False}),
    )

    resp = client.post(
        "/api/community/posts",
        json={
            "kind": "question",
            "title": "Why does a lens form a real image?",
            "body": "In ray optics...",
            "category": "hsc",
        },
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["subject"] == "Physics"
    assert body["chapter"] == "Optics"
    assert body["analyzedBy"] == "ai"
    assert body["kind"] == "question"
    stored = fake_db._collections["community_posts"][body["id"]]
    assert stored["subject"] == "Physics"
    assert stored["authorId"] == uid


def test_create_post_falls_back_to_rule_based_tags_offline(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import community_service as community

    uid = "p7-offline"
    seed_profile(fake_db, uid)

    async def _boom(uid, prompt, feature=None):
        raise RuntimeError("no provider")

    monkeypatch.setattr(community, "_ai", _boom)

    resp = client.post(
        "/api/community/posts",
        json={
            "kind": "question",
            "title": "Derivative of sin x",
            "body": "calculus homework",
            "category": "hsc",
        },
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["analyzedBy"] == "fallback"
    assert body["subject"] == "Mathematics"


def test_duplicate_question_is_flagged(client, fake_db, fake_auth):
    uid = "p7-dupe"
    seed_profile(fake_db, uid)
    _seed_post(
        fake_db,
        "p7-first",
        title="What is the lens formula in ray optics",
        body="1/f = 1/v - 1/u sign conventions",
    )

    resp = client.post(
        "/api/community/posts",
        json={
            "kind": "question",
            "title": "What is the lens formula in ray optics",
            "body": "1/f = 1/v - 1/u sign conventions",
            "category": "hsc",
        },
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["duplicateOf"] == "p7-first"
    assert body["duplicateConfidence"] >= 0.75


def test_post_kind_and_category_are_validated(client, fake_db, fake_auth):
    uid = "p7-validate"
    seed_profile(fake_db, uid)
    headers = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/community/posts",
        json={"kind": "meme", "title": "x", "body": "y"},
        headers=headers,
    )
    assert resp.status_code == 422, resp.text

    resp = client.post(
        "/api/community/posts",
        json={"kind": "question", "title": "x", "body": "y", "category": "random"},
        headers=headers,
    )
    assert resp.status_code == 400, resp.text


def test_list_posts_filters_kind_category_and_popularity(
    client, fake_db, fake_auth
):
    uid = "p7-list"
    seed_profile(fake_db, uid)
    _seed_post(fake_db, "p1", kind="question", category="hsc",
               createdAtIso="2026-10-01T09:00:00+00:00")
    _seed_post(fake_db, "p2", kind="notes", category="ielts",
               title="IELTS writing notes", createdAtIso="2026-10-02T09:00:00+00:00")
    _seed_post(fake_db, "p3", kind="question", category="hsc",
               answerCount=5, createdAtIso="2026-09-30T09:00:00+00:00")
    headers = bearer(fake_auth.issue(uid))

    resp = client.get("/api/community/posts?kind=question", headers=headers)
    assert resp.status_code == 200, resp.text
    ids = [p["id"] for p in resp.json()["posts"]]
    assert set(ids) == {"p1", "p3"}
    # newest first
    assert ids[0] == "p1"

    resp = client.get("/api/community/posts?category=ielts", headers=headers)
    assert [p["id"] for p in resp.json()["posts"]] == ["p2"]

    resp = client.get("/api/community/posts?popular=true", headers=headers)
    assert resp.json()["posts"][0]["id"] == "p3"


def test_group_posts_require_membership(client, fake_db, fake_auth):
    owner = "p7-member"
    stranger = "p7-stranger"
    seed_profile(fake_db, owner)
    seed_profile(fake_db, stranger)
    _seed_group(fake_db, owner=owner, members=[owner])

    # member can post into the group
    resp = client.post(
        "/api/community/posts",
        json={"kind": "question", "title": "Group doubt", "body": "help", "groupId": "grp-p7"},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    post_id = resp.json()["id"]
    assert resp.json()["groupName"] == "Physics HSC 2027"

    # stranger: create, list and read are all denied
    resp = client.post(
        "/api/community/posts",
        json={"kind": "question", "title": "Nope", "body": "x", "groupId": "grp-p7"},
        headers=bearer(fake_auth.issue(stranger)),
    )
    assert resp.status_code == 403, resp.text

    resp = client.get(
        "/api/community/posts?group_id=grp-p7",
        headers=bearer(fake_auth.issue(stranger)),
    )
    assert resp.status_code == 403, resp.text

    resp = client.get(
        f"/api/community/posts/{post_id}",
        headers=bearer(fake_auth.issue(stranger)),
    )
    assert resp.status_code == 403, resp.text


def test_answers_and_accept_award_five_points(client, fake_db, fake_auth):
    asker = "p7-asker2"
    answerer = "p7-answerer2"
    seed_profile(fake_db, asker)
    seed_profile(fake_db, answerer, name="Sara")
    _seed_post(fake_db, "p-acc", authorId=asker, authorName="Asker")
    headers_a = bearer(fake_auth.issue(asker))
    headers_b = bearer(fake_auth.issue(answerer))

    resp = client.post(
        "/api/community/posts/p-acc/answers",
        json={"body": "Because the object is beyond 2f."},
        headers=headers_b,
    )
    assert resp.status_code == 200, resp.text
    answer_id = resp.json()["id"]
    assert resp.json()["postAnswerCount"] == 1

    # only the asker may accept
    resp = client.post(
        f"/api/community/posts/p-acc/answers/{answer_id}/accept",
        headers=headers_b,
    )
    assert resp.status_code == 403, resp.text

    resp = client.post(
        f"/api/community/posts/p-acc/answers/{answer_id}/accept",
        headers=headers_a,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 5

    rep = fake_db._collections["community_reputation"][answerer]
    assert rep["points"] == 5
    assert rep["breakdown"]["answer_accepted"] == 1
    assert rep["displayName"] == "Sara"

    # double accept rejected
    resp = client.post(
        f"/api/community/posts/p-acc/answers/{answer_id}/accept",
        headers=headers_a,
    )
    assert resp.status_code == 400, resp.text


def test_self_answer_accept_gives_no_points(client, fake_db, fake_auth):
    uid = "p7-self"
    seed_profile(fake_db, uid)
    _seed_post(fake_db, "p-self", authorId=uid, authorName="Self")
    _seed_answer(fake_db, "p-self", "a-self", authorId=uid, authorName="Self")
    headers = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/community/posts/p-self/answers/a-self/accept",
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 0
    assert "community_reputation" not in fake_db._collections


def test_helpful_marks_award_three_points_once(client, fake_db, fake_auth):
    asker = "p7-help-asker"
    helper = "p7-helper"
    author = "p7-help-author"
    seed_profile(fake_db, asker)
    seed_profile(fake_db, helper)
    seed_profile(fake_db, author, name="Ali")
    _seed_post(fake_db, "p-help", authorId=asker)
    _seed_answer(fake_db, "p-help", "a-help", authorId=author, authorName="Ali")
    headers = bearer(fake_auth.issue(helper))
    headers_author = bearer(fake_auth.issue(author))

    # the author cannot mark their own answer helpful
    resp = client.post(
        "/api/community/posts/p-help/answers/a-help/helpful",
        headers=headers_author,
    )
    assert resp.status_code == 400, resp.text

    resp = client.post(
        "/api/community/posts/p-help/answers/a-help/helpful",
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 3

    # idempotent: no double award
    resp = client.post(
        "/api/community/posts/p-help/answers/a-help/helpful",
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 0
    assert fake_db._collections["community_reputation"][author]["points"] == 3


def test_useful_notes_award_ten_points(client, fake_db, fake_auth):
    author = "p7-notes-author"
    reader = "p7-notes-reader"
    seed_profile(fake_db, author, name="Karim")
    seed_profile(fake_db, reader)
    _seed_post(fake_db, "p-notes", kind="notes", title="Optics summary",
               authorId=author, authorName="Karim")
    headers = bearer(fake_auth.issue(reader))
    headers_author = bearer(fake_auth.issue(author))

    # kind gate: a question cannot be marked useful
    _seed_post(fake_db, "p-not-notes", kind="question", authorId=author)
    resp = client.post(
        "/api/community/posts/p-not-notes/useful",
        headers=headers,
    )
    assert resp.status_code == 400, resp.text

    resp = client.post("/api/community/posts/p-notes/useful", headers=headers_author)
    assert resp.status_code == 400, resp.text  # own note

    resp = client.post("/api/community/posts/p-notes/useful", headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 10

    # second peer: count grows, points do not
    seed_profile(fake_db, "p7-notes-reader-2")
    resp = client.post(
        "/api/community/posts/p-notes/useful",
        headers=bearer(fake_auth.issue("p7-notes-reader-2")),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["pointsAwarded"] == 0
    assert resp.json()["usefulCount"] == 2
    assert fake_db._collections["community_reputation"][author]["points"] == 10


def test_leaderboard_global_and_group_scopes(client, fake_db, fake_auth):
    uid = "p7-board"
    seed_profile(fake_db, uid)
    _seed_group(fake_db, owner=uid, members=[uid, "u-top"])
    fake_db.seed(
        "community_reputation",
        "u-top",
        {
            "uid": "u-top",
            "displayName": "Top Student",
            "points": 18,
            "breakdown": {"answer_accepted": 3},
            "groupPoints": {"grp-p7": 15},
        },
    )
    fake_db.seed(
        "community_reputation",
        uid,
        {
            "uid": uid,
            "displayName": "Me",
            "points": 8,
            "breakdown": {"helpful_explanation": 2},
            "groupPoints": {"grp-p7": 3},
        },
    )
    headers = bearer(fake_auth.issue(uid))

    resp = client.get("/api/community/leaderboard", headers=headers)
    assert resp.status_code == 200, resp.text
    entries = resp.json()["entries"]
    assert entries[0]["displayName"] == "Top Student"
    assert entries[0]["points"] == 18

    resp = client.get(
        "/api/community/leaderboard?scope=group&group_id=grp-p7",
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    group_entries = resp.json()["entries"]
    assert group_entries[0]["uid"] == "u-top"
    assert group_entries[0]["points"] == 15

    # a stranger cannot read the group leaderboard
    seed_profile(fake_db, "p7-outside")
    resp = client.get(
        "/api/community/leaderboard?scope=group&group_id=grp-p7",
        headers=bearer(fake_auth.issue("p7-outside")),
    )
    assert resp.status_code == 403, resp.text


def test_community_requires_student_role(client, fake_db, fake_auth):
    fake_auth.tokens["token-p7-general"] = {
        "uid": "u-p7-general",
        "email": "g@example.com",
        "email_verified": True,
        "role": "general",
    }
    fake_db.seed(
        "users",
        "u-p7-general",
        {"role": "general", "displayName": "Parent", "emailVerified": True},
    )
    resp = client.get(
        "/api/community/posts",
        headers=bearer("token-p7-general"),
    )
    assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# Group category / kind (spec 7.5 + 7.7)
# ---------------------------------------------------------------------------

def test_create_group_stores_category_and_defaults(client, fake_db, fake_auth):
    uid = "p7-group-create"
    seed_profile(fake_db, uid)
    resp = client.post(
        "/api/groups",
        json={"name": "Physics HSC 2027 Group", "description": "board prep",
              "category": "HSC"},
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 200, resp.text
    group_id = resp.json()["id"]
    stored = fake_db._collections["groups"][group_id]
    assert stored["category"] == "hsc"
    assert stored["kind"] == "study"
    assert stored["roles"] == {uid: "student"}


def test_create_class_group_records_teacher_role(client, fake_db, fake_auth):
    uid = "p7-teacher"
    seed_profile(fake_db, uid)
    resp = client.post(
        "/api/groups",
        json={"name": "CSE Section A", "kind": "class", "category": "university"},
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 200, resp.text
    stored = fake_db._collections["groups"][resp.json()["id"]]
    assert stored["kind"] == "class"
    assert stored["roles"] == {uid: "teacher"}


def test_create_group_rejects_unknown_category_and_kind(client, fake_db, fake_auth):
    uid = "p7-group-bad"
    seed_profile(fake_db, uid)
    headers = bearer(fake_auth.issue(uid))
    resp = client.post(
        "/api/groups",
        json={"name": "Bad Category", "category": "party"},
        headers=headers,
    )
    assert resp.status_code == 400, resp.text
    resp = client.post(
        "/api/groups",
        json={"name": "Bad Kind", "kind": "club"},
        headers=headers,
    )
    assert resp.status_code == 400, resp.text


# ---------------------------------------------------------------------------
# Exam Challenge Mode (spec 7.4)
# ---------------------------------------------------------------------------

def test_create_challenge_from_exam_and_redacts_answers(
    client, fake_db, fake_auth
):
    uid = "p7-challenger"
    seed_profile(fake_db, uid, name="Rahim")
    _seed_exam(fake_db, uid)
    headers = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/community/challenges",
        json={"title": "Physics Challenge", "examId": "ex-p7",
              "questionCount": 3, "timeLimitMinutes": 15},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["title"] == "Physics Challenge"
    assert body["questionCount"] == 3
    assert body["status"] == "pending"
    assert body["inviteCode"]
    # the payload must not leak the answer key
    assert "correct" not in json.dumps(body).lower().replace('"correctflags"', "")
    stored = fake_db._collections["community_challenges"][body["id"]]
    assert stored["questions"][0]["correct"] == "C"
    # targeted-opponent restriction: nobody else can fetch it
    seed_profile(fake_db, "p7-outsider")
    resp = client.get(
        f"/api/community/challenges/{body['id']}",
        headers=bearer(fake_auth.issue("p7-outsider")),
    )
    assert resp.status_code == 403, resp.text


def test_challenge_requires_existing_exam_with_questions(
    client, fake_db, fake_auth
):
    uid = "p7-noexam"
    seed_profile(fake_db, uid)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "missing-exam"},
        headers=bearer(fake_auth.issue(uid)),
    )
    assert resp.status_code == 404, resp.text


def test_challenge_join_accept_flow(client, fake_db, fake_auth):
    challenger = "p7-ch-join"
    opponent = "p7-op-join"
    seed_profile(fake_db, challenger)
    seed_profile(fake_db, opponent, name="Sara")
    _seed_exam(fake_db, challenger, exam_id="ex-join", count=2)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "ex-join", "questionCount": 2, "timeLimitMinutes": 10},
        headers=bearer(fake_auth.issue(challenger)),
    )
    challenge_id = resp.json()["id"]
    code = resp.json()["inviteCode"]
    headers_opp = bearer(fake_auth.issue(opponent))

    # wrong code
    resp = client.post(
        "/api/community/challenges/join",
        json={"code": "ZZZZZZZZ"},
        headers=headers_opp,
    )
    assert resp.status_code == 404, resp.text

    # the challenger cannot join their own challenge
    resp = client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=bearer(fake_auth.issue(challenger)),
    )
    assert resp.status_code == 400, resp.text

    resp = client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=headers_opp,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "accepted"
    assert body["opponentName"] == "Sara"

    # re-join rejected
    resp = client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=headers_opp,
    )
    assert resp.status_code == 400, resp.text


def test_targeted_challenge_only_that_classmate_can_join(
    client, fake_db, fake_auth
):
    challenger = "p7-ch-target"
    target = "p7-op-target"
    stranger = "p7-op-stranger"
    for uid in (challenger, target, stranger):
        seed_profile(fake_db, uid)
    _seed_group(fake_db, owner=challenger, members=[challenger, target])
    _seed_exam(fake_db, challenger, exam_id="ex-target", count=2)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "ex-target", "opponentId": target},
        headers=bearer(fake_auth.issue(challenger)),
    )
    assert resp.status_code == 200, resp.text
    code = resp.json()["inviteCode"]

    resp = client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=bearer(fake_auth.issue(stranger)),
    )
    assert resp.status_code == 403, resp.text

    resp = client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=bearer(fake_auth.issue(target)),
    )
    assert resp.status_code == 200, resp.text


def test_targeted_challenge_requires_shared_group(client, fake_db, fake_auth):
    challenger = "p7-ch-nogroup"
    other = "p7-op-nogroup"
    seed_profile(fake_db, challenger)
    seed_profile(fake_db, other)
    _seed_exam(fake_db, challenger, exam_id="ex-nogroup", count=1)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "ex-nogroup", "opponentId": other},
        headers=bearer(fake_auth.issue(challenger)),
    )
    assert resp.status_code == 404, resp.text


def _joinable_challenge(client, fake_db, fake_auth, *, question_count=3):
    challenger = "p7-flow-ch"
    opponent = "p7-flow-op"
    seed_profile(fake_db, challenger)
    seed_profile(fake_db, opponent)
    _seed_exam(fake_db, challenger, exam_id="ex-flow", count=question_count)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "ex-flow", "questionCount": question_count,
              "timeLimitMinutes": 15},
        headers=bearer(fake_auth.issue(challenger)),
    )
    challenge_id = resp.json()["id"]
    code = resp.json()["inviteCode"]
    client.post(
        "/api/community/challenges/join",
        json={"code": code},
        headers=bearer(fake_auth.issue(opponent)),
    )
    return challenge_id, challenger, opponent


def test_challenge_start_before_join_is_conflict(client, fake_db, fake_auth):
    challenger = "p7-ch-wait"
    seed_profile(fake_db, challenger)
    _seed_exam(fake_db, challenger, exam_id="ex-wait", count=1)
    resp = client.post(
        "/api/community/challenges",
        json={"examId": "ex-wait"},
        headers=bearer(fake_auth.issue(challenger)),
    )
    challenge_id = resp.json()["id"]
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/start",
        headers=bearer(fake_auth.issue(challenger)),
    )
    assert resp.status_code == 409, resp.text


def test_challenge_full_flow_grades_and_compares(client, fake_db, fake_auth):
    challenge_id, challenger, opponent = _joinable_challenge(
        client, fake_db, fake_auth, question_count=3
    )
    headers_ch = bearer(fake_auth.issue(challenger))
    headers_op = bearer(fake_auth.issue(opponent))

    # start serves redacted questions (no answer key)
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/start",
        headers=headers_ch,
    )
    assert resp.status_code == 200, resp.text
    started = resp.json()
    assert len(started["questions"]) == 3
    assert "correct" not in json.dumps(started)
    assert started["timeLimitSeconds"] == 15 * 60

    # submit before start is rejected
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/submit",
        json={"answers": ["C", "C", "C"], "durationSeconds": 42},
        headers=headers_op,
    )
    assert resp.status_code == 400, resp.text

    # challenger: 2/3 correct
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/submit",
        json={"answers": ["C", "C", "A"], "durationSeconds": 120},
        headers=headers_ch,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["myResult"]["score"] == 2
    assert body["myResult"]["accuracy"] == 66.7
    assert body["myResult"]["durationSeconds"] == 120
    assert body["opponentResult"] is None  # not finished yet
    assert body["status"] == "accepted"

    # double submit rejected
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/submit",
        json={"answers": ["C", "C", "C"], "durationSeconds": 100},
        headers=headers_ch,
    )
    assert resp.status_code == 400, resp.text

    # opponent starts and aces it → completed comparison on both sides
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/start",
        headers=headers_op,
    )
    assert resp.status_code == 200, resp.text
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/submit",
        json={"answers": ["C", "C", "C"], "durationSeconds": 90},
        headers=headers_op,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "completed"
    assert body["myResult"]["score"] == 3
    assert body["opponentResult"]["score"] == 2
    assert "Optics" in body["myResult"]["topicScores"]

    # both sides see the same completed state
    resp = client.get(
        f"/api/community/challenges/{challenge_id}",
        headers=headers_ch,
    )
    assert resp.json()["status"] == "completed"
    assert resp.json()["opponentResult"] is not None


def test_challenge_duration_is_clamped_to_the_limit(
    client, fake_db, fake_auth
):
    challenge_id, challenger, _ = _joinable_challenge(
        client, fake_db, fake_auth, question_count=2
    )
    headers = bearer(fake_auth.issue(challenger))
    client.post(
        f"/api/community/challenges/{challenge_id}/start",
        headers=headers,
    )
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/submit",
        json={"answers": ["C", "C"], "durationSeconds": 99999},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["myResult"]["durationSeconds"] == 15 * 60


def test_challenge_decline_by_opponent(client, fake_db, fake_auth):
    challenge_id, _, opponent = _joinable_challenge(
        client, fake_db, fake_auth, question_count=1
    )
    resp = client.post(
        f"/api/community/challenges/{challenge_id}/decline",
        headers=bearer(fake_auth.issue(opponent)),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "declined"


def test_challenge_list_only_shows_participants(client, fake_db, fake_auth):
    challenge_id, challenger, opponent = _joinable_challenge(
        client, fake_db, fake_auth, question_count=1
    )
    resp = client.get(
        "/api/community/challenges",
        headers=bearer(fake_auth.issue(challenger)),
    )
    assert [c["id"] for c in resp.json()["challenges"]] == [challenge_id]
    resp = client.get(
        "/api/community/challenges",
        headers=bearer(fake_auth.issue(opponent)),
    )
    assert [c["id"] for c in resp.json()["challenges"]] == [challenge_id]

    seed_profile(fake_db, "p7-nobody")
    resp = client.get(
        "/api/community/challenges",
        headers=bearer(fake_auth.issue("p7-nobody")),
    )
    assert resp.json()["challenges"] == []


# ---------------------------------------------------------------------------
# Ziku Moderator + group quizzes (spec 7.1 / 7.2)
# ---------------------------------------------------------------------------

def test_ziku_ask_is_member_only_and_uses_group_context(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import community_service as community

    owner = "p7-asker-g"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    _seed_post(fake_db, "p7-gq", groupId="grp-p7", title="Why is refraction tricky?")
    seen: dict[str, str] = {}

    async def _fake(uid, prompt, feature=None):
        seen["prompt"] = prompt
        return "Bends because of a change in speed."

    monkeypatch.setattr(community, "_ai", _fake)

    # non-member denied
    seed_profile(fake_db, "p7-no-member")
    resp = client.post(
        "/api/groups/grp-p7/ziku/ask",
        json={"question": "Why does light bend?"},
        headers=bearer(fake_auth.issue("p7-no-member")),
    )
    assert resp.status_code == 403, resp.text

    resp = client.post(
        "/api/groups/grp-p7/ziku/ask",
        json={"question": "Why does light bend?"},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    assert "change in speed" in resp.json()["answer"]
    assert "Physics HSC 2027" in seen["prompt"]
    assert "refraction" in seen["prompt"]


def test_ziku_moderate_starts_with_the_analysis_line(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import community_service as community

    owner = "p7-mod"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    seen: dict[str, str] = {}

    async def _fake(uid, prompt, feature=None):
        seen["prompt"] = prompt
        return "Let's analyze both solutions... B is right."

    monkeypatch.setattr(community, "_ai", _fake)

    resp = client.post(
        "/api/groups/grp-p7/ziku/moderate",
        json={"claimA": "Answer is B", "claimB": "Answer is C"},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["analysis"].startswith("Let's analyze both solutions...")
    assert "Answer is B" in seen["prompt"]
    assert "Answer is C" in seen["prompt"]
    assert "start your reply with exactly" in seen["prompt"]


def test_ziku_topics_falls_back_to_rules_offline(client, fake_db, fake_auth):
    owner = "p7-topics"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    _seed_post(fake_db, "p7-t1", groupId="grp-p7", title="Optics Q1",
               chapter="Optics", subject="Physics")
    _seed_post(fake_db, "p7-t2", groupId="grp-p7", title="Optics Q2",
               chapter="Optics", subject="Physics")

    # the conftest fake AI returns prose, so JSON parsing fails → rules
    resp = client.post(
        "/api/groups/grp-p7/ziku/topics",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["source"] == "rule"
    assert body["topics"]
    assert any("Optics" in t["title"] for t in body["topics"])


def test_group_quiz_generated_and_redacted(
    client, fake_db, fake_auth, monkeypatch
):
    from app.routers import ai_study as ai_study_mod

    owner = "p7-quiz-owner"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    _seed_post(fake_db, "p7-q1", groupId="grp-p7", title="Optics doubt",
               chapter="Optics", subject="Physics")

    async def _fake_generate(uid, prompt, feature=None):
        return json.dumps(
            {
                "questions": [
                    {
                        "question": "Mirror formula relates which quantities?",
                        "type": "mcq",
                        "options": ["f, u, v", "only f", "none", "mass"],
                        "correct": "A",
                        "explanation": "1/f = 1/v + 1/u.",
                        "topic": "Optics",
                    }
                ]
            }
        )

    monkeypatch.setattr(ai_study_mod, "_call_generate", _fake_generate)

    resp = client.post(
        "/api/groups/grp-p7/ziku/quiz",
        json={"questionCount": 5},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["quizId"]
    assert body["topic"] == "Optics"
    assert "Physics HSC 2027" in body["reason"]
    assert "Optics" in body["reason"]
    # redacted: no answer key in the response
    assert "correct" not in json.dumps(body).lower()

    stored = fake_db._collections["groups/grp-p7/quizzes"][body["quizId"]]
    assert stored["questions"][0]["correct"] == "A"

    # non-member cannot list quizzes
    seed_profile(fake_db, "p7-quiz-outsider")
    resp = client.get(
        "/api/groups/grp-p7/quizzes",
        headers=bearer(fake_auth.issue("p7-quiz-outsider")),
    )
    assert resp.status_code == 403, resp.text

    # listing as a member shows the quiz without answers
    resp = client.get(
        "/api/groups/grp-p7/quizzes",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["quizzes"][0]["id"] == body["quizId"]
    assert "correct" not in json.dumps(resp.json()).lower()

    # take it: server grades, explanations come back after submit
    resp = client.post(
        f"/api/groups/grp-p7/quizzes/{body['quizId']}/attempt",
        json={"answers": ["A"], "durationSeconds": 30},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    attempt = resp.json()
    assert attempt["score"] == 1
    assert attempt["total"] == 1
    assert attempt["accuracy"] == 100.0
    assert attempt["topicScores"]["Optics"]["correct"] == 1
    assert attempt["explanations"][0]  # explanation unlocked after submit


def test_group_quiz_degrades_gracefully_offline(
    client, fake_db, fake_auth, monkeypatch
):
    from app.routers import ai_study as ai_study_mod

    owner = "p7-quiz-offline"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    # ai_study binds generate at import time, so conftest's ai_service patch
    # never reaches it — pin _call_generate to prose (unparseable JSON) to
    # model the provider being down. The moderator must degrade, not 500.
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value="Sorry, I cannot generate a quiz right now."),
    )
    resp = client.post(
        "/api/groups/grp-p7/ziku/quiz",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["quizId"] == ""
    assert body["questions"] == []
    assert body["error"]


def test_group_insights_reports_hot_chapters(client, fake_db, fake_auth):
    owner = "p7-insights"
    seed_profile(fake_db, owner)
    _seed_group(fake_db, owner=owner, members=[owner])
    _seed_post(fake_db, "p7-i1", groupId="grp-p7", chapter="Optics",
               subject="Physics")
    _seed_post(fake_db, "p7-i2", groupId="grp-p7", chapter="Optics",
               subject="Physics")
    _seed_post(fake_db, "p7-i3", groupId="grp-p7", chapter="Thermodynamics",
               subject="Physics")

    resp = client.get(
        "/api/groups/grp-p7/insights",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["questionCount"] == 3
    assert body["hotChapters"][0]["chapter"] == "Optics"
    assert body["hotChapters"][0]["count"] == 2

    seed_profile(fake_db, "p7-insights-out")
    resp = client.get(
        "/api/groups/grp-p7/insights",
        headers=bearer(fake_auth.issue("p7-insights-out")),
    )
    assert resp.status_code == 403, resp.text


def test_group_trend_line_feeds_the_study_coach(
    client, fake_db, fake_auth
):
    from app.services.community_service import group_trend_line
    from app.services.study_coach_service import chat_context

    uid = "p7-coach-trend"
    seed_profile(fake_db, uid)
    _seed_group(fake_db, owner=uid, members=[uid], name="Physics HSC 2027")
    for i in range(2):
        _seed_post(
            fake_db,
            f"p7-tr{i}",
            groupId="grp-p7",
            chapter="Optics",
            subject="Physics",
            title=f"Refraction doubt {i}",
        )
    # one signal so the coach builds a brief at all
    fake_db.seed(
        f"users/{uid}/quiz_results",
        "qr-trend",
        {
            "ownerId": uid,
            "score": 55,
            "topicScores": {"Optics": 55},
            "subjectId": "Physics",
            "createdAt": datetime.now(timezone.utc),
            "dayKey": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        },
    )

    line = group_trend_line(uid)
    assert line is not None
    assert "Optics" in line
    assert "Physics HSC 2027" in line

    coach_line = chat_context(uid)
    assert coach_line is not None
    assert "Group hotspot: Optics" in coach_line
    # the line stays last-but-one: mission steps still close the sentence
    assert coach_line.endswith("step(s).") or "step(s)." in coach_line


def test_group_trend_line_is_none_without_a_hot_topic(client, fake_db, fake_auth):
    from app.services.community_service import group_trend_line

    uid = "p7-coach-quiet"
    seed_profile(fake_db, uid)
    assert group_trend_line(uid) is None

    _seed_group(fake_db, owner=uid, members=[uid])
    _seed_post(fake_db, "p7-lonely", groupId="grp-p7", chapter="Optics")
    assert group_trend_line(uid) is None  # needs at least two on one chapter


# ---------------------------------------------------------------------------
# Family links (spec 7.7 — architecture only)
# ---------------------------------------------------------------------------

def test_family_link_code_and_redeem(client, fake_db, fake_auth):
    child = "p7-child"
    parent = "p7-parent"
    seed_profile(fake_db, child, name="Nafisa")
    fake_db.seed(
        "users",
        parent,
        {"role": "general", "displayName": "Mother", "emailVerified": True},
    )
    child_headers = bearer(fake_auth.issue(child))
    parent_headers = bearer(fake_auth.issue(parent))

    resp = client.post("/api/family/link-code", headers=child_headers)
    assert resp.status_code == 200, resp.text
    code = resp.json()["code"]

    # a student cannot redeem
    resp = client.post(
        "/api/family/link/redeem",
        json={"code": code},
        headers=child_headers,
    )
    assert resp.status_code == 403, resp.text

    # unknown code
    resp = client.post(
        "/api/family/link/redeem",
        json={"code": "NOPE12"},
        headers=parent_headers,
    )
    assert resp.status_code == 404, resp.text

    resp = client.post(
        "/api/family/link/redeem",
        json={"code": code},
        headers=parent_headers,
    )
    assert resp.status_code == 200, resp.text
    link = resp.json()
    assert link["status"] == "active"
    assert link["childId"] == child
    assert link["parentId"] == parent
    # architecture-only: no progress data leaks into the link payload
    for banned in ("score", "health", "mistake", "exam", "result"):
        assert banned not in json.dumps(link).lower()

    # both sides can list it
    resp = client.get("/api/family/links", headers=child_headers)
    assert [l["myRole"] for l in resp.json()["links"]] == ["child"]
    resp = client.get("/api/family/links", headers=parent_headers)
    assert [l["myRole"] for l in resp.json()["links"]] == ["parent"]

    # reissuing the child's code invalidates nothing already linked, and a
    # fresh code can be issued again
    resp = client.post("/api/family/link-code", headers=child_headers)
    assert resp.status_code == 200, resp.text

    # reusing the old (now consumed) code fails
    resp = client.post(
        "/api/family/link/redeem",
        json={"code": code},
        headers=parent_headers,
    )
    assert resp.status_code == 400, resp.text


def test_family_link_code_requires_a_student(client, fake_db, fake_auth):
    fake_db.seed(
        "users",
        "p7-parent-only",
        {"role": "general", "displayName": "Parent", "emailVerified": True},
    )
    resp = client.post(
        "/api/family/link-code",
        headers=bearer(fake_auth.issue("p7-parent-only")),
    )
    assert resp.status_code == 403, resp.text


def test_family_links_require_auth(client, fake_db):
    resp = client.post("/api/family/link-code")
    assert resp.status_code == 401, resp.text
    resp = client.get("/api/family/links")
    assert resp.status_code == 401, resp.text
