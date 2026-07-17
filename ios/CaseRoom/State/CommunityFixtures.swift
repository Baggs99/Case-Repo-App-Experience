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
}
#endif
