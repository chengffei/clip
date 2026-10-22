import AppKit
import ImageIO
import UniformTypeIdentifiers
import zlib

struct EncodedImageOutput {
    let data: Data
    let fileExtension: String
    let contentType: String
    let pasteboardType: NSPasteboard.PasteboardType
    let pixelSize: CGSize
}

struct EncodedClipboardImageOutput {
    let primary: EncodedImageOutput
    let tiffData: Data?
}

enum ImageOutputEncoder {
    private static let indexedPNGColorLimit = 104
    private static let indexedPNGCompressionLevel: Int32 = 6
    private static let queue = DispatchQueue(label: "capcap.image-output-encoder", qos: .userInitiated)

    static func encodeAsync(
        image: NSImage,
        quality: ScreenshotImageQuality,
        completion: @escaping (Result<EncodedImageOutput, Error>) -> Void
    ) {
        guard let source = ImageOutputSource(image: image) else {
            completion(.failure(ImageOutputEncodingError.missingImage))
            return
        }

        queue.async {
            let result = Result {
                try encode(source: source, quality: quality)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    static func encodeClipboardAsync(
        image: NSImage,
        quality: ScreenshotImageQuality,
        completion: @escaping (Result<EncodedClipboardImageOutput, Error>) -> Void
    ) {
        guard let source = ImageOutputSource(image: image) else {
            completion(.failure(ImageOutputEncodingError.missingImage))
            return
        }

        queue.async {
            let result = Result {
                let primary = try encode(source: source, quality: quality)
                let tiffData: Data?
                if quality == .original {
                    tiffData = try? encodeImage(
                        source.cgImage,
                        typeIdentifier: UTType.tiff.identifier,
                        pointSize: source.pointSize
                    )
                } else {
                    tiffData = nil
                }
                return EncodedClipboardImageOutput(primary: primary, tiffData: tiffData)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func encode(
        source: ImageOutputSource,
        quality: ScreenshotImageQuality
    ) throws -> EncodedImageOutput {
        let data: Data
        if quality == .compressed {
            data = try compressedPNGData(source: source)
        } else {
            data = try encodeImage(
                source.cgImage,
                typeIdentifier: UTType.png.identifier,
                pointSize: source.pointSize
            )
        }
        return EncodedImageOutput(
            data: data,
            fileExtension: quality.fileExtension,
            contentType: quality.contentType,
            pasteboardType: .png,
            pixelSize: CGSize(width: source.cgImage.width, height: source.cgImage.height)
        )
    }

    private static func encodeImage(
        _ image: CGImage,
        typeIdentifier: String,
        pointSize: CGSize
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ImageOutputEncodingError.encoderUnavailable
        }

        var properties: [CFString: Any] = [:]
        if typeIdentifier == UTType.png.identifier {
            properties[kCGImagePropertyPNGDictionary] = [
                kCGImagePropertyPNGCompressionFilter: 0xF8,
            ] as CFDictionary
        }
        if pointSize.width > 0, pointSize.height > 0 {
            properties[kCGImagePropertyDPIWidth] = Double(image.width) * 72.0 / Double(pointSize.width)
            properties[kCGImagePropertyDPIHeight] = Double(image.height) * 72.0 / Double(pointSize.height)
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageOutputEncodingError.encodingFailed
        }
        return data as Data
    }

    private static func compressedPNGData(
        source: ImageOutputSource
    ) throws -> Data {
        let pixelBuffer = try rgbaPixelBuffer(from: source.cgImage)

        if pixelBuffer.isOpaque {
            return try indexedPNGData(from: pixelBuffer, maxColors: indexedPNGColorLimit)
        }

        var best = try encodeImage(
            source.cgImage,
            typeIdentifier: UTType.png.identifier,
            pointSize: source.pointSize
        )

        for step in [6, 10] {
            let image = try quantizedImage(from: pixelBuffer, colorStep: step)
            let data = try encodeImage(
                image,
                typeIdentifier: UTType.png.identifier,
                pointSize: source.pointSize
            )
            guard data.count < best.count else { continue }
            best = data
        }

        return best
    }

    private static func rgbaPixelBuffer(from image: CGImage) throws -> RGBAPixelBuffer {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw ImageOutputEncodingError.missingImage
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  )
            else {
                throw ImageOutputEncodingError.encoderUnavailable
            }

            context.interpolationQuality = .none
            context.clear(rect)
            context.draw(image, in: rect)
        }

        let isOpaque = stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 }
        return RGBAPixelBuffer(width: width, height: height, pixels: pixels, isOpaque: isOpaque)
    }

    private static func indexedPNGData(
        from buffer: RGBAPixelBuffer,
        maxColors: Int
    ) throws -> Data {
        let histogram = colorHistogram(from: buffer.pixels)
        guard !histogram.isEmpty else {
            throw ImageOutputEncodingError.encodingFailed
        }

        let palette = paletteColors(from: histogram, maxColors: maxColors)
        let lookup = paletteLookup(for: palette)
        var indexes = [UInt8](repeating: 0, count: buffer.width * buffer.height)
        var pixelOffset = 0

        for index in indexes.indices {
            let bin = histogramBin(
                red: buffer.pixels[pixelOffset],
                green: buffer.pixels[pixelOffset + 1],
                blue: buffer.pixels[pixelOffset + 2]
            )
            indexes[index] = lookup[bin]
            pixelOffset += 4
        }

        return try indexedPNGData(
            width: buffer.width,
            height: buffer.height,
            indexes: indexes,
            palette: palette
        )
    }

    private static func indexedPNGData(
        width: Int,
        height: Int,
        indexes: [UInt8],
        palette: [PaletteColor]
    ) throws -> Data {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        appendUInt32(UInt32(width), to: &ihdr)
        appendUInt32(UInt32(height), to: &ihdr)
        ihdr.append(8)
        ihdr.append(3)
        ihdr.append(0)
        ihdr.append(0)
        ihdr.append(0)
        appendPNGChunk(type: "IHDR", payload: ihdr, to: &png)

        var plte = Data()
        plte.reserveCapacity(palette.count * 3)
        for color in palette {
            plte.append(color.red)
            plte.append(color.green)
            plte.append(color.blue)
        }
        appendPNGChunk(type: "PLTE", payload: plte, to: &png)

        let filteredRows = filteredIndexedRows(indexes: indexes, width: width, height: height)
        let idat = try zlibCompressed(filteredRows)
        appendPNGChunk(type: "IDAT", payload: idat, to: &png)
        appendPNGChunk(type: "IEND", payload: Data(), to: &png)
        return png
    }

    private static func quantizedImage(from buffer: RGBAPixelBuffer, colorStep: Int) throws -> CGImage {
        let width = buffer.width
        let height = buffer.height
        let bytesPerRow = width * 4
        var pixels = buffer.pixels

        quantizeRGBA(&pixels, colorStep: colorStep)

        let data = Data(pixels)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let provider = CGDataProvider(data: data as CFData),
              let quantized = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw ImageOutputEncodingError.encodingFailed
        }
        return quantized
    }

    private static func colorHistogram(from pixels: [UInt8]) -> [HistogramColor] {
        let binCount = 32 * 32 * 32
        var counts = [Int](repeating: 0, count: binCount)
        var redSums = [Int](repeating: 0, count: binCount)
        var greenSums = [Int](repeating: 0, count: binCount)
        var blueSums = [Int](repeating: 0, count: binCount)

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            let bin = histogramBin(red: red, green: green, blue: blue)
            counts[bin] += 1
            redSums[bin] += Int(red)
            greenSums[bin] += Int(green)
            blueSums[bin] += Int(blue)
        }

        var colors: [HistogramColor] = []
        colors.reserveCapacity(counts.lazy.filter { $0 > 0 }.count)
        for bin in counts.indices where counts[bin] > 0 {
            colors.append(
                HistogramColor(
                    redBin: (bin >> 10) & 31,
                    greenBin: (bin >> 5) & 31,
                    blueBin: bin & 31,
                    count: counts[bin],
                    redSum: redSums[bin],
                    greenSum: greenSums[bin],
                    blueSum: blueSums[bin]
                )
            )
        }
        return colors
    }

