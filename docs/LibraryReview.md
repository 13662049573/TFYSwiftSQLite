<!--
//
//  LibraryReview.md
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//
-->

# TFYSwiftSQLiteKit 全面检查与补充

检查日期：2026-10-01。基线：1.0.7，master。当前本地源码版本：1.1.0，待发布。

最低平台版本已统一为 iOS 16、macOS 13、tvOS 16、watchOS 9，覆盖两份 Package、Podspec、Xcode、SQLCipher 示例及部署目标 hook；两种 RuntimeTests 的 macOS 13 与库保持一致。源码与可注释配置/文档已按要求补齐文件头。

## 当前状态

这是 Foundation + SQLite C API 的轻量同步 ORM，不依赖示例 App。18 个 Swift 文件覆盖属性包装器、反射 schema、连接/语句、模型 CRUD、查询、迁移、数据库中心及类型转换。SwiftPM 和 CocoaPods 支持相同运行时源码；UIKit Demo 是单独消费者。原有 29 项测试在修改前全部通过。

数据路径为 Library/TFYSwiftSQLite/<databaseName>.db；模型通过 databaseName 路由到共享中心。连接使用递归锁，事务整体持锁，嵌套事务以 savepoint 实现。模型依赖 Codable + init()，行读取经过 SQLite → JSON → 模型，不是编译器生成的 ORM。

## 优点

- 分层清晰，运行时不依赖 UIKit；另一 App 可以通过 Pod/Package 独立接入。
- 业务值使用绑定参数；字段/表/索引标识符进行转义，默认日志脱敏。
- 批量插入复用 prepared statement 并整体事务化；并发事务有独立行为测试。
- 安全迁移拒绝缺乏值来源的必填新增列，支持重命名/转换/验证 hook，迁移日志与 schema 修改一起提交。
- Date/Data/Bool、可选值、JSON、复合唯一索引及多库隔离已具备基础支持。
- 源码、资源、平台与版本有分发一致性检查，Privacy Manifest 同步打包。

## 本轮问题与修复

| 优先级 | 问题/触发条件 | 影响 | 处理 |
| --- | --- | --- | --- |
| 高 | 用自定义配置打开后调用模型 CRUD，模型仍默认开库 | 配置冲突，加密无法贯通 | 中心按库名注册配置；模型 configureDatabase；所有原接口复用，关闭重开保留 |
| 高 | 中心持全局锁创建连接，初始化 SQL logger 重入中心 | 死锁，其他库也无法打开 | 初始化在锁外执行，同名首次并发调用等待；同线程初始化重入明确拒绝 |
| 高 | 一次传入多条 SQL，prepare 只执行首条 | 调用者误认为全部执行 | 检查 SQLite parser 返回的尾部；允许注释，拒绝第二条及 NUL，执行前报错 |
| 高 | table rebuild 遇到 ON DELETE CASCADE | DROP TABLE 可能删除关联数据 | 自动重建前检查出入外键依赖；明确拒绝，转交 App 显式迁移 |
| 高 | rebuild 丢失触发器、外部索引或历史自增序列 | 行为变化、旧 ID 重用 | 保存并恢复对象与 sqlite_sequence；恢复无效时整体回滚；视图数据库明确拒绝自动重建 |
| 高 | 显式索引名已用于另一张表 | IF NOT EXISTS 静默跳过约束 | 在数据库级验证索引归属，冲突回滚 |
| 高 | 关闭/删除提前标记不可用，进行中的模型事务再次开库 | 事务被外部生命周期操作打断 | 先等待连接事务锁，再保留关闭/删除状态；事务完成后操作 |
| 高 | 部分索引、不同排序规则或大小写索引名误匹配 | 期望的完整唯一约束未建立 | 检查 index_xinfo、partial、排序/表达式及名称大小写；冲突明确拒绝 |
| 高 | CREATE TRIGGER 接受引用已删除字段的定义 | 重建成功后首次写入失败 | 恢复后预编译三种 DML 路径，错误使迁移整体回滚 |
| 高 | 外部 SQL UNIQUE/CHECK/排序规则/生成列等约束不在模型中 | 自动重建静默丢弃约束 | 重建前保守拒绝未建模约束，要求显式应用迁移 |
| 中 | 保存 JSON 字符串/数值/Bool，而读取只接受 JSON 容器 | 无法往返 | fragmentsAllowed 解码，增加标量测试 |
| 中 | 普通属性 `_label` 被当作包装器 backing field | 字段/Codable 映射错误 | 仅实际包装器移除 backing 下划线；补充 superclass 反射 |
| 中 | 自定义 CodingKeys 与反射属性名不同 | 读取旧默认值或失败 | databaseCodingKeys 显式映射，并校验重复/未知键 |
| 中 | 非法数字文本、分数、越界数据被容错工具转换为 0/截断 | 数据错误被掩盖 | ORM 解码严格检查；兼容工具 numericValue 仍保留原有行为 |
| 中 | Prepared statement 因约束失败后再次执行 | reset 返回前次错误，下一次正常写入也失败 | 连接内部正确重置执行状态；公开 reset 仍保留 SQLite 状态报告语义 |
| 中 | 连接被直接关闭仍留在中心缓存 | ORM 返回已关闭连接 | 检查失效缓存后重开；prepared statement 持有原连接直到 finalize |
| 中 | 分离读取 lastInsertedRowID，其他线程先完成插入 | 返回其他写入的 ID | executeReturningRowID / insertReturningRowID 在同一锁内取得 ID |
| 中 | INSERT OR REPLACE 用于逻辑更新 | DELETE+INSERT 导致关联行级联删除 | 增加真实 ON CONFLICT(primaryKey) DO UPDATE 的 upsert，原方法保留原语义 |
| 低 | Benchmark.measure 的迭代数为负 | 构造 Range 崩溃 | 零次执行，不崩溃 |

