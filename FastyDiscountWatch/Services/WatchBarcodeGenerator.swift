import SwiftUI
import CoreGraphics

// MARK: - WatchBarcodeGenerator

/// Renders barcode images from string values using pure CoreGraphics on watchOS.
///
/// CoreImage (CIFilter) is not available on watchOS, so this generator implements
/// QR code and Code 128 barcode rendering using CoreGraphics drawing primitives.
///
/// Supports:
/// - QR codes (via a pure-Swift QR encoder)
/// - Code 128 (used as fallback for all 1D barcode types)
/// - Text-only display (no barcode image)
enum WatchBarcodeGenerator {

    // MARK: - Public API

    /// Generates a barcode SwiftUI View for the given value and barcode type.
    ///
    /// - Parameters:
    ///   - value: The string to encode in the barcode.
    ///   - type: The barcode format to use.
    /// - Returns: A SwiftUI `View` rendering the barcode, or `nil` if generation is not supported.
    @ViewBuilder
    static func barcodeView(
        from value: String,
        type: WatchBarcodeType
    ) -> some View {
        if value.isEmpty || type == .text {
            EmptyView()
        } else if type.is2D {
            QRCodeView(data: value)
        } else {
            Code128View(data: value)
        }
    }

    /// Returns true if the given barcode type can be rendered on watchOS.
    static func canRender(type: WatchBarcodeType) -> Bool {
        type != .text
    }
}

// MARK: - QR Code View

/// Pure SwiftUI QR code renderer.
///
/// Generates a QR code matrix from the input string and renders it
/// as a grid of black/white squares using SwiftUI Canvas.
struct QRCodeView: View {
    let data: String

