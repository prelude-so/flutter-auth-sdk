// PreludeFlutterAuthSdkPlugin
//
// iOS plugin for the Flutter Auth SDK. Bridges the Dart
// `PreludeAuthClient` API onto the native auth client.
//
// One Dart instance maps to one native client, looked up by the
// per-instance handle string the Dart side stamps at construction.
// Native clients are created lazily on first use and reused for
// the lifetime of the handle so DPoP keys, refresh tokens, and
// the access-token cache stay stable across calls.
//
// In-flight step-up challenges are cached on the native side,
// keyed by (handle, challengeID), so the wire form sent across
// the channel can omit the bearer challenge token.

import Flutter
import UIKit

public class PreludeFlutterAuthSdkPlugin: NSObject, FlutterPlugin {
    /// Per-handle native client cache. Reads + writes are
    /// serialised behind ``registryQueue`` so concurrent Dart
    /// calls under the same handle observe a consistent client.
    private var registry: [String: PreludeAuthClient] = [:]

    /// Per-handle in-flight step-up challenges, keyed by
    /// (handle, challengeID). Filled by ``requestStepUp`` /
    /// ``submitStepUpOTP`` when a challenge advances; read by
    /// ``sendStepUpOTP`` to resolve the cached token; cleared on
    /// flow completion, on non-OTP errors, and on ``dispose``.
    /// The Dart-side `StepUpChallenge` carries only public
    /// metadata; the wire form maps back to the cached value
    /// here so the challenge JWT never leaves the iOS process.
    private var challenges: [String: [String: StepUpChallenge]] = [:]

