import SwiftUI

/// Uses bundled card network logos so displaying a card never requires a network request.
struct VaultItemIcon: View {
    let item: VaultItem
    let loader: FaviconLoader
    var size: CGFloat = 16

    var body: some View {
        Group {
            if case .card(let card) = item.content, let brand = CardBrand(card.brand) {
                Image(brand.assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                FaviconView(domain: primaryDomain, itemType: itemType, loader: loader, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var primaryDomain: String? {
        guard case .login(let login) = item.content, let first = login.uris.first else { return nil }
        return URL(string: first.uri)?.host
    }

    private var itemType: ItemType {
        switch item.content {
        case .login: .login
        case .card: .card
        case .identity: .identity
        case .secureNote: .secureNote
        case .sshKey: .sshKey
        }
    }
}

/// Brand is free-form in the editor; normalize common spellings without changing vault data.
nonisolated enum CardBrand: String {
    case visa
    case mastercard
    case americanExpress = "american-express"
    case discover
    case dinersClub = "diners"
    case jcb
    case maestro
    case unionPay = "unionpay"
    case ruPay = "rupay"

    init?(_ brand: String?) {
        guard let brand else { return nil }
        let normalized = brand.lowercased().filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "visa": self = .visa
        case "mastercard": self = .mastercard
        case "amex", "americanexpress": self = .americanExpress
        case "discover": self = .discover
        case "diners", "dinersclub": self = .dinersClub
        case "jcb": self = .jcb
        case "maestro": self = .maestro
        case "unionpay", "银联", "銀聯", "chinaunionpay": self = .unionPay
        case "rupay": self = .ruPay
        default: return nil
        }
    }

    var assetName: String { "CardBrand-\(rawValue)" }
}
