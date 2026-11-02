import Foundation
import SwiftData

enum GrowthSchema {
    static let models: [any PersistentModel.Type] = [
        Goal.self,
        Phase.self,
        Checkpoint.self,
        ResourceLink.self,
        ProgressEntry.self,
        HabitLog.self,
        Reminder.self,
        ActivityEvent.self,
        JournalEntry.self,
        Reflection.self,
        CheckInSchedule.self,
        CheckInSession.self,
        CheckInItem.self,
        Recalibration.self
    ]
}

enum ModelContainerFactory {
    /// Local store only. Models avoid unique constraints so CloudKit can be enabled later.
    static let shared: ModelContainer = make()

    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(GrowthSchema.models)
        let configuration = ModelConfiguration(
            "Growth",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Growth store: \(error)")
        }
    }
}
