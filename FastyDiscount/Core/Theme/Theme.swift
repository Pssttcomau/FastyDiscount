import SwiftUI

enum Theme {
    enum Colors {
        static let primary = Color.accentColor
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
    }

    enum Typography {
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let headline = Font.headline
        static let body = Font.body
        static let caption = Font.caption
    }
}