    /// Single serial queue covering both ``registry`` and
    /// ``challenges``. Their lifetimes are coupled — disposing a
    /// handle should evict both in lockstep — so a shared queue
    /// keeps that invariant cheap to express.
    private let registryQueue = DispatchQueue(
        label: "so.prelude.flutterauthsdk.registry"
    )

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "prelude_so_flutter_auth_sdk",
            binaryMessenger: registrar.messenger()
        )
        let instance = PreludeFlutterAuthSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// Methods routed through ``dispatch(call:args:client:)``.
    /// Listed up front so unknown method names short-circuit with
    /// `FlutterMethodNotImplemented` *before* we provision a
    /// native client (DPoP key + Keychain hits are not free, and
    /// a typo doesn't deserve them).
    private static let asyncMethods: Set<String> = [
        "startOTPLogin", "resendOTP", "checkOTP",
        "loginWithPassword", "passwordCompliancy", "changePassword",
        "refresh", "logout", "invalidateSession",
        "listSessions", "revokeSessions",
        "requestStepUp", "sendStepUpOTP", "submitStepUpOTP",
        "getActiveStepUp",
        "getProfile", "getSessionID",
        "getAccessToken", "getAccessTokenExpiresAt",
    ]

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Methods that don't need a native client live on the
        // synchronous side so we don't pay for a Task hop.
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            return
        case "dispose":
            handleDispose(call, result: result)
            return
        default:
            break
        }

        // Reject unknown methods before resolving the client.
        // Otherwise a typo'd method name would still mint DPoP
        // keys + read Keychain just to answer "not implemented".
        guard Self.asyncMethods.contains(call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }

        // All other methods are async. Resolve the native client
        // up front so handler bodies stay flat.
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? String,
              let configRaw = args["config"] as? [String: Any]
        else {
            result(missingArgs(call.method))
            return
        }

        // Resolve + dispatch run on the cooperative pool, not the
        // platform thread. `resolveClient` lazily provisions the
        // native client on first use, which hits Keychain and, on
        // the first call per process, the Secure Enclave probe.
        // Doing that work here would block the Flutter messenger
        // thread.
        Task {
            do {
                let client = try resolveClient(handle: handle, configRaw: configRaw)
                let value = try await dispatch(
                    call: call,
                    args: args,
                    handle: handle,
                    client: client
                )
                Self.deliver(value, to: result)
            } catch {
                Self.deliver(toFlutterError(error), to: result)
            }
        }
    }

    /// Forward `value` to `result` on the platform (main) thread.
    ///
    /// `FlutterResult` callbacks must fire on the binary
    /// messenger's thread, which is the main thread for the
    /// default Flutter engine. `Task { ... }` resumes on Swift's
    /// global executor, so anything called from a Task
    /// continuation has to hop back. Synchronous call sites in
    /// ``handle(_:result:)`` skip this — they are already on
    /// main — to avoid round-tripping a sentinel through the
    /// runloop for free.
    private static func deliver(_ value: Any?, to result: @escaping FlutterResult) {
        if Thread.isMainThread {
            result(value)
        } else {
            DispatchQueue.main.async { result(value) }
        }
    }

    // MARK: - Registry

    private func resolveClient(
        handle: String,
        configRaw: [String: Any]
    ) throws -> PreludeAuthClient {
        // Lookup-or-create runs inside the same `registryQueue.sync`
        // block on purpose: a split read-then-write would let two
        // callers for the same handle both miss the cache, both run
        // `PreludeAuthClient.init` (which provisions DPoP key
        // state via Keychain), and the second writer would win —
        // leaving the loser's keychain footprint with no Dart-side
        // reference to dispose it. Construction is on the order of
        // milliseconds and runs at most once per handle for the
        // process lifetime, so holding the serial queue across it
        // is cheap insurance. `DispatchQueue.sync` is `rethrows`,
        // so a throwing init still surfaces correctly to the caller.
        // Decode + dispatcher creation outside the lock — both are
        // pure functions of the call args, hold no Pod state, and
        // don't depend on `registry`. Keeps the locked section
        // small and side-steps closure-inference fragility around
        // the protocol-typed `signalsDispatcher` parameter.
        let config = try ClientConfig(decoding: configRaw)
        let signalsKey = resolveSignalsSDKKey(
            keyOverride: config.signalsKeyOverride
        )
        // Adapter no-ops when the key is nil, so we always pass
        // it through. Hides the manifest / override choice from
        // the auth client.
        let dispatcher: PreludeSignalsDispatcher =
            FlutterPreludeSignalsAdapter(sdkKey: signalsKey)
        return try registryQueue.sync { () throws -> PreludeAuthClient in
            if let existing = registry[handle] {
                return existing
            }
            let client = try PreludeAuthClient(
                endpoint: config.endpoint,
                hostOverride: config.hostOverride,
                signalsDispatcher: dispatcher,
                timeout: config.timeout,
                allowInsecureTLS: config.allowInsecureTLS
            )
            registry[handle] = client
            return client
        }
    }

    private func handleDispose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? String
        else {
            result(missingArgs(call.method))
            return
        }
        registryQueue.sync {
            registry.removeValue(forKey: handle)
            challenges.removeValue(forKey: handle)
        }
        result(nil)
    }

    // MARK: - Challenge cache

    /// Insert or replace a challenge under (handle, challengeID).
    /// `blocked` challenges and the empty `challengeID` sentinel
    /// are skipped: neither is submittable, so caching them would
    /// only grow the dict.
    private func cacheChallenge(handle: String, challenge: StepUpChallenge) {
        guard challenge.status != .blocked, !challenge.challengeID.isEmpty else {
            return
        }
        registryQueue.sync {
            // Don't resurrect entries for a handle that's already
            // been disposed; the writer raced the dispose call.
            guard registry[handle] != nil else { return }
            var slot = challenges[handle] ?? [:]
            slot[challenge.challengeID] = challenge
            challenges[handle] = slot
        }
    }

    private func evictChallenge(handle: String, challengeID: String) {
        registryQueue.sync {
            guard var slot = challenges[handle] else { return }
            slot.removeValue(forKey: challengeID)
            if slot.isEmpty {
                challenges.removeValue(forKey: handle)
            } else {
                challenges[handle] = slot
            }
        }
    }

    /// Resolve a Dart-side challengeID back to the cached
    /// `StepUpChallenge`. Throws ``PreludeAuthError/invalidChallengeToken``
    /// when the challenge is unknown or has expired locally — both
    /// recover via ``requestStepUp(scope:)`` so the consumer
    /// handles a single error path.
    private func lookupChallenge(
        handle: String,
        challengeID: String
    ) throws -> StepUpChallenge {
        var found: StepUpChallenge?
        registryQueue.sync { found = challenges[handle]?[challengeID] }
        guard let challenge = found else {
            throw PreludeAuthError.invalidChallengeToken(
                "Step-up challenge `\(challengeID)` not found. " +
                "Pass the value returned by requestStepUp / submitStepUpOTP " +
                "unchanged, or call requestStepUp(scope:) again."
            )
        }
        return challenge
    }

    // MARK: - Method dispatch

    /// Route a single call to the matching `PreludeAuthClient`
    /// async method, encode the result back to a Dart-friendly
    /// dictionary, and surface any throw as a `PreludeAuthError`
    /// for the outer error mapper to translate.
    ///
    /// `handle` is threaded through explicitly because the
    /// step-up cache helpers are keyed on it; without an explicit
    /// parameter, naming a local `handle` here would shadow into
    /// `self.handle` (the `FlutterPlugin` method).
    private func dispatch(
        call: FlutterMethodCall,
        args: [String: Any],
        handle: String,
        client: PreludeAuthClient
    ) async throws -> Any? {
        switch call.method {
        // OTP -----------------------------------------------------
        case "startOTPLogin":
            let options = try decodeStartOTPLoginOptions(args["options"])
            try await client.startOTPLogin(options)
            return nil
        case "resendOTP":
            try await client.resendOTP()
            return nil
        case "checkOTP":
            guard let code = args["code"] as? String else {
                throw missingArgError(call.method, "code")
            }
            let user = try await client.checkOTP(code)
            return Codec.encode(user: user)

        // Password ------------------------------------------------
        case "loginWithPassword":
            let options = try decodeLoginWithPasswordOptions(args["options"])
            let user = try await client.loginWithPassword(options)
            return Codec.encode(user: user)
        case "passwordCompliancy":
            let compliancy = try await client.passwordCompliancy()
            return Codec.encode(compliancy: compliancy)
        // `validatePassword` is intentionally absent — Dart
        // classifies locally against the cached compliancy.
        case "changePassword":
            guard let newPassword = args["newPassword"] as? String else {
                throw missingArgError(call.method, "newPassword")
            }
            try await client.changePassword(RedactedString(newPassword))
            return nil

        // Refresh / logout / invalidate ---------------------------
        case "refresh":
            let user = try await client.refresh()
            return Codec.encode(user: user)
        case "logout":
            try await client.logout()
            return nil
        case "invalidateSession":
            try await client.invalidateSession()
            return nil

        // Manage sessions ----------------------------------------
        case "listSessions":
            let options = try decodeListSessionsOptions(args["options"])
            let response = try await client.listSessions(options)
            return Codec.encode(listSessions: response)
        case "revokeSessions":
            let target = try decodeRevokeTarget(args["target"])
            try await client.revokeSessions(target)
            return nil

        // Step-up -------------------------------------------------
        case "requestStepUp":
            guard let scope = args["scope"] as? String else {
                throw missingArgError(call.method, "scope")
            }
            let metadata = try decodeMetadata(args["metadata"])
            let challenge = try await client.requestStepUp(
                scope: scope,
                metadata: metadata
            )
            cacheChallenge(handle: handle, challenge: challenge)
            return Codec.encode(challenge: challenge)
        case "getActiveStepUp":
            guard let challenge = await client.activeStepUp else { return nil }
            // Mirror into the per-handle cache so a follow-up
            // `submitStepUpOTP` resolves the bearer challenge token
            // without the caller needing to hold the handle locally.
            cacheChallenge(handle: handle, challenge: challenge)
            return Codec.encode(challenge: challenge)
        case "sendStepUpOTP":
            guard let challengeID = args["challengeID"] as? String else {
                throw missingArgError(call.method, "challengeID")
            }
            let challenge = try lookupChallenge(handle: handle, challengeID: challengeID)
            try await client.sendStepUpOTP(challenge)
            return nil
        case "submitStepUpOTP":
            guard let challengeID = args["challengeID"] as? String,
                  let code = args["code"] as? String
            else {
                throw missingArgError(call.method, "challengeID/code")
            }
            let challenge = try lookupChallenge(handle: handle, challengeID: challengeID)
            do {
                let next = try await client.submitStepUpOTP(challenge, code: code)
                if let next {
                    // Insert before evicting so a concurrent reader
                    // observing under the new ID never sees an empty
                    // slot during a multi-step transition.
                    cacheChallenge(handle: handle, challenge: next)
                    if next.challengeID != challenge.challengeID {
                        evictChallenge(handle: handle, challengeID: challenge.challengeID)
                    }
                    return Codec.encode(challenge: next)
                }
                // Flow completed: post-completion refresh has
                // already minted the scoped access token.
                evictChallenge(handle: handle, challengeID: challenge.challengeID)
                return nil
            } catch let error as PreludeAuthError {
                // `invalidOTPCode` keeps the challenge usable up to
                // the server's bucket limit. Any other error kills
                // the challenge.
                if case .invalidOTPCode = error {
                    // keep cached
                } else {
                    evictChallenge(handle: handle, challengeID: challenge.challengeID)
                }
                throw error
            }

        // Cached readers -----------------------------------------
        case "getProfile":
            guard let profile = await client.profile else { return nil }
            return Codec.encode(profile: profile)
        case "getSessionID":
            return await client.sessionID
        case "getAccessToken":
            return await client.accessToken
        case "getAccessTokenExpiresAt":
            guard let date = await client.accessTokenExpiresAt else { return nil }
            return Int(date.timeIntervalSince1970)

        default:
            // Should be unreachable: ``handle(_:result:)`` filters
            // unknown methods against ``asyncMethods`` before
            // reaching us. If you're adding a new method, also add
            // it to the allowlist *and* a switch case here.
            //
            // Surface as `bad_request` rather than `fatalError`
            // so the next person who adds to ``asyncMethods`` but
            // forgets to wire the dispatch arm gets a visible Dart
            // error instead of an app crash.
            throw decodeError("dispatch: unhandled method `\(call.method)`")
        }
    }
}

