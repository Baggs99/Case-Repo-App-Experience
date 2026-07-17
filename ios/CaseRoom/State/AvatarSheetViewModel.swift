/*
 * Purpose: Backing state for the avatar sheet (canvas 7a) — loads profile +
 *          notification settings, exposes verified/linked derivations, and a
 *          single master notifications toggle that writes all five B5 categories.
 * Inputs: ProfileService (default APIClient.shared).
 * Outputs: PUT /api/v1/profile, /settings/notifications side effects.
 * Run: owned by AvatarSheetView.
 */

import Observation

@Observable
@MainActor
final class AvatarSheetViewModel {
    private(set) var profile: ProfileDetail?
    private(set) var notificationsOn = true
    var errorMessage: String?

    private var settings: NotificationSettings?
    private let service: ProfileService

    init(service: ProfileService = APIClient.shared) {
        self.service = service
    }

    var schoolVerified: Bool { !(profile?.school ?? "").isEmpty }
    var linkedAccountsLinked: Bool { !(profile?.linkedinUrl ?? "").isEmpty }

    func load() async {
        do {
            async let p = service.profile()
            async let s = service.notificationSettings()
            profile = try await p
            let loaded = try await s
            settings = loaded
            notificationsOn = loaded.allEnabled
        } catch {
            errorMessage = "Couldn't load your profile."
        }
    }

    /// Master toggle: writes all five categories to `on`. Optimistic; reverts on
    /// failure. Granular per-category settings are a later, undesigned screen.
    func setNotifications(_ on: Bool) async {
        let previous = notificationsOn
        notificationsOn = on
        let all = NotificationSettings(proposals: on, sessionReminders: on, feedback: on, freeNow: on, community: on)
        do {
            settings = try await service.updateNotificationSettings(all)
        } catch {
            notificationsOn = previous
            errorMessage = "Couldn't update notifications."
        }
    }

    func saveProfile(displayName: String, bio: String, linkedinUrl: String) async {
        do {
            profile = try await service.updateProfile(
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                linkedinUrl: linkedinUrl.isEmpty ? nil : linkedinUrl
            )
        } catch {
            errorMessage = "Couldn't save your profile."
        }
    }
}
