/// CheckInDetailsView.swift — §16.25.2
///
/// Step 2: Customer notes, internal notes, passcode, photos.
/// Spec: mockup frame "CI-2 · Details · customer notes · internal notes · passcode · photos".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

struct CheckInDetailsView: View {
    @Bindable var draft: CheckInDraft
    @State private var showPasscode: Bool = false
    @FocusState private var diagFocused: Bool
    @FocusState private var internalFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // 1. Diagnostic notes (customer-facing)
                diagnosticNotesSection

                Divider().padding(.horizontal, BrandSpacing.base)

                // 2. Internal notes (tech-only)
                internalNotesSection

                Divider().padding(.horizontal, BrandSpacing.base)

                // 3. Passcode
                passcodeSection

                Divider().padding(.horizontal, BrandSpacing.base)

                // 4. Photos placeholder
                photosSection
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.bottom, BrandSpacing.xl)
        }
    }

    // MARK: - Diagnostic notes

    private var diagnosticNotesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Customer description", systemImage: "text.bubble.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)

            TextEditor(text: $draft.diagnosticNotes)
                .focused($diagFocused)
                .frame(minHeight: 72)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.bizarreOrange.opacity(diagFocused ? 0.6 : 0.25), lineWidth: 1)
                )
                .accessibilityLabel("Diagnostic notes — shown to customer")

            HStack {
                Spacer()
                Text("\(draft.diagnosticNotes.count) / 2000")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Internal notes

    private var internalNotesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Internal notes", systemImage: "lock.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Text("Tech only — never shown to customer")
                .font(.system(size: 11))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            TextEditor(text: $draft.internalNotes)
                .focused($internalFocused)
                .frame(minHeight: 60)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.bizarreWarning.opacity(0.5), lineWidth: 1)
                )
                .accessibilityLabel("Internal note — tech only, not shown to customer")

            HStack {
                Spacer()
                Text("\(draft.internalNotes.count) / 5000")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Passcode

    private var passcodeSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Device passcode", systemImage: "lock.rectangle.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Text("Stored encrypted — auto-deleted when ticket closes")
                .font(.system(size: 11))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            // Type picker chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(CheckInDraft.PasscodeType.allCases, id: \.self) { type in
                        Button {
                            BrandHaptics.tap()
                            withAnimation(.easeOut(duration: 0.15)) {
                                draft.passcodeType = type
                            }
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(draft.passcodeType == type ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(draft.passcodeType == type ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if draft.passcodeType != .none {
                HStack {
                    if showPasscode {
                        TextField("Enter passcode", text: $draft.passcode)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("Device passcode — stored encrypted, deleted when ticket closes")
                    } else {
                        SecureField("Enter passcode", text: $draft.passcode)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityLabel("Device passcode — stored encrypted, deleted when ticket closes")
                    }
                    Button {
                        showPasscode.toggle()
                        if showPasscode {
                            Task {
                                try? await Task.sleep(for: .seconds(5))
                                showPasscode = false
                            }
                        }
                    } label: {
                        Image(systemName: showPasscode ? "eye.slash" : "eye")
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPasscode ? "Hide passcode" : "Show passcode temporarily")
                }
                .padding(.horizontal, BrandSpacing.md)
                .frame(height: 44)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onAppear { BrandHaptics.success() }
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Photos (placeholder — CameraCaptureView from Agent 2)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Photos", systemImage: "camera.fill")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Text("Up to 10 photos")
                .font(.system(size: 11))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            // Photo strip placeholder (CameraCaptureView integration deferred to Agent 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    // Existing photo stubs
                    ForEach(draft.photoPaths, id: \.self) { path in
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(Color.bizarreSurface2)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            )
                    }

                    // Add photo button
                    if draft.photoPaths.count < 10 {
                        Button {
                            // CameraCaptureView integration — Agent 2 wires this
                        } label: {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(Color.bizarreOutline.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: "plus")
                                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add photo")
                    }
                }
            }
            .accessibilityLabel("\(draft.photoPaths.count) photos, tap plus to add")
        }
        .padding(.horizontal, BrandSpacing.base)
    }
}

#endif
