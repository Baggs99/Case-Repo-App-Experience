/*
 * Purpose: Authored, client-side stage script + PDF case-pack for the
 *          interviewer console (F6, decision A4 — no backend stage/case-pack
 *          endpoint exists). Verbatim from the Tablet 1a canvas `STAGES`,
 *          `DIMS`, and PDF-mode markup (Case-07 Nordic). Consumed by the console
 *          view-model (stage nav, exhibit-ref→reveal mapping, dim resolution)
 *          and the T2/T3/T5 views. Pure value types — no I/O, no view code.
 * Inputs: none (all content is compiled-in).
 * Outputs: ConsoleScript.tablet (7 stages) / .phone (6-stage subset) /
 *          .dims (dim id → name+desc, since RubricTemplateItem carries no desc) /
 *          .pdfPages (3 authored pages) / CAP.
 * Run: `ConsoleViewModel(stages: ConsoleScript.tablet, isPhone: false, ...)`.
 */

import Foundation

/// One interviewer stage: the read-aloud line, interviewer-only guidance, any
/// exhibits released in this stage, and the rubric dimensions it scores.
///
/// `dimKeys` is the resolution key set matched (by id OR dimension) against the
/// loaded `RubricTemplateItem`s. It holds the union of the canvas DIM keys and
/// the plausible real backend ids (structure/quant/insight/communication/
/// synthesis) so BOTH the canvas 12-dim fixture and the shipping 5-dim template
/// map (decision A4). On phone the set is 1:1 (a single real dim per stage).
struct ConsoleStage: Equatable {
    let num: String
    let name: String
    let readAloud: String
    let guidance: [String]
    let exhibitRefs: [ConsoleExhibitRef]
    let dimKeys: [String]
}

/// A script exhibit reference. `scriptId` (e1/e2/e3) is the console-local id;
/// `idx` (0/1/2) maps to `ExhibitMeta.idx` → `.exhibitId` for `reveal(...)`.
struct ConsoleExhibitRef: Equatable {
    let scriptId: String
    let idx: Int
    let label: String
}

// MARK: - PDF case-pack model (authored, rendered by the T5 PDF view)

/// One authored PDF page. Plain value type (A4: authored client-side, never
/// serialized over the wire) — `blocks` is the ordered body the T5 view renders.
struct ConsolePDFPage: Identifiable, Equatable {
    let id: Int          // 0/1/2 — also the pager index
    let kicker: String   // top-left rule kicker, e.g. "CASE 07 · EXHIBIT 01"
    let corner: PDFCorner
    let title: String
    let blocks: [PDFBlock]
}

/// The top-right corner affordance of a page.
enum PDFCorner: Equatable {
    case meta(String)               // e.g. "D4 · ~40 MIN"
    case interviewerOnly            // green "INTERVIEWER ONLY"
    case exhibitRelease(scriptId: String)  // Release ⇄ SENT · mm:ss (synced to e1)
}

/// One rendered body block on a PDF page.
enum PDFBlock: Equatable {
    case sectionKicker(String)                     // e.g. "BACKGROUND"
    case serif(String)                             // a serif body paragraph
    case timingPlan(title: String, rows: [PDFRow]) // label/value grid
    case table(columns: [String], rows: [PDFTableRow], footnote: String)
    case bulletChain([String])                     // "—" dashed quant chain
    case gradingNotes(title: String, body: String) // italic serif callout
}

struct PDFRow: Equatable {
    let label: String
    let value: String
}

struct PDFTableRow: Equatable {
    let cells: [String]
    let isTotal: Bool
}

// MARK: - Authored content

enum ConsoleScript {

    /// Interview time cap — 45 minutes (canvas `CAP = 45 * 60`).
    static let cap = 45 * 60

