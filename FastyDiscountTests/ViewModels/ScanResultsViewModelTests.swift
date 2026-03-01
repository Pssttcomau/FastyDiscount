import Testing
import Foundation
import SwiftData
@testable import FastyDiscount

// MARK: - ScanResultsViewModelTests

@Suite("ScanResultsViewModel Tests")
@MainActor
struct ScanResultsViewModelTests {

    // MARK: - Helpers

    private func makeAIParsedData(
        confidence: Double = 0.92,
        title: String = "AI Parsed",
        code: String = "CODE1"
    ) -> ScanInputData {
        let extraction = DVGExtractionResult.testFixture(
            title: title,
            code: code,
            confidenceScore: confidence
        )
        return .aiParsed(extraction: extraction, barcode: nil, originalImageData: nil)
    }

    private func makeBarcodeOnlyData() -> ScanInputData {
        let barcode = DetectedBarcode(
            value: "1234567890",
            barcodeType: .ean13,
            confidence: 0.95,
            boundingBox: .zero,
            imageData: nil
        )
        return .barcodeOnly(barcode: barcode, originalImageData: nil)
    }

    private func makeOCRTextOnlyData() -> ScanInputData {
        .ocrTextOnly(text: "Raw OCR text content", originalImageData: nil)
    }

    // MARK: - AI Parsed Scenario

    @Test("test_aiParsed_populatesFieldsFromExtraction")
    func test_aiParsed_populatesFieldsFromExtraction() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData(title: "My Deal", code: "DEAL50"))

        #expect(vm.title == "My Deal")
        #expect(vm.code == "DEAL50")
        #expect(vm.scenario == .aiParsed)
        #expect(vm.showFullForm == true)
    }

    @Test("test_aiParsed_setsConfidenceData")
    func test_aiParsed_setsConfidenceData() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData(confidence: 0.85))

        #expect(vm.overallConfidence == 0.85)
        #expect(!vm.fieldConfidences.isEmpty)
    }

    @Test("test_aiParsed_zeroConfidence_fallsToBarcodeOrOCR")
    func test_aiParsed_zeroConfidence_fallsToBarcodeOrOCR() {
        let extraction = DVGExtractionResult.testFixture(
            discountDescription: "Some OCR text",
            confidenceScore: 0.0
        )
        let data = ScanInputData.aiParsed(extraction: extraction, barcode: nil, originalImageData: nil)
        let vm = ScanResultsViewModel(inputData: data)

        #expect(vm.scenario == .ocrFallback)
        #expect(vm.showFullForm == false)
    }

    // MARK: - Barcode Only Scenario

    @Test("test_barcodeOnly_populatesBarcodeFields")
    func test_barcodeOnly_populatesBarcodeFields() {
        let vm = ScanResultsViewModel(inputData: makeBarcodeOnlyData())

        #expect(vm.code == "1234567890")
        #expect(vm.barcodeType == .ean13)
        #expect(vm.dvgType == .barcodeCoupon)
        #expect(vm.scenario == .barcodeOnly)
        #expect(vm.showFullForm == false)
    }

    // MARK: - OCR Text Only Scenario

    @Test("test_ocrTextOnly_populatesDescription")
    func test_ocrTextOnly_populatesDescription() {
        let vm = ScanResultsViewModel(inputData: makeOCRTextOnlyData())

        #expect(vm.discountDescription == "Raw OCR text content")
        #expect(vm.scenario == .ocrTextOnly)
        #expect(vm.rawOCRText == "Raw OCR text content")
    }

    // MARK: - Validation

    @Test("test_canSave_emptyTitle_returnsFalse")
    func test_canSave_emptyTitle_returnsFalse() {
        let vm = ScanResultsViewModel(inputData: makeBarcodeOnlyData())
        vm.title = ""
        #expect(vm.canSave == false)
    }

    @Test("test_canSave_withTitle_returnsTrue")
    func test_canSave_withTitle_returnsTrue() {
        let vm = ScanResultsViewModel(inputData: makeBarcodeOnlyData())
        vm.title = "My Barcode"
        #expect(vm.canSave == true)
    }

    // MARK: - Save

    @Test("test_saveDVG_validData_saveSucceeds")
    func test_saveDVG_validData_saveSucceeds() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        vm.title = "Saved DVG"

        await vm.saveDVG(modelContext: context)

        #expect(vm.saveSucceeded == true)
        #expect(vm.hasError == false)

        let dvgDescriptor = FetchDescriptor<DVG>()
        let dvgs = try context.fetch(dvgDescriptor)
        #expect(dvgs.count == 1)
        #expect(dvgs.first?.title == "Saved DVG")
        #expect(dvgs.first?.sourceEnum == .scan)
    }

    @Test("test_saveDVG_createsScanResult")
    func test_saveDVG_createsScanResult() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        vm.title = "With ScanResult"

        await vm.saveDVG(modelContext: context)

        let scanDescriptor = FetchDescriptor<ScanResult>()
        let results = try context.fetch(scanDescriptor)
        #expect(results.count == 1)
    }

    @Test("test_saveDVG_emptyTitle_doesNotSave")
    func test_saveDVG_emptyTitle_doesNotSave() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let vm = ScanResultsViewModel(inputData: makeBarcodeOnlyData())
        vm.title = ""

        await vm.saveDVG(modelContext: context)

        #expect(vm.saveSucceeded == false)
    }

    // MARK: - Confidence Color

    @Test("test_confidenceColor_high_isGreen")
    func test_confidenceColor_high_isGreen() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        let color = vm.confidenceColor(for: 0.9)
        #expect(color == Theme.Colors.success)
    }

    @Test("test_confidenceColor_medium_isWarning")
    func test_confidenceColor_medium_isWarning() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        let color = vm.confidenceColor(for: 0.6)
        #expect(color == Theme.Colors.warning)
    }

    @Test("test_confidenceColor_low_isError")
    func test_confidenceColor_low_isError() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        let color = vm.confidenceColor(for: 0.3)
        #expect(color == Theme.Colors.error)
    }

    // MARK: - Confidence Per Field

    @Test("test_confidence_existingField_returnsScore")
    func test_confidence_existingField_returnsScore() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        let score = vm.confidence(for: "title")
        #expect(score != nil)
        #expect(score! > 0.0)
    }

    @Test("test_confidence_unknownField_returnsNil")
    func test_confidence_unknownField_returnsNil() {
        let vm = ScanResultsViewModel(inputData: makeAIParsedData())
        let score = vm.confidence(for: "nonexistent")
        #expect(score == nil)
    }
}
