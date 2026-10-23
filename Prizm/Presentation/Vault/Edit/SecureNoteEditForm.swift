import SwiftUI

// MARK: - SecureNoteEditForm

/// Edit form for Secure Note vault items.
///
/// A multiline note editor that grows with the sheet, followed by custom fields.
struct SecureNoteEditForm: View {

    @Binding var draft: DraftSecureNoteContent

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSectionCard(String(localized: "Note")) {
                        TextEditor(text: Binding(
                            get: { draft.notes ?? "" },
                            set: { draft.notes = $0.isEmpty ? nil : $0 }
                        ))
                        .font(Typography.fieldValue)
                        .scrollContentBackground(.hidden)
                        .frame(height: max(EditorLayout.minimumNoteHeight, geometry.size.height * 0.7))
                        .padding(.vertical, Spacing.rowVertical)
                        .padding(.horizontal, Spacing.rowHorizontal)
                        .accessibilityLabel("Note")
                        .accessibilityIdentifier(AccessibilityID.Edit.secureNoteBody)
                    }

                    CustomFieldsEditSection(fields: $draft.customFields)
                }
            }
        }
    }
}
