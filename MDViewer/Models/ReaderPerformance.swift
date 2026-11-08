import Foundation
import SwiftUI
import Observation

// MARK: - Scroll progress (fine-grained observation)

/// Holds scroll progress outside of `ReaderView`'s @State.
///
/// `ReaderView` only passes this object around; it never reads `fraction`
/// inside its own body. With @Observable, a change to `fraction` therefore
/// invalidates only the tiny progress bar, not the whole document.
@MainActor
@Observable
final class ReadingProgress {
    /// 0...1, committed at most ~12 times per second.
    var fraction: Double = 0
    private var lastUpdate: TimeInterval = 0

    func reset() {
        fraction = 0
        lastUpdate = 0
    }

    /// Consumes a progress value derived from `ScrollGeometry`. Quantising and
    /// throttling here keeps the glass toolbar from re-compositing every frame.
    func setFraction(_ value: Double) {
        let v = min(1, max(0, value))
        let delta = abs(v - fraction)
        guard delta > 0.003 else { return }
        // Snap exactly at the ends so "back to top" / "jump to end" are precise.
        if v <= 0.001 || v >= 0.999 {
            fraction = v
            lastUpdate = Date.timeIntervalSinceReferenceDate
            return
        }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastUpdate > 0.08 || delta > 0.08 else { return }
        lastUpdate = now
        fraction = v
    }
}

/// A cheap, self-contained progress indicator. UIKit's `ProgressView`
/// would otherwise sit inside the glass container and force it to re-composite.
struct ReaderProgressBar: View {
    let progress: ReadingProgress
    @Environment(\.readerStyle) private var style

    private let width: CGFloat = 56

    var body: some View {
        let value = progress.fraction
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.15))
            Capsule()
                .fill(style.accentColor)
                .frame(width: max(3, width * value), height: 5)
        }
        .frame(width: width, height: 5)
        // No implicit animation: updates are already quantised to ~12 Hz and
        // a perpetual animation here would keep the compositor busy forever.
        .accessibilityLabel("阅读进度")
        .accessibilityValue("\(Int(value * 100))%")
    }
}

// MARK: - AttributedString cache

/// Building an `AttributedString` walks the whole inline syntax tree. Doing
/// that on every body evaluation was the main source of reader jank.
/// The cache is keyed by document + block + slot + style + highlight, so it
/// stays correct across font-size / theme / search changes.
final class InlineTextCache {
    private let lock = NSLock()
    private var storage: [String: AttributedString] = [:]
    private let limit = 2400

    func attributed(_ key: String, build: () -> AttributedString) -> AttributedString {
        lock.lock()
        defer { lock.unlock() }
        if let hit = storage[key] { return hit }
        let value = build()
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[key] = value
        return value
    }
}