    private static func paletteColors(
        from histogram: [HistogramColor],
        maxColors: Int
    ) -> [PaletteColor] {
        let colorLimit = max(1, min(maxColors, 256))
        guard histogram.count > colorLimit else {
            return histogram.map { $0.paletteColor }
        }

        var boxes = [ColorBox(indices: Array(histogram.indices), colors: histogram)]
        while boxes.count < colorLimit {
            guard let index = boxes.indices.max(by: { boxes[$0].splitScore < boxes[$1].splitScore }),
                  boxes[index].canSplit,
                  let split = boxes[index].split(colors: histogram)
            else {
                break
            }
            boxes.remove(at: index)
            boxes.append(split.left)
            boxes.append(split.right)
        }

        let palette = boxes
            .sorted { $0.pixelCount > $1.pixelCount }
            .map { $0.paletteColor(colors: histogram) }
        return refinedPalette(palette, histogram: histogram, iterations: 1)
    }

    private static func refinedPalette(
        _ palette: [PaletteColor],
        histogram: [HistogramColor],
        iterations: Int
    ) -> [PaletteColor] {
        guard palette.count > 1 else { return palette }
        var palette = palette

        for _ in 0..<iterations {
            var counts = [Int](repeating: 0, count: palette.count)
            var redSums = [Int](repeating: 0, count: palette.count)
            var greenSums = [Int](repeating: 0, count: palette.count)
            var blueSums = [Int](repeating: 0, count: palette.count)

            for color in histogram {
                let index = nearestPaletteIndex(
                    forRed: color.averageRed,
                    green: color.averageGreen,
                    blue: color.averageBlue,
                    in: palette
                )
                counts[index] += color.count
                redSums[index] += color.redSum
                greenSums[index] += color.greenSum
                blueSums[index] += color.blueSum
            }

            var changed = false
            for index in palette.indices where counts[index] > 0 {
                let refined = PaletteColor(
                    red: UInt8(redSums[index] / counts[index]),
                    green: UInt8(greenSums[index] / counts[index]),
                    blue: UInt8(blueSums[index] / counts[index])
                )
                if refined != palette[index] {
                    changed = true
                    palette[index] = refined
                }
            }
            if !changed { break }
        }

        return palette
    }

