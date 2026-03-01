import Testing
import Foundation
@testable import FastyDiscount

// MARK: - DVGModelTests

@Suite("DVG Model Tests")
struct DVGModelTests {

    // MARK: - Type-Safe Computed Properties

    @Test("test_dvgTypeEnum_getAndSet")
    func test_dvgTypeEnum_getAndSet() {
        let dvg = DVG.testFixture(dvgType: .giftCard)
        #expect(dvg.dvgTypeEnum == .giftCard)

        dvg.dvgTypeEnum = .voucher
        #expect(dvg.dvgTypeEnum == .voucher)
        #expect(dvg.dvgType == "voucher")
    }

    @Test("test_statusEnum_getAndSet")
    func test_statusEnum_getAndSet() {
        let dvg = DVG.testFixture(status: .active)
        #expect(dvg.statusEnum == .active)

        dvg.statusEnum = .used
        #expect(dvg.statusEnum == .used)
        #expect(dvg.status == "used")
    }

    @Test("test_sourceEnum_getAndSet")
    func test_sourceEnum_getAndSet() {
        let dvg = DVG.testFixture(source: .email)
        #expect(dvg.sourceEnum == .email)

        dvg.sourceEnum = .scan
        #expect(dvg.sourceEnum == .scan)
    }

    @Test("test_barcodeTypeEnum_getAndSet")
    func test_barcodeTypeEnum_getAndSet() {
        let dvg = DVG.testFixture()
        dvg.barcodeTypeEnum = .qr
        #expect(dvg.barcodeTypeEnum == .qr)
        #expect(dvg.barcodeType == "qr")
    }

    // MARK: - isExpired

    @Test("test_isExpired_pastDate_returnsTrue")
    func test_isExpired_pastDate_returnsTrue() {
        let dvg = DVG.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        #expect(dvg.isExpired == true)
    }

    @Test("test_isExpired_futureDate_returnsFalse")
    func test_isExpired_futureDate_returnsFalse() {
        let dvg = DVG.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        #expect(dvg.isExpired == false)
    }

    @Test("test_isExpired_nilDate_returnsFalse")
    func test_isExpired_nilDate_returnsFalse() {
        let dvg = DVG.testFixture(expirationDate: nil)
        #expect(dvg.isExpired == false)
    }

    // MARK: - daysUntilExpiry

    @Test("test_daysUntilExpiry_nilDate_returnsNil")
    func test_daysUntilExpiry_nilDate_returnsNil() {
        let dvg = DVG.testFixture(expirationDate: nil)
        #expect(dvg.daysUntilExpiry == nil)
    }

    @Test("test_daysUntilExpiry_futureDate_returnsPositive")
    func test_daysUntilExpiry_futureDate_returnsPositive() {
        let dvg = DVG.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )
        let days = dvg.daysUntilExpiry
        #expect(days != nil)
        #expect(days! >= 9 && days! <= 10)
    }

    @Test("test_daysUntilExpiry_pastDate_returnsNegative")
    func test_daysUntilExpiry_pastDate_returnsNegative() {
        let dvg = DVG.testFixture(
            expirationDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())
        )
        let days = dvg.daysUntilExpiry
        #expect(days != nil)
        #expect(days! < 0)
    }

    // MARK: - displayValue

    @Test("test_displayValue_giftCard_showsCurrency")
    func test_displayValue_giftCard_showsCurrency() {
        let dvg = DVG.testFixture(dvgType: .giftCard, originalValue: 50.0, remainingBalance: 25.0)
        let value = dvg.displayValue
        #expect(value.contains("25"))
    }

    @Test("test_displayValue_loyaltyPoints_showsPoints")
    func test_displayValue_loyaltyPoints_showsPoints() {
        let dvg = DVG.testFixture(dvgType: .loyaltyPoints, pointsBalance: 500.0)
        #expect(dvg.displayValue == "500 pts")
    }

    @Test("test_displayValue_discountCode_showsPercentage")
    func test_displayValue_discountCode_showsPercentage() {
        let dvg = DVG.testFixture(dvgType: .discountCode, originalValue: 20.0)
        #expect(dvg.displayValue == "20% off")
    }

    @Test("test_displayValue_discountCode_over100_showsCurrency")
    func test_displayValue_discountCode_over100_showsCurrency() {
        let dvg = DVG.testFixture(dvgType: .discountCode, originalValue: 150.0)
        #expect(dvg.displayValue.contains("150"))
    }

    // MARK: - DVGType

    @Test("test_dvgType_allCases_haveDisplayNames")
    func test_dvgType_allCases_haveDisplayNames() {
        for type in DVGType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.iconName.isEmpty)
        }
    }

    // MARK: - DVGStatus

    @Test("test_dvgStatus_allCases_haveDisplayNames")
    func test_dvgStatus_allCases_haveDisplayNames() {
        for status in DVGStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - DVGSource

    @Test("test_dvgSource_allCases_haveDisplayNames")
    func test_dvgSource_allCases_haveDisplayNames() {
        for source in DVGSource.allCases {
            #expect(!source.displayName.isEmpty)
        }
    }

    // MARK: - BarcodeType

    @Test("test_barcodeType_allCases_haveDisplayNames")
    func test_barcodeType_allCases_haveDisplayNames() {
        for type in BarcodeType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    // MARK: - DVGSortOrder

    @Test("test_dvgSortOrder_allCases_haveDisplayNames")
    func test_dvgSortOrder_allCases_haveDisplayNames() {
        for sort in DVGSortOrder.allCases {
            #expect(!sort.displayName.isEmpty)
        }
    }

    // MARK: - DVGFilter

    @Test("test_dvgFilter_isEmpty_allNil_returnsTrue")
    func test_dvgFilter_isEmpty_allNil_returnsTrue() {
        let filter = DVGFilter()
        #expect(filter.isEmpty == true)
    }

    @Test("test_dvgFilter_isEmpty_withType_returnsFalse")
    func test_dvgFilter_isEmpty_withType_returnsFalse() {
        let filter = DVGFilter(type: .giftCard)
        #expect(filter.isEmpty == false)
    }

    @Test("test_dvgFilter_isEmpty_withFavorite_returnsFalse")
    func test_dvgFilter_isEmpty_withFavorite_returnsFalse() {
        let filter = DVGFilter(isFavoriteOnly: true)
        #expect(filter.isEmpty == false)
    }

    // MARK: - DVGRepositoryError

    @Test("test_dvgRepositoryError_allCases_haveDescriptions")
    func test_dvgRepositoryError_allCases_haveDescriptions() {
        let errors: [DVGRepositoryError] = [
            .notFound(UUID()),
            .fetchFailed("test"),
            .saveFailed("test"),
            .deleteFailed("test"),
            .invalidBalance(-1.0),
            .contextUnavailable
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}
