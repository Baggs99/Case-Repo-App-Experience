/*
 * Purpose: App Group plumbing shared by the app and the widget extension — the
 *          group identifier, its container URL, a URLSession configuration
 *          backed by the group's shared cookie store, and a one-time migration
 *          of the API host's cookies from the per-process store into it.
 * Inputs: FileManager App Group container; HTTPCookieStorage (shared or the
 *         group store); UserDefaults(suiteName: id) for the migration flag.
 * Outputs: side effects on the group cookie store and the migration flag.
 * Run: APIClient/SignalingClient use makeURLSessionConfiguration(); CaseRoomApp
 *      calls migrateCookiesIfNeeded(apiHost:) once at launch.
 */

import Foundation

enum AppGroup {
    static let id = "group.study.mycase"

    /// The App Group container, or nil on unprovisioned/dev builds where the
    /// group is not granted. Callers must treat nil as "no shared storage".
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// A URLSession configuration whose cookie storage is the App Group's
    /// shared store when the container resolves, so the app and the widget
    /// extension authenticate with the same session cookie. Falls back to
    /// HTTPCookieStorage.shared when the group is unavailable (dev builds,
    /// unprovisioned sims) so cookie auth still works in-process.
    static func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        if containerURL != nil {
            configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id)
        } else {
            configuration.httpCookieStorage = HTTPCookieStorage.shared
        }
        return configuration
    }

    private static let migrationFlagKey = "cookiesMigratedToGroupStore"

    /// One-time copy of the API host's cookies from `source` (the per-process
    /// store used before this change) into the group store, so a user who
    /// logged in on an older build stays authenticated after upgrading. Guarded
    /// by a UserDefaults(suiteName:) flag so it runs at most once; a no-op when
    /// the group container is unavailable.
    static func migrateCookiesIfNeeded(from source: HTTPCookieStorage = .shared, apiHost: String) {
        guard let defaults = UserDefaults(suiteName: id) else { return }
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        guard containerURL != nil else { return }

        let destination = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id)
        copyCookies(for: apiHost, from: source, into: destination)
        defaults.set(true, forKey: migrationFlagKey)
    }

    /// Deletes the API host's cookies from the group store (or the shared store
    /// fallback). Called on logout so a stale session cookie never lingers in
    /// the shared container for the widget process to reuse.
    static func clearCookies(for apiHost: String) {
        let store = containerURL != nil
            ? HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id)
            : HTTPCookieStorage.shared
        guard let cookies = store.cookies else { return }
        for cookie in cookies where cookieMatchesHost(cookie, apiHost: apiHost) {
            store.deleteCookie(cookie)
        }
    }

    /// Copies the API host's cookies from one store to another. Idempotent:
    /// HTTPCookieStorage keys cookies by (domain, path, name), so re-copying
    /// replaces rather than duplicates. Exposed for the migration test's
    /// scratch source/destination pair.
    static func copyCookies(for apiHost: String, from source: HTTPCookieStorage, into destination: HTTPCookieStorage) {
        guard let cookies = source.cookies else { return }
        for cookie in cookies where cookieMatchesHost(cookie, apiHost: apiHost) {
            destination.setCookie(cookie)
        }
    }

    private static func cookieMatchesHost(_ cookie: HTTPCookie, apiHost: String) -> Bool {
        let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return apiHost == domain || apiHost.hasSuffix("." + domain)
    }
}
