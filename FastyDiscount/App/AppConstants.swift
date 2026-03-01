import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.fastydiscount.shared"
    static let iCloudContainerIdentifier = "iCloud.com.fastydiscount.app"
    static let bundleIdentifier = "com.fastydiscount.app"

    enum DeepLink {
        static let scheme = "fastydiscount"
        static let dvgPath = "dvg"
    }

    enum PassKit {
        /// Pass Type ID registered in Apple Developer portal.
        /// Must match the identifier provisioned in the developer account.
        static let passTypeIdentifier = "pass.com.fastydiscount.dvg"

        /// Apple Developer Team Identifier.
        /// Replace with the actual team ID from the developer account.
        static let teamIdentifier = "XXXXXXXXXX"

        /// Default organization name displayed on passes when no store name is available.
        static let organizationName = "FastyDiscount"
    }
}
