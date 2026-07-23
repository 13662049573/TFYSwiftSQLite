# TFYSwiftSQLiteKit

基于 **SQLite3** 的轻量 Swift ORM：用 **Codable + 属性包装器** 描述表结构，自动生成建表 / 增量迁移 SQL，并提供常用 CRUD。数据库文件由 `TFYSwiftDatabaseCenter` 统一放在用户 Library 下的 `TFYSwiftSQLite` 目录。

示例应用与单元测试位于本仓库的 Xcode 工程 `TFYSwiftSQLite.xcodeproj`（目标 `TFYSwiftSQLite` / `TFYSwiftSQLiteTests`）。独立集成库时请使用下方 **Swift Package Manager** 或 **CocoaPods**。

**当前版本：`1.0.5`**

## 功能概览

| 模块 | 说明 |
|------|------|
| **Annotation** | `@TFYColumn`、`@TFYPrimaryKey`、`@TFYIndex`、`@TFYUnique`、`@TFYDefault`、`@TFYIgnore` 等 |
| **ORM** | `TFYSwiftDBModel`、`TFYSwiftORM`（insert / update / delete / fetch）、类型安全 `TFYQuery` |
| **Schema** | `TFYSwiftAutoTable`、`TFYSwiftSchemaMigrator`、复合索引 `TFYCompositeIndex`、`TFYMigrationPolicy` |
| **Core** | `TFYSwiftDBConnection`（连接级线程安全、嵌套事务、WAL、busy timeout）、`TFYSwiftDBStatement`、`TFYSwiftDBError` |
| **Manager** | `TFYSwiftDatabaseCenter` 单例：按库名缓存连接、路径解析、删除库文件 |
| **Utils** | `TFYSwiftTypeMapper`（含 `Date` / `Data` / `Bool` 往返）、`TFYSwiftBenchmark` |

面向生产环境的默认策略包括：同一连接上的 SQL 与事务串行化、5 秒锁等待、WAL 自动 checkpoint、外键开启、迁移整体事务化、SQL 日志绑定值默认脱敏，以及批量写入复用 prepared statement。

库不采集数据、不联网，随 SPM 与 CocoaPods 分发 Privacy Manifest。

## 集成

### Swift Package Manager

在 Xcode：**File → Add Package Dependencies**，填入仓库 URL，选择产品 **TFYSwiftSQLiteKit**。

或在其它 Package 中依赖：

```swift
.package(url: "https://github.com/13662049573/TFYSwiftSQLite.git", from: "1.0.5"),
```

```swift
.target(
    name: "YourApp",
    dependencies: ["TFYSwiftSQLiteKit"]
)
```

### CocoaPods

```ruby
pod 'TFYSwiftSQLiteKit', '~> 1.0.5'
```

`TFYSwiftSQLiteKit` 的 pod 会按库当前目录结构收录以下源码目录，并自动链接 `sqlite3`：

- `Annotation`
- `Core`
- `Manager`
- `ORM`
- `Reflection`
- `Schema`
- `Utils`

当前 CocoaPods 形态仍然是一个完整 runtime pod；由于库内部存在跨目录引用，`podspec` 里保留了按文件夹维护的源码清单，并在注释中标明内部依赖关系，方便后续继续拆边界。

版本号与 `TFYSwiftSQLiteKit.podspec` 中 `s.version` 保持一致；发版时请打对应 git tag（例如 `1.0.5`）。

## 快速上手

### 1. 定义模型

遵循 `TFYSwiftDBModel`（`Codable` + `init()`），按需重写 `tableName`、`databaseName`、`compositeIndexes`、`migrationPolicy`。

```swift
import TFYSwiftSQLiteKit

struct User: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYIndex
    var username: String = ""

    @TFYUnique
    var email: String = ""

    var age: Int = 0
    var createdAt: Date = Date()
    var avatar: Data = Data()
    var isActive: Bool = true

    static var tableName: String { "user" }
    static var databaseName: String { "demo_main" }
}
```

标量类型支持 `Int*` / `UInt*` / `Bool` / `Double` / `Float` / `String` / `Data` / `Date`（`Date` 以 `timeIntervalSinceReferenceDate` 存为 REAL）。嵌套 `Codable` 请使用 `@TFYColumn(storageStrategy: .json)`。

### 2. 建表 / 迁移

首次或模型变更后调用（内部会执行增量迁移）：

```swift
try User.createTable()
// 或
try TFYSwiftORM.createTable(User.self)
```

### 3. CRUD

```swift
var u = User()
u.username = "alice"
try u.insert()

let all = try User.fetchAll()
let one = try User.fetch(byPrimaryKey: 1)
try u.update()
try u.delete()
```

条件查询使用 SQL 片段与绑定参数（见 `TFYSwiftORM.fetchAll(_:where:bindings:)`）。

### 4. 类型安全查询

业务代码优先使用类型安全查询，避免手写字段名：

```swift
let adults = try User.fetchAll(
    User.query()
        .where(User.fields.age >= 18)
        .orderBy(User.fields.age.descending())
        .limit(20)
)
```

`delete(_ query:)` 必须包含真实谓词；只有排序或分页条件时会拒绝执行，防止误删整表。

`contains` / `starts(with:)` 按字面量匹配 `%`、`_` 和 `\`；需要自行使用 SQL 通配符时请调用 `like(_:)`。

### 5. 数据库运行参数

默认配置适合大多数移动端业务，也可以在首次打开数据库时覆盖：

```swift
let configuration = TFYSwiftDBConfiguration(
    foreignKeysEnabled: true,
    journalMode: .wal,
    synchronousMode: .normal,
    busyTimeout: 8,
    walAutoCheckpoint: 1_000
)