// MARK: - Args / config decoding

private struct ClientConfig {
    let endpoint: Endpoint
    let hostOverride: String?
    let timeout: TimeInterval
    let allowInsecureTLS: Bool
    /// Dart-supplied override; nil falls back to `Info.plist`.
    let signalsKeyOverride: String?

    init(decoding raw: [String: Any]) throws {
        guard let endpointRaw = raw["endpoint"] as? [String: Any] else {
            throw decodeError("config.endpoint missing or wrong shape")
        }
        switch endpointRaw["kind"] as? String {
        case "default":
            self.endpoint = .default
        case "custom":
            guard let address = endpointRaw["address"] as? String else {
                throw decodeError("Endpoint.custom missing address")
            }
            self.endpoint = .custom(address)
        default:
            throw decodeError("Unknown Endpoint kind")
        }
        self.hostOverride = raw["hostOverride"] as? String
        // `timeoutSeconds` arrives as either Double or Int.
        if let secs = raw["timeoutSeconds"] as? Double {
            self.timeout = secs
        } else if let secs = raw["timeoutSeconds"] as? Int {
            self.timeout = TimeInterval(secs)
        } else {
            self.timeout = 10.0
        }
        self.allowInsecureTLS = (raw["allowInsecureTLS"] as? Bool) ?? false
        // Empty string is treated as absent so a misconfigured
        // Dart-side `String.fromEnvironment` doesn't construct a
        // half-wired dispatcher.
        if let override = raw["signalsKeyOverride"] as? String, !override.isEmpty {
            self.signalsKeyOverride = override
        } else {
            self.signalsKeyOverride = nil
        }
    }
}

