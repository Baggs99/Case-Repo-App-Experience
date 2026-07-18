/*
 * Purpose: DEBUG-only fixture data for Community screenshots (F8 Task 1) —
 *          the Design Decisions §3 persona (Wharton №2 THIS WEEK / 69.8 avg
 *          pctl, C-14, S. Park FREE NOW / T. Becker / M. Lindqvist) so
 *          `-CommunityFixtures` renders without a live server. Mirrors
 *          LibraryFixtures.swift's structure exactly.
 * Inputs: none.
 * Outputs: CommunityFixtures (standing/groups/connections).
 * Run: CommunityView reads -CommunityFixtures and constructs a fixture-backed
 *      CommunityViewModel from this data; CaseRoomApp.applyDebugLaunchHatches
 *      fakes auth + selects the community tab for the same arg.
 */

#if DEBUG
import Foundation

enum CommunityFixtures {
    // Decisions §3: Wharton, cohort C-14, school percentile 91 (reused from
    // PreviewFixtures.phone.standing for persona continuity). Campus city is
    // a documented estimate — not pinned by §3 (Wharton = UPenn, Philadelphia).
    static let standing = SchoolStanding(
        school: SchoolInfo(schoolId: 1, name: "Wharton", campusCity: "Philadelphia",
                            avgMemberPercentile: 69.8, rank: 2),
        yourPercentile: 91.0)

    static let groups: [GroupSummary] = [
        GroupSummary(id: 14, name: "C-14", schoolId: 1, inviteCode: "C14-7QK2", role: "member"),
    ]

    // CONNECTIONS rows (§2 canvas 6a copy): S. Park FREE NOW, T. Becker,
    // M. Lindqvist. M. Lindqvist's swap_invite_pending decoration is a
    // tablet-2d canvas element (T1 plan §"Canvas 6a copy" line 40) — sanctioned
    // for this phone fixture too per the T1 brief's documented deviation note.
    static let connections: [Connection] = [
        Connection(userId: 21, displayName: "S. Park", photoUrl: nil, bio: nil,
                   freeNow: true, swapInvitePending: false),
        Connection(userId: 22, displayName: "T. Becker", photoUrl: nil, bio: nil,
                   freeNow: false, swapInvitePending: false),
        Connection(userId: 23, displayName: "M. Lindqvist", photoUrl: nil, bio: nil,
                   freeNow: false, swapInvitePending: true),
    ]