示例对比：

```swift
// 以前：仅连接支持自定义配置，模型仍按默认配置打开。
let connection = try center.open(named: User.databaseName, configuration: configuration)
try user.insert() // 可能配置冲突

// 现在：配置以数据库名为单位贯通全部模型能力。
try User.configureDatabase(configuration)
try user.insert()
```

```swift
// 以前：第二条语句静默未执行。
try connection.execute("CREATE TABLE a(id); CREATE TABLE b(id);")

// 现在：上面的调用直接报错，两表都不会创建；显式事务逐条执行。
try connection.withTransaction {
    try connection.execute("CREATE TABLE a(id);")
    try connection.execute("CREATE TABLE b(id);")
}
```

## SQLCipher 的匹配方式

加密集成在连接层，现有模块名、模型、字段包装器、CRUD、查询、事务和迁移使用同一份实现。默认仍为系统 SQLite；SwiftPM 6.1+ 的 SQLCipher trait 和 CocoaPods SQLCipher subspec 二选一切换后端，未提供密钥时仍可操作明文库。

加密密钥通过 sqlite3_key/rekey 的字节 API 设置，不拼接 SQL。设置后立即验证 schema，错误密钥拒绝打开；未启用 SQLCipher 的构建在创建文件前报错。密钥类型的显示/反射脱敏；库提供的密钥与导出绑定绕过 SQL logger，包括 full 模式。SwiftPM 使用官方 4.19.0 xcframework；Pods 使用官方 4.10.x 分发，不同时显式链接系统 SQLite。Xcode 27 下 Pod 宿主须按 README 的 post_install 对齐 SQLCipher/Privacy bundle 部署目标；校验脚本应用相同设置完成完整构建。

支持 SQLCipher 3/4 标准格式、二进制口令、32 字节 raw key、轮换、导出转换、解密、加密备份、SQLite/HMAC 完整性检查与 checkpoint。导出使用新文件并重新打开检查，保留源文件及 user_version/application_id，防止文件替换意外破坏现有连接。

