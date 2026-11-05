import Foundation

enum RoadmapConfidence: Equatable, Sendable {
    case high
    case low
    case none
}

struct RoadmapLinkDraft: Equatable, Sendable {
    var title: String
    var url: String
}

struct RoadmapCheckpointDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var notes: String
    var links: [RoadmapLinkDraft] = []
}

struct RoadmapPhaseDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var notes: String
    var checkpoints: [RoadmapCheckpointDraft]
    var links: [RoadmapLinkDraft] = []
}

struct RoadmapDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var suggestedTitle: String
    var summary: String
    var phases: [RoadmapPhaseDraft]
    var warnings: [String]
    var confidence: RoadmapConfidence

    var checkpointCount: Int {
        phases.reduce(0) { $0 + $1.checkpoints.count }
    }

    var canImport: Bool {
        confidence != .none && phases.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct DocxBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case listItem
        case paragraph
        case table([[String]])
    }

    var kind: Kind
    var text: String
    /// The first run of text is bold. Heading styles often are not bold runs.
    var leadIsBold: Bool
}

enum RoadmapOutline {
    static let maxPhases = 40
    static let maxCheckpoints = 50
    static let noteLimit = 700

    static func draft(from blocks: [DocxBlock]) -> RoadmapDraft {
        var titleLines: [String] = []
        var summaryLines: [String] = []
        var phases: [MutablePhase] = []
        var pendingTitle: String?
        var pendingNotes: [String] = []
        var pendingLinks: [RoadmapLinkDraft] = []
        var foldedDetail = false
        var usedHeading = false
        var usedBoldSection = false
        var truncated = false

        func flushPending() {
            guard let title = pendingTitle, !phases.isEmpty else {
                pendingTitle = nil
                pendingNotes = []
                pendingLinks = []
                return
            }
            if !pendingNotes.isEmpty || !pendingLinks.isEmpty {
                appendCheckpoint(
                    title: title,
                    notes: pendingNotes,
                    links: pendingLinks,
                    to: &phases[phases.count - 1],
                    truncated: &truncated
                )
            }
            pendingTitle = nil
            pendingNotes = []
            pendingLinks = []
        }

        for block in blocks {
            if case .table(let rows) = block.kind {
                let lines = rows.map { row in
                    row.map { collapse($0) }.filter { !$0.isEmpty }.joined(separator: " · ")
                }.filter { !$0.isEmpty }
                if lines.isEmpty { continue }
                if phases.isEmpty {
                    summaryLines.append(contentsOf: lines)
                } else if pendingTitle != nil {
                    pendingNotes.append(contentsOf: lines)
                    foldedDetail = true
                } else if !phases[phases.count - 1].checkpoints.isEmpty {
                    phases[phases.count - 1].checkpoints[phases[phases.count - 1].checkpoints.count - 1].notes.append(contentsOf: lines)
                    foldedDetail = true
                } else {
                    phases[phases.count - 1].notes.append(contentsOf: lines)
                }
                continue
            }

            let text = collapse(block.text)
            guard !text.isEmpty else { continue }

            if isPhaseStart(block, text: text) {
                flushPending()
                if phases.count >= maxPhases {
                    truncated = true
                    continue
                }
                if case .heading = block.kind {
                    usedHeading = true
                } else {
                    usedBoldSection = true
                }
                phases.append(MutablePhase(title: cleanTitle(text)))
                continue
            }

            if phases.isEmpty {
                if isMasthead(block, text: text), summaryLines.isEmpty {
                    titleLines.append(text)
                } else {
                    summaryLines.append(text)
                }
                continue
            }

            if case .heading(let level) = block.kind, level >= 2 {
                flushPending()
                pendingTitle = cleanTitle(text)
                usedHeading = true
                continue
            }

            if isTaskLine(block, text: text), pendingTitle == nil {
                appendCheckpoint(title: text, notes: [], links: [], to: &phases[phases.count - 1], truncated: &truncated)
                continue
            }

            if let link = RoadmapLinks.parse(text), pendingTitle == nil, isMostlyLink(text) {
                if phases[phases.count - 1].checkpoints.isEmpty {
                    phases[phases.count - 1].links.append(link)
                } else {
                    let last = phases[phases.count - 1].checkpoints.count - 1
                    phases[phases.count - 1].checkpoints[last].links.append(link)
                }
                continue
            }

            foldedDetail = true
            if pendingTitle != nil {
                if let link = RoadmapLinks.parse(text), isMostlyLink(text) {
                    pendingLinks.append(link)
                } else {
                    pendingNotes.append(text)
                }
            } else if !phases[phases.count - 1].checkpoints.isEmpty {
                let last = phases[phases.count - 1].checkpoints.count - 1
                if let link = RoadmapLinks.parse(text), isMostlyLink(text) {
                    phases[phases.count - 1].checkpoints[last].links.append(link)
                } else {
                    phases[phases.count - 1].checkpoints[last].notes.append(text)
                }
            } else if let link = RoadmapLinks.parse(text), isMostlyLink(text) {
                phases[phases.count - 1].links.append(link)
            } else {
                phases[phases.count - 1].notes.append(text)
            }
        }
        flushPending()

        if phases.isEmpty {
            let tasks = blocks.compactMap { block -> String? in
                let text = collapse(block.text)
                guard !text.isEmpty, isTaskLine(block, text: text) else { return nil }
                return text
            }
            if !tasks.isEmpty {
                var phase = MutablePhase(title: "Plan")
                for task in tasks {
                    appendCheckpoint(title: task, notes: [], links: [], to: &phase, truncated: &truncated)
                }
                phases = [phase]
                return finish(
                    titleLines: titleLines,
                    summaryLines: summaryLines,
                    phases: phases,
                    warnings: [
                        "No headings or numbered sections were found, so each bullet became a checkpoint.",
                        truncated ? "The rest of the document was left out so the plan stays readable." : nil
                    ].compactMap { $0 },
                    confidence: .low
                )
            }
            return finish(
                titleLines: titleLines,
                summaryLines: summaryLines,
                phases: [],
                warnings: ["Nothing in this document lined up with a plan. Headings, numbered sections, or a bullet list give it something to use."],
                confidence: .none
            )
        }

        var warnings: [String] = []
        if usedHeading || usedBoldSection {
            warnings.append("Heading 1 and bold numbered lines became phases. Smaller headings became checkpoints, and the bullets under them were saved as notes.")
        }
        if foldedDetail {
            warnings.append("You can rename or remove anything that should not be its own phase before importing.")
        }
        if truncated {
            warnings.append("The rest of the document was left out so the plan stays readable.")
        }
        let confidence: RoadmapConfidence = phases.contains { !$0.checkpoints.isEmpty } ? .high : .low
        return finish(
            titleLines: titleLines,
            summaryLines: summaryLines,
            phases: phases,
            warnings: warnings,
            confidence: confidence
        )
    }

