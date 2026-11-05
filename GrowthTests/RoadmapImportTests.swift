import XCTest
import SwiftData
@testable import Growth

final class RoadmapOutlineTests: XCTestCase {
    func testBoldNumberedLinesBecomeSeparatePhases() {
        let blocks = [
            DocxBlock(kind: .paragraph, text: "4. Phase 2 — MLOps | 4 weeks", leadIsBold: true),
            DocxBlock(kind: .heading(2), text: "Made With ML", leadIsBold: false),
            DocxBlock(kind: .listItem, text: "Packaging", leadIsBold: false),
            DocxBlock(kind: .paragraph, text: "5. Phase 3 — NLP | 6 weeks", leadIsBold: true),
            DocxBlock(kind: .heading(3), text: "Transformers", leadIsBold: false),
            DocxBlock(kind: .listItem, text: "Attention", leadIsBold: false),
            DocxBlock(kind: .paragraph, text: "Course: https://example.com/nlp", leadIsBold: false)
        ]
        let draft = RoadmapOutline.draft(from: blocks)
        XCTAssertEqual(draft.phases.map(\.title), [
            "4. Phase 2 — MLOps · 4 weeks",
            "5. Phase 3 — NLP · 6 weeks"
        ])
        XCTAssertEqual(draft.phases[0].checkpoints.map(\.title), ["Made With ML"])
        XCTAssertEqual(draft.phases[0].checkpoints[0].notes, "Packaging")
        XCTAssertEqual(draft.phases[1].checkpoints[0].links.map(\.url), ["https://example.com/nlp"])
        XCTAssertEqual(draft.confidence, .high)
    }

    func testFlatBulletsBecomeOnePhase() {
        let blocks = [
            DocxBlock(kind: .listItem, text: "Read", leadIsBold: false),
            DocxBlock(kind: .listItem, text: "Build", leadIsBold: false)
        ]
        let draft = RoadmapOutline.draft(from: blocks)
        XCTAssertEqual(draft.confidence, .low)
        XCTAssertEqual(draft.phases.map(\.title), ["Plan"])
        XCTAssertEqual(draft.phases[0].checkpoints.map(\.title), ["Read", "Build"])
    }

    func testProseDoesNotInventAPlan() {
        let blocks = [
            DocxBlock(kind: .paragraph, text: "This is a paragraph about learning.", leadIsBold: false),
            DocxBlock(kind: .paragraph, text: "It never becomes a checklist.", leadIsBold: false)
        ]
        let draft = RoadmapOutline.draft(from: blocks)
        XCTAssertEqual(draft.confidence, .none)
        XCTAssertTrue(draft.phases.isEmpty)
        XCTAssertFalse(draft.canImport)
    }

    func testCurriculumDocumentSplitsEveryPhase() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AI_ML_Engineering_Curriculum.docx")
        let draft = try RoadmapImport.parse(Data(contentsOf: url))
        let titles = draft.phases.map(\.title)
        XCTAssertEqual(draft.confidence, .high, titles.joined(separator: "\n"))
        XCTAssertTrue(draft.suggestedTitle.contains("CURRICULUM"), draft.suggestedTitle)
        XCTAssertEqual(titles.count, 12, titles.joined(separator: "\n"))
        XCTAssertTrue(titles.contains { $0.contains("Phase 0") && $0.contains("Mathematics") })
        XCTAssertTrue(titles.contains { $0.contains("Phase 3") && $0.contains("NLP") })
        XCTAssertTrue(titles.contains { $0.contains("Phase 5") && $0.contains("Production") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("8. Parallel") })
        XCTAssertTrue(titles.contains { $0.contains("Portfolio") })
        let portfolio = try XCTUnwrap(draft.phases.first { $0.title.contains("Portfolio") })
        XCTAssertEqual(portfolio.checkpoints.count, 4)

        let math = try XCTUnwrap(draft.phases.first { $0.title.contains("Phase 0") })
        XCTAssertEqual(math.checkpoints.map(\.title), [
            "A. 3Blue1Brown — Essence of Linear Algebra (free)",
            "B. 3Blue1Brown — Essence of Calculus (free)",
            "C. StatQuest — selected videos (free)"
        ])
        let algebra = math.checkpoints[0]
        XCTAssertTrue(algebra.notes.contains("Vectors"))
        XCTAssertTrue(algebra.links.contains { $0.url.contains("3blue1brown.com") })
        XCTAssertFalse(math.checkpoints.contains { $0.title.contains("Andrew Ng") })

