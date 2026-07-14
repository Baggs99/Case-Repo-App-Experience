/*
 * Purpose: Starts/ends the session's Live Activity and keeps its APNs push
 *          token registered with the backend (Task 9) so server-side session
 *          transitions can update the lock-screen banner / Dynamic Island.
 * Inputs: sessionId + SessionActivityAttributes.ContentState from
 *         SessionViewModel; ActivityKit's ActivityAuthorizationInfo and
 *         Activity<SessionActivityAttributes>.pushTokenUpdates.
 * Outputs: an ActivityKit Activity<SessionActivityAttributes>; POSTs the
 *          rotating push token via APIClient.registerLiveActivity.
 * Run: injected into SessionViewModel as the default LiveActivityControlling.
 */

import ActivityKit

@MainActor
final class LiveActivityController: LiveActivityControlling {
    private var activity: Activity<SessionActivityAttributes>?
    private var tokenTask: Task<Void, Never>?

    // nonisolated so `LiveActivityController()` can be used as a
    // SessionViewModel.init default-argument value (default-argument
    // expressions evaluate outside the enclosing @MainActor context) — safe
    // since both stored properties start nil and touch no isolated state.
    nonisolated init() {}

    func start(sessionId: Int, initial: SessionActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SessionActivityAttributes(sessionId: sessionId)
        let content = ActivityContent(state: initial, staleDate: nil)
        guard let activity = try? Activity<SessionActivityAttributes>.request(
            attributes: attributes, content: content, pushType: .token
        ) else {
            return
        }
        self.activity = activity

        tokenTask?.cancel()
        tokenTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                try? await APIClient.shared.registerLiveActivity(sessionId: sessionId, pushToken: token)
            }
        }
    }

    func end() async {
        tokenTask?.cancel()
        tokenTask = nil
        await activity?.end(nil, dismissalPolicy: .default)
        activity = nil
    }
}