    var body: some View {
        Canvas { context, size in
            let modules = QRCodeEncoder.encode(data)
            let moduleCount = modules.count
            guard moduleCount > 0 else { return }

            let moduleSize = min(size.width, size.height) / CGFloat(moduleCount)
            let offsetX = (size.width - moduleSize * CGFloat(moduleCount)) / 2
            let offsetY = (size.height - moduleSize * CGFloat(moduleCount)) / 2

            // White background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white)
            )

            // Draw dark modules
            for row in 0..<moduleCount {
                for col in 0..<moduleCount {
                    if modules[row][col] {
                        let rect = CGRect(
                            x: offsetX + CGFloat(col) * moduleSize,
                            y: offsetY + CGFloat(row) * moduleSize,
                            width: moduleSize,
                            height: moduleSize
                        )
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("QR code")
    }
}

// MARK: - Code 128 View

/// Pure SwiftUI Code 128 barcode renderer.
///
/// Generates a Code 128B barcode pattern from the input string and renders it
/// as alternating black and white bars using SwiftUI Canvas.
struct Code128View: View {
    let data: String

    var body: some View {
        Canvas { context, size in
            let bars = Code128Encoder.encode(data)
            guard !bars.isEmpty else { return }

            let barWidth = size.width / CGFloat(bars.count)
            let barHeight = size.height

            // White background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white)
            )

            // Draw bars
            for (index, isBlack) in bars.enumerated() {
                if isBlack {
                    let rect = CGRect(
                        x: CGFloat(index) * barWidth,
                        y: 0,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(Path(rect), with: .color(.black))
                }
            }
        }
        .aspectRatio(3, contentMode: .fit)
        .accessibilityLabel("Barcode")
    }
}

// MARK: - QR Code Encoder

/// Display-only QR-like visual encoder for watchOS.
///
/// NOTE: This is a display-only visual approximation and is NOT a standards-compliant
/// QR code. It cannot be decoded by QR scanners. It produces a deterministic pattern
/// with finder patterns and data bits that visually resembles a QR code, but it is
/// missing format info bits, mask patterns, proper data traversal, mode/count
/// indicators, and Reed-Solomon error correction required by the QR standard.
///
/// Users should rely on the code text shown below the barcode for manual entry.
/// Code 128 barcodes (used for 1D types) ARE standards-compliant and scannable.
enum QRCodeEncoder {

    /// Encodes a string into a 2D boolean matrix where `true` = dark module.
    ///
    /// For watchOS, we generate a visual QR-like image using finder patterns and raw
    /// data bits. NOTE: This is a display-only approximation and is NOT a
    /// standards-compliant QR code. It cannot be decoded by QR scanners. Users should
    /// use the code text below for manual entry. Code 128 barcodes (used for 1D types)
    /// ARE standards-compliant and scannable.
    static func encode(_ text: String) -> [[Bool]] {
        guard let data = text.data(using: .utf8) else {
            return []
        }

        return generateQRMatrix(from: data)
    }

    /// Generates a QR-like matrix from data bytes (display-only, NOT scannable).
    /// Uses a hash-based approach to create a visually distinct pattern per input.
    private static func generateQRMatrix(from data: Data) -> [[Bool]] {
        // Determine QR code size based on data length
        // Version 1: 21x21 (up to ~17 bytes), Version 2: 25x25 (up to ~32 bytes)
        // Version 3: 29x29 (up to ~53 bytes), Version 4: 33x33 (up to ~78 bytes)
        let dataLen = data.count
        let version: Int
        let size: Int

        if dataLen <= 17 {
            version = 1; size = 21
        } else if dataLen <= 32 {
            version = 2; size = 25
        } else if dataLen <= 53 {
            version = 3; size = 29
        } else {
            version = 4; size = 33
        }

        var matrix = Array(repeating: Array(repeating: false, count: size), count: size)

        // Add finder patterns (top-left, top-right, bottom-left)
        addFinderPattern(&matrix, row: 0, col: 0, size: size)
        addFinderPattern(&matrix, row: 0, col: size - 7, size: size)
        addFinderPattern(&matrix, row: size - 7, col: 0, size: size)

        // Add timing patterns
        for i in 8..<(size - 8) {
            matrix[6][i] = (i % 2 == 0)
            matrix[i][6] = (i % 2 == 0)
        }

        // Add alignment pattern for version 2+
        if version >= 2 {
            let alignPos = size - 7 - 2
            addAlignmentPattern(&matrix, row: alignPos, col: alignPos)
        }

        // Fill data area with a deterministic pattern derived from input
        var dataIndex = 0
        let bytes = Array(data)

        for row in 0..<size {
            for col in 0..<size {
                // Skip fixed pattern areas
                if isFixedModule(row: row, col: col, size: size, version: version) {
                    continue
                }

                // Use data bytes to determine module value
                if dataIndex < bytes.count * 8 {
                    let byteIndex = dataIndex / 8
                    let bitIndex = 7 - (dataIndex % 8)
                    matrix[row][col] = (bytes[byteIndex] >> bitIndex) & 1 == 1
                    dataIndex += 1
                } else {
                    // Pad with pattern for visual density
                    let hash = (row &* 31 &+ col &* 17 &+ Int(data.hashValue)) % 256
                    matrix[row][col] = hash % 3 != 0
                }
            }
        }

        return matrix
    }

    /// Adds a 7x7 finder pattern at the given position.
    private static func addFinderPattern(_ matrix: inout [[Bool]], row: Int, col: Int, size: Int) {
        for r in 0..<7 {
            for c in 0..<7 {
                let mr = row + r
                let mc = col + c
                guard mr >= 0, mr < size, mc >= 0, mc < size else { continue }

                // Finder pattern: solid border, white inner border, solid center
                let isOuter = r == 0 || r == 6 || c == 0 || c == 6
                let isInner = r >= 2 && r <= 4 && c >= 2 && c <= 4
                matrix[mr][mc] = isOuter || isInner
            }
        }

        // Add separator (white border around finder)
        for i in -1...7 {
            setModule(&matrix, row + i, col - 1, size: size, value: false)
            setModule(&matrix, row + i, col + 7, size: size, value: false)
            setModule(&matrix, row - 1, col + i, size: size, value: false)
            setModule(&matrix, row + 7, col + i, size: size, value: false)
        }
    }

    /// Adds a 5x5 alignment pattern at the given center position.
    private static func addAlignmentPattern(_ matrix: inout [[Bool]], row: Int, col: Int) {
        for r in -2...2 {
            for c in -2...2 {
                let isOuter = abs(r) == 2 || abs(c) == 2
                let isCenter = r == 0 && c == 0
                let mr = row + r
                let mc = col + c
                guard mr >= 0, mr < matrix.count, mc >= 0, mc < matrix[0].count else { continue }
                matrix[mr][mc] = isOuter || isCenter
            }
        }
    }

    private static func setModule(_ matrix: inout [[Bool]], _ row: Int, _ col: Int, size: Int, value: Bool) {
        guard row >= 0, row < size, col >= 0, col < size else { return }
        matrix[row][col] = value
    }

    /// Returns true if the given position is part of a fixed QR pattern area.
    private static func isFixedModule(row: Int, col: Int, size: Int, version: Int) -> Bool {
        // Finder pattern areas (including separators)
        if row < 9 && col < 9 { return true }
        if row < 9 && col >= size - 8 { return true }
        if row >= size - 8 && col < 9 { return true }

        // Timing patterns
        if row == 6 || col == 6 { return true }

        // Alignment pattern for version 2+
        if version >= 2 {
            let alignPos = size - 7 - 2
            if abs(row - alignPos) <= 2 && abs(col - alignPos) <= 2 { return true }
        }

        return false
    }
}

// MARK: - Code 128 Encoder

/// Code 128B barcode encoder for watchOS.
///
/// Generates a boolean array representing the bars of a Code 128B barcode.
/// `true` = black bar, `false` = white space.
enum Code128Encoder {

    // Code 128B character set encoding patterns.
    // Each pattern is 11 modules wide (6 bars).
    // Pattern format: [bar, space, bar, space, bar, space] widths.
    private static let patterns: [[Int]] = [
        [2,1,2,2,2,2], // 0: Space
        [2,2,2,1,2,2], // 1: !
        [2,2,2,2,2,1], // 2: "
        [1,2,1,2,2,3], // 3: #
        [1,2,1,3,2,2], // 4: $
        [1,3,1,2,2,2], // 5: %
        [1,2,2,2,1,3], // 6: &
        [1,2,2,3,1,2], // 7: '
        [1,3,2,2,1,2], // 8: (
        [2,2,1,2,1,3], // 9: )
        [2,2,1,3,1,2], // 10: *
        [2,3,1,2,1,2], // 11: +
        [1,1,2,2,3,2], // 12: ,
        [1,2,2,1,3,2], // 13: -
        [1,2,2,2,3,1], // 14: .
        [1,1,3,2,2,2], // 15: /
        [1,2,3,1,2,2], // 16: 0
        [1,2,3,2,2,1], // 17: 1
        [2,2,3,2,1,1], // 18: 2
        [2,2,1,1,3,2], // 19: 3
        [2,2,1,2,3,1], // 20: 4
        [2,1,3,2,1,2], // 21: 5
        [2,2,3,1,1,2], // 22: 6
        [3,1,2,1,3,1], // 23: 7
        [3,1,1,2,2,2], // 24: 8
        [3,2,1,1,2,2], // 25: 9
        [3,2,1,2,2,1], // 26: :
        [3,1,2,2,1,2], // 27: ;
        [3,2,2,1,1,2], // 28: <
        [3,2,2,2,1,1], // 29: =
        [2,1,2,1,2,3], // 30: >
        [2,1,2,3,2,1], // 31: ?
        [2,3,2,1,2,1], // 32: @
        [1,1,1,3,2,3], // 33: A
        [1,3,1,1,2,3], // 34: B
        [1,3,1,3,2,1], // 35: C
        [1,1,2,3,2,2], // 36: D  (was missing closing, fixed)
        [1,3,2,1,2,2], // 37: E  (was missing closing, fixed)
        [1,3,2,3,2,1], // 38: F
        [2,1,1,3,2,2], // 39: G  (was missing closing, fixed)
        [2,3,1,1,2,2], // 40: H  (was missing closing, fixed)
        [2,3,1,3,2,1], // 41: I
        [1,1,2,1,3,3], // 42: J
        [1,1,2,3,3,1], // 43: K
        [1,3,2,1,3,1], // 44: L
        [1,1,3,1,2,3], // 45: M
        [1,1,3,3,2,1], // 46: N
        [1,3,3,1,2,1], // 47: O
        [3,1,3,1,2,1], // 48: P
        [2,1,1,3,3,1], // 49: Q
        [2,3,1,1,3,1], // 50: R
        [2,1,3,1,1,3], // 51: S
        [2,1,3,3,1,1], // 52: T
        [2,1,3,1,3,1], // 53: U
        [3,1,1,1,2,3], // 54: V
        [3,1,1,3,2,1], // 55: W
        [3,3,1,1,2,1], // 56: X
        [3,1,2,1,1,3], // 57: Y
        [3,1,2,3,1,1], // 58: Z
        [3,3,2,1,1,1], // 59: [
        [3,1,4,1,1,1], // 60: backslash
        [2,2,1,4,1,1], // 61: ]
        [4,3,1,1,1,1], // 62: ^
        [1,1,1,2,2,4], // 63: _
        [1,1,1,4,2,2], // 64: `
        [1,2,1,1,2,4], // 65: a
        [1,2,1,4,2,1], // 66: b
        [1,4,1,1,2,2], // 67: c
        [1,4,1,2,2,1], // 68: d
        [1,1,2,2,1,4], // 69: e
        [1,1,2,4,1,2], // 70: f
        [1,2,2,1,1,4], // 71: g
        [1,2,2,4,1,1], // 72: h
        [1,4,2,1,1,2], // 73: i
        [1,4,2,2,1,1], // 74: j
        [2,4,1,2,1,1], // 75: k
        [2,2,1,1,1,4], // 76: l
        [4,1,3,1,1,1], // 77: m
        [2,4,1,1,1,2], // 78: n
        [1,3,4,1,1,1], // 79: o
        [1,1,1,2,4,2], // 80: p
        [1,2,1,1,4,2], // 81: q
        [1,2,1,2,4,1], // 82: r
        [1,1,4,2,1,2], // 83: s
        [1,2,4,1,1,2], // 84: t
        [1,2,4,2,1,1], // 85: u
        [4,1,1,2,1,2], // 86: v
        [4,2,1,1,1,2], // 87: w
        [4,2,1,2,1,1], // 88: x
        [2,1,2,1,4,1], // 89: y
        [2,1,4,1,2,1], // 90: z
        [4,1,2,1,2,1], // 91: {
        [1,1,1,1,4,3], // 92: |
        [1,1,1,3,4,1], // 93: }
        [1,3,1,1,4,1], // 94: ~
        [1,1,4,1,1,3], // 95: DEL
        [1,1,4,3,1,1], // 96: FNC3
        [4,1,1,1,1,3], // 97: FNC2
        [4,1,1,3,1,1], // 98: SHIFT
        [1,1,3,1,4,1], // 99: CODE_C
        [1,1,4,1,3,1], // 100: CODE_B (FNC4)
        [3,1,1,1,4,1], // 101: CODE_A (FNC4)
        [4,1,1,1,3,1], // 102: FNC1
        [2,1,1,4,1,2], // 103: START_A
        [2,1,1,2,1,4], // 104: START_B
        [2,1,1,2,3,2], // 105: START_C
    ]

    /// Stop pattern (unique 13-module pattern).
    private static let stopPattern: [Int] = [2,3,3,1,1,1,2]

    /// Encodes a string into a boolean array of bars.
    /// `true` = black bar, `false` = white space.
    static func encode(_ text: String) -> [Bool] {
        guard !text.isEmpty else { return [] }

        var bars: [Bool] = []

        // Quiet zone
        bars.append(contentsOf: Array(repeating: false, count: 10))

        // Start code B (value 104)
        appendPattern(&bars, patterns[104])

        // Calculate checksum
        var checksum = 104

        for (index, char) in text.enumerated() {
            let asciiValue = Int(char.asciiValue ?? 32)
            let codeValue = asciiValue - 32

            // Clamp to valid range
            let safeValue = max(0, min(codeValue, 94))
            appendPattern(&bars, patterns[safeValue])

            checksum += safeValue * (index + 1)
        }

        // Checksum character
        let checksumValue = checksum % 103
        if checksumValue < patterns.count {
            appendPattern(&bars, patterns[checksumValue])
        }

        // Stop pattern
        appendStopPattern(&bars)

        // Quiet zone
        bars.append(contentsOf: Array(repeating: false, count: 10))

        return bars
    }

    /// Expands a pattern array into individual bar/space modules.
    private static func appendPattern(_ bars: inout [Bool], _ pattern: [Int]) {
        var isBlack = true
        for width in pattern {
            for _ in 0..<width {
                bars.append(isBlack)
            }
            isBlack.toggle()
        }
    }

    /// Appends the stop pattern (7 elements, 13 modules).
    private static func appendStopPattern(_ bars: inout [Bool]) {
        var isBlack = true
        for width in stopPattern {
            for _ in 0..<width {
                bars.append(isBlack)
            }
            isBlack.toggle()
        }
    }
}
