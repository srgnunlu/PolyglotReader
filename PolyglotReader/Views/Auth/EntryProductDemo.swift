import SwiftUI

/// Interactive, network-free product story shown before authentication.
struct EntryProductDemo: View {
    let phase: EntryDemoPhase
    let reduceMotion: Bool
    let onSelect: (EntryDemoPhase) -> Void

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            ZStack {
                switch phase {
                case .library:
                    EntryLibraryScene { onSelect(.reader) }
                        .transition(sceneTransition)
                case .reader:
                    EntryReaderScene { onSelect(.translation) }
                        .transition(sceneTransition)
                case .translation:
                    EntryTranslationScene(reduceMotion: reduceMotion) {
                        onSelect(.annotation)
                    }
                    .transition(sceneTransition)
                case .annotation:
                    EntryAnnotationScene()
                        .transition(sceneTransition)
                }
            }
            .id(phase)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DSSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                            .stroke(DSColor.brandInk.opacity(0.08), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .dsShadow(.floating)

            VStack(spacing: DSSpacing.xxs) {
                Text(phase.titleKey.localized)
                    .font(DSFont.cardTitle)
                    .foregroundStyle(DSColor.brandInk)
                    .contentTransition(.opacity)

                Text(phase.subtitleKey.localized)
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            .id("copy-\(phase.rawValue)")
            .transition(.opacity)
        }
        .dsAnimation(DSMotion.smooth, value: phase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "entry.demo.accessibility".localized(
                with: phase.rawValue + 1,
                EntryDemoPhase.allCases.count
            )
        )
    }

    private var sceneTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }
}

/// Direct stage navigation doubles as a concise feature map.
struct EntryDemoSelector: View {
    let selectedPhase: EntryDemoPhase
    let onSelect: (EntryDemoPhase) -> Void

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(EntryDemoPhase.allCases) { phase in
                Button {
                    onSelect(phase)
                } label: {
                    VStack(spacing: DSSpacing.xxs) {
                        Image(systemName: phase.icon)
                            .font(DSFont.controlIcon)
                            .frame(width: 28, height: 24)

                        Capsule()
                            .fill(selectedPhase == phase ? DSColor.brand : Color.secondary.opacity(0.2))
                            .frame(width: selectedPhase == phase ? 24 : 8, height: 4)
                    }
                    .foregroundStyle(selectedPhase == phase ? DSColor.brand : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(phase.titleKey.localized)
                .accessibilityAddTraits(selectedPhase == phase ? .isSelected : [])
            }
        }
    }
}

private extension EntryDemoPhase {
    var icon: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .reader: return "doc.richtext.fill"
        case .translation: return "character.bubble.fill"
        case .annotation: return "highlighter"
        }
    }

    var titleKey: String {
        switch self {
        case .library: return "entry.demo.library.title"
        case .reader: return "entry.demo.reader.title"
        case .translation: return "entry.demo.translation.title"
        case .annotation: return "entry.demo.annotation.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .library: return "entry.demo.library.subtitle"
        case .reader: return "entry.demo.reader.subtitle"
        case .translation: return "entry.demo.translation.subtitle"
        case .annotation: return "entry.demo.annotation.subtitle"
        }
    }
}

// MARK: - Library

private struct EntryLibraryScene: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            EntryWindowBar(
                title: "entry.scene.library".localized,
                systemImage: "books.vertical.fill",
                trailingSystemImage: "plus"
            )

            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                DemoBookCard(
                    titleKey: "entry.scene.book.one",
                    accent: DSColor.brandSecondary,
                    height: 150,
                    action: onOpen
                )

                DemoBookCard(
                    titleKey: "entry.scene.book.two",
                    accent: DSColor.brand,
                    height: 178,
                    isFeatured: true,
                    action: onOpen
                )

                DemoBookCard(
                    titleKey: "entry.scene.book.three",
                    accent: DSColor.aiAccent,
                    height: 136,
                    action: onOpen
                )
            }

            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "hand.tap.fill")
                Text("entry.scene.open_hint".localized)
            }
            .font(DSFont.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct DemoBookCard: View {
    let titleKey: String
    let accent: Color
    let height: CGFloat
    var isFeatured = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(accent)
                            Capsule()
                                .fill(accent.opacity(0.35))
                                .frame(maxWidth: 54, minHeight: 4, maxHeight: 4)
                        }
                        .padding(DSSpacing.xs)
                    }
                    .frame(height: height * 0.58)

                Text(titleKey.localized)
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(DSColor.brandInk)
                    .lineLimit(2)

                Text("PDF")
                    .font(DSFont.meta.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        if isFeatured {
                            RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                                .stroke(DSColor.brand.opacity(0.55), lineWidth: 2)
                        }
                    }
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityHint("entry.scene.open_hint".localized)
    }
}

