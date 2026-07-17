/*
 * Purpose: The single source of persona fixture data (Decisions §3 verbatim for
 *          phone/July-16, §7 for tablet/July-17) for SwiftUI Previews and UI-test
 *          fixtures ONLY. Live screens bind to the API, never this.
 * Inputs: none.
 * Outputs: PreviewFixtures.phone / .tablet.
 * Run: `SteppedTimeline(firms: PreviewFixtures.phone.timeline)` in a #Preview.
 */

import Foundation

struct PreviewProfile {
    let name: String
    let initials: String
    let school: String
    let cohort: String
    let cohortLead: String
    let streakDays: Int
    let rankInCohort: Int
    let cohortSize: Int
    let behindNext: Int
    let points: Int
}

struct PreviewDiagnostic {
    let structure: Double
    let communication: Double
    let quant: Double
    let marketSizing: Double
    let focus: String
    let casesLogged: Int
}

struct PreviewSession {
    let opponent: String
    let opponentSchool: String
    let caseTitle: String
    let provenance: String
    let time: String
}

struct PreviewRecommendation {
    let title: String
    let provenance: String
}

struct PreviewRecap {
    let caseTitle: String
    let interviewer: String
    let rating: Double
    let note: String
}

struct PreviewPending {
    let interviewer: String
    let time: String
    let caseTitle: String
}

struct PreviewCohortStanding {
    let schoolPercentile: Int
}

struct PreviewDay {
    let profile: PreviewProfile
    let diagnostic: PreviewDiagnostic
    let tonight: PreviewSession
    let recommendation: PreviewRecommendation
    let recap: PreviewRecap
    let pending: [PreviewPending]
    let timeline: [TimelineFirm]
    let standing: PreviewCohortStanding
}

enum PreviewFixtures {
    // Decisions §3 — July 16 (phone canvas state).
    static let phone = PreviewDay(
        profile: PreviewProfile(
            name: "Amara Osei", initials: "AO", school: "Wharton MBA '27",
            cohort: "C-14", cohortLead: "R. Vance", streakDays: 12,
            rankInCohort: 6, cohortSize: 10, behindNext: 8, points: 331),
        diagnostic: PreviewDiagnostic(
            structure: 8.2, communication: 7.4, quant: 6.8,
            marketSizing: 5.1, focus: "Market sizing", casesLogged: 14),
        tonight: PreviewSession(
            opponent: "M. Lindqvist", opponentSchool: "LBS",
            caseTitle: "Low-cost carrier enters the Nordic market",
            provenance: "Kellogg 2019 · D4", time: "19:00"),
        recommendation: PreviewRecommendation(
            title: "EV charging — size the German market", provenance: "Stern 2024 · D3"),
        recap: PreviewRecap(
            caseTitle: "Ski resort profitability", interviewer: "T. Becker", rating: 4.1,
            note: "Structure held. The quant went soft in the middle — drill it before Thursday."),
        pending: [
            PreviewPending(interviewer: "T. Becker", time: "Thu 18:00", caseTitle: "Dental roll-up"),
            PreviewPending(interviewer: "S. Park", time: "Tonight 21:30", caseTitle: "asks you to interview"),
        ],
        timeline: [
            TimelineFirm(name: "McKinsey", date: "Sep 12", days: "58d", readiness: "ON PACE", onPace: true),
            TimelineFirm(name: "BCG", date: "Sep 30", days: "76d", readiness: "PUSH QUANT", onPace: false),
            TimelineFirm(name: "Bain", date: "Oct 08", days: "84d", readiness: "EARLY", onPace: false),
        ],
        standing: PreviewCohortStanding(schoolPercentile: 91)
    )

    // Decisions §7 — July 17 (tablet canvas state, one day advanced).
    static let tablet = PreviewDay(
        profile: PreviewProfile(
            name: "Amara Osei", initials: "AO", school: "Wharton MBA '27",
            cohort: "C-14", cohortLead: "R. Vance", streakDays: 13,
            rankInCohort: 6, cohortSize: 10, behindNext: 4, points: 335),
        diagnostic: PreviewDiagnostic(
            structure: 8.2, communication: 7.4, quant: 6.6,
            marketSizing: 5.3, focus: "Market sizing", casesLogged: 15),
        tonight: PreviewSession(
            opponent: "T. Becker", opponentSchool: "",
            caseTitle: "Dental roll-up", provenance: "T-9H", time: "Today 18:00"),
        recommendation: PreviewRecommendation(
            title: "EV charging — size the German market", provenance: "Stern 2024 · D3"),
        recap: PreviewRecap(
            caseTitle: "Low-cost carrier enters the Nordic market", interviewer: "M. Lindqvist",
            rating: 5.0, note: "Jul 16 · M. Lindqvist · 7.2 avg"),
        pending: [
            PreviewPending(interviewer: "T. Becker", time: "Today 18:00", caseTitle: "Dental roll-up"),
        ],
        timeline: [
            TimelineFirm(name: "McKinsey", date: "Sep 12", days: "57d", readiness: "ON PACE", onPace: true),
            TimelineFirm(name: "BCG", date: "Sep 30", days: "75d", readiness: "PUSH QUANT", onPace: false),
            TimelineFirm(name: "Bain", date: "Oct 08", days: "83d", readiness: "EARLY", onPace: false),
        ],
        standing: PreviewCohortStanding(schoolPercentile: 88)
    )
}
