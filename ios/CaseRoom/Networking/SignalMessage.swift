/*
 * Purpose: Message model for the practice-session signaling WebSocket
 *          (GET /ws/practice/{session_id}) — pure JSON <-> enum mapping.
 * Inputs: raw Data frames received over SignalingClient's WebSocket.
 * Outputs: Data frames for outbound control messages (knock/admit/deny/bye/ping).
 * Run: SignalMessage.parse(_:) from SignalingClient; SignalMessage.knock() etc.
 */

import Foundation

enum SignalMessage: Equatable {
    case ok(role: String, peerPresent: Bool, admitted: Bool)
    case knock(displayName: String)
    case admit
    case deny
    case peerJoined
    case peerLeft
    case reveal(exhibitId: Int, keyB64: String)
    case sessionUpdate
    case pong
    case unknown

    /// Pure decoder — no socket/session dependency. Malformed JSON or a
    /// missing/absent "type" key returns nil; a well-formed but unrecognized
    /// type (e.g. a future P3 addition) returns .unknown rather than nil.
    static func parse(_ data: Data) -> SignalMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "ok":
            guard let role = json["role"] as? String,
                  let peerPresent = json["peer_present"] as? Bool,
                  let admitted = json["admitted"] as? Bool else {
                return nil
            }
            return .ok(role: role, peerPresent: peerPresent, admitted: admitted)
        case "knock":
            guard let displayName = json["display_name"] as? String else {
                return nil
            }
            return .knock(displayName: displayName)
        case "admit":
            return .admit
        case "deny":
            return .deny
        case "peer-joined":
            return .peerJoined
        case "peer-left":
            return .peerLeft
        case "reveal":
            guard let exhibitId = intValue(json["exhibit_id"]),
                  let keyB64 = json["key_b64"] as? String else {
                return nil
            }
            return .reveal(exhibitId: exhibitId, keyB64: keyB64)
        case "session-update":
            return .sessionUpdate
        case "pong":
            return .pong
        default:
            return .unknown
        }
    }

    // APNs/JSON numbers can arrive as either a JSON number or a string;
    // handle both defensively.
    private static func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    // MARK: - Outbound helpers
    // Only these five types are ever emitted — sdp/ice are P3 media-only
    // and must never be produced by this client.

    static func knock() -> Data {
        encode(["type": "knock"])
    }

    static func admit() -> Data {
        encode(["type": "admit"])
    }

    static func deny() -> Data {
        encode(["type": "deny"])
    }

    static func bye() -> Data {
        encode(["type": "bye"])
    }

    static func ping() -> Data {
        encode(["type": "ping"])
    }

    private static func encode(_ dict: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }
}
