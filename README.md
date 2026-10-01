<!--
//
//  README.md
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//
-->

# TFYSwiftSQLiteKit

基于 **SQLite3** 的轻量 Swift ORM：用 **Codable + 属性包装器** 描述表结构，自动生成建表 / 增量迁移 SQL，并提供常用 CRUD。数据库文件由 `TFYSwiftDatabaseCenter` 统一放在用户 Library 下的 `TFYSwiftSQLite` 目录。

示例应用与单元测试位于本仓库的 Xcode 工程 `TFYSwiftSQLite.xcodeproj`（目标 `TFYSwiftSQLite` / `TFYSwiftSQLiteTests`）。独立集成库时请使用下方 **Swift Package Manager** 或 **CocoaPods**。

**当前版本：`1.1.0`**（当前为本地待发布源码，尚未创建 tag 或发布 CocoaPods）

## 功能概览

| 模块 | 说明 |
|------|------|
| **Annotation** | `@TFYColumn`、`@TFYPrimaryKey`、`@TFYIndex`、`@TFYUnique`、`@TFYDefault`、`@TFYIgnore` 等 |
| **ORM** | `TFYSwiftDBModel`、`TFYSwiftORM`（insert / update / delete / fetch）、类型安全 `TFYQuery` |
| **Schema** | `TFYSwiftAutoTable`、`TFYSwiftSchemaMigrator`、复合索引 `TFYCompositeIndex`、`TFYMigrationPolicy` |
| **Core** | `TFYSwiftDBConnection`（连接级线程安全、嵌套事务、WAL、busy timeout、预编译查询与变更计数）、`TFYSwiftDBStatement`、`TFYSwiftDBError` |
| **Manager** | `TFYSwiftDatabaseCenter` 单例：按库名缓存连接、路径解析、删除库文件 |
| **Utils** | `TFYSwiftTypeMapper`（含 `Date` / `Data` / `Bool` 往返）、`TFYSwiftBenchmark` |

面向生产环境的默认策略包括：同一连接上的 SQL 与事务串行化、5 秒锁等待、WAL 自动 checkpoint、外键开启、迁移整体事务化、SQL 日志绑定值默认脱敏，以及批量写入复用 prepared statement。

库不采集数据、不联网，随 SPM 与 CocoaPods 分发 Privacy Manifest。

## Demo 应用

打开 `TFYSwiftSQLite.xcodeproj` 并运行 `TFYSwiftSQLite` scheme，即可使用可搜索的交互式示例目录。Demo 当前包含 10 个主题、44 个可独立运行的示例：

- 数据库连接、WAL 配置、路径管理、关闭生命周期与脱敏 SQL 日志
- 属性包装器建表、单列/复合索引、CRUD、分页和强类型查询
- JSON、可选值、Bool、Date、Data、Double 等类型往返
- 返回值事务、失败回滚、嵌套 Savepoint
- 不安全必填列迁移拒绝、默认值安全升级、重建迁移与迁移日志
- 原始 SQL、预编译执行/查询、列读取、变更计数和读写 Benchmark

点击任一条目会执行真实 SQLite 操作并显示成功状态、耗时及完整输出；结果支持重新运行和复制。“全部运行”会顺序执行 44 个示例并汇总失败项，“重置”仅删除 Demo 自己创建的数据库。

## 集成

### Swift Package Manager

在 Xcode：**File → Add Package Dependencies**，填入仓库 URL，选择产品 **TFYSwiftSQLiteKit**。

或在其它 Package 中依赖：

```swift
.package(url: "https://github.com/13662049573/TFYSwiftSQLite.git", from: "1.1.0"),
```

```swift
.target(
    name: "YourApp",
    dependencies: ["TFYSwiftSQLiteKit"]
)
```

### CocoaPods

```ruby
pod 'TFYSwiftSQLiteKit', '~> 1.1.0'
```

`TFYSwiftSQLiteKit` 的 Podspec 会逐文件显式收录库根目录下的全部 Swift 源码。明文后端链接 `sqlite3`，加密后端仅依赖 SQLCipher。默认使用 `Standard` 明文后端；`SQLCipher` subspec 使用加密后端。当前源码目录为：

