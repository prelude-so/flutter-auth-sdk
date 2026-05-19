import Foundation

/// Bridges the vendored `PreludeSignalsDispatcher` protocol onto
/// the vendored `Prelude` signals type.
///
/// The upstream `PreludeSignalsAdapter` declared in
/// `apple-auth-sdk` does the same thing, but ships with
/// `import Prelude` because that repo consumes `apple-sdk` as a
/// separate SwiftPM module. The Flutter plugin vendors both
/// source trees into a single CocoaPods module, so a separate
/// `import` won't resolve — the types are already in scope. This
/// file re-implements the adapter without that import.
///
/// `nil` / empty `sdkKey` is a permissive no-op: `dispatch()`
/// returns `nil`, the auth client omits `dispatch_id` from
/// the login body, and the rest of the flow proceeds as if
/// signals weren't configured.
struct FlutterPreludeSignalsAdapter: PreludeSignalsDispatcher, @unchecked Sendable {
    private let prelude: Prelude?

    init(sdkKey: String?, timeout: TimeInterval = 5.0) {
        guard let sdkKey, !sdkKey.isEmpty else {
            self.prelude = nil
            return
        }
        self.prelude = Prelude(Configuration(sdkKey: sdkKey, timeout: timeout))
    }

    func dispatch() async throws -> String? {
        guard let prelude else { return nil }
        return try await prelude.dispatchSignals()
    }
}