let connection = try TFYSwiftDatabaseCenter.shared.open(
    named: "business",
    configuration: configuration
)
```

同名数据库已打开后不能切换配置；请先调用 `close(named:)`，再使用新配置打开。

### 6. SQL 观测与隐私

绑定值默认脱敏，适合接入生产日志或性能监控：

```swift
TFYSwiftDBRuntime.setSQLLogger { event in
    print(event.sql, event.duration, event.succeeded)
}
```

只有在受控开发环境中才应显式使用 `bindingPolicy: .full`。日志回调应保持轻量，避免执行阻塞操作。

### 7. 事务

```swift
try User.transaction {
    try firstUser.insert()
    try secondUser.insert()
}
```

事务支持嵌套，内部通过 savepoint 实现。同一连接上的其他线程会等待当前事务完成，避免写入被意外纳入其他线程的事务。

### 8. 迁移策略

`.safe` 只执行 SQLite 可安全原地完成的新增列和索引；类型变化、删列等情况写入报告警告，不破坏原表。需要重建时显式使用 `.rebuildTable`：

```swift
static var migrationPolicy: TFYMigrationPolicy { .rebuildTable }

static func renamedColumns(
    for schema: TFYSwiftModelSchema,
    existingColumns: [TFYSQLiteTableColumnInfo]
) throws -> [String: String] {
    ["displayName": "nickname"] // 新列名: 旧列名
}
```

新增的必填列必须有 `@TFYDefault`、重命名来源或 `rebuildExpressions`；否则迁移会回滚并报告冲突，避免静默写入 NULL。生产升级前仍应备份数据库并在真实数据副本上演练迁移。

### 9. 错误处理与原始 SQL

所有数据库 API 都通过 `throws` 返回 `TFYSwiftDBError`。类型安全查询会绑定业务值；接收外部输入时不要把它直接拼进 `where`、`orderBy`、`TFYPredicate(sql:)` 或迁移表达式，这些接口是为受信任 SQL 片段保留的。

## 示例 Demo（TableView）

仓库内 `TFYSwiftSQLite/demoClass` 提供可交互的功能目录：

- 分组 `UITableView` 覆盖连接、建表、CRUD、查询、JSON/类型、事务、迁移、底层 API、Benchmark
- 导航栏 **Run All** 一键跑完全部用例；结果页展示 PASS/耗时
- 设置环境变量 `DEMO_VERIFY=1` 启动时自动全量自检，结果写入 App Documents/`demo_verify.txt`

```
TFYSwiftSQLite/demoClass/
├── ViewController.swift              # 功能目录
├── DemoCatalog.swift                 # 全部演示用例
├── DemoResultViewController.swift    # 结果输出
└── DemoModels.swift                  # User / Order / Audit / TypeSample
```

## 仓库结构（库源码）

```
TFYSwiftSQLite/TFYSwiftSQLiteKit/
├── Annotation/       # 列注解与属性包装器
├── Core/             # 连接、语句、错误、SQL 日志
├── Manager/          # TFYSwiftDatabaseCenter
├── ORM/              # 模型协议、ORM、表构建、Query
├── Reflection/       # 反射与 schema
├── Schema/           # 迁移、索引、AutoTable
└── Utils/            # 类型映射、benchmark 等
```

## 版本历史

### 1.0.5

- 修复 `Date` / `Data` ORM 解码：识别 `Foundation.Date` / `Foundation.Data`，并用 `timeIntervalSinceReferenceDate` 策略解码
- 示例 App 增加分组 TableView 全功能 Demo（含 Run All / `DEMO_VERIFY`）
- 示例 App 补充 `UILaunchScreen`，修复现代机型上下黑边
- CocoaPods / README 同步至 `1.0.5`

### 1.0.4

- Privacy Manifest（`PrivacyInfo.xcprivacy`）随 SPM / CocoaPods 分发
- 强化迁移、查询边界与 SQL 日志脱敏相关行为
- macOS deployment target 与文档对齐为 15.0（CocoaPods）

## 发布说明

- Swift Package：由 `Package.swift` 暴露单一产品 `TFYSwiftSQLiteKit`
- CocoaPods：由 `TFYSwiftSQLiteKit.podspec` 直接收录 `TFYSwiftSQLite/TFYSwiftSQLiteKit` 下全部 Swift 文件
- 两种分发方式均包含 `PrivacyInfo.xcprivacy`，版本号以 podspec 和 git tag 为准
- 示例 app / tests / benchmark 仍位于 `TFYSwiftSQLite.xcodeproj`

发版检查清单：

```bash
# 1. 确认 podspec / README 版本一致
# 2. 跑测试
swift test
# 3. 提交后打 tag 并推送
git tag 1.0.5
git push origin 1.0.5
# 4. （可选）推 CocoaPods trunk
pod trunk push TFYSwiftSQLiteKit.podspec
```

## 质量验证

Swift Package 已包含测试目标，本地与 CI 使用同一入口：

```bash
swift test
swift build -c release
```

当前测试覆盖 CRUD、批量写入、分页与计数、唯一索引、多数据库隔离、迁移与重建、日志脱敏、绑定参数校验、NULL/LIKE 边界、整数溢出，以及并发事务隔离。

## 系统要求

- Swift 5.9+
- iOS 15+
- macOS 15+（CocoaPods）；SPM `Package.swift` 平台下限见仓库声明
- 示例 Xcode 工程内应用目标的 **IPHONEOS_DEPLOYMENT_TARGET** 可能与上述不同，以工程设置为准

## 许可

见仓库根目录 [LICENSE](LICENSE)（MIT）。
