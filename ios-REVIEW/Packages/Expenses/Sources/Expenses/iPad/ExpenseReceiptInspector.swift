import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ExpenseReceiptInspector
//
// Inline receipt image preview with pinch-zoom, rendered in the 3rd column
// of ExpensesThreeColumnView (or as an overlay on compact layouts).
//
// Route grounding:
//   GET  /api/v1/expenses/:id/receipt  → APIClient.getExpenseReceiptStatus(expenseId:)
//   POST /api/v1/expenses/:id/receipt  → APIClient.uploadExpenseReceipt(...) [existing]
//   DELETE /api/v1/expenses/:id/receipt → APIClient.deleteExpenseReceipt(expenseId:)
//   (Receipt image itself is fetched from the file-path URL returned by the above.)
//
// Pinch-zoom implementation uses a MagnifyGesture (iOS 17+) composited with
// a DragGesture for pan-while-zoomed. State is fully local; no ViewModel needed.
//
// Liquid Glass: the overlay toolbar (zoom controls, share) uses .brandGlass.
// The image canvas itself is plain to avoid glass-on-glass.

// MARK: - ViewModel

@MainActor
@Observable
public final class ExpenseReceiptInspectorViewModel {

    public enum State: Sendable {
        case idle
        case loading
        case loaded(receiptURL: URL)
        case noReceipt
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var isDeleting: Bool = false
    public private(set) var deleteError: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let expenseId: Int64

    public init(api: APIClient, expenseId: Int64) {
        self.api = api
        self.expenseId = expenseId
    }

    // MARK: - Load receipt status

    public func load() async {
        state = .loading
        do {
            let status = try await api.getExpenseReceiptStatus(expenseId: expenseId)
            guard let path = status.receiptImagePath, !path.isEmpty else {
                state = .noReceipt
                return
            }
            guard let base = await api.currentBaseURL() else {
                state = .failed("Could not resolve server URL")
                return
            }
            let url = resolveURL(path: path, base: base)
            state = .loaded(receiptURL: url)
        } catch {
            AppLog.ui.error(
                "Receipt status load failed: \(error.localizedDescription, privacy: .public)"
            )
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Delete receipt

    public func deleteReceipt() async {
        guard !isDeleting else { return }
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteExpenseReceipt(expenseId: expenseId)
            state = .noReceipt
        } catch {
            AppLog.ui.error(
                "Receipt delete failed: \(error.localizedDescription, privacy: .public)"
            )
            deleteError = error.localizedDescription
        }
    }

    // MARK: Helpers

    private func resolveURL(path: String, base: URL) -> URL {
        if path.hasPrefix("http") {
            return URL(string: path) ?? base
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(trimmed)
    }
}

// MARK: - ExpenseReceiptInspector View

/// Inline receipt image preview panel with pinch-zoom and a Liquid Glass toolbar.
public struct ExpenseReceiptInspector: View {

    @State private var vm: ExpenseReceiptInspectorViewModel

    // Zoom / pan state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Toolbar state
    @State private var showDeleteConfirm: Bool = false

    /// Called when receipt is deleted (parent can update its own state).
    var onReceiptDeleted: (() -> Void)?

    private static let minScale: CGFloat = 1.0
    private static let maxScale: CGFloat = 6.0

    // MARK: Init

    public init(api: APIClient, expenseId: Int64, onReceiptDeleted: (() -> Void)? = nil) {
        _vm = State(wrappedValue: ExpenseReceiptInspectorViewModel(api: api, expenseId: expenseId))
        self.onReceiptDeleted = onReceiptDeleted
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            stateContent
        }
        .task { await vm.load() }
        .confirmationDialog(
            "Delete Receipt?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Receipt", role: .destructive) {
                Task {
                    await vm.deleteReceipt()
                    if vm.deleteError == nil {
                        onReceiptDeleted?()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The receipt image will be permanently removed from this expense.")
        }
        .alert("Delete failed", isPresented: Binding(
            get: { vm.deleteError != nil },
            set: { _ in }
        )) {
            Button("OK") { }
        } message: {
            Text(vm.deleteError ?? "")
        }
    }

    // MARK: - State rendering

    @ViewBuilder
    private var stateContent: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading receipt")

        case .noReceipt:
            noReceiptView

        case .failed(let msg):
            errorView(msg)

        case .loaded(let url):
            inspectorCanvas(url: url)
        }
    }

    // MARK: - No receipt placeholder

    private var noReceiptView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No receipt attached")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Attach a receipt image from the expense detail view.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No receipt attached")
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "photo.slash")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Couldn't load receipt")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Retry loading receipt")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector canvas (pinch-zoom)

    private func inspectorCanvas(url: URL) -> some View {
        ZStack(alignment: .bottom) {
            // Image canvas
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading receipt image")
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(pinchGesture, dragGesture)
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.5 {
                                    resetZoom()
                                } else {
                                    scale = min(2.5, Self.maxScale)
                                    lastScale = scale
                                }
                            }
                        }
                        .accessibilityLabel("Receipt image. Double-tap to zoom.")
                        .accessibilityAddTraits(.isImage)
                case .failure:
                    VStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "photo.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text("Image failed to load")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Receipt image failed to load")
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Liquid Glass overlay toolbar
            glassToolbar(url: url)
        }
    }

    // MARK: - Pinch gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = lastScale * value.magnification
                scale = min(Self.maxScale, max(Self.minScale, proposed))
            }
            .onEnded { value in
                let final = lastScale * value.magnification
                scale = min(Self.maxScale, max(Self.minScale, final))
                lastScale = scale
                // Clamp offset when zooming out to 1x
                if scale <= Self.minScale {
                    withAnimation(.spring(response: 0.25)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    // MARK: - Drag gesture (pan while zoomed)

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width:  lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - Glass toolbar

    private func glassToolbar(url: URL) -> some View {
        HStack(spacing: BrandSpacing.base) {
            // Zoom out
            Button {
                withAnimation(.spring(response: 0.25)) {
                    scale = max(Self.minScale, scale / 1.5)
                    lastScale = scale
                    if scale <= Self.minScale {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.bizarreOnSurface)
            .disabled(scale <= Self.minScale)
            .accessibilityLabel("Zoom out")
            .keyboardShortcut("-", modifiers: .command)

            // Zoom reset
            Button {
                withAnimation(.spring(response: 0.25)) {
                    resetZoom()
                }
            } label: {
                Text("\(Int(scale * 100))%")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .frame(minWidth: 48)
            }
            .buttonStyle(.plain)
            .disabled(scale == Self.minScale && offset == .zero)
            .accessibilityLabel("Reset zoom to 100%")

            // Zoom in
            Button {
                withAnimation(.spring(response: 0.25)) {
                    scale = min(Self.maxScale, scale * 1.5)
                    lastScale = scale
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.bizarreOnSurface)
            .disabled(scale >= Self.maxScale)
            .accessibilityLabel("Zoom in")
            .keyboardShortcut("+", modifiers: .command)

            Divider()
                .frame(height: 20)

            // Share
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.bizarreOnSurface)
            }
            .accessibilityLabel("Share receipt image")

            // Delete
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: vm.isDeleting ? "clock" : "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.bizarreError)
            }
            .buttonStyle(.plain)
            .disabled(vm.isDeleting)
            .accessibilityLabel("Delete receipt")
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: Capsule())
        .padding(.bottom, BrandSpacing.lg)
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    // MARK: - Helpers

    private func resetZoom() {
        scale = Self.minScale
        lastScale = Self.minScale
        offset = .zero
        lastOffset = .zero
    }
}