    // GroupPageView fixture (F8 Task 2, `-GroupPageFixtures`): C-14, 10
    // members — Decisions §3 canon (day-12 streak, 6th of 10, 8 behind №5 on
    // 331 base pts; cohort "led by R. Vance"). Points/streaks for ranks 1–4
    // and 7–10 aren't individually pinned by §3 — filled in descending order
    // to exercise the TOP FIVE ADVANCE divider with a plausible full board.
    // DEVIATION (screenshot-only): §3 names R. Vance as the cohort lead, but
    // the task requires isAdmin=true on this hatch to exercise the admin-only
    // note/transfer/progress surfaces. Group *admin* (members[].role) and
    // leaderboard *rank* are distinct concepts in the pinned schema, so this
    // fixture keeps R. Vance ranked №1 on the board (canon) while granting
    // Amara (the fixture's fake-authed user, id 1) the admin role — the
    // narrative "led by R. Vance" is a ranking fact, not an admin claim the
    // API shape even carries a field for.
    static let groupDetail = GroupDetail(
        group: GroupInfo(id: 14, name: "C-14", schoolId: 1, inviteCode: "C14-7QK2"),
        members: [
            GroupMember(userId: 10, displayName: "R. Vance", photoUrl: nil, role: "member"),
            GroupMember(userId: 11, displayName: "P. Nair", photoUrl: nil, role: "member"),
            GroupMember(userId: 12, displayName: "K. Chen", photoUrl: nil, role: "member"),
            GroupMember(userId: 13, displayName: "S. Park", photoUrl: nil, role: "member"),
            GroupMember(userId: 14, displayName: "T. Becker", photoUrl: nil, role: "member"),
            GroupMember(userId: 1, displayName: "Amara Osei", photoUrl: nil, role: "admin"),
            GroupMember(userId: 15, displayName: "J. Silva", photoUrl: nil, role: "member"),
            GroupMember(userId: 16, displayName: "M. Lindqvist", photoUrl: nil, role: "member"),
            GroupMember(userId: 17, displayName: "A. Kim", photoUrl: nil, role: "member"),
            GroupMember(userId: 18, displayName: "D. Ortiz", photoUrl: nil, role: "member"),
        ],
        leaderboard: [
            GroupLeaderboardEntry(userId: 10, displayName: "R. Vance", photoUrl: nil, points: 400, rank: 1, streak: 20),
            GroupLeaderboardEntry(userId: 11, displayName: "P. Nair", photoUrl: nil, points: 380, rank: 2, streak: 18),
            GroupLeaderboardEntry(userId: 12, displayName: "K. Chen", photoUrl: nil, points: 360, rank: 3, streak: 15),
            GroupLeaderboardEntry(userId: 13, displayName: "S. Park", photoUrl: nil, points: 350, rank: 4, streak: 14),
            GroupLeaderboardEntry(userId: 14, displayName: "T. Becker", photoUrl: nil, points: 339, rank: 5, streak: 13),
            // Amara: 6th of 10, 331 base pts, day-12 streak (§3, verbatim).
            GroupLeaderboardEntry(userId: 1, displayName: "Amara Osei", photoUrl: nil, points: 331, rank: 6, streak: 12),
            GroupLeaderboardEntry(userId: 15, displayName: "J. Silva", photoUrl: nil, points: 320, rank: 7, streak: 11),
            GroupLeaderboardEntry(userId: 16, displayName: "M. Lindqvist", photoUrl: nil, points: 310, rank: 8, streak: 9),
            GroupLeaderboardEntry(userId: 17, displayName: "A. Kim", photoUrl: nil, points: 300, rank: 9, streak: 7),
            GroupLeaderboardEntry(userId: 18, displayName: "D. Ortiz", photoUrl: nil, points: 290, rank: 10, streak: 5),
        ])

    // Admin-only member-progress fixture — one nullable mean_grade (D. Ortiz,
    // no finalized candidate sessions yet) exercising the documented nullable
    // field (CommunityModels.swift GroupProgressMember).
    static let groupProgress: [GroupProgressMember] = [
        GroupProgressMember(userId: 10, displayName: "R. Vance", casesDone: 22, meanGrade: 8.1, drillAttempts30D: 40, streak: 20),
        GroupProgressMember(userId: 11, displayName: "P. Nair", casesDone: 20, meanGrade: 7.8, drillAttempts30D: 36, streak: 18),
        GroupProgressMember(userId: 12, displayName: "K. Chen", casesDone: 18, meanGrade: 7.5, drillAttempts30D: 33, streak: 15),
        GroupProgressMember(userId: 13, displayName: "S. Park", casesDone: 17, meanGrade: 7.3, drillAttempts30D: 31, streak: 14),
        GroupProgressMember(userId: 14, displayName: "T. Becker", casesDone: 16, meanGrade: 7.1, drillAttempts30D: 29, streak: 13),
        GroupProgressMember(userId: 1, displayName: "Amara Osei", casesDone: 15, meanGrade: 6.9, drillAttempts30D: 27, streak: 12),
        GroupProgressMember(userId: 15, displayName: "J. Silva", casesDone: 13, meanGrade: 6.7, drillAttempts30D: 24, streak: 11),
        GroupProgressMember(userId: 16, displayName: "M. Lindqvist", casesDone: 12, meanGrade: 6.5, drillAttempts30D: 21, streak: 9),
        GroupProgressMember(userId: 17, displayName: "A. Kim", casesDone: 10, meanGrade: 6.2, drillAttempts30D: 18, streak: 7),
        GroupProgressMember(userId: 18, displayName: "D. Ortiz", casesDone: 6, meanGrade: nil, drillAttempts30D: 12, streak: 5),
    ]

    // GroupCreateView fixture (F8 Task 3, `-GroupCreateFixtures`): the POST
    // /groups response shape (creator role is always "admin") for a
    // screenshot of the "YOU'RE THE ADMIN" success state with no live server.
    static let createdGroup = GroupSummary(id: 20, name: "C-14 East", schoolId: 1,
                                            inviteCode: "C14E-9XJT", role: "admin")
}
#endif
