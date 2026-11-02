# Growth

Growth is a native iOS app for personal goals. You can keep a milestone or project plan, track a number up or down, log a habit, and write journal entries. Everything stays on the device.

## Requirements

- macOS with Xcode 16 or later
- iOS 18 or later

The project does not use a signing team. Xcode can run it on the simulator without an Apple Developer account.

## Run it

1. Open `Growth.xcodeproj`.
2. Select the **Growth** scheme.
3. Choose an iPhone simulator.
4. Press **Run** (⌘R).

The first launch is empty. Add a goal from Home or Goals, or a journal entry from the pencil button.

## What is included

- **Home** shows goals that are not started or in progress, plus upcoming reminders.
- **Goals** lists every goal, with search and a status filter. Types are milestone, project, number, and habit.
- **Journal** is a list you can search. An entry can stand alone or link to goals.
- Goal pages cover the plan, an activity timeline, reminders, reflections, and recalibration.
- An optional weekly check-in walks through active goals.
- Reminders use local notifications. If permission is denied, the reminder is still saved.

Paused and archived goals stay off Home. Deleting a goal hides it and keeps the activity history.

## Tests

The **Growth** scheme includes unit tests and a UI test. In Xcode, press **⌘U**, or from the project folder:

```sh
xcodebuild -scheme Growth -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use an iPhone simulator name that exists on your Mac.

## Data

Growth uses SwiftData and stores data only on the device. There is no account and no network sync. Records use stable IDs and soft deletes so CloudKit can be added later without replacing the model.