    private static func paletteLookup(for palette: [PaletteColor]) -> [UInt8] {
        var lookup = [UInt8](repeating: 0, count: 32 * 32 * 32)
        for bin in lookup.indices {
            let red = ((bin >> 10) & 31) * 8 + 4
            let green = ((bin >> 5) & 31) * 8 + 4
            let blue = (bin & 31) * 8 + 4
            lookup[bin] = UInt8(nearestPaletteIndex(forRed: red, green: green, blue: blue, in: palette))
        }
        return lookup
    }

    private static func nearestPaletteIndex(
        forRed red: Int,
        green: Int,
        blue: Int,
        in palette: [PaletteColor]
    ) -> Int {
        var bestIndex = 0
        var bestDistance = Int.max

        for (index, color) in palette.enumerated() {
            let distance = color.distanceSquared(toRed: red, green: green, blue: blue)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func histogramBin(red: UInt8, green: UInt8, blue: UInt8) -> Int {
        (Int(red) >> 3) << 10 | (Int(green) >> 3) << 5 | (Int(blue) >> 3)
    }

    private static func filteredIndexedRows(indexes: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity((width + 1) * height)

        for row in 0..<height {
            let rowStart = row * width
            output.append(0)
            output.append(contentsOf: indexes[rowStart..<(rowStart + width)])
        }

        return output
    }

    private static func zlibCompressed(_ bytes: [UInt8]) throws -> Data {
        var destinationLength = uLongf(compressBound(uLong(bytes.count)))
        var destination = [UInt8](repeating: 0, count: Int(destinationLength))
        let status = bytes.withUnsafeBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                compress2(
                    destinationBuffer.baseAddress,
                    &destinationLength,
                    sourceBuffer.baseAddress,
                    uLong(bytes.count),
                    indexedPNGCompressionLevel
                )
            }
        }
        guard status == Z_OK else {
            throw ImageOutputEncodingError.encodingFailed
        }
        return Data(destination.prefix(Int(destinationLength)))
    }

    private static func appendPNGChunk(type: String, payload: Data, to png: inout Data) {
        let typeBytes = [UInt8](type.utf8)
        appendUInt32(UInt32(payload.count), to: &png)
        png.append(contentsOf: typeBytes)
        png.append(payload)
        appendUInt32(crc32Value(typeBytes: typeBytes, payload: payload), to: &png)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func crc32Value(typeBytes: [UInt8], payload: Data) -> UInt32 {
        var checksum = crc32(0, nil, 0)
        typeBytes.withUnsafeBufferPointer { buffer in
            checksum = crc32(checksum, buffer.baseAddress, uInt(buffer.count))
        }
        payload.withUnsafeBytes { bytes in
            if let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress {
                checksum = crc32(checksum, baseAddress, uInt(payload.count))
            }
        }
        return UInt32(checksum)
    }

    private static func quantizeRGBA(_ pixels: inout [UInt8], colorStep: Int) {
        let step = max(2, min(colorStep, 32))
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            if alpha == 0 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                continue
            }

            for channel in 0..<3 {
                let value = quantizedChannel(pixels[offset + channel], step: step)
                pixels[offset + channel] = alpha < 255 ? min(value, alpha) : value
            }
        }
    }

    private static func quantizedChannel(_ value: UInt8, step: Int) -> UInt8 {
        guard value > 0, value < 255 else { return value }
        let rounded = ((Int(value) + step / 2) / step) * step
        return UInt8(min(255, max(0, rounded)))
    }
}

