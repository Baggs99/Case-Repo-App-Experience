/*
 * Purpose: On-device cache of the /api/v1/drills/templates bank bytes — the
 *          offline source the LocalDrillGenerator reads. Cache-first read plus a
 *          best-effort refresh called on app foreground.
 * Inputs: a DrillService (for refresh); the App Group container (fallback: the
 *         caches directory) holding drill-templates.json.
 * Outputs: reads/writes drill-templates.json in the resolved directory.
 * Run: TemplateCache().load(); await TemplateCache().refresh(service: APIClient.shared)
 */

import Foundation

struct TemplateCache {
    private static let fileName = "drill-templates.json"

    /// App Group container when provisioned, else the caches directory so the
    /// engine still works on unprovisioned dev builds (mirrors AppGroup's fallback
    /// philosophy). nil only if even the caches directory cannot be resolved.
    static var defaultDirectory: URL? {
        AppGroup.containerURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private let directory: URL?

    init(directory: URL? = TemplateCache.defaultDirectory) {
        self.directory = directory
    }

    private var fileURL: URL? {
        directory?.appendingPathComponent(Self.fileName)
    }

    /// The cached bank bytes, or nil when nothing has been cached yet.
    func load() -> Data? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    /// Best-effort overwrite from the server. Silent on any failure (offline,
    /// empty body, unwritable directory) — the last good cache is left intact.
    func refresh(service: DrillService) async {
        guard let data = try? await service.templatePack(), !data.isEmpty,
              let url = fileURL else { return }
        try? data.write(to: url, options: .atomic)
    }
}
