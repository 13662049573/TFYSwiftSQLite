# Interactive Demo Feature Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-shot Demo script with an interactive UIKit catalog that independently demonstrates every public TFYSwiftSQLiteKit feature and can run all cases as an end-to-end check.

**Architecture:** `DemoModels.swift` owns demonstration schemas, `DemoCases.swift` owns isolated executable examples and formatted output, and `ViewController.swift` owns navigation and rendering. Each case deletes only its declared Demo databases before execution and throws unexpected errors to one result screen.

**Tech Stack:** Swift 5.9, UIKit, Foundation, TFYSwiftSQLiteKit, XCTest/SPM, xcodebuild.

---

## File map

- Create `TFYSwiftSQLite/demoClass/DemoCases.swift`: metadata, grouping, isolation, examples, run-all summary.
- Modify `TFYSwiftSQLite/demoClass/DemoModels.swift`: focused schemas needed by the examples.
- Replace `TFYSwiftSQLite/demoClass/ViewController.swift`: grouped catalog and result screen.
- Modify `TFYSwiftSQLite.xcodeproj/project.pbxproj` only if its synchronized group does not compile the new file automatically.

### Task 1: Add complete demonstration schemas

**Files:**
- Modify: `TFYSwiftSQLite/demoClass/DemoModels.swift`

- [ ] **Step 1: Add focused models**

Add these models while retaining the existing migration models:

```swift
struct DemoProfile: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id = 0
    @TFYIndex var username = ""
    @TFYUnique var email = ""
    @TFYDefault("guest") var nickname = ""
    var age = 0
    var note: String?
    @TFYIgnore var memoryOnly = ""
    @TFYColumn(storageStrategy: .json) var address = DemoAddress()
    static var tableName: String { "demo_profile" }
    static var databaseName: String { "demo_catalog_main" }
    static let usernameField = field("username", as: String.self)
    static let ageField = field("age", as: Int.self)
    static let noteField = field("note", as: String?.self)
}

struct DemoAutoID: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id = 0
    static var databaseName: String { "demo_catalog_edge" }
}

struct DemoLedger: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id = 0
    var account = ""
    var amount = 0.0
    static var databaseName: String { "demo_catalog_transactions" }
}
```

- [ ] **Step 2: Build the Demo target**

Run `xcodebuild -project TFYSwiftSQLite.xcodeproj -scheme TFYSwiftSQLite -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

Expected: `** BUILD SUCCEEDED **`.

### Task 2: Build the case catalog and execution harness

**Files:**
- Create: `TFYSwiftSQLite/demoClass/DemoCases.swift`

- [ ] **Step 1: Define metadata and isolation**

```swift
struct DemoCase: Identifiable {
    let id: String
    let section: String
    let title: String
    let detail: String
    let databases: [String]
    let run: @Sendable () async throws -> [String]
}

struct DemoSection { let title: String; let cases: [DemoCase] }

enum DemoCatalog {
    static let sections: [DemoSection] = buildSections()
    static func prepare(_ names: [String]) throws {
        TFYSwiftDatabaseCenter.shared.closeAll()
        for name in names { try TFYSwiftDatabaseCenter.shared.removeDatabase(named: name) }
    }
}
```

Add compact row, migration-report, and benchmark formatters only.

- [ ] **Step 2: Add schema and migration cases**

Execute `LegacyUser.createTable()`, insert legacy data, migrate with `User.createTable()`, rerun for idempotency, and print reports and journal rows. Separately execute `LegacyAuditEvent` to `AuditEvent` rebuild migration and verify transformed JSON data.

- [ ] **Step 3: Add CRUD and query cases**

Cover single/batch insert, `insertOrReplace`, primary-key fetch, update, instance delete, primary-key delete, raw bound predicates, dynamic and typed fields, AND/OR/NOT, NULL, IN, `like`, literal `contains`, `starts`, sorting, pagination, `count`, and `exists`. Unexpected results throw `TFYSwiftDBError.invalidQuery`.

- [ ] **Step 4: Add transaction and multi-database cases**

Demonstrate commit, intentional rollback, and nested savepoint rollback. Verify stored rows after each stage. Open two database names, print distinct paths and configuration, close, and reopen one connection.

- [ ] **Step 5: Add low-level SQLite and logging cases**

Demonstrate `execute`, `prepare`, statement reuse, `query`, `scalar`, `pragmaTableInfo`, `pragmaIndexList`, `tableExists`, and `lastInsertedRowID`. Check default log redaction, then `.full`; always restore logging using `defer { TFYSwiftDBRuntime.setSQLLogger(nil) }`.

- [ ] **Step 6: Add expected-error, benchmark, maintenance, and run-all cases**

Catch and label unique-index, binding-count, unknown-field, delete-without-predicate, and configuration-conflict errors. Run small read/write benchmarks and require positive throughput. Demonstrate close/remove and absence of `.db`, `-wal`, and `-shm`. `runAll()` executes every non-run-all case, catches failures independently, and prints passed/failed counts and titles.

- [ ] **Step 7: Build the Demo target**

Run the Task 1 xcodebuild command. Expected: `** BUILD SUCCEEDED **`.

### Task 3: Replace the one-shot UI

**Files:**
- Replace: `TFYSwiftSQLite/demoClass/ViewController.swift`

- [ ] **Step 1: Implement grouped catalog**

Make `ViewController` a `UITableViewController`. Use `DemoCatalog.sections` for section/row counts, headers, and subtitle cells. Add a navigation bar “运行全部” button.

- [ ] **Step 2: Implement result screen**

Add private `DemoResultViewController` with a read-only monospaced `UITextView`, activity indicator, and “重新运行” button. Run the case in a `Task`, join returned lines with newlines, render unexpected errors with `❌`, and disable rerun during execution. Keep all UIKit mutation main-actor isolated.

- [ ] **Step 3: Build and smoke-test**

Build with xcodebuild. Launch an available iOS Simulator and verify grouped rows, one normal case, one expected-error case, rerun, and run-all with zero failures.

### Task 4: Final regression verification

**Files:**
- Verify: all Demo files and existing package tests.

- [ ] **Step 1: Run package tests**

Run `swift test`. Expected: 23 tests, 0 failures.

- [ ] **Step 2: Run release and concurrency builds**

Run `swift build -c release` and `swift build -Xswiftc -warn-concurrency -Xswiftc -strict-concurrency=complete`.

Expected: both complete without warnings or errors.

- [ ] **Step 3: Run final Xcode build and diff check**

Run the Task 1 xcodebuild command, followed by `git diff --check`.

Expected: Xcode build succeeds and diff check emits no output.
