import SwiftUI

/// A view that displays preview metadata for a pull request
///
/// Shows change statistics (additions, deletions, changed files) when available.
/// Displays "—" for unavailable data to distinguish from zero values.
struct PreviewMetadataView: View {
    /// The preview metadata to display, or nil if not yet loaded
    let previewMetadata: PRPreviewMetadata?

    var body: some View {
        HStack(spacing: 8) {
            // Changed files
            metadataItem(
                value: previewMetadata?.changedFiles,
                label: "files",
                accessibilityLabel: filesAccessibilityLabel
            )

            // Additions
            metadataItem(
                value: previewMetadata?.additions,
                label: "+",
                color: .green,
                accessibilityLabel: additionsAccessibilityLabel
            )

            // Deletions
            metadataItem(
                value: previewMetadata?.deletions,
                label: "−",
                color: .red,
                accessibilityLabel: deletionsAccessibilityLabel
            )
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    /// Creates a metadata item view
    ///
    /// - Parameters:
    ///   - value: The numeric value to display, or nil if unavailable
    ///   - label: The label text (e.g., "files", "+", "−")
    ///   - color: Optional color for the value
    ///   - accessibilityLabel: Accessibility label for VoiceOver
    /// - Returns: A view displaying the metadata item
    @ViewBuilder
    private func metadataItem(
        value: Int?,
        label: String,
        color: Color? = nil,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 2) {
            if let value = value {
                Text("\(value)")
                    .foregroundStyle(color ?? .primary)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Accessibility Labels

    private var filesAccessibilityLabel: String {
        guard let changedFiles = previewMetadata?.changedFiles else {
            return "Files changed: unavailable"
        }

        let fileWord = changedFiles == 1 ? "file" : "files"
        return "\(changedFiles) \(fileWord) changed"
    }

    private var additionsAccessibilityLabel: String {
        guard let additions = previewMetadata?.additions else {
            return "Lines added: unavailable"
        }

        let lineWord = additions == 1 ? "line" : "lines"
        return "\(additions) \(lineWord) added"
    }

    private var deletionsAccessibilityLabel: String {
        guard let deletions = previewMetadata?.deletions else {
            return "Lines deleted: unavailable"
        }

        let lineWord = deletions == 1 ? "line" : "lines"
        return "\(deletions) \(lineWord) deleted"
    }
}

// MARK: - Previews

#Preview("With Metadata") {
    PreviewMetadataView(
        previewMetadata: PRPreviewMetadata(
            additions: 145,
            deletions: 23,
            changedFiles: 7,
            requestedReviewers: []
        )
    )
    .padding()
}

#Preview("Zero Values") {
    PreviewMetadataView(
        previewMetadata: PRPreviewMetadata(
            additions: 0,
            deletions: 0,
            changedFiles: 1,
            requestedReviewers: []
        )
    )
    .padding()
}

#Preview("Unavailable Data") {
    PreviewMetadataView(previewMetadata: nil)
        .padding()
}
