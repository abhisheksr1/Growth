import Foundation
import zlib

enum RoadmapImportError: LocalizedError, Equatable {
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This document couldn't be read. If it has a password, export a copy without one."
        case .tooLarge:
            "This document is too large to import."
        }
    }
}

enum RoadmapImport {
    static let maxFileBytes = 12_000_000

    static func parse(_ data: Data) throws -> RoadmapDraft {
        guard data.count <= maxFileBytes else { throw RoadmapImportError.tooLarge }
        let files = try DocxArchive.extract(data)
        guard let document = files["word/document.xml"] else { throw RoadmapImportError.unreadable }
        let styles = files["word/styles.xml"].map(DocxStyles.parse) ?? [:]
        let blocks = try DocxDocument.parse(document, styles: styles)
        return RoadmapOutline.draft(from: blocks)
    }
}

enum DocxArchive {
    static let maxEntryBytes = 8_000_000
    static let maxEntries = 400

    static func extract(_ data: Data) throws -> [String: Data] {
        guard let eocd = endOfCentralDirectory(in: data) else { throw RoadmapImportError.unreadable }
        let entryCount = Int(u16(data, eocd + 10))
        let directorySize = Int(u32(data, eocd + 12))
        let directoryOffset = Int(u32(data, eocd + 16))
        guard entryCount <= maxEntries, directoryOffset >= 0, directorySize >= 0 else {
            throw RoadmapImportError.tooLarge
        }
        guard directoryOffset + directorySize <= data.count else { throw RoadmapImportError.unreadable }

        var files: [String: Data] = [:]
        var cursor = directoryOffset
        let end = directoryOffset + directorySize
        for _ in 0..<entryCount {
            guard cursor + 46 <= end, u32(data, cursor) == 0x02014b50 else { throw RoadmapImportError.unreadable }
            let method = u16(data, cursor + 10)
            let compressedSize = Int(u32(data, cursor + 20))
            let uncompressedSize = Int(u32(data, cursor + 24))
            let nameLength = Int(u16(data, cursor + 28))
            let extraLength = Int(u16(data, cursor + 30))
            let commentLength = Int(u16(data, cursor + 32))
            let localOffset = Int(u32(data, cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= end else { throw RoadmapImportError.unreadable }
            let name = (String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? "")
                .replacingOccurrences(of: "\\", with: "/")
            cursor = nameEnd + extraLength + commentLength
            guard cursor <= end else { throw RoadmapImportError.unreadable }

            let wanted = name == "word/document.xml" || name == "word/styles.xml"
            guard wanted else { continue }
            if compressedSize > maxEntryBytes || uncompressedSize > maxEntryBytes {
                throw RoadmapImportError.tooLarge
            }
            files[name] = try readEntry(
                data: data,
                localOffset: localOffset,
                method: method,
                compressedSize: compressedSize
            )
        }
        return files
    }

    private static func readEntry(data: Data, localOffset: Int, method: UInt16, compressedSize: Int) throws -> Data {
        guard localOffset >= 0, localOffset + 30 <= data.count, u32(data, localOffset) == 0x04034b50 else {
            throw RoadmapImportError.unreadable
        }
        let nameLength = Int(u16(data, localOffset + 26))
        let extraLength = Int(u16(data, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        let end = start + compressedSize
        guard start >= 0, end <= data.count else { throw RoadmapImportError.unreadable }
        let payload = data.subdata(in: start..<end)
        switch method {
        case 0:
            return payload
        case 8:
            return try RawDeflate.decompress(payload, limit: maxEntryBytes)
        default:
            throw RoadmapImportError.unreadable
        }
    }

    private static func endOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let start = max(0, data.count - 22 - 65_535)
        var index = data.count - 22
        while index >= start {
            if u32(data, index) == 0x06054b50 {
                return index
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

enum RawDeflate {
    static func decompress(_ input: Data, limit: Int) throws -> Data {
        if input.isEmpty { return Data() }
        var stream = z_stream()
        let opened = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard opened == Z_OK else { throw RoadmapImportError.unreadable }
        defer { inflateEnd(&stream) }

        var output = Data()
        let status: Int32 = input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(input.count)
            let chunk = 16_384
            var buffer = [UInt8](repeating: 0, count: chunk)
            var inflateStatus: Int32 = Z_OK
            while inflateStatus != Z_STREAM_END {
                let produced = buffer.withUnsafeMutableBytes { out -> Int in
                    stream.next_out = out.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(chunk)
                    inflateStatus = inflate(&stream, Z_NO_FLUSH)
                    let count = chunk - Int(stream.avail_out)
                    if count > 0, let base = out.bindMemory(to: UInt8.self).baseAddress {
                        output.append(base, count: count)
                    }
                    return count
                }
                if output.count > limit { return Z_DATA_ERROR }
                if inflateStatus == Z_STREAM_END { break }
                if inflateStatus != Z_OK { return inflateStatus }
                if produced == 0 && stream.avail_in == 0 { return Z_DATA_ERROR }
            }
            return Z_OK
        }
        guard status == Z_OK else { throw RoadmapImportError.unreadable }
        return output
    }
}

struct DocxStyle {
    var headingLevel: Int?
    var isList: Bool
}

enum DocxStyles {
    static func parse(_ data: Data) -> [String: DocxStyle] {
        let parser = StyleParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.styles
    }
}

enum DocxDocument {
    static func parse(_ data: Data, styles: [String: DocxStyle]) throws -> [DocxBlock] {
        let parser = DocumentParser(styles: styles)
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw RoadmapImportError.unreadable }
        return parser.blocks
    }
}

private final class StyleParser: NSObject, XMLParserDelegate {
    var styles: [String: DocxStyle] = [:]
    private var styleID: String?
    private var name = ""
    private var outline: Int?
    private var isList = false
    private var inStyle = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = local(elementName)
        if name == "style" {
            inStyle = true
            styleID = attribute(attributes, "styleId")
            self.name = ""
            outline = nil
            isList = false
        } else if inStyle, name == "name" {
            self.name = attribute(attributes, "val") ?? ""
        } else if inStyle, name == "outlineLvl" {
            if let raw = attribute(attributes, "val"), let level = Int(raw) {
                outline = level
            }
        } else if inStyle, name == "numPr" {
            isList = true
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard local(elementName) == "style", let styleID else { return }
        let heading = headingLevel(id: styleID, name: name, outline: outline)
        let list = isList || "\(styleID) \(name)".lowercased().contains("list")
        styles[styleID] = DocxStyle(headingLevel: heading, isList: list && heading == nil)
        self.styleID = nil
        inStyle = false
    }
}

private final class DocumentParser: NSObject, XMLParserDelegate {
    var blocks: [DocxBlock] = []
    private let styles: [String: DocxStyle]
    private var tableDepth = 0
    private var inCell = false
    private var inDelete = false
    private var inInstruction = false
    private var collecting = false
    private var styleID: String?
    private var outline: Int?
    private var numbered = false
    private var text = ""
    private var leadIsBold: Bool?
    private var runBold = false
    private var runHasText = false
    private var rows: [[String]] = []
    private var cells: [String] = []
    private var cellText = ""

    init(styles: [String: DocxStyle]) {
        self.styles = styles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch local(elementName) {
        case "tbl":
            tableDepth += 1
            if tableDepth == 1 {
                rows = []
            }
        case "tr":
            if tableDepth > 0 { cells = [] }
        case "tc":
            if tableDepth > 0 {
                inCell = true
                cellText = ""
            }
        case "p":
            collecting = true
            styleID = nil
            outline = nil
            numbered = false
            text = ""
            leadIsBold = nil
            runBold = false
            runHasText = false
        case "pStyle":
            styleID = attribute(attributes, "val")
        case "outlineLvl":
            if let raw = attribute(attributes, "val") {
                outline = Int(raw)
            }
        case "numPr":
            numbered = true
        case "r":
            runBold = false
            runHasText = false
        case "b":
            let raw = (attribute(attributes, "val") ?? "1").lowercased()
            runBold = raw != "0" && raw != "false" && raw != "off"
        case "tab", "br", "cr":
            if collecting { text.append(" ") }
        case "instrText":
            inInstruction = true
        case "del":
            inDelete = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard collecting, !inDelete, !inInstruction else { return }
        text.append(string)
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runHasText = true
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch local(elementName) {
        case "r":
            if runHasText, leadIsBold == nil {
                leadIsBold = runBold
            }
        case "instrText":
            inInstruction = false
        case "del":
            inDelete = false
        case "p":
            let value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if inCell {
                if !value.isEmpty {
                    cellText = cellText.isEmpty ? value : cellText + " " + value
                }
            } else if tableDepth == 0, !value.isEmpty {
                blocks.append(DocxBlock(kind: paragraphKind(), text: value, leadIsBold: leadIsBold ?? false))
            }
            collecting = false
        case "tc":
            cells.append(cellText)
            cellText = ""
            inCell = false
        case "tr":
            if cells.contains(where: { !$0.isEmpty }) {
                rows.append(cells)
            }
        case "tbl":
            if tableDepth == 1, !rows.isEmpty {
                blocks.append(DocxBlock(kind: .table(rows), text: "", leadIsBold: false))
            }
            tableDepth = max(0, tableDepth - 1)
        default:
            break
        }
    }

    private func paragraphKind() -> DocxBlock.Kind {
        let style = styleID.flatMap { styles[$0] }
        let level = outline.map { $0 + 1 } ?? style?.headingLevel ?? headingLevel(id: styleID ?? "", name: "", outline: nil)
        if let level {
            return .heading(min(max(level, 1), 6))
        }
        if numbered || style?.isList == true || (styleID ?? "").lowercased().contains("list") {
            return .listItem
        }
        return .paragraph
    }
}

private func attribute(_ attributes: [String: String], _ name: String) -> String? {
    if let value = attributes["w:\(name)"] ?? attributes[name] {
        return value
    }
    return attributes.first { key, _ in
        key.split(separator: ":").last.map(String.init) == name
    }?.value
}

private func local(_ name: String) -> String {
    guard let index = name.lastIndex(of: ":") else { return name }
    return String(name[name.index(after: index)...])
}

private func headingLevel(id: String, name: String, outline: Int?) -> Int? {
    if let outline {
        return min(max(outline + 1, 1), 6)
    }
    let source = "\(id) \(name)"
    guard let regex = try? NSRegularExpression(pattern: "(?i)heading\\s*([1-6])") else { return nil }
    let range = NSRange(source.startIndex..., in: source)
    guard
        let match = regex.firstMatch(in: source, range: range),
        let digit = Range(match.range(at: 1), in: source),
        let level = Int(source[digit])
    else { return nil }
    return level
}