- `Annotation`
- `Core`
- `Manager`
- `ORM`
- `Reflection`
- `Schema`
- `Utils`

当前 CocoaPods 形态仍然是一个完整 runtime pod；由于库内部存在跨目录引用，Podspec 与 Package 均逐文件声明源码和资源。发布前的一致性脚本会进行双向逐项检查，新增、遗漏或多余文件都会使验证失败，避免三处配置发生漂移。

版本号与 `TFYSwiftSQLiteKit.podspec` 中 `s.version` 保持一致；Swift Package Manager 使用同名 git tag 解析版本（例如 `1.1.0`）。Podspec 与 Package 均从 `TFYSwiftSQLite/TFYSwiftSQLiteKit` 收录完整源码，并打包同一份 `PrivacyInfo.xcprivacy`。

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
try u.upsert() // 以主键更新，不触发 INSERT OR REPLACE 的隐式删除
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

`User.fields.age` 在运行时验证字段名；需要显式值类型时使用 `User.field("age", as: Int.self)`。动态字段不提供编译期拼写/类型检查。

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

传入配置或提前调用 `configure(named:configuration:)` 后，该配置会按库名保存，所有模型 CRUD / 查询 / 事务 / 迁移都会复用它，关闭重开也会保留。

同名数据库已打开后不能切换配置；请先调用 `close(named:)`，再使用新配置打开。该方法返回是否真正关闭；若仍有存活的预编译语句，它会返回 `false` 并保留原连接，避免出现“表面关闭、实际仍占用文件”的状态。

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

Swift 非可选属性会生成 `NOT NULL` 约束。向已有数据的表新增必填列时，必须有 `@TFYDefault`、重命名来源或 `rebuildExpressions`；否则迁移会回滚并报告冲突，避免静默写入 NULL。生产升级前仍应备份数据库并在真实数据副本上演练迁移。

### 9. 错误处理与原始 SQL

所有数据库 API 都通过 `throws` 返回 `TFYSwiftDBError`。类型安全查询会绑定业务值；接收外部输入时不要把它直接拼进 `where`、`orderBy`、`TFYPredicate(sql:)` 或迁移表达式，这些接口是为受信任 SQL 片段保留的。

## SQLCipher 加密（与现有接口匹配）

本次发布源码版本为 `1.1.0`；下方远端依赖示例在 GitHub tag / CocoaPods 发布后生效，本地验证期间使用 path 依赖。原有 `1.0.7` 不包含以下加密 API。

### 选择后端

SwiftPM 明文模式继续支持 Swift 5.9。Swift 6.1+ 会选择 `Package@swift-6.1.swift`，可通过 trait 启用官方 SQLCipher 4.19.0：

```swift
.package(url: "https://github.com/13662049573/TFYSwiftSQLite.git", from: "1.1.0", traits: ["SQLCipher"]),
// 本地验证可使用：
// .package(name: "TFYSwiftSQLiteKit", path: "../TFYSwiftSQLite", traits: ["SQLCipher"]),
```

产品和 `import TFYSwiftSQLiteKit` 均不变。Xcode 若支持 package traits，可在包设置中启用 `SQLCipher`；仓库 Demo 使用 `Examples/SQLCipherDemo` 的小型桥接 Package 选择 trait，因此无需修改库默认配置。SwiftPM 的窄 C/Objective-C 桥接只暴露 key/rekey，避免给依赖库添加 unsafe Swift 编译标志。

CocoaPods 使用互斥 subspec：

```ruby
# 二选一，禁止同时选择 Standard 与 SQLCipher
pod 'TFYSwiftSQLiteKit/Standard', '~> 1.1.0'
# 或
pod 'TFYSwiftSQLiteKit/SQLCipher', '~> 1.1.0'
# 本地验证：pod 'TFYSwiftSQLiteKit/SQLCipher', :path => '../TFYSwiftSQLite'
```