        let overview = draft.phases[0]
        XCTAssertTrue(overview.checkpoints.contains { $0.title.contains("PyTorch") })
        XCTAssertGreaterThan(draft.checkpointCount, 40)
        XCTAssertLessThan(draft.checkpointCount, 120)
    }

    func testStoredDocxWithoutStylesStillReadsHeadings() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
              <w:r><w:t>Ship the essay</w:t></w:r>
            </w:p>
            <w:p>
              <w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>
              <w:r><w:t>Outline the argument</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let archive = StoredZip.archive([("word/document.xml", Data(xml.utf8))])
        let draft = try RoadmapImport.parse(archive)
        XCTAssertEqual(draft.phases.map(\.title), ["Ship the essay"])
        XCTAssertEqual(draft.phases[0].checkpoints.map(\.title), ["Outline the argument"])
    }

    func testCorruptFileIsRejected() {
        XCTAssertThrowsError(try RoadmapImport.parse(Data("hello".utf8)))
    }
}

@MainActor
final class RoadmapImportRepositoryTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = ModelContainerFactory.make(inMemory: true)
    }

    private var context: ModelContext { container.mainContext }

    func testImportReplacesTheExistingPlan() throws {
        var goalDraft = GoalDraft()
        goalDraft.title = "Learn ML"
        goalDraft.type = .milestone
        let goal = try GoalRepository(context: context).create(goalDraft)
        _ = try PlanRepository(context: context).addPhase(to: goal, title: "Old")

        let imported = RoadmapDraft(
            suggestedTitle: "",
            summary: "",
            phases: [
                RoadmapPhaseDraft(
                    title: "Phase 0",
                    notes: "Build intuition",
                    checkpoints: [
                        RoadmapCheckpointDraft(
                            title: "Linear algebra",
                            notes: "Vectors",
                            links: [RoadmapLinkDraft(title: "Course · 3blue1brown.com", url: "https://www.3blue1brown.com/topics/linear-algebra")]
                        )
                    ]
                )
            ],
            warnings: [],
            confidence: .high
        )
        try PlanRepository(context: context).importRoadmap(imported, into: goal, mode: .replace)
        XCTAssertEqual(goal.sortedPhases.map(\.title), ["Phase 0"])
        XCTAssertEqual(goal.sortedPhases[0].notes, "Build intuition")
        XCTAssertEqual(goal.sortedPhases[0].sortedCheckpoints.map(\.title), ["Linear algebra"])
        XCTAssertEqual(goal.sortedPhases[0].sortedCheckpoints[0].notes, "Vectors")
        XCTAssertEqual(goal.sortedPhases[0].sortedCheckpoints[0].activeResources.map(\.urlString), [
            "https://www.3blue1brown.com/topics/linear-algebra"
        ])
        XCTAssertEqual(goal.progressPresentation().fraction, 0)
        let events = (goal.activityEvents ?? []).map(\.type)
        XCTAssertTrue(events.contains(.roadmapEdited))
    }
}

private enum StoredZip {
    static func archive(_ files: [(String, Data)]) -> Data {
        var locals = Data()
        var central = Data()
        for (name, content) in files {
            let nameData = Data(name.utf8)
            let localOffset = UInt32(locals.count)
            var local = Data()
            append(&local, UInt32(0x04034b50))
            append(&local, UInt16(20))
            append(&local, UInt16(1 << 11))
            append(&local, UInt16(0))
            append(&local, UInt16(0))
            append(&local, UInt16(0))
            append(&local, UInt32(0))
            append(&local, UInt32(content.count))
            append(&local, UInt32(content.count))
            append(&local, UInt16(nameData.count))
            append(&local, UInt16(0))
            local.append(nameData)
            local.append(content)
            locals.append(local)

            var header = Data()
            append(&header, UInt32(0x02014b50))
            append(&header, UInt16(20))
            append(&header, UInt16(20))
            append(&header, UInt16(1 << 11))
            append(&header, UInt16(0))
            append(&header, UInt16(0))
            append(&header, UInt16(0))
            append(&header, UInt32(0))
            append(&header, UInt32(content.count))
            append(&header, UInt32(content.count))
            append(&header, UInt16(nameData.count))
            append(&header, UInt16(0))
            append(&header, UInt16(0))
            append(&header, UInt16(0))
            append(&header, UInt16(0))
            append(&header, UInt32(0))
            append(&header, localOffset)
            header.append(nameData)
            central.append(header)
        }

        var end = Data()
        append(&end, UInt32(0x06054b50))
        append(&end, UInt16(0))
        append(&end, UInt16(0))
        append(&end, UInt16(files.count))
        append(&end, UInt16(files.count))
        append(&end, UInt32(central.count))
        append(&end, UInt32(locals.count))
        append(&end, UInt16(0))
        locals.append(central)
        locals.append(end)
        return locals
    }

    private static func append(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func append(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
