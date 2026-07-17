/*
 * Purpose: Verify the bundled variable fonts register (Archivo + Source Serif 4)
 *          and the §1 type-scale tracking values are exact.
 * Inputs: DSFonts, DSTextStyle. Requires the Fonts as a test-target resource.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/TypographyTests
 */

import XCTest
import UIKit
@testable import CaseRoom

final class TypographyTests: XCTestCase {
    func testFontsRegisterAndFamiliesAvailable() {
        DSFonts.register()
        XCTAssertFalse(UIFont.fontNames(forFamilyName: "Archivo").isEmpty,
                       "Archivo not registered — check Fonts resources on the test target")
        XCTAssertFalse(UIFont.fontNames(forFamilyName: "Source Serif 4").isEmpty,
                       "Source Serif 4 not registered")
    }

    func testArchivoResolvesToArchivoFamilyNotSystemFallback() {
        DSFonts.register()
        // family + weight-trait resolution → the ExtraBold named instance.
        let desc = UIFontDescriptor(fontAttributes: [
            .family: "Archivo",
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.heavy],
        ])
        let f = UIFont(descriptor: desc, size: 28)
        XCTAssertEqual(f.familyName, "Archivo")
    }

    func testSerifItalicResolvesToSourceSerifFamily() {
        DSFonts.register()
        let desc = UIFontDescriptor(fontAttributes: [.family: "Source Serif 4"])
            .withSymbolicTraits(.traitItalic)
        let f = UIFont(descriptor: desc ?? UIFontDescriptor(), size: 15)
        XCTAssertEqual(f.familyName, "Source Serif 4")
    }

    func testTypeScaleTrackingValues() {
        XCTAssertEqual(DSTextStyle.h1Tab.tracking, -0.84, accuracy: 0.001)       // 28 × -.03em
        XCTAssertEqual(DSTextStyle.h1TabSmall.tracking, -0.72, accuracy: 0.001)  // 24 × -.03em
        XCTAssertEqual(DSTextStyle.takeoverDisplay.tracking, -1.12, accuracy: 0.001) // 32 × -.035em
        XCTAssertEqual(DSTextStyle.kicker.tracking, 1.6, accuracy: 0.001)        // 10 × .16em
        XCTAssertEqual(DSTextStyle.rowTitle.tracking, 0, accuracy: 0.001)
        XCTAssertEqual(DSTextStyle.actionLabel.tracking, 0, accuracy: 0.001) // 11.5/600 small underlined actions
    }

    // Timeline label statics = canvas pixel-truth (3a 1484-1497 / 7b 365-377):
    // firm·date 9px/.1em, days 14px tabular no-tracking, tag 8px/.1em, TODAY 8.5px/.14em.
    func testTimelineTypeScaleTrackingValues() {
        XCTAssertEqual(DSTextStyle.timelineFirmKicker.tracking, 0.9, accuracy: 0.001)   // 9 × .1em
        XCTAssertEqual(DSTextStyle.timelineDays.tracking, 0, accuracy: 0.001)           // 14 tabular
        XCTAssertEqual(DSTextStyle.timelineTag.tracking, 0.8, accuracy: 0.001)          // 8 × .1em
        XCTAssertEqual(DSTextStyle.timelineTodayLabel.tracking, 1.19, accuracy: 0.001)  // 8.5 × .14em
    }
}