// MARK: - Reader

private struct EntryReaderScene: View {
    let onSelectionComplete: () -> Void
    @State private var selectionProgress: CGFloat = 0.34

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            EntryWindowBar(
                title: "entry.scene.reader".localized,
                systemImage: "chevron.left",
                trailingSystemImage: "text.magnifyingglass"
            )

            DemoPaper {
                VStack(alignment: .leading, spacing: 10) {
                    Text("entry.scene.paper.title".localized)
                        .font(DSFont.cardTitle)
                        .foregroundStyle(DSColor.brandInk)

                    DemoTextLine(width: 0.96)
                    DemoTextLine(width: 0.82)

                    Text("entry.scene.sample".localized)
                        .font(DSFont.translation)
                        .foregroundStyle(DSColor.brandInk)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(alignment: .leading) {
                            RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                                .fill(DSColor.brandSecondary.opacity(0.28))
                                .scaleEffect(x: selectionProgress, anchor: .leading)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    selectionProgress = min(max(0.2 + abs(value.translation.width) / 180, 0.2), 1)
                                }
                                .onEnded { _ in
                                    selectionProgress = 1
                                    onSelectionComplete()
                                }
                        )
                        .accessibilityLabel("entry.scene.selection_hint".localized)
                        .accessibilityAddTraits(.isButton)

                    DemoTextLine(width: 0.90)
                    DemoTextLine(width: 0.72)
                }
            }

            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "hand.draw.fill")
                Text("entry.scene.selection_hint".localized)
            }
            .font(DSFont.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Translation

private struct EntryTranslationScene: View {
    let reduceMotion: Bool
    let onContinue: () -> Void
    @State private var phase: TranslationPopupPhase = .loading

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            DemoPaper {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    DemoTextLine(width: 0.84)
                    Text("entry.scene.sample".localized)
                        .font(DSFont.translation)
                        .foregroundStyle(DSColor.brandInk)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(DSColor.brandSecondary.opacity(0.26))
                    DemoTextLine(width: 0.72)
                }
            }
            .frame(maxHeight: 126)

            Button(action: onContinue) {
                VStack(spacing: 0) {
                    TranslationPopupDragHandle()
                    TranslationPopupContentArea(phase: phase, maxHeight: 92)
                }
                .frame(maxWidth: 310)
                .translationPopupSurface()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("entry.scene.translation_result".localized)
            .accessibilityHint("entry.scene.translation_continue".localized)
        }
        .task {
            if reduceMotion {
                phase = .translated("entry.scene.translation".localized)
                return
            }

            phase = .loading
            do {
                try await Task.sleep(nanoseconds: 850_000_000)
            } catch {
                return
            }
            phase = .translated("entry.scene.translation".localized)
        }
    }
}

// MARK: - Annotation

private struct EntryAnnotationScene: View {
    @State private var selectedHighlight = DSColor.Highlight.yellow

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            DemoPaper {
                VStack(alignment: .leading, spacing: 10) {
                    Text("entry.scene.annotation_title".localized)
                        .font(DSFont.cardTitle)
                        .foregroundStyle(DSColor.brandInk)

                    DemoTextLine(width: 0.94)
                    Text("entry.scene.annotation_quote".localized)
                        .font(DSFont.translation)
                        .foregroundStyle(DSColor.brandInk)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(selectedHighlight.color.opacity(0.75))
                    DemoTextLine(width: 0.70)

                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "note.text")
                            .foregroundStyle(DSColor.brand)

                        Text("entry.scene.note".localized)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.brandInk)
                    }
                    .padding(DSSpacing.xs)
                    .background {
                        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                            .fill(DSColor.brand.opacity(0.10))
                    }
                }
            }

            HStack(spacing: DSSpacing.md) {
                ForEach(DSColor.Highlight.allCases, id: \.rawValue) { highlight in
                    Button {
                        selectedHighlight = highlight
                    } label: {
                        Circle()
                            .fill(highlight.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .stroke(
                                        selectedHighlight == highlight ? DSColor.brandInk : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("selection.highlight_with".localized(with: highlight.localizedName))
                    .accessibilityAddTraits(selectedHighlight == highlight ? .isSelected : [])
                }
            }
        }
    }
}

#Preview("Entry Demo") {
    ZStack {
        CorioEntryBackground()
        EntryProductDemo(phase: .translation, reduceMotion: false) { _ in }
            .frame(width: 380, height: 420)
            .padding()
    }
}