    private static func finish(
        titleLines: [String],
        summaryLines: [String],
        phases: [MutablePhase],
        warnings: [String],
        confidence: RoadmapConfidence
    ) -> RoadmapDraft {
        var drafted = phases.map { phase in
            RoadmapPhaseDraft(
                title: String(phase.title.prefix(180)),
                notes: joined(phase.notes),
                checkpoints: phase.checkpoints.map { checkpoint in
                    RoadmapCheckpointDraft(
                        title: String(checkpoint.title.prefix(240)),
                        notes: joined(checkpoint.notes),
                        links: checkpoint.links
                    )
                },
                links: phase.links
            )
        }
        let summary = joined(summaryLines, limit: 500)
        if !summary.isEmpty, !drafted.isEmpty, drafted[0].notes.isEmpty {
            drafted[0].notes = summary
        }
        return RoadmapDraft(
            suggestedTitle: collapse(titleLines.joined(separator: " ")),
            summary: drafted.first?.notes == summary ? "" : summary,
            phases: drafted,
            warnings: warnings,
            confidence: confidence
        )
    }

    private static func appendCheckpoint(
        title: String,
        notes: [String],
        links: [RoadmapLinkDraft],
        to phase: inout MutablePhase,
        truncated: inout Bool
    ) {
        let cleaned = cleanTitle(title)
        guard !cleaned.isEmpty else { return }
        guard phase.checkpoints.count < maxCheckpoints else {
            truncated = true
            return
        }
        phase.checkpoints.append(MutableCheckpoint(title: cleaned, notes: notes, links: links))
    }

    private static func isPhaseStart(_ block: DocxBlock, text: String) -> Bool {
        if case .heading(let level) = block.kind, level <= 1 {
            return text.count <= 200
        }
        guard case .paragraph = block.kind, block.leadIsBold else { return false }
        if text.range(of: #"(?i)\bphase\s+\d"#, options: .regularExpression) != nil {
            return text.count <= 200
        }
        // A short bold numbered line is a section. A long one is a described task, often with commas.
        guard text.count <= 110 else { return false }
        if text.range(of: #"^\d{1,2}\.\s+\S"#, options: .regularExpression) != nil {
            return true
        }
        return text.range(of: #"^(?i)(phase|stage|module|part)\b"#, options: .regularExpression) != nil
    }

    private static func isMasthead(_ block: DocxBlock, text: String) -> Bool {
        guard block.leadIsBold, case .paragraph = block.kind, text.count <= 80 else { return false }
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upper = letters.filter(\.isUppercase).count
        return upper * 2 >= letters.count
    }

    private static func isTaskLine(_ block: DocxBlock, text: String) -> Bool {
        switch block.kind {
        case .listItem:
            return true
        case .paragraph:
            guard text.count < 280 else { return false }
            return text.range(of: #"^\d{1,2}[\.)]\s+\S"#, options: .regularExpression) != nil
        case .heading, .table:
            return false
        }
    }

    private static func isMostlyLink(_ text: String) -> Bool {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression) else { return false }
        let remainder = text.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.count < 48
    }

    private static func cleanTitle(_ text: String) -> String {
        collapse(text).replacingOccurrences(of: #"\s+\|\s+"#, with: " · ", options: .regularExpression)
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func joined(_ lines: [String], limit: Int = noteLimit) -> String {
        var result = ""
        for line in lines {
            let trimmed = collapse(line)
            guard !trimmed.isEmpty, result.split(separator: "\n").last.map(String.init) != trimmed else { continue }
            let next = result.isEmpty ? trimmed : result + "\n" + trimmed
            if next.count > limit {
                let room = max(0, limit - 1)
                return String(next.prefix(room)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
            result = next
        }
        return result
    }
}

enum RoadmapLinks {
    static func parse(_ text: String) -> RoadmapLinkDraft? {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression) else { return nil }
        var raw = String(text[range])
        while let last = raw.last, ".,);]".contains(last) {
            raw.removeLast()
        }
        guard let url = LinkURL.normalize(raw) else { return nil }
        let prefix = text[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":–-·| "))
        let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Link"
        let title = prefix.isEmpty ? host : "\(prefix) · \(host)"
        return RoadmapLinkDraft(title: String(title.prefix(80)), url: url)
    }
}

private struct MutablePhase {
    var title: String
    var notes: [String] = []
    var checkpoints: [MutableCheckpoint] = []
    var links: [RoadmapLinkDraft] = []
}

private struct MutableCheckpoint {
    var title: String
    var notes: [String]
    var links: [RoadmapLinkDraft]
}