    /// Formats a second count as MM:SS with zero-padding (canvas `fmt`).
    static func mmss(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Dim names + descriptions (RubricTemplateItem carries no desc)
    //
    // Verbatim from the canvas `DIMS` (the 12 canvas keys) plus the real backend
    // ids not covered there (insight, communication) so BOTH the 12-dim shot
    // fixture and the shipping 5-dim template render name + one-line desc.
    // Contract for T2/T3: name = dims[id]?.name ?? templateItem.label;
    // desc = dims[id]?.desc.
    static let dims: [String: (name: String, desc: String)] = [
        // Canvas DIMS (lines 1037-1049), verbatim.
        "fit": ("Fit", "Motivation and self-awareness — would you staff them"),
        "star": ("STAR", "Situation, task, action, result — led with the result"),
        "summary": ("Summary", "Accurate, brief recaps at transitions"),
        "comm": ("Communication", "Top-down, concise, composed"),
        "questions": ("Questions", "Clarifying questions that earn new facts"),
        "structure": ("Structure", "MECE, hypothesis-led, tailored to the case"),
        "quant": ("Quant accuracy", "Setup, arithmetic, sanity checks"),
        "judgment": ("Business judgment", "So-whats, practical insight"),
        "creativity": ("Creativity", "Breadth and originality of ideas"),
        "synthesis": ("Synthesis", "Answer-first close with next steps"),
        "leading": ("Leading required", "Steering needed — 10 means none"),
        "time": ("Time management", "Paced the case within the caps"),
        // Real backend ids absent from the canvas DIMS — authored to match.
        "insight": ("Business insight", "So-whats and practical insight"),
        "communication": ("Communication", "Top-down, concise, composed"),
    ]

    // MARK: Exhibit references (e1/e2/e3 → idx 0/1/2)

    static let e1 = ConsoleExhibitRef(scriptId: "e1", idx: 0, label: "Nordic market — volumes & average fares")
    static let e2 = ConsoleExhibitRef(scriptId: "e2", idx: 1, label: "Competitor unit costs per seat-km")
    static let e3 = ConsoleExhibitRef(scriptId: "e3", idx: 2, label: "Ancillary revenue benchmarks — European LCCs")

    // MARK: Tablet — 7 stages (BEHAVIORAL…CLOSE), union dimKeys

    static let tablet: [ConsoleStage] = [
        ConsoleStage(
            num: "01", name: "BEHAVIORAL",
            readAloud: "Before the case, two questions about you. First — tell me about a time you led a team through real disagreement about direction. Second — a piece of hard feedback you received, and what you changed because of it.",
            guidance: [
                "Two questions, two to three minutes each; redirect gently at four.",
                "Listen for STAR shape — ideally a result with a number in it.",
            ],
            exhibitRefs: [],
            dimKeys: ["fit", "star"]),
        ConsoleStage(
            num: "02", name: "OPENING",
            readAloud: "Our client is Skanwing, a Copenhagen-based low-cost carrier with 42 aircraft and €1.1B in annual revenue. Management is weighing entry into the Nordic domestic market — Norway, Sweden and Finland. The CEO has asked: should Skanwing enter, and if so, how?",
            guidance: [
                "Read once at speaking pace; repeat figures once if asked.",
                "Let the candidate take notes in silence.",
                "Start the segment timer when they begin structuring.",
            ],
            exhibitRefs: [],
            dimKeys: ["summary", "comm", "communication"]),
        ConsoleStage(
            num: "03", name: "CLARIFY",
            readAloud: "You may answer, if asked: the goal is €120M of incremental revenue within three years, profitable by year two. Scope is domestic routes only. Acquisitions have not been ruled out.",
            guidance: [
                "Only reveal a fact when asked directly.",
                "If they ask nothing, prompt once: 'What would you want to know?'",
            ],
            exhibitRefs: [],
            dimKeys: ["questions"]),
        ConsoleStage(
            num: "04", name: "FRAMEWORK",
            readAloud: "How would you structure your approach to this decision?",
            guidance: [
                "Strong answers cover market attractiveness, competitive response, unit economics, entry mode.",
                "Allow 90 seconds of silence before probing.",
                "Probe once: 'Which branch would you start with, and why?'",
            ],
            exhibitRefs: [],
            dimKeys: ["structure"]),
        ConsoleStage(
            num: "05", name: "QUANT",
            readAloud: "The Nordic domestic market carries 14 million passengers per year at an average one-way fare of €95. Assume Skanwing captures 8% by year three, pricing 15% below market.",
            guidance: [
                "Answer key: 14M × 8% = 1.12M pax; fare €80.75; ≈ €90M — short of the €120M goal.",
                "Push for the so-what against the €120M target.",
                "Release exhibits only when the data is requested.",
            ],
            exhibitRefs: [e1, e2],
            dimKeys: ["quant", "judgment", "insight"]),
        ConsoleStage(
            num: "06", name: "BRAINSTORM",
            readAloud: "Ticket revenue alone falls short of the goal. What levers could close the gap?",
            guidance: [
                "Expect: ancillaries, cargo, trunk-route frequency, partnerships, base costs.",
                "Push past the third idea — breadth first, then depth on one.",
            ],
            exhibitRefs: [e3],
            dimKeys: ["creativity"]),
        ConsoleStage(
            num: "07", name: "CLOSE",
            readAloud: "The CEO joins in two minutes. What do you recommend?",
            guidance: [
                "Answer-first, one number, two risks, one next step.",
                "No new analysis — synthesis only.",
                "Stop the interview clock when they finish.",
            ],
            exhibitRefs: [],
            dimKeys: ["synthesis", "leading", "time"]),
    ]

    // MARK: Phone — 6-stage subset (drops BEHAVIORAL), 1:1 real dim per stage
    //
    // Each real shipping dim (structure/quant/insight/communication/synthesis)
    // lands on a DISTINCT stage (A4 phone mode); Clarify carries none (its score
    // block is hidden). Read-aloud / guidance / exhibits are the tablet content.

    static let phone: [ConsoleStage] = [
        stage(from: tablet[1], phoneDimKeys: ["communication"]),  // OPENING
        stage(from: tablet[2], phoneDimKeys: []),                  // CLARIFY (none)
        stage(from: tablet[3], phoneDimKeys: ["structure"]),       // FRAMEWORK
        stage(from: tablet[4], phoneDimKeys: ["quant"]),           // QUANT
        stage(from: tablet[5], phoneDimKeys: ["insight"]),         // BRAINSTORM
        stage(from: tablet[6], phoneDimKeys: ["synthesis"]),       // CLOSE
    ]

    private static func stage(from base: ConsoleStage, phoneDimKeys: [String]) -> ConsoleStage {
        ConsoleStage(
            num: base.num, name: base.name, readAloud: base.readAloud,
            guidance: base.guidance, exhibitRefs: base.exhibitRefs,
            dimKeys: phoneDimKeys)
    }

    // MARK: PDF case-pack — 3 authored pages (verbatim Tablet 1a PDF mode)

    static let pdfPages: [ConsolePDFPage] = [
        ConsolePDFPage(
            id: 0,
            kicker: "CASE 07 · MARKET ENTRY · KELLOGG CONSULTING CLUB 2019",
            corner: .meta("D4 · ~40 MIN"),
            title: "Low-cost carrier enters the Nordic market",
            blocks: [
                .sectionKicker("BACKGROUND"),
                .serif("Skanwing is a Copenhagen-based low-cost carrier operating 42 narrow-body aircraft on intra-European routes, with €1.1B in annual revenue and unit costs among the lowest in the region. Management is weighing entry into the Nordic domestic market — Norway, Sweden and Finland — where incumbent full-service carriers hold roughly 80% of seats."),
                .sectionKicker("THE ASK"),
                .serif("The CEO has asked: should Skanwing enter the Nordic domestic market, and if so, how? The board's bar is €120M of incremental revenue within three years, profitable by year two."),
                .timingPlan(title: "TIMING PLAN — HOLD THE LAST TWO MINUTES", rows: [
                    PDFRow(label: "Behavioral", value: "0–5 min"),
                    PDFRow(label: "Opening & clarify", value: "5–12 min"),
                    PDFRow(label: "Framework", value: "12–20 min"),
                    PDFRow(label: "Quant", value: "20–32 min"),
                    PDFRow(label: "Brainstorm", value: "32–40 min"),
                    PDFRow(label: "Close", value: "40–44 min"),
                ]),
            ]),
        ConsolePDFPage(
            id: 1,
            kicker: "CASE 07 · EXHIBIT 01",
            corner: .exhibitRelease(scriptId: "e1"),
            title: "Nordic domestic market — volumes & average fares",
            blocks: [
                .table(
                    columns: ["COUNTRY", "PAX / YR", "AVG ONE-WAY FARE"],
                    rows: [
                        PDFTableRow(cells: ["Norway", "6.1M", "€92"], isTotal: false),
                        PDFTableRow(cells: ["Sweden", "5.2M", "€97"], isTotal: false),
                        PDFTableRow(cells: ["Finland", "2.7M", "€99"], isTotal: false),
                        PDFTableRow(cells: ["Total / weighted avg", "14.0M", "€95"], isTotal: true),
                    ],
                    footnote: "Domestic O&D traffic only; charter and transfer excluded. Source: national CAAs, 2018."),
            ]),
        ConsolePDFPage(
            id: 2,
            kicker: "CASE 07 · ANSWER KEY",
            corner: .interviewerOnly,
            title: "Quant chain & expected so-what",
            blocks: [
                .bulletChain([
                    "Volume: 14M pax × 8% share = 1.12M pax by year three.",
                    "Fare: €95 × (1 − 15%) = €80.75 average one-way.",
                    "Revenue: 1.12M × €80.75 ≈ €90M — €30M short of the €120M bar.",
                    "So-what: ticket revenue alone fails the goal → brainstorm must close the gap (ancillaries ~€12–15 per pax, cargo, trunk frequency, partnerships).",
                ]),
                .gradingNotes(
                    title: "GRADING NOTES",
                    body: "Let one arithmetic slip pass; flag the second. A candidate who reaches the €30M gap unprompted and names two closing levers is at an 8 or above on judgment."),
            ]),
    ]

    /// Pager label for a 0-based PDF page index (canvas `pdfPageText`).
    static func pdfPageText(_ index: Int) -> String {
        let base = String(format: "PAGE %02d OF 08", index + 1)
        return index == pdfPages.count - 1 ? base + " — 04–08 IN THE FULL PACK" : base
    }
}