/// Resolve the Prelude signals SDK key for this process.
///
/// Precedence: Dart-supplied overrideKey > `Info.plist` `PreludeSDKKey`.
/// Empty strings are treated as "not configured" so accidentally
/// shipping an empty plist entry doesn't construct a half-wired
/// dispatcher. Returning `nil` here is a supported no-op — signals
/// just don't dispatch and `dispatch_id` is omitted from login
/// bodies.
private func resolveSignalsSDKKey(keyOverride: String?) -> String? {
    if let keyOverride, !keyOverride.isEmpty { return keyOverride }
    let plistValue = Bundle.main.object(
        forInfoDictionaryKey: "PreludeSDKKey"
    ) as? String
    return (plistValue?.isEmpty == false) ? plistValue : nil
}

private func decodeStartOTPLoginOptions(_ raw: Any?) throws -> StartOTPLoginOptions {
    guard let json = raw as? [String: Any],
          let identifierRaw = json["identifier"] as? [String: Any],
          let typeWire = identifierRaw["type"] as? String,
          let value = identifierRaw["value"] as? String
    else {
        throw decodeError("StartOTPLoginOptions: malformed payload")
    }
    guard let type = PreludeIdentifierType(rawValue: typeWire) else {
        throw decodeError("Unknown PreludeIdentifierType: \(typeWire)")
    }
    let identifier = PreludeIdentifier(type: type, value: value)
    let loginConfigID = json["loginConfigID"] as? String
    return StartOTPLoginOptions(identifier: identifier, loginConfigID: loginConfigID)
}

