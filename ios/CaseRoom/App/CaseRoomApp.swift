/*
 * Purpose: App entry point; launches the root tab-based UI.
 * Inputs: none.
 * Outputs: none.
 * Run: built as part of the CaseRoom.app target via Xcode/xcodebuild.
 */

import SwiftUI

@main
struct CaseRoomApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
