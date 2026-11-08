import SwiftUI

/// A typography control with a labelled tick scale.
///
/// Tapping a tick (or the −/+ buttons) commits a single value change, so the
/// user never has to drag: every drag frame used to reflow the whole document.
/// The slider is still there for fine adjustment, but its value stays local
/// and is committed only after a short pause or on release.
struct StyleSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double

    @Environment(\.readerStyle) private var style
    @State private var local: Double
    @State private var editing = false
    @State private var pending: Task<Void, Never>?

    init(title: String,
         value: Binding<Double>,
         range: ClosedRange<Double>,
         step: Double = 1) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self._local = State(initialValue: value.wrappedValue)
    }

    private var ticks: [Double] {
        let span = range.upperBound - range.lowerBound
        return (0...5).map { index in
            (range.lowerBound + (span * Double(index) / 5).rounded()).clamped(to: range)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(title) · \(Int(local)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                stepButton(systemImage: "minus") { nudge(-step) }
                stepButton(systemImage: "plus") { nudge(step) }
            }

            Slider(value: $local, in: range, step: step, onEditingChanged: { isEditing in
                editing = isEditing
                if isEditing { scheduleCommit() }
                else { commitNow() }
            })
            .tint(style.accentColor)

            tickScale
        }
        .onChange(of: local) { _, _ in
            guard editing else { return }
            scheduleCommit()
        }
        .onChange(of: value) { _, newValue in
            if !editing, local != newValue { local = newValue }
        }
        .onDisappear { pending?.cancel() }
    }

    // MARK: - Parts

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "minus" ? "减小\(title)" : "增大\(title)")
    }

    /// Six evenly-spaced, tappable major ticks. Positions mirror the Slider's
    /// 14 pt thumb inset so the labels line up with the track.
    private var tickScale: some View {
        GeometryReader { geo in
            let inset: CGFloat = 14
            let track = max(1, geo.size.width - inset * 2)
            let span = range.upperBound - range.lowerBound
            ForEach(ticks, id: \.self) { tick in
                let fraction = (tick - range.lowerBound) / span
                let x = inset + CGFloat(fraction) * track
                let selected = abs(local - tick) < 0.5
                Button { select(tick) } label: {
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(selected ? style.accentColor : Color.primary.opacity(0.30))
                            .frame(width: 2, height: selected ? 9 : 6)
                        Text("\(Int(tick))")
                            .font(.system(size: 10, weight: selected ? .semibold : .regular,
                                          design: .monospaced))
                            .foregroundStyle(selected ? style.accentColor : Color.secondary)
                    }
                    .frame(width: 32, height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: x, y: 13)
                .accessibilityLabel("\(title) \(Int(tick)) pt")
            }
        }
        .frame(height: 26)
    }

    // MARK: - Value changes

    private func select(_ tick: Double) {
        pending?.cancel()
        pending = nil
        local = tick
        if value != tick { value = tick }
    }

    private func nudge(_ delta: Double) {
        select((local + delta).rounded().clamped(to: range))
    }

    private func scheduleCommit() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            if value != local { value = local }
        }
    }

    private func commitNow() {
        pending?.cancel()
        pending = nil
        if value != local { value = local }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