private func decodeListSessionsOptions(_ raw: Any?) throws -> ListSessionsOptions {
    // Empty / nil maps fall through to ListSessionsOptions() so the
    // server's defaults apply without a Dart-side change.
    let json = (raw as? [String: Any]) ?? [:]
    let limit = json["limit"] as? Int
    let offset = json["offset"] as? Int
    return ListSessionsOptions(limit: limit, offset: offset)
}

private func decodeRevokeTarget(_ raw: Any?) throws -> RevokeTarget {
    guard let json = raw as? [String: Any],
          let kind = json["kind"] as? String
    else {
        throw decodeError("RevokeTarget: malformed payload")
    }
    switch kind {
    case "all": return .all
    case "others": return .others
    case "mine": return .mine
    case "session":
        guard let id = json["sessionID"] as? String else {
            throw decodeError("RevokeTarget.session: missing sessionID")
        }
        return .session(id: id)
    default:
        throw decodeError("Unknown RevokeTarget kind: \(kind)")
    }
}

/// Optional `[String: String]` step-up audit metadata. The
/// standard channel codec types maps as `[AnyHashable: Any]` so a
/// direct `as? [String: String]` cast can drop intent silently —
/// validate every key/value individually instead.
private func decodeMetadata(_ raw: Any?) throws -> [String: String]? {
    if raw is NSNull { return nil }
    guard let any = raw else { return nil }
    guard let map = any as? [String: Any] else {
        throw decodeError("metadata: expected map of String → String")
    }
    var out: [String: String] = [:]
    out.reserveCapacity(map.count)
    for (key, value) in map {
        guard let str = value as? String else {
            throw decodeError("metadata: non-string value for `\(key)`")
        }
        out[key] = str
    }
    return out
}