不指定 subspec 时默认 `Standard`。SQLCipher subspec 使用官方最后分发到 CocoaPods 的 4.10.x 版本；SwiftPM 使用官方 4.19.0 二进制，两者默认均为 SQLCipher 4 文件格式。加密目标不额外链接系统 `sqlite3`。宿主 App 的其他依赖也应统一 SQLite 后端，避免同进程两套同名 C 符号互相覆盖。

Xcode 27 会拒绝 SQLCipher 4.10.0 Pod 及其 Privacy bundle 原始的低部署目标。宿主 Podfile 的现有 `post_install` 中应仅将 SQLCipher 目标提升到本库下限（不修改其他 Pods）：

```ruby
post_install do |installer|
  minimums = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.0',
    'MACOSX_DEPLOYMENT_TARGET' => '13.0',
    'TVOS_DEPLOYMENT_TARGET' => '16.0',
    'WATCHOS_DEPLOYMENT_TARGET' => '9.0'
  }
  installer.pods_project.targets.each do |target|
    next unless target.name == 'SQLCipher' || target.name.start_with?('SQLCipher-')
    target.build_configurations.each do |config|
      minimums.each do |setting, minimum|
        current = config.build_settings[setting]
        if current && Gem::Version.new(current) < Gem::Version.new(minimum)
          config.build_settings[setting] = minimum
        end
      end
    end
  end
end
```

仓库提供同等逻辑的 `Scripts/sqlcipher_platforms.rb`。`ruby Scripts/validate_cocoapods.rb SQLCipher` 在临时校验宿主中应用同样设置，再完整编译并验证导入；它不跳过构建，也不修改官方 SQLCipher 源码。普通 `pod lib lint` 在 Xcode 27 不应用宿主 hook，因此加密 subspec 的直接 lint 会因官方依赖下限失败。本地、远端 tag 校验和 trunk 发布均可使用仓库脚本应用相同设置；保留完整构建、导入与 RuntimeTests。详见 [1.1.0 发布步骤](docs/Release-1.1.0.md)。


### 配置一次，所有模型接口复用

```swift
// passphraseFromKeychain 由 App 的 Keychain 管理逻辑读取，不要在生产源码中硬编码。
let key = try TFYSwiftDBKey(passphrase: passphraseFromKeychain)
let encryption = TFYSwiftDBEncryption(key: key) // 默认 SQLCipher 4 格式
let configuration = TFYSwiftDBConfiguration(encryption: encryption)
try User.configureDatabase(configuration) // 首次访问前配置，相同 databaseName 的模型共享

try User.createTable()
let rowID = try user.insertReturningRowID()
let saved = try User.fetch(byPrimaryKey: rowID)
try user.upsert()
try User.transaction { try anotherUser.insert() }

let connection = try TFYSwiftDatabaseCenter.shared.open(named: User.databaseName)
print(try connection.cipherVersion() ?? "unavailable")
```

底层连接也支持 `TFYSwiftDBConnection(path:databaseName:configuration:)`。可用 `TFYSwiftDBConnection.supportsEncryption` 判断编译后端；运行时还会核对 `cipher_version`。未启用后端时传入密钥会在创建文件之前抛出 `encryptionUnavailable`，不会悄悄创建明文库。密钥会在首次读取 schema、WAL 配置之前设置，并立即读取 schema 验证；错误密钥、损坏文件和格式不符均拒绝打开。

`TFYSwiftDBKey(bytes:)` 是任意二进制口令（仍进行 PBKDF2）；`init(rawKey:salt:)` 接受 32 字节随机原始密钥和可选的 16 字节盐。密钥类型的描述与反射均脱敏，但 Swift 的 Data/String 复制与生命周期无法保证内存清零。连接与中心注册配置在进程内持有密钥，不会替你写入磁盘或 Keychain。关闭后可调用 `User.configureDatabase(nil)` 释放中心持有的配置；外部变量也需由 App 释放。

### 轮换密钥

```swift
let newKey = try TFYSwiftDBKey(passphrase: newPassphraseFromKeychain)
try TFYSwiftDatabaseCenter.shared.rekey(named: User.databaseName, key: newKey)
// 成功后再更新 App 的 Keychain；后续模型调用与中心关闭重开会使用新密钥。
```

