import SwiftUI

enum Destination: Hashable {
    case dashboard
    case nearby
    case scan
    case history
    case settings
    case dvgDetail(id: String)
    case dvgForm
    case emailImport
    case onboarding
    case search
}
