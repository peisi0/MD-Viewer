import SwiftUI
import UIKit

// MARK: - Backdrop
// Liquid Glass needs something colourful behind it to refract. A static mesh
// gradient is enough: MeshGradient already interpolates smoothly, so no blur
// or hue-rotation filter is needed (both would force a full-screen
// re-rasterisation on every frame). The optional drift is opt-in from Settings
// and only animates a compositor-friendly transform.

struct GlassBackdrop: View {
    var intensity: CGFloat = 1

    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.animatedBackdrop) private var animated = false
    @State private var drifting = false

    private let points: [SIMD2<Float>] = [
        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1.0, 0.5),
        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
    ]

    private var palette: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.19, green: 0.13, blue: 0.44),
                Color(red: 0.12, green: 0.32, blue: 0.56),
                Color(red: 0.10, green: 0.16, blue: 0.36),
                Color(red: 0.36, green: 0.16, blue: 0.45),
                Color(red: 0.14, green: 0.28, blue: 0.50),
                Color(red: 0.10, green: 0.44, blue: 0.50),
                Color(red: 0.12, green: 0.16, blue: 0.34),
                Color(red: 0.36, green: 0.20, blue: 0.40),
                Color(red: 0.12, green: 0.34, blue: 0.46)
            ]
        }
        return [
            Color(red: 0.68, green: 0.66, blue: 1.00),
            Color(red: 0.62, green: 0.86, blue: 0.98),
            Color(red: 0.78, green: 0.72, blue: 1.00),
            Color(red: 0.98, green: 0.72, blue: 0.86),
            Color(red: 0.74, green: 0.90, blue: 0.98),
            Color(red: 0.70, green: 0.94, blue: 0.88),
            Color(red: 0.80, green: 0.76, blue: 1.00),
            Color(red: 0.99, green: 0.82, blue: 0.74),
            Color(red: 0.68, green: 0.88, blue: 0.98)
        ]
    }

    var body: some View {
        ZStack {
            (scheme == .dark
             ? Color(red: 0.05, green: 0.06, blue: 0.12)
             : Color(red: 0.965, green: 0.972, blue: 0.995))
                .ignoresSafeArea()

            Rectangle()
                .fill(MeshGradient(width: 3, height: 3, points: points, colors: palette))
                .opacity((scheme == .dark ? 0.62 : 0.52) * intensity)
                .scaleEffect(drifting ? 1.24 : 1.14)
                .offset(x: drifting ? 16 : -16, y: drifting ? -12 : 12)
                .ignoresSafeArea()

            // A radial bloom is much cheaper than a blurred solid circle.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.42, green: 0.46, blue: 1.0).opacity(0.22 * intensity),
                             Color.clear],
                    center: .center, startRadius: 0, endRadius: 140))
                .frame(width: 280, height: 280)
                .offset(x: drifting ? -130 : -90, y: drifting ? -300 : -240)
        }
        .animation(animated ? Animation.easeInOut(duration: 26).repeatForever(autoreverses: true) : nil,
                   value: drifting)
        .onAppear { drifting = animated }
        .onChange(of: animated) { _, on in drifting = on }
        .allowsHitTesting(false)
    }
}

// MARK: - Reusable glass surfaces

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var tint: Color = .clear
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(
                .regular.tint(tint),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

struct GlassChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .clear

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint), in: Capsule())
    }
}

struct GlassToolButton: View {
    let title: String
    let systemImage: String
    var prominent: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - Share sheet (UIKit API)

/// Presents `UIActivityViewController` from a transparent host controller.
/// Wrapping it (instead of returning the activity controller directly as a
/// sheet root) keeps the popover anchor correct on iPad.
final class ShareHostController: UIViewController {
    var onReady: (() -> Void)?
    private var fired = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !fired else { return }
        fired = true
        onReady?()
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> ShareHostController {
        let host = ShareHostController()
        host.view.backgroundColor = .clear
        host.onReady = { [weak host] in
            guard let host else { return }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = host.view
            activity.popoverPresentationController?.sourceRect = CGRect(
                x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1
            )
            activity.completionWithItemsHandler = { _, _, _, _ in
                DispatchQueue.main.async { isPresented = false }
            }
            host.present(activity, animated: true)
        }
        return host
    }

    func updateUIViewController(_ host: ShareHostController, context: Context) {}
}

// MARK: - Small drawn app-icon badge for Settings

struct AppIconBadge: View {
    var size: CGFloat = 92

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(
                    LinearGradient(colors: [
                        Color(red: 0.38, green: 0.30, blue: 0.85),
                        Color(red: 0.22, green: 0.62, blue: 0.86),
                        Color(red: 0.20, green: 0.78, blue: 0.72)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 2)
                .padding(size * 0.07)
            Text("MD")
                .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.20), radius: 5, y: 3)
        }
        .frame(width: size, height: size)
    }
}