已有加密库可调用 `connection.rekey(newKey)`；中心关闭时也会保存更新后的配置。轮换前须结束事务并释放存活的 prepared statements。`rekey` 不用于把明文库改为加密库。

### 明文转换、加密备份、解密与格式升级

```swift
// 需要 SQLCipher 后端。encryptedURL 必须是尚不存在的新文件，父目录须已存在。
try plainConnection.export(to: encryptedURL, encryption: encryption)
let encrypted = try TFYSwiftDBConnection(
    path: encryptedURL.path,
    databaseName: "encrypted",
    configuration: configuration
)
try encrypted.backup(to: backupURL) // 仍为加密文件，包含已提交的 WAL 数据
try encrypted.export(to: plaintextURL, encryption: nil) // 显式导出明文，请按业务需要使用

let sqliteErrors = try encrypted.integrityCheck() // 健康时 ["ok"]
let hmacErrors = try encrypted.cipherIntegrityCheck() // 健康时 []
let checkpoint = try encrypted.checkpoint(.truncate) // busy=true 时业务侧重试
```

导出使用官方 `sqlcipher_export`，保留 schema、数据、索引、触发器，以及额外同步 `user_version` / `application_id`。写入后重新打开并检查完整性。源文件保持原样，目标文件采用独占创建，不覆盖已有文件；失败时清理本次创建的目标。普通明文备份使用 SQLite backup API，不直接复制 `.db` 文件。

存量明文升级请先关闭业务读写、导出新文件、验证数据，再由 App 安排文件切换与备份保留；库不会自动替换正在使用的源文件。旧 SQLCipher 3 标准格式可显式配置 `.version3` 打开，再导出为默认 `.version4` 新文件。自定义旧 KDF/page-size、SQLCipher 1/2 与共享容器明文头/外部 salt 需要专门迁移方案，不属于当前高级配置支持范围。

### 使用边界

- 所有 API 都是同步调用。串行锁保证连接与事务隔离，IO/迁移/导出应在业务的后台执行器中调用。
- `forEachRow` 避免完整结果数组，回调期间持有连接锁；不要等待另一线程在同一连接上完成操作。手动共享 prepared statement 的 bind/step/row 跨调用序列需要业务自行串行化，优先用连接的 execute/query 接口。
- SQL API 每次接受一条语句；多条语句请在 `withTransaction` 中逐条执行。字符串中的 NUL 必须作为绑定值传入。
- `insertOrReplace` 保留 SQLite 的 DELETE+INSERT 语义，可能触发外键级联；需要保留原行关联数据时使用主键 `upsert`。
- `.rebuildTable` 自动迁移遇到外键依赖或数据库视图会明确拒绝；触发器/外部索引恢复失败会整体回滚。复杂关联 schema 请使用 App 的显式迁移。
- 加密 Demo 的口令仅用于演示。生产密钥持久化、账户隔离、恢复策略和 iOS 后台/App Group 生命周期由宿主 App 管理。

### Codable 自定义键

普通合成 Codable 无需额外配置。若 `CodingKeys` 重命名持久属性，需要声明属性名到 Codable key 的映射；数据库列名仍由 `@TFYColumn(name:)` 控制：

```swift
@TFYColumn(name: "db_label") var label = ""
enum CodingKeys: String, CodingKey { case label = "json_label" }
static var databaseCodingKeys: [String: String] { ["label": "json_label"] }
```

详见 [完整评估与维护计划](docs/LibraryReview.md)。

## 示例 Demo（TableView）

仓库内 `TFYSwiftSQLite/demoClass` 提供可交互的功能目录：

- 分组 `UITableView` 覆盖连接、建表、CRUD、查询、JSON/类型、事务、迁移、底层 API、Benchmark、SQLCipher
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

### 1.1.0（2026-10-01，待发布）

- 最低平台版本统一为 iOS 16、macOS 13、tvOS 16、watchOS 9；配置、脚本和文档保持一致

