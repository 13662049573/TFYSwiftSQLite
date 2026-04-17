# TFYSwiftSQLiteKit

基于 **SQLite3** 的轻量 Swift ORM：用 **Codable + 属性包装器** 描述表结构，自动生成建表 / 增量迁移 SQL，并提供常用 CRUD。数据库文件由 `TFYSwiftDatabaseCenter` 统一放在 Application Support 下的 `TFYSwiftSQLite` 目录。

示例应用与单元测试位于本仓库的 Xcode 工程 `TFYSwiftSQLite.xcodeproj`（目标 `TFYSwiftSQLite` / `TFYSwiftSQLiteTests`）。独立集成库时请使用下方 **Swift Package Manager** 或 **CocoaPods**。

## 功能概览

| 模块 | 说明 |
|------|------|
| **Annotation** | `@TFYColumn`、`@TFYPrimaryKey`、`@TFYIndex`、`@TFYUnique`、`@TFYDefault`、`@TFYIgnore` 等 |
| **ORM** | `TFYSwiftDBModel`、`TFYSwiftORM`（insert / update / delete / fetch） |
| **Schema** | `TFYSwiftAutoTable`、`TFYSwiftSchemaMigrator`、复合索引 `TFYCompositeIndex`、`TFYMigrationPolicy` |
| **Core** | `TFYSwiftDBConnection`（WAL、foreign_keys）、`TFYSwiftDBStatement`、`TFYSwiftDBError` |
| **Manager** | `TFYSwiftDatabaseCenter` 单例：按库名缓存连接、路径解析、删除库文件 |

## 集成

### Swift Package Manager

在 Xcode：**File → Add Package Dependencies**，填入仓库 URL，选择产品 **TFYSwiftSQLiteKit**。

或在其它 Package 中依赖：

```swift
.package(url: "https://github.com/13662049573/TFYSwiftSQLite.git", from: "1.0.0"),
```

```swift
.target(
    name: "YourApp",
    dependencies: ["TFYSwiftSQLiteKit"]
)
```

### CocoaPods

```ruby
pod 'TFYSwiftSQLiteKit', '~> 1.0.0'
```

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

## 仓库结构（库源码）

```
TFYSwiftSQLite/TFYSwiftSQLiteKit/
├── Annotation/       # 列注解与属性包装器
├── Core/               # 连接、语句、错误
├── Manager/            # TFYSwiftDatabaseCenter
├── ORM/                # 模型协议、ORM、表构建
├── Reflection/         # 反射与 schema
├── Schema/             # 迁移、索引、AutoTable
└── Utils/              # 类型映射等
```

## 系统要求

- Swift 5.0+
- **SPM / CocoaPods**：iOS 13+、macOS 10.15+、tvOS 13+、watchOS 6+（与 `Package.swift`、`podspec` 一致）
- 示例 Xcode 工程内应用目标的 **IPHONEOS_DEPLOYMENT_TARGET** 可能与上述不同，以工程设置为准

## 许可

见仓库根目录 [LICENSE](LICENSE)（MIT）。
