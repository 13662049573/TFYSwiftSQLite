<!--
//
//  Validation.md
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//
-->

# 1.1.0 验证与发布记录

日期：2026-10-01。工具链：Xcode 27.0 (27A266a)、Apple Swift 6.4。GitHub `1.1.0` Release 已创建，CocoaPods 已收录 `1.1.0`。以下记录包含本地与正式 tag 验证；未据此推断 GitHub Actions 的远端执行结果。

| 验证 | 结果 | 范围 |
| --- | --- | --- |
| 修改前测试 | 29 项，0 失败 | 1.0.7 基线 |
| 系统 SQLite 测试 | 59 项，5 项按后端跳过，0 失败 | macOS / 默认构建 |
| SQLCipher 4.19.0 测试 | 59 项，1 项按后端跳过，0 失败 | macOS / 官方 xcframework |
| Release 构建 | 两种后端通过 | SwiftPM 产品 |
| 旧 manifest 兼容检查 | 59 项，5 项跳过，0 失败 | 单独复制 Package.swift 的 Swift 5 语言模式；仍使用本机 Swift 6.4 编译器，未实测 Swift 5.9 编译器 |
| iOS 模拟器测试 | 59 项，1 项按后端跳过，0 失败 | 最低 iOS 16；iPhone 18 Pro Max / iOS 27 / SQLCipher |
| SwiftPM SQLCipher 跨平台构建 | tvOS / watchOS Simulator 通过 | 官方 4.19.0、SQLCipher trait 和 C/Objective-C 桥接；编译验证，未运行行为测试 |
| Demo 全量运行 | 44 通过，0 失败 | 10 个主题，包括 5 个真实加密场景 |
| CocoaPods Standard | 全平台编译/导入校验通过 | iOS、macOS、tvOS、watchOS |
| CocoaPods SQLCipher | 全平台编译/导入校验通过 | 同四平台；官方 4.10.0 源码；临时宿主应用 README 部署目标 hook |
| CocoaPods RuntimeTests | 每种后端 59 项、0 失败 | macOS；Standard 跳过 5 项，SQLCipher 4.10.0 跳过 1 项；通过完整 `All` 校验 |
| 分发一致性 | 18 Swift 源文件、1 资源一致 | 两份 SwiftPM manifest、两种 Pod subspec、Xcode 引用/源文件排除 |
| Diff 空白检查 | 通过 | git diff --check |

平台下限最终统一为 **iOS 16 / macOS 13 / tvOS 16 / watchOS 9**。两种 CocoaPods RuntimeTests 的 macOS 下限均为 13，与库一致。tvOS 从 15 提升到 16 后，重新执行 SwiftPM SQLCipher Simulator 构建及 CocoaPods 根 spec、Standard、SQLCipher 的 tvOS 编译/导入校验，全部通过；其他平台下限未改变。

SQLCipher 行为测试验证了文件头和敏感字符串不以明文存储、正确密钥重开、错误/缺失密钥拒绝、SQLCipher 3 raw-key 到 4 格式导出、加密 ORM/事务/迁移、轮换、完整性、加密备份、明文转换/解密，以及 full 日志不含库管理的密钥。

发布复核增加了并发关闭/删除等待模型事务、部分唯一索引不能替代全表约束、索引名称大小写和排序规则冲突、无效触发器回滚，以及未建模 SQL 约束重建拒绝测试；加密转换/备份还验证了 sqlite_sequence 历史值保留。iOS 16 下限及 1.1.0 版本由分发脚本检查，文件头按各格式校验。

两种后端的测试共用 Library 中固定的测试数据库，应顺序执行；iOS 模拟器在独立容器中执行。CocoaPods RuntimeTests 仅声明 macOS 支持，其他三平台的 lint 完整编译/导入库、按平台声明跳过 RuntimeTests；iOS 行为测试使用仓库 Xcode 测试目标。此处“iOS 16”表示编译最低版本，本机实际运行环境为 iOS 27，未实测 iOS 16 系统运行环境。

直接 `pod lib lint --subspec=SQLCipher` 在 Xcode 27 会因官方依赖原始部署目标低于 SDK 支持范围失败。`Scripts/validate_cocoapods.rb` 将 SQLCipher 及其 Privacy bundle 的目标对齐本库下限，保持构建、导入和 RuntimeTests 启用。远端 tag 校验使用 `All --remote`；`publish_cocoapods.rb` 在 trunk 的远端源码全量校验中使用同样设置。正式 tag `1.1.0` 的远端 spec lint 已通过，CocoaPods trunk 与官方 Specs 仓库均已收录；GitHub Actions 结果未在本次发布中核验。

Xcode 的 AppIntents 无依赖提示、当前工具链 Swift 搜索路径提示及 XCTest 最低版本链接提示不影响本次构建/测试结果。负向错误密钥测试产生的 SQLCipher HMAC 错误输出符合预期。

本次尚未进行真机、大文件/空间不足、App Group 跨进程、进程中断恢复、宿主账户与 Keychain 生命周期验收；这些限制不应从模拟器或编译通过推断为已验证。

## 正式发布确认

2026-10-01 使用独立目录下载正式 `1.1.0` tag，提交为 `85fcf19d3d2522f5858a2cee5a9e754eb9b70467`。当前主分支比该 tag 多出的 README、Demo 截图和个人窗口状态不影响发布的库源码、Podspec、脚本与测试。

| 检查 | 结果 |
| --- | --- |
| `ruby Scripts/validate_cocoapods.rb All --remote` | 退出码 0；两种后端、四平台编译与导入、macOS RuntimeTests 通过 |
| `ruby Scripts/publish_cocoapods.rb` | 上传前全量验证通过；提交后服务器返回内部错误，命令退出码 1；随后核实已正式收录，无重复提交 |
| `pod trunk info TFYSwiftSQLiteKit` | 版本列表包含 `1.1.0` |
| Trunk 官方 `specs/1.1.0` 接口 | 返回已发布 Podspec；内容与正式 tag Podspec 完全一致，仅发布工具附加 Swift 版本元数据 |
| 官方 Specs 仓库 | 提交 `861eb09e1ea2188b5da06320b03a64faf5d3e1a6` 已添加 `TFYSwiftSQLiteKit 1.1.0` |
| 独立 Standard 宿主 | 官方 Git Specs 版本安装、macOS Release 编译和运行通过；确认使用系统 SQLite，写入后关闭/重开仍可读取 |
| 独立 SQLCipher 宿主 | 官方 Git Specs 版本安装、macOS Release 编译和运行通过；确认官方 SQLCipher `4.10.0 community`，加密配置写入后关闭/重开仍可读取 |

本机访问 CocoaPods CDN 返回 403，首次 CDN 安装未解析到新版本；改用 `source 'https://github.com/CocoaPods/Specs.git'` 并更新索引后，两种宿主均成功安装。这是本次网络/索引环境的实际结果，未据此判断所有用户的 CDN 可用性。README 已提供备用源配置。两个独立宿主通过版本依赖安装，未使用本地 `:path` 或未发布的 Podspec。

公开核验入口：[GitHub Release](https://github.com/13662049573/TFYSwiftSQLite/releases/tag/1.1.0)、[官方 Specs 文件](https://github.com/CocoaPods/Specs/blob/master/Specs/d/d/7/TFYSwiftSQLiteKit/1.1.0/TFYSwiftSQLiteKit.podspec.json)。