private func decodeLoginWithPasswordOptions(_ raw: Any?) throws -> LoginWithPasswordOptions {
    guard let json = raw as? [String: Any],
          let email = json["emailAddress"] as? String,
          let password = json["password"] as? String
    else {
        throw decodeError("LoginWithPasswordOptions: malformed payload")
    }
    // `password:` is a plain `String` here on purpose:
    // `LoginWithPasswordOptions.init(emailAddress:password:)` takes
    // `String` and wraps internally with `RedactedString`. The
    // sibling `changePassword` bridge wraps explicitly because that
    // method's signature is `func changePassword(_ : RedactedString)`
    // with no String overload — the two paths diverge at the iOS
    // SDK API, not here.
    return LoginWithPasswordOptions(emailAddress: email, password: password)
}

// MARK: - Codec (Swift ↔ Dart-friendly dictionaries)

private enum Codec {
    static func encode(user: PreludeUser) -> [String: Any] {
        [
            "accessToken": user.accessToken,
            "profile": encode(profile: user.profile),
        ]
    }

    static func encode(profile: PreludeProfile) -> [String: Any] {
        var extras: [String: Any] = [:]
        for (k, v) in profile.extras {
            extras[k] = encode(json: v)
        }
        // Use NSNull for absent string fields so the standard
        // Flutter codec encodes them as Dart `null` instead of
        // wrapping a nil Optional through `as Any`.
        return [
            "userID": profile.userID ?? NSNull(),
            "sessionID": profile.sessionID ?? NSNull(),
            "extras": extras,
        ]
    }

    static func encode(compliancy: PreludePasswordCompliancy) -> [String: Any] {
        [
            "minLength": compliancy.minLength,
            "maxLength": compliancy.maxLength,
            "uppercase": compliancy.uppercase,
            "lowercase": compliancy.lowercase,
            "numbers": compliancy.numbers,
            "symbols": compliancy.symbols,
        ]
    }

    static func encode(sessionView v: PreludeSessionView) -> [String: Any] {
        // Timestamps are server-provided ISO 8601 strings on the
        // iOS SDK; pass them through `.isoString` to validate and
        // re-emit in canonical form before they cross the channel.
        [
            "id": v.id,
            "deviceModel": v.deviceModel,
            "deviceType": v.deviceType.rawValue,
            "osVersion": v.osVersion,
            "countryCode": v.countryCode,
            "createdAt": v.createdAt.isoString,
            "lastSeenAt": v.lastSeenAt.isoString,
            "expiresAt": v.expiresAt.isoString,
        ]
    }

    static func encode(listSessions r: ListSessionsResponse) -> [String: Any] {
        [
            "sessions": r.sessions.map { encode(sessionView: $0) },
            "total": r.total,
            "limit": r.limit,
            "offset": r.offset,
        ]
    }

    /// Encode the public-surface fields only. The challenge token
    /// and expiry stay in the plugin's per-handle cache so the
    /// bearer credential never crosses the channel. See
    /// ``PreludeFlutterAuthSdkPlugin/cacheChallenge(handle:challenge:)``.
    static func encode(challenge: StepUpChallenge) -> [String: Any] {
        [
            "status": challenge.status.rawValue,
            "challengeID": challenge.challengeID,
            "currentStep": challenge.currentStep ?? NSNull(),
            "requestedScope": challenge.requestedScope,
        ]
    }

    /// Tagged JSON encoding so 64-bit-int claims survive the
    /// channel without dropping precision through `Double`.
    static func encode(json: PreludeJSONValue) -> [String: Any] {
        switch json {
        case .string(let s):
            return ["kind": "string", "value": s]
        case .int(let i):
            return ["kind": "int", "value": NSNumber(value: i)]
        case .double(let d):
            return ["kind": "double", "value": d]
        case .bool(let b):
            return ["kind": "bool", "value": b]
        case .array(let arr):
            return ["kind": "array", "value": arr.map(encode(json:))]
        case .object(let obj):
            var bridged: [String: Any] = [:]
            for (k, v) in obj { bridged[k] = encode(json: v) }
            return ["kind": "object", "value": bridged]
        case .null:
            return ["kind": "null"]
        }
    }
}

// MARK: - ISO 8601 normalization