private struct RGBAPixelBuffer {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let isOpaque: Bool
}

private struct HistogramColor {
    let redBin: Int
    let greenBin: Int
    let blueBin: Int
    let count: Int
    let redSum: Int
    let greenSum: Int
    let blueSum: Int

    var averageRed: Int { redSum / count }
    var averageGreen: Int { greenSum / count }
    var averageBlue: Int { blueSum / count }

    var paletteColor: PaletteColor {
        PaletteColor(
            red: UInt8(averageRed),
            green: UInt8(averageGreen),
            blue: UInt8(averageBlue)
        )
    }

    func binValue(for axis: ColorAxis) -> Int {
        switch axis {
        case .red: return redBin
        case .green: return greenBin
        case .blue: return blueBin
        }
    }
}

private struct PaletteColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    func distanceSquared(toRed otherRed: Int, green otherGreen: Int, blue otherBlue: Int) -> Int {
        let redDistance = Int(red) - otherRed
        let greenDistance = Int(green) - otherGreen
        let blueDistance = Int(blue) - otherBlue
        return redDistance * redDistance + greenDistance * greenDistance + blueDistance * blueDistance
    }
}

private enum ColorAxis {
    case red
    case green
    case blue
}

private struct ColorBox {
    let indices: [Int]
    let pixelCount: Int
    let redRange: Int
    let greenRange: Int
    let blueRange: Int

    init(indices: [Int], colors: [HistogramColor]) {
        self.indices = indices

        var pixelCount = 0
        var redMin = Int.max
        var greenMin = Int.max
        var blueMin = Int.max
        var redMax = Int.min
        var greenMax = Int.min
        var blueMax = Int.min

        for index in indices {
            let color = colors[index]
            pixelCount += color.count
            redMin = min(redMin, color.redBin)
            greenMin = min(greenMin, color.greenBin)
            blueMin = min(blueMin, color.blueBin)
            redMax = max(redMax, color.redBin)
            greenMax = max(greenMax, color.greenBin)
            blueMax = max(blueMax, color.blueBin)
        }

        self.pixelCount = pixelCount
        self.redRange = max(0, redMax - redMin)
        self.greenRange = max(0, greenMax - greenMin)
        self.blueRange = max(0, blueMax - blueMin)
    }

    var canSplit: Bool {
        indices.count > 1
    }

    var splitScore: Int {
        max(redRange, greenRange, blueRange) * pixelCount
    }

    func split(colors: [HistogramColor]) -> (left: ColorBox, right: ColorBox)? {
        let axis = splitAxis
        let sorted = indices.sorted {
            colors[$0].binValue(for: axis) < colors[$1].binValue(for: axis)
        }
        guard sorted.count > 1 else { return nil }

        let halfCount = pixelCount / 2
        var runningCount = 0
        var splitIndex = sorted.count / 2

        for index in 0..<(sorted.count - 1) {
            runningCount += colors[sorted[index]].count
            if runningCount >= halfCount {
                splitIndex = index + 1
                break
            }
        }

        splitIndex = min(max(1, splitIndex), sorted.count - 1)
        let leftIndices = Array(sorted[..<splitIndex])
        let rightIndices = Array(sorted[splitIndex...])
        return (
            ColorBox(indices: leftIndices, colors: colors),
            ColorBox(indices: rightIndices, colors: colors)
        )
    }

    func paletteColor(colors: [HistogramColor]) -> PaletteColor {
        var pixelCount = 0
        var redSum = 0
        var greenSum = 0
        var blueSum = 0

        for index in indices {
            let color = colors[index]
            pixelCount += color.count
            redSum += color.redSum
            greenSum += color.greenSum
            blueSum += color.blueSum
        }

        return PaletteColor(
            red: UInt8(redSum / pixelCount),
            green: UInt8(greenSum / pixelCount),
            blue: UInt8(blueSum / pixelCount)
        )
    }

    private var splitAxis: ColorAxis {
        if redRange >= greenRange, redRange >= blueRange {
            return .red
        }
        if greenRange >= blueRange {
            return .green
        }
        return .blue
    }
}

private struct ImageOutputSource {
    let cgImage: CGImage
    let pointSize: CGSize

    init?(image: NSImage) {
        guard let cgImage = image.cgImagePreservingBacking() else { return nil }
        self.cgImage = cgImage
        self.pointSize = image.size
    }
}

private enum ImageOutputEncodingError: LocalizedError {
    case missingImage
    case encoderUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingImage: return "Could not read image data"
        case .encoderUnavailable: return "Image encoder unavailable"
        case .encodingFailed: return "Image encoding failed"
        }
    }
}
