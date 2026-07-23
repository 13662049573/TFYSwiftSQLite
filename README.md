# TFYSwiftSQLiteKit

基于 **SQLite3** 的轻量 Swift ORM：用 **Codable + 属性包装器** 描述表结构，自动生成建表 / 增量迁移 SQL，并提供常用 CRUD。数据库文件由 `TFYSwiftDatabaseCenter` 统一放在 Application Support 下的 `TFYSwiftSQLite` 目录。

示例应用与单元测试位于本仓库的 Xcode 工程 `TFYSwiftSQLite.xcodeproj`（目标 `TFYSwiftSQLite` / `TFYSwiftSQLiteTests`）。独立集成库时请使用下方 **Swift Package Manager** 或 **CocoaPods**。

## 功能概览

| 模块 | 说明 |
|------|------|
| **Annotation** | `@TFYColumn`、`@TFYPrimaryKey`、`@TFYIndex`、`@TFYUnique`、`@TFYDefault`、`@TFYIgnore` 等 |
| **ORM** | `TFYSwiftDBModel`、`TFYSwiftORM`（insert / update / delete / fetch） |
| **Schema** | `TFYSwiftAutoTable`、`TFYSwiftSchemaMigrator`、复合索引 `TFYCompositeIndex`、`TFYMigrationPolicy` |
| **Core** | `TFYSwiftDBConnection`（连接级线程安全、嵌套事务、WAL、busy timeout）、`TFYSwiftDBStatement`、`TFYSwiftDBError` |
| **Manager** | `TFYSwiftDatabaseCenter` 单例：按库名缓存连接、路径解析、删除库文件 |

面向生产环境的默认策略包括：同一连接上的 SQL 与事务串行化、5 秒锁等待、WAL 自动 checkpoint、外键开启、迁移整体事务化、SQL 日志绑定值默认脱敏，以及批量写入复用 prepared statement。

## 集成

### Swift Package Manager

在 Xcode：**File → Add Package Dependencies**，填入仓库 URL，选择产品 **TFYSwiftSQLiteKit**。

或在其它 Package 中依赖：

```swift
.package(url: "https://github.com/13662049573/TFYSwiftSQLite.git", from: "1.0.3"),
```

```swift
.target(
    name: "YourApp",
    dependencies: ["TFYSwiftSQLiteKit"]
)
```

### CocoaPods

```ruby
pod 'TFYSwiftSQLiteKit', '~> 1.0.3'
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

版本号与 `TFYSwiftSQLiteKit.podspec` 中 `s.version` 保持一致；发版时请打对应 git tag。

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

    static var tableName: String { "user" }
    static var databaseName: String { "demo_main" }
}
```

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

## 仓库结构（库源码）

```
TFYSwiftSQLite/TFYSwiftSQLiteKit/
├── Annotation/       # 列注解与属性包装器
├── Core/             # 连接、语句、错误
├── Manager/          # TFYSwiftDatabaseCenter
├── ORM/              # 模型协议、ORM、表构建
├── Reflection/       # 反射与 schema
├── Schema/           # 迁移、索引、AutoTable
└── Utils/            # 类型映射、benchmark 等
```

## 发布说明

- Swift Package：由 `Package.swift` 暴露单一产品 `TFYSwiftSQLiteKit`
- CocoaPods：由 `TFYSwiftSQLiteKit.podspec` 直接收录 `TFYSwiftSQLite/TFYSwiftSQLiteKit` 下全部 Swift 文件
- 示例 app / tests / benchmark 仍位于 `TFYSwiftSQLite.xcodeproj`

## 质量验证

Swift Package 已包含测试目标，本地与 CI 使用同一入口：

```bash
swift test
swift build -c release
```

当前测试覆盖 CRUD、批量写入、分页与计数、唯一索引、多数据库隔离、迁移与重建、日志脱敏、绑定参数校验，以及并发事务隔离。

## 系统要求

- Swift 5.9+
- **Swift Package Manager**：iOS 13+、macOS 13+、
- **CocoaPods**：iOS 15+、macOS 13.5+、
- 示例 Xcode 工程内应用目标的 **IPHONEOS_DEPLOYMENT_TARGET** 可能与上述不同，以工程设置为准

## 许可

见仓库根目录 [LICENSE](LICENSE)（MIT）。