- 可选 SQLCipher 后端；现有明文默认行为与模块名保持不变
- 按库名注册配置贯通所有 ORM / 查询 / 事务 / 迁移；支持密钥轮换与重开
- 明文/加密导出、加密备份、WAL checkpoint、SQLite 与 HMAC 完整性检查
- 密钥不进入库提供的 SQL 日志，即使 `.full` 也跳过密钥绑定
- 修复多条 SQL 静默截断、预编译语句失败后复用、连接生命周期与首次并发开库
- 修复 JSON 标量、下划线属性、继承反射、CodingKeys 映射及非法数值静默解码
- 表重建拒绝外键/视图风险，保留触发器、外部索引与 AUTOINCREMENT 历史序列
- 新增真正的主键 upsert、原子返回插入 rowID、逐行遍历与加密 Demo

### 1.0.7

- 将 CocoaPods 与 SwiftPM 的 tvOS 下限统一提升至 15、watchOS 下限统一提升至 9
- 修复新版 Xcode 无法对过低 Simulator Deployment Target 执行全平台 Pod 校验的问题
- Demo 版本展示改为读取应用构建版本，避免发布版本说明漂移

### 1.0.6

- 非可选模型属性生成 `NOT NULL`，并阻止已有数据表静默新增无默认值的必填列
- 增加预编译查询、列读取、连接变更计数与可返回值事务，修复分页 offset 残留
- 强化连接关闭生命周期、数值边界、Benchmark 溢出保护与 Swift 6 严格并发兼容
- 统一 Xcode、CocoaPods 与 SwiftPM 的源码、Privacy Manifest、平台下限和版本说明

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

- Swift Package：由 `Package.swift` / `Package@swift-6.1.swift` 暴露同名产品 `TFYSwiftSQLiteKit`
- CocoaPods：由 `TFYSwiftSQLiteKit.podspec` 的互斥后端 subspec 收录 `TFYSwiftSQLite/TFYSwiftSQLiteKit` 下全部 Swift 文件
- 两种分发方式均包含 `PrivacyInfo.xcprivacy`，版本号以 podspec 和 git tag 为准
- 示例 app / tests / benchmark 仍位于 `TFYSwiftSQLite.xcodeproj`

发版分为本地验证、提交源码并创建 GitHub `1.1.0` tag、远端 tag 验证、CocoaPods 发布。**GitHub Release 必须指向包含本次修改的提交**，不能在旧的 `1.0.7` 提交上创建新 tag。

```bash
ruby Scripts/validate_distribution_layout.rb
swift test
swift build -c release
swift test --traits SQLCipher --scratch-path .build-sqlcipher
swift build -c release --traits SQLCipher --scratch-path .build-sqlcipher
# 全平台编译/导入；macOS RuntimeTests 分别测试 Standard 和 SQLCipher 4.10.0
ruby Scripts/validate_cocoapods.rb All
# 提交并推送源码后，在 GitHub 创建 1.1.0 Release/tag，再校验实际远端源码
ruby Scripts/validate_cocoapods.rb All --remote
# 发布到 trunk：同样进行远端源码全量校验后才上传
ruby Scripts/publish_cocoapods.rb
```

详细升级说明、GitHub Release 正文和发布顺序见 [1.1.0 发布步骤](docs/Release-1.1.0.md)。

## 质量验证

本轮实际结果和平台范围见 [本地验证记录](docs/Validation.md)。

Swift Package 已包含测试目标，本地与 CI 使用同一入口：

```bash
swift test
swift build -c release
```

当前测试共 59 项；明文后端跳过 5 项加密专用测试，加密后端跳过 1 项明文缺失后端检查。测试覆盖加密文件头、错误密钥、轮换、格式兼容、加密 ORM、转换/解密、备份、日志保密、CodingKeys、JSON 标量、重建关联保护与首次并发开库，以及原有 CRUD、批量写入、分页与计数、唯一索引、多数据库隔离、迁移与重建、必填列保护、预编译查询、连接关闭生命周期、日志脱敏、绑定参数校验、NULL/LIKE 边界、数值溢出，以及并发事务隔离。

## 系统要求

- Swift 5.9+
- iOS 16+
- macOS 13+
- tvOS 16+
- watchOS 9+
- 示例 App 与 iOS 测试目标统一使用 iOS 16

## 许可

见仓库根目录 [LICENSE](LICENSE)（MIT）。
