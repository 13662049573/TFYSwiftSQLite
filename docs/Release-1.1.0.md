<!--
//
//  Release-1.1.0.md
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//
-->

# 1.1.0 发布步骤与升级说明

准备日期：2026-10-01。上一远端版本为 1.0.7。本次版本为 **1.1.0**，GitHub tag 使用 `1.1.0`，与 Podspec 完全相同。GitHub Release 与 CocoaPods 均已发布，正式 tag 指向 `85fcf19d3d2522f5858a2cee5a9e754eb9b70467`；该 tag 的源码已通过远端全量验证。

## GitHub Release 正文

TFYSwiftSQLiteKit 1.1.0 增加可选 SQLCipher 加密后端，并补强连接生命周期、模型映射、迁移和分发验证。最低支持 iOS 16、macOS 13、tvOS 16、watchOS 9，统一为 iOS 16 同期平台版本。

- 保持 `TFYSwiftSQLiteKit` 产品、模块名及现有模型/CRUD 接口；默认使用系统 SQLite。
- SwiftPM 6.1+ 使用 SQLCipher trait（官方 4.19.0）；CocoaPods 使用 SQLCipher subspec（官方 4.10.0）。支持按库注册密钥、轮换、加密备份、明文与加密转换、格式升级、完整性检查和 WAL checkpoint。
- 库管理的密钥始终绕过 SQL 日志；错误密钥拒绝打开，缺失加密后端时拒绝创建明文文件。
- 增加主键 upsert、原子插入 rowID 和逐行读取；修复预编译语句失败后复用、首次并发开库及并发关闭/删除对模型事务的干扰。
- 修复 JSON 标量、下划线属性、继承反射与自定义 CodingKeys；非法数值解码明确报错。
- 迁移保留外部索引、可用触发器及自增历史序列；危险外键/视图/原始 SQL 约束重建、无效触发器及不匹配的索引定义会回滚并报错。
- Demo 提供 44 个可独立运行示例，包含真实加密场景。CocoaPods 两种后端附带 macOS RuntimeTests。

## 升级注意

1. iOS 15 / tvOS 15 宿主须提升到 16，或继续使用 1.0.7。SwiftPM 明文支持 Swift 5.9+；加密 trait 需要 Swift 6.1+。
2. 加密是显式选择；Standard 与 SQLCipher 只选一种。宿主其他依赖须使用一致的 SQLite 后端。现有明文文件通过 `export(to:encryption:)` 创建并验证新文件，由 App 关闭读写后切换文件。
3. 原始 SQL 每次只允许一条可执行语句，原先依赖多语句静默截断的调用须拆分。无效数据解码现在报错，应修复存量数据。
4. 自定义 CodingKeys 与属性名不同时声明 `databaseCodingKeys`。密钥持久化与 Keychain/账户生命周期由 App 管理。
5. 对包含外键、视图、原始 SQL CHECK/UNIQUE/排序规则/生成列等复杂定义的表，使用显式迁移；自动重建不会静默丢弃这些约束。手动开始的 SQL 事务须由调用者提交或回滚。
6. Xcode 27 的 SQLCipher Pod 部署目标要求，按 README 添加 `post_install`。仓库校验/发布脚本应用同等设置，不跳过编译、导入或测试。

## 发布顺序

在仓库根目录完成以下步骤。库源码、配置、脚本和测试必须先提交并推送；个人 Xcode 窗口状态文件不属于发布内容。

```bash
ruby Scripts/validate_distribution_layout.rb
swift test
swift build -c release
swift test --traits SQLCipher --scratch-path .build-sqlcipher
swift build -c release --traits SQLCipher --scratch-path .build-sqlcipher
ruby Scripts/validate_cocoapods.rb All
```

确认本次发布文件已提交并推送，再在 GitHub 创建 tag 为 `1.1.0` 的 Release，目标选择本次发布提交；正文可使用上面的“GitHub Release 正文”。随后校验真实 tag 下载到的源码：

```bash
ruby Scripts/validate_cocoapods.rb All --remote
```

通过后，在已注册 CocoaPods trunk 的账号环境执行：

```bash
ruby Scripts/publish_cocoapods.rb
```

发布脚本确认远端 tag 指向本地 HEAD、发布源码无未提交变更，然后由 trunk 完整验证远端 Git 源及所有 subspec，验证成功才上传。标准 `pod trunk push` 在 Xcode 27 缺少依赖部署目标调整；请使用上述入口。脚本允许 CocoaPods 工具链提示类警告，但不会跳过编译错误、运行失败或导入校验。

发布后确认 CocoaPods 收录 `1.1.0`，并用独立宿主分别安装 Standard 与 SQLCipher 验证；GitHub Release 与 CocoaPods 发布是两个独立步骤。远端 CI、远端 tag 验证和 trunk 发布结果以实际执行为准，本地通过不能代替这些结果。

本次已完成正式 tag 校验与发布确认，并通过官方 Git Specs 在两个独立 macOS 宿主安装、编译和运行 Standard / SQLCipher。提交时服务器返回内部错误，但后续核实 trunk 与官方 Specs 已收录，因此未重复发布。本机 CDN 返回 403 的备用接入方式见 README。完整结果及未覆盖范围见 [Validation.md](Validation.md)。
