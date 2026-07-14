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
    case sdp(description: SDP)
    case ice(candidate: ICECandidate?)
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
        case "sdp":
            guard let description = json["description"] as? [String: Any],
                  let sdpType = description["type"] as? String,
                  let sdp = description["sdp"] as? String else {
                return nil
            }
            return .sdp(description: SDP(type: sdpType, sdp: sdp))
        case "ice":
            guard let candidateValue = json["candidate"] else {
                return nil
            }
            if candidateValue is NSNull {
                return .ice(candidate: nil)
            }
            guard let candidateDict = candidateValue as? [String: Any],
                  let candidate = candidateDict["candidate"] as? String else {
                return nil
            }
            let sdpMid = candidateDict["sdpMid"] as? String
            let sdpMLineIndex = intValue(candidateDict["sdpMLineIndex"]).map { Int32($0) }
            return .ice(candidate: ICECandidate(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex))
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
    // knock/admit/deny/bye/ping are the lobby-control set. sdp/ice are P3
    // media-negotiation payloads, produced only by Negotiator via
    // SignalingChannel.sendSDP/sendICE — never by the lobby-control paths.

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

    /// Wire shape for sdp matches the web peer's rtc.js:
    /// {"type":"sdp","description":{"type":"offer"|"answer","sdp":"..."}}.
    static func sdp(_ description: SDP) -> Data {
        encode([
            "type": "sdp",
            "description": ["type": description.type, "sdp": description.sdp],
        ])
    }

    /// Wire shape for ice matches what the web peer's rtc.js feeds to
    /// addIceCandidate: {"type":"ice","candidate":{candidate,sdpMid,sdpMLineIndex}}
    /// or {"type":"ice","candidate":null} for end-of-candidates.
    static func ice(_ candidate: ICECandidate?) -> Data {
        guard let candidate else {
            return encode(["type": "ice", "candidate": NSNull()])
        }
        let candidateDict: [String: Any] = [
            "candidate": candidate.candidate,
            "sdpMid": candidate.sdpMid ?? NSNull(),
            "sdpMLineIndex": candidate.sdpMLineIndex.map { NSNumber(value: $0) } ?? NSNull(),
        ]
        return encode(["type": "ice", "candidate": candidateDict])
    }

    private static func encode(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }
}
