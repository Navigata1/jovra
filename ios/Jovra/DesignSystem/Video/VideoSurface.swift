import AVFoundation
import SwiftUI
import UIKit

/// What a `VideoSurface` shows.
enum VideoSurfaceContent {
    /// Opening: the poster (if any), with a spinner after 300 ms.
    case loading(poster: CGImage?)
    /// Playing or paused. `still` is an exact decoded frame drawn over the player while it catches up.
    case player(AVPlayer, still: CGImage?)
    /// The file is not on this device. Copy belongs to the caller ("The original isn't on this iPhone.").
    case missing(title: String, message: String, action: StateCard.Action?)
    /// The file is here but cannot be played.
    case failed(title: String, message: String)
}

/// The video card every review screen uses: the player (or a poster or the exact still), three overlay slots,
/// pinch zoom with a reset control, and the states a video can be in. A missing original is a `StateCard`,
/// never a crash or a black box.
struct VideoSurface<TopLeading: View, TopTrailing: View, BottomBar: View>: View {
    typealias Content = VideoSurfaceContent

    var content: Content
    @Binding var zoom: VideoZoom
    var aspectRatio: CGFloat = 16 / 9
    @ViewBuilder var topLeading: () -> TopLeading
    @ViewBuilder var topTrailing: () -> TopTrailing
    @ViewBuilder var bottomBar: () -> BottomBar

    @State private var pinchBase: CGFloat?
    @State private var panBase: CGSize?
    @State private var showSpinner = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch content {
        case .missing(let title, let message, let action):
            stateCard(symbol: "video.slash", title: title, message: message, action: action)
        case .failed(let title, let message):
            stateCard(symbol: "exclamationmark.triangle", title: title, message: message, action: nil)
        case .loading, .player:
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest text sizes overlay labels would cover the picture or clip: they sit above it.
                VStack(alignment: .leading, spacing: Space.x1) {
                    topRow
                    surface
                }
            } else {
                surface
            }
        }
    }

    private var surface: some View {
        GeometryReader { proxy in
            ZStack {
                picture
                    .scaleEffect(zoom.scale)
                    .offset(zoom.offset)
                    .gesture(magnify(in: proxy.size))
                    .simultaneousGesture(pan(in: proxy.size), including: zoom.isZoomed ? .all : .subviews)
                    .accessibilityHidden(true)
                overlays
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.surface")
        .task(id: isLoading) {
            showSpinner = false
            guard isLoading else { return }
            try? await Task.sleep(for: .milliseconds(300))
            showSpinner = !Task.isCancelled
        }
    }

    private var isLoading: Bool { if case .loading = content { true } else { false } }

    @ViewBuilder private var picture: some View {
        switch content {
        case .player(let player, let still):
            ZStack {
                PlayerLayerView(player: player)
                if let still { Image(decorative: still, scale: 1).resizable().scaledToFit() }
            }
        case .loading(let poster):
            ZStack {
                if let poster { Image(decorative: poster, scale: 1).resizable().scaledToFit() }
                if showSpinner { ProgressView().tint(.jovra(.textOnEditorial)) }
            }
        case .missing, .failed:
            EmptyView()
        }
    }

    private var overlays: some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                topRow.padding(Space.x2 - Space.half)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.x1) {
                bottomBar()
                if zoom.isZoomed {
                    Button {
                        withAnimation(Motion.standard.animation(reduceMotion: reduceMotion)) { zoom.reset() }
                    } label: {
                        Label { Text("Reset zoom", tableName: "DesignSystem.Video") } icon: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                        }
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.jovra(.textOnEditorial))
                        .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("video.zoom.reset")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.x1)
            .padding(.top, Space.x3)
            .padding(.bottom, Space.half)
            .videoScrim(.bottom)
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            topLeading()
            Spacer(minLength: Space.x1)
            topTrailing()
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? zoom.scale
                pinchBase = base
                zoom.setScale(base * value.magnification, in: size)
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                let base = panBase ?? zoom.offset
                panBase = base
                zoom.pan(to: CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height), in: size)
            }
            .onEnded { _ in panBase = nil }
    }

    /// A dark state card that is at least as tall as the video would be and grows with its text.
    private func stateCard(symbol: String, title: String, message: String, action: StateCard.Action?) -> some View {
        ZStack {
            Color.clear.aspectRatio(aspectRatio, contentMode: .fit)
            StateCard(symbol: symbol, title: title, message: message, primaryAction: action)
                .padding(Space.x1)
        }
        .frame(maxWidth: .infinity)
        .background(Color.jovra(.background), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.state")
    }
}

extension VideoSurface where TopLeading == EmptyView {
    init(content: Content, zoom: Binding<VideoZoom>, aspectRatio: CGFloat = 16 / 9,
         @ViewBuilder topTrailing: @escaping () -> TopTrailing, @ViewBuilder bottomBar: @escaping () -> BottomBar) {
        self.init(content: content, zoom: zoom, aspectRatio: aspectRatio, topLeading: { EmptyView() },
                  topTrailing: topTrailing, bottomBar: bottomBar)
    }
}

/// `AVPlayerLayer` hosted in SwiftUI, aspect-fit on black.
struct PlayerLayerView: UIViewRepresentable {
    var player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
