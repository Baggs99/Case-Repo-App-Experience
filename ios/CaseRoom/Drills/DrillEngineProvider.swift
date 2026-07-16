/*
 * Purpose: Selects the drill engine — the on-device Foundation Models engine when
 *          iOS 26+, the model is available, and a template pack is cached; else the
 *          server engine. The app's single entry point for obtaining a DrillEngine.
 * Inputs: a DrillService (server fallback), an injectable FM-availability probe, a
 *         user id + date for the on-device seed, and a TemplateCache.
 * Outputs: a DrillEngine (FoundationModelDrillEngine or ServerDrillEngine).
 * Run: DrillEngineProvider.make(service: APIClient.shared, userId: user.id)
 *
 * This file does NOT import FoundationModels: the probe reaches the FM type only
 * inside a #available(iOS 26.0, *) block, keeping all FM touches in the engine file.
 */

import Foundation

enum DrillEngineProvider {
    /// Default probe: true only when iOS 26+ AND the on-device model reports ready.
    /// Injected as a closure in tests so engine selection is exercised without the
    /// live model (which never runs in the simulator).
    static func defaultFMProbe() -> Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelDrillEngine.isModelAvailable()
        }
        return false
    }

    /// Returns the on-device FM engine when iOS 26+, `fmAvailable()` is true, and a
    /// template pack is cached (needed to seed the local generator); else the
    /// server engine. `userId`/`date` seed the on-device generator — they default
    /// so the documented `make(service:)`/`make(service:fmAvailable:)` calls compile;
    /// Task 7 passes the signed-in user's id.
    static func make(service: DrillService,
                     fmAvailable: () -> Bool = defaultFMProbe,
                     userId: Int = 0,
                     date: @escaping () -> Date = { Date() },
                     cache: TemplateCache = TemplateCache()) -> DrillEngine {
        if #available(iOS 26.0, *) {
            if fmAvailable(),
               let pack = cache.load(),
               let generator = try? LocalDrillGenerator(templatePack: pack) {
                return FoundationModelDrillEngine(generator: generator, userId: userId, dateProvider: date)
            }
        }
        return ServerDrillEngine(service: service)
    }
}
