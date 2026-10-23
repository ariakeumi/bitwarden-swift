import SwiftUI

// MARK: - IdentityDetailView

/// Detail view for Identity items (FR-030, FR-046).
///
/// The 17+ identity fields are grouped into six labelled card sections to reduce
/// cognitive load: Personal Info, ID Numbers, Contact, Address, Notes, Custom Fields.
/// Each section is hidden entirely when all of its fields are nil/empty.
struct IdentityDetailView: View {

    let item:     VaultItem
    let identity: IdentityContent
    let onCopy:   (String) -> Void

    // MARK: - Section presence helpers

    private var hasPersonalInfo: Bool {
        identity.title != nil || identity.firstName != nil ||
        identity.middleName != nil || identity.lastName != nil || identity.company != nil
    }

    private var hasIDNumbers: Bool {
        identity.ssn != nil || identity.passportNumber != nil || identity.licenseNumber != nil
    }

    private var hasContact: Bool {
        identity.email != nil || identity.phone != nil || identity.username != nil
    }

    private var hasAddress: Bool {
        identity.address1 != nil || identity.address2 != nil || identity.address3 != nil ||
        identity.city != nil || identity.state != nil ||
        identity.postalCode != nil || identity.country != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

                if hasPersonalInfo {
                    DetailSectionCard(String(localized: "Personal Info")) {
                        fieldRows([
                            (String(localized: "Title"),       identity.title),
                            (String(localized: "First Name"),  identity.firstName),
                            (String(localized: "Middle Name"), identity.middleName),
                            (String(localized: "Last Name"),   identity.lastName),
                            (String(localized: "Company"),     identity.company),
                        ])
                    }
                }

                if hasIDNumbers {
                    DetailSectionCard(String(localized: "ID Numbers")) {
                        fieldRows([
                            (String(localized: "SSN"),             identity.ssn),
                            (String(localized: "Passport Number"), identity.passportNumber),
                            (String(localized: "License Number"),  identity.licenseNumber),
                        ])
                    }
                }

                if hasContact {
                    DetailSectionCard(String(localized: "Contact")) {
                        fieldRows([
                            (String(localized: "Email"),    identity.email),
                            (String(localized: "Phone"),    identity.phone),
                            (String(localized: "Username"), identity.username),
                        ])
                    }
                }

                if hasAddress {
                    DetailSectionCard(String(localized: "Address")) {
                        fieldRows([
                            (String(localized: "Address 1"),    identity.address1),
                            (String(localized: "Address 2"),    identity.address2),
                            (String(localized: "Address 3"),    identity.address3),
                            (String(localized: "City"),         identity.city),
                            (String(localized: "State"),        identity.state),
                            (String(localized: "Postal Code"),  identity.postalCode),
                            (String(localized: "Country"),      identity.country),
                        ])
                    }
                }

                if let notes = identity.notes, !notes.isEmpty {
                    DetailSectionCard(String(localized: "Notes")) {
                        FieldRowView(label: "", value: notes, itemId: item.id, isMultiLine: true, onCopy: onCopy)
                    }
                }

                if !identity.customFields.isEmpty {
                    DetailSectionCard(String(localized: "Custom Fields")) {
                        CustomFieldsSection(fields: identity.customFields, itemId: item.id, onCopy: onCopy)
                    }
                }
            }
    }

    // MARK: - Private helpers

    /// Renders a sequence of optional field rows with dividers between present fields.
    @ViewBuilder
    private func fieldRows(_ pairs: [(String, String?)]) -> some View {
        // Filter to only present values first so dividers are placed correctly.
        let present = pairs.filter { $0.1 != nil }
        ForEach(present.indices, id: \.self) { index in
            let (label, value) = present[index]
            if index > 0 { Divider() }
            FieldRowView(label: label, value: value!, itemId: item.id, onCopy: onCopy)
        }
    }
}