官方依据：[Swift Package](https://github.com/sqlcipher/SQLCipher.swift)、[SQLCipher key/rekey/export API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)、[4.10 CocoaPods 分发说明](https://www.zetetic.net/blog/2025/08/04/sqlcipher-4.10.0-release/)。

## 保留的边界与不足

- 反射 + JSON 桥接有开销；本轮将默认模型 JSON 与 decoder 改为每批读取复用，但尚未提供宏生成映射或行 decoder。
- 动态字段仅在运行时校验，不能在编译期检查拼写/实际值类型；显式 TFYField<Model, Value> 可约束值类型，但仍不是 Swift KeyPath schema。
- 所有 API 同步。Sendable 标注结合锁不意味着异步 IO、任务取消或多连接读池；长查询可能阻塞同库其他工作。
- 中心为单例且默认 Library 路径固定。底层连接可注入自定义路径，但模型还不能绑定任意 center/connection context，App Group 与独立测试容器需要业务配置方案。
- 不提供关系对象映射、复合主键、外键声明、局部索引表达式、联表模型映射和版本化应用迁移队列；原始 SQL 可执行这些能力，但自动重建会保守拒绝不受支持的关联 schema。
- safe migration 对不能原地修复的 schema 漂移仍给警告。业务必须处理 report.warnings；建表成功不代表所有期望约束已经匹配。
- public raw-pointer statement initializer 仍保留兼容；调用者负责指针与连接生命周期。连接 prepare 是推荐入口，手动共享语句跨调用需要外部串行化。
- 密钥由宿主 Keychain 管理；内存中的 Swift 值不能承诺安全擦除。注册配置在进程内保存，进程重启需重新提供密钥。加密文件换钥与 Keychain 更新不是跨介质原子事务，需要 App 的恢复策略。
- 仅支持默认 SQLCipher 3/4 兼容参数，不覆盖自定义旧 KDF/page-size、1/2 格式和 App Group 明文头/外置盐。宿主仍需管理 iOS 后台锁及账户切换生命周期。
- 错误按类型分类，SQLite extended result code 尚未贯通所有高层错误；批量性能尚未在大型真实数据/真机/空间不足场景下验收。
- 不能声称完成生产全部场景验收：本轮覆盖本机 macOS、iOS 模拟器和分发构建，真机、跨进程、App Group、大文件、磁盘耗尽与杀进程恢复仍需专门演练。

## 质量评价

本轮修复后的主观评分约 **8/10**，用于维护排序，不代表安全认证。Swift 用法 8、架构 8、错误处理 7、命名 8、组织 9、性能 7。主要扣分点为运行时反射/JSON 开销、全局模型连接上下文、同步阻塞及复杂 schema 迁移能力边界。

## 团队维护计划

1. **发布前**：两种后端的单元测试、Release 构建、源码/资源一致性、Pod 两种 subspec 校验与 Demo 全量运行必须通过；将当前严格行为变化列入升级说明。不要只依据示例能运行就发布。
2. **接入验收**：在第二个独立 App 验证数据库名隔离、Keychain 读写、旧库转换、账户切换与后台/前台生命周期；真实数据副本演练迁移与密钥轮换失败恢复。
3. **维护分工**：Core 维护连接锁/语句/加密和文件生命周期；ORM 维护类型映射与查询；Schema 维护迁移保护；一个 release owner 管理分发列表、版本与依赖升级。各模块变更必须附能复现缺陷的行为测试。
4. **后续阶段**：按业务证据推进可注入数据库上下文、版本化迁移、结构化 SQLite 错误与只读访问；大结果集性能需要时再加入直接行 decoder/宏映射、读连接池和取消支持。

## 本地验证入口

```bash
ruby Scripts/validate_distribution_layout.rb
swift test
swift build -c release
swift test --traits SQLCipher --scratch-path .build-sqlcipher
swift build -c release --traits SQLCipher --scratch-path .build-sqlcipher
```

两个后端的测试请顺序运行；模型测试默认使用共享 Library 路径。测试共 59 项：明文构建跳过 5 项加密专用测试，加密构建跳过 1 项后端缺失检查。原有 29 项在加密构建中也运行。Demo 共 44 个独立示例，新增 5 个真实加密场景。CocoaPods 两种 subspec 各提供同一批 macOS RuntimeTests。

实际结果与验证范围见 [本地验证记录](Validation.md)。
