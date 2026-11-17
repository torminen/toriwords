import Foundation
import Observation
import SwiftUI
import ToriCore
import ToriStore
import ToriUI

/// Delete with Undo (§5.7): the words are hidden at once, and the tombstones are written only when the toast goes away,
/// when another delete starts, or when the app goes to the background. A crash inside the window keeps the words.
@MainActor @Observable
final class PendingDeletion {
    struct Item: Equatable {
        var ids: [ToriID]
        var message: LocalizedStringResource

        static func == (a: Item, b: Item) -> Bool { a.ids == b.ids }
    }

    static let window: Duration = .seconds(4)

    private(set) var current: Item?
    var hidden: Set<ToriID> { Set(current?.ids ?? []) }
    @ObservationIgnored var store: ToriStore?
    @ObservationIgnored var didDelete: () -> Void = {}
    @ObservationIgnored private var timer: Task<Void, Never>?

    func schedule(_ ids: [ToriID], word: String) {
        schedule(ids, message: "“\(word)” deleted")
    }

    func schedule(_ ids: [ToriID], message: LocalizedStringResource) {
        commit()
        current = Item(ids: ids, message: message)
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.window)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    func undo() {
        timer?.cancel()
        current = nil
    }

    func commit() {
        timer?.cancel()
        guard let item = current else { return }
        current = nil
        try? store?.deleteEntries(item.ids)
        didDelete()
    }
}

/// The "'thorough' deleted · Undo" toast, shown over every screen of the stack.
struct UndoToast: View {
    @Environment(PendingDeletion.self) private var deletion

    var body: some View {
        if let item = deletion.current {
            HStack(spacing: Spacing.m) {
                Text(item.message).font(Typography.body).foregroundStyle(.white).lineLimit(2)
                Spacer()
                Button("Undo") { withAnimation { deletion.undo() } }
                    .font(Typography.body.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous))
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.s)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Undo")) { deletion.undo() }
        }
    }
}
