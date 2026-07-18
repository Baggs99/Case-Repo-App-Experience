/*
 * Purpose: Video-call view — remote video full-screen, local preview
 *          picture-in-picture, mute/camera-toggle controls mirroring the
 *          web's btn-mute/btn-cam. Real camera capture + rendering only
 *          exercises on a device (Task 12); the simulator build only needs
 *          this to compile and the toggle wiring to be correct.
 * Inputs: a MediaCapturing (local capture, already start()ed by the caller);
 *         a RemoteMediaSlot the session screen (Task 8) populates from
 *         MediaTransport.onRemoteTrack; the current videoEnabled/audioEnabled
 *         flags; and onToggleVideo/onToggleAudio callbacks the parent owns.
 * Outputs: none beyond the onToggleVideo/onToggleAudio callbacks the parent
 *          uses to drive capture.setVideoEnabled/setAudioEnabled.
 * Run: pushed for a live session once local media capture has started.
 */

import SwiftUI
import WebRTC

/// Settable slot for the remote peer's track handle. The remote track
/// arrives asynchronously from MediaTransport.onRemoteTrack (wired by
/// Task 8) after VideoCallView is already on screen, so it can't be passed
/// as a constant init parameter — the session screen sets it as it arrives.
@Observable
final class RemoteMediaSlot {
    var trackHandle: MediaTrackHandle?

    init(trackHandle: MediaTrackHandle? = nil) {
        self.trackHandle = trackHandle
    }
}

struct VideoCallView: View {
    let capture: MediaCapturing
    var remoteMediaSlot: RemoteMediaSlot
    let videoEnabled: Bool
    let audioEnabled: Bool
    let onToggleVideo: () -> Void
    let onToggleAudio: () -> Void
    @Environment(\.dsPalette) private var palette

    init(
        capture: MediaCapturing,
        remoteMediaSlot: RemoteMediaSlot = RemoteMediaSlot(),
        videoEnabled: Bool,
        audioEnabled: Bool,
        onToggleVideo: @escaping () -> Void,
        onToggleAudio: @escaping () -> Void
    ) {
        self.capture = capture
        self.remoteMediaSlot = remoteMediaSlot
        self.videoEnabled = videoEnabled
        self.audioEnabled = audioEnabled
        self.onToggleVideo = onToggleVideo
        self.onToggleAudio = onToggleAudio
    }

    var body: some View {
        ZStack {
            // Dark striped interviewer pane — the placeholder the remote video
            // renders over once frames arrive (canvas 4a live surface).
            Rectangle()
                .fill(palette.surface)
                .overlay(DiagonalStripes(color: palette.ink.opacity(0.05)))
                .ignoresSafeArea()

            RTCVideoRepresentable(track: remoteVideoTrack)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    liveChip
                    Spacer()
                    // Self-view inset over the untouched local representable.
                    RTCVideoRepresentable(track: localVideoTrack)
                        .frame(width: 96, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(palette.ink.opacity(0.14), lineWidth: 1)
                        )
                }
                .padding(16)

                Spacer()
                controls
            }
        }
    }

    private var liveChip: some View {
        HStack(spacing: 7) {
            BlinkDot()
            Text("LIVE")
                .font(.archivo(10, weight: 600))
                .tracking(10 * 0.14)
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassChip()
    }

    private var controls: some View {
        HStack(spacing: 12) {
            controlChip(audioEnabled ? "Mute" : "Unmute", action: onToggleAudio)
            controlChip(videoEnabled ? "Camera off" : "Camera on", action: onToggleVideo)
        }
        .padding(.bottom, 24)
    }

    private func controlChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.archivo(12.5, weight: 600))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .glassChip()
        }
        .buttonStyle(DSPressStyle())
    }

    private var localVideoTrack: RTCVideoTrack? {
        capture.localTrackHandles
            .compactMap { ($0 as? RTCPeerConnectionWrapper.TrackHandle)?.track as? RTCVideoTrack }
            .first
    }

    private var remoteVideoTrack: RTCVideoTrack? {
        (remoteMediaSlot.trackHandle as? RTCPeerConnectionWrapper.TrackHandle)?.track as? RTCVideoTrack
    }
}

/// Wraps RTCMTLVideoView for SwiftUI and attaches the given track as a
/// renderer. Renders nothing until a track with live frames is attached on
/// a real device (Task 12) — the simulator build only needs this to compile.
///
/// The remote track's identity changes once the session populates it (it
/// starts nil, then becomes the peer's track), so the Coordinator remembers
/// the previously-attached track and detaches it before attaching the new
/// one — otherwise the old track keeps rendering into this view too (leak +
/// double-render).
private struct RTCVideoRepresentable: UIViewRepresentable {
    let track: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        guard context.coordinator.attachedTrack !== track else { return }
        context.coordinator.attachedTrack?.remove(uiView)
        track?.add(uiView)
        context.coordinator.attachedTrack = track
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }
}

#Preview {
    VideoCallView(
        capture: WebRTCMediaCapture(),
        videoEnabled: true,
        audioEnabled: true,
        onToggleVideo: {},
        onToggleAudio: {}
    )
    .frame(height: 300)
    .dsTheme(.dark)
}