/// `ISO8601DateFormatter` is the canonical Foundation formatter; we
/// instantiate two variants because the server can emit timestamps
/// with or without fractional seconds and a single formatter only
/// accepts one shape at a time.
private let iso8601WithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private extension String {
    /// Defensive ISO 8601 normalization. Parses with either fractional
    /// or plain ISO 8601 and re-emits in canonical fractional form.
    /// Falls back to `self` when parsing fails so a malformed
    /// timestamp surfaces as a structured `ArgumentError` on the
    /// Dart side instead of being silently rewritten here.
    var isoString: String {
        if let d = iso8601WithFraction.date(from: self) {
            return iso8601WithFraction.string(from: d)
        }
        if let d = iso8601Plain.date(from: self) {
            return iso8601WithFraction.string(from: d)
        }
        return self
    }
}

// MARK: - Error helpers

private struct DecodeError: Error { let message: String }

private func decodeError(_ message: String) -> Error {
    DecodeError(message: message)
}

private func missingArgError(_ method: String, _ name: String) -> Error {
    DecodeError(message: "\(method): missing required arg `\(name)`")
}

private func missingArgs(_ method: String) -> FlutterError {
    FlutterError(
        code: "bad_request",
        message: "\(method): malformed arguments",
        details: nil
    )
}

private func toFlutterError(_ error: Error) -> FlutterError {
    if let e = error as? PreludeAuthError {
        return mapSessionError(e)
    }
    if let e = error as? DecodeError {
        return FlutterError(code: "bad_request", message: e.message, details: nil)
    }
    return FlutterError(
        code: "generic",
        message: String(describing: error),
        details: nil
    )
}

/// Match Dart's `PreludeAuthException.fromPlatformException`
/// switch arm-for-arm so the typed Dart exceptions hydrate
/// correctly. `generic(code:message:)` round-trips its server
/// code as the FlutterError code so unknown codes still get
/// surfaced to consumers.
private func mapSessionError(_ error: PreludeAuthError) -> FlutterError {
    switch error {
    case .badRequest(let m):
        return FlutterError(code: "bad_request", message: m, details: nil)
    case .unauthorized(let m):
        return FlutterError(code: "unauthorized", message: m, details: nil)
    case .rateLimited(let m):
        return FlutterError(code: "rate_limited", message: m, details: nil)
    case .internalServerError(let m):
        return FlutterError(code: "internal_server_error", message: m, details: nil)
    case .missingChallengeToken(let m):
        return FlutterError(code: "missing_challenge_token", message: m, details: nil)
    case .invalidChallengeToken(let m):
        return FlutterError(code: "invalid_challenge_token", message: m, details: nil)
    case .expiredChallengeToken(let m):
        return FlutterError(code: "expired_challenge_token", message: m, details: nil)
    case .tokenReused(let m):
        return FlutterError(code: "token_reused", message: m, details: nil)
    case .invalidOTPCode(let m):
        return FlutterError(code: "invalid_otp_code", message: m, details: nil)
    case .refreshFailed(let m):
        return FlutterError(code: "refresh_failed", message: m, details: nil)
    case .timeout:
        return FlutterError(code: "timeout", message: "Request timed out", details: nil)
    case .invalidConfiguration(let m):
        return FlutterError(code: "invalid_configuration", message: m, details: nil)
    case .invalidPassword(let m):
        return FlutterError(code: "invalid_password", message: m, details: nil)
    case .forbidden(let m):
        return FlutterError(code: "forbidden", message: m, details: nil)
    case .insufficientScope(let m):
        return FlutterError(code: "insufficient_scope", message: m, details: nil)
    case .notFound(let m):
        return FlutterError(code: "not_found", message: m, details: nil)
    case .conflict(let m):
        return FlutterError(code: "conflict", message: m, details: nil)
    case .network(let underlying):
        return FlutterError(
            code: "network",
            message: underlying.localizedDescription,
            details: nil
        )
    case .generic(let code, let message):
        return FlutterError(code: code, message: message, details: nil)
    }
}
