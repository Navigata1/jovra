import JovraCore
import JovraMedia
import SwiftUI

/// One source tile (Photos, Files, Google Drive). Selection is shown by a filled check, a chartreuse
/// border and the button's selected trait, never by colour alone.
struct ImportSourceTile: View {
    var source: ImportSourceKind
    var isSelected: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    // A compact row at accessibility sizes: the words grow, the decorative glyphs do not.
                    HStack(alignment: .top, spacing: Space.x2) {
                        sourceGlyph
                        words
                        Spacer(minLength: 0)
                        selectionGlyph
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        HStack(alignment: .top) {
                            sourceGlyph
                            Spacer(minLength: Space.x1)
                            selectionGlyph
                        }
                        words
                    }
                }
            }
            .padding(Space.x2)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? HitTarget.minimum : 132, alignment: .topLeading)
            .background(Color.jovra(isSelected ? .positiveFill : .surface),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.jovra(.accentInk) : Color.jovra(.separator), lineWidth: isSelected ? 2 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.title)
        .accessibilityHint(source.subtitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("import.source.\(source.rawValue)")
    }

    private var sourceGlyph: some View {
        Image(systemName: source.symbol)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(.jovra(.textPrimary))
            .frame(width: 32, height: 32, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var selectionGlyph: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.jovra(.onAccent) : Color.jovra(.textSecondary),
                             isSelected ? Color.jovra(.accent) : Color.clear)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(source.title)
                .font(.jovraLabel.weight(.semibold))
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Text(source.subtitle)
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The Google Drive tile's content. Other Drive videos import through Files (story 105); the archive
/// restore slot below is filled by the restore ticket (T54).
struct DriveTileExplanation: View {
    var chooseFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            InfoCard(symbol: "folder",
                     title: String(localized: "Other Drive videos import through Files", table: "Sessions.Import"),
                     message: String(localized: "Choose Files, then Google Drive in the Files sidebar. JOVRA copies the video onto this iPhone.", table: "Sessions.Import"))
            Button(String(localized: "Choose from Files", table: "Sessions.Import"), action: chooseFiles)
                .buttonStyle(.jovraPrimary)
                .accessibilityIdentifier("import.drive.files")
            DriveTileArchiveSlot()
        }
    }
}

/// Named slot for restoring sessions from the player's own JOVRA Drive archive. T54 replaces this view's body;
/// until then it says plainly that restore is not available on this build.
struct DriveTileArchiveSlot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Label {
                Text("Restore from your JOVRA archive", tableName: "Sessions.Import")
                    .font(.jovraLabel.weight(.semibold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "archivebox").foregroundStyle(.jovra(.textPrimary))
            }
            Text("Restoring sessions backed up to your own Google Drive is not available yet. Nothing on this screen uploads your video.", tableName: "Sessions.Import")
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            StatusPill(text: String(localized: "Not available yet", table: "Sessions.Import"), tone: .neutral, symbol: "clock")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jovraCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.drive.archiveSlot")
    }
}

/// One file's result: a status glyph (shape and words carry the meaning), the file name, what happened,
/// and the actions that row allows.
struct ImportResultRow: View {
    var row: ImportModel.Row
    var viewSession: (SessionID) -> Void
    var rotate: () -> Void
    var openExisting: () -> Void
    var importAnyway: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the glyph sits above the words, so the words keep the full width.
        let summary = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x1))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.x2))
        VStack(alignment: .leading, spacing: Space.x2) {
            summary {
                // Decorative, inside a fixed 32 pt box: a fixed size at every text size (the words carry the status).
                glyph
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(row.name)
                        .font(.jovraLabel.weight(.semibold))
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ImportRowCopy.title(for: row.status))
                        .font(.jovraBody.weight(.medium))
                        .foregroundStyle(.jovra(isProblem ? .attentionInk : .textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ImportRowCopy.detail(for: row.status))
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if case .saved(let video) = row.status, let turned = ImportRowCopy.rotationText(quarterTurns: video.manualQuarterTurns) {
                        Text(turned)
                            .font(.jovraCaption)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("import.row.summary")
            actions
        }
        .padding(.vertical, Space.x1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.row")
    }

    @ViewBuilder private var actions: some View {
        switch row.status {
        case .saved(let video):
            actionStack { viewButton(video.session); rotateButton }
        case .openedExisting(let session):
            viewButton(session)
        case .duplicate:
            actionStack { openButton; anywayButton }
        default:
            EmptyView()
        }
    }

    /// Side by side at standard sizes, stacked at accessibility sizes so labels never clip.
    @ViewBuilder private func actionStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.x1) { content() }
        } else {
            HStack(spacing: Space.x1) { content() }
        }
    }

    private func viewButton(_ session: SessionID) -> some View {
        Button(String(localized: "View session", table: "Sessions.Import")) { viewSession(session) }
            .buttonStyle(JovraButtonStyle(kind: .primary, size: .compact))
            .accessibilityIdentifier("import.row.view")
    }

    private var rotateButton: some View {
        Button(String(localized: "Rotate 90°", table: "Sessions.Import"), action: rotate)
        .buttonStyle(.jovraCompact)
        .accessibilityHint(String(localized: "Saves a 90° clockwise turn with this session. The video still plays as recorded.", table: "Sessions.Import"))
        .accessibilityIdentifier("import.row.rotate")
    }

    private var openButton: some View {
        Button(String(localized: "Open existing", table: "Sessions.Import"), action: openExisting)
            .buttonStyle(JovraButtonStyle(kind: .primary, size: .compact))
            .accessibilityIdentifier("import.row.openExisting")
    }

    private var anywayButton: some View {
        Button(String(localized: "Import anyway", table: "Sessions.Import"), action: importAnyway)
            .buttonStyle(.jovraCompact)
            .accessibilityIdentifier("import.row.importAnyway")
    }

    private var isProblem: Bool {
        switch row.status {
        case .unsupported, .failed, .actionFailed: true
        default: false
        }
    }

    @ViewBuilder private var glyph: some View {
        switch row.status {
        case .receiving, .copying, .working:
            ProgressView().controlSize(.regular)
        case .queued:
            Image(systemName: "circle.dotted").font(.system(size: 24, weight: .regular)).foregroundStyle(.jovra(.textSecondary))
        case .waitingForDownload:
            Image(systemName: "icloud.and.arrow.down").font(.system(size: 24, weight: .regular)).foregroundStyle(.jovra(.textPrimary))
        case .saved, .openedExisting:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.jovra(.onAccent), Color.jovra(.accent))
        case .duplicate:
            Image(systemName: "doc.on.doc").font(.system(size: 24, weight: .regular)).foregroundStyle(.jovra(.textPrimary))
        case .unsupported, .failed, .actionFailed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 24, weight: .regular)).foregroundStyle(.jovra(.attentionInk))
        case .cancelled:
            Image(systemName: "xmark.circle").font(.system(size: 24, weight: .regular)).foregroundStyle(.jovra(.textSecondary))
        }
    }
}
