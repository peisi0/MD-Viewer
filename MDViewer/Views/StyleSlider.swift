import SwiftUI

/// A slider that keeps its live value local and only commits to the bound
/// preference when the drag pauses or ends.
///
/// `@AppStorage` was previously bound directly to `Slider`, so every pixel of
/// a drag re-rendered all three tabs and rebuilt every AttributedString in the
/// document. This version reflows the document at most a handful of times.
struct StyleSlider<Leading: View, Trailing: View>: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var local: Double
    @State private var editing = false
    @State private var pending: Task<Void, Never>?

    init(title: String,
         value: Binding<Double>,
         range: ClosedRange<Double>,
         step: Double = 1,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.leading = leading
        self.trailing = trailing
        self._local = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) · \(Int(local)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                leading()
                Slider(value: $local, in: range, step: step, onEditingChanged: { isEditing in
                    editing = isEditing
                    if isEditing { scheduleCommit() }
                    else { commitNow() }
                })
                trailing()
            }
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
