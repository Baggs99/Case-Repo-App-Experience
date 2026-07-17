/*
 * Purpose: Smoke-verify the glass modifiers, scrim, and rise transition build.
 * Inputs: Glass.swift API.
 * Outputs: none.
 * Run: xcodebuild test -only-testing:CaseRoomTests/GlassTests
 */

import XCTest
import SwiftUI
@testable import CaseRoom

final class GlassTests: XCTestCase {
    func testGlassModifiersProduceViews() {
        _ = AnyView(Text("x").glassPanel())
        _ = AnyView(Text("x").glassChip())
        _ = AnyView(Text("x").glassSheet(cornerRadius: 34))
        _ = AnyView(DSScrim())
    }

    // Flat key/chip glass (Canon §1 line 29): keys radius 16, chips capsule.
    func testFlatGlassKeyModifiersProduceViews() {
        _ = AnyView(Text("x").glassKey())
        _ = AnyView(Text("x").glassKey(cornerRadius: 999))
        _ = AnyView(Text("x").glassChipFlat())
    }

    func testRiseTransitionExists() {
        _ = AnyTransition.dsRise
    }
}
