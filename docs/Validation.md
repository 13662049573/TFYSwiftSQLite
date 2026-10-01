<!--
//
//  Validation.md
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//
-->

# 1.1.0 本地验证记录

日期：2026-10-01。工具链：Xcode 27.0 (27A266a)、Apple Swift 6.4。源码尚未提交/打 tag/发布；以下记录是本地验证，CI 配置已更新但尚未在远端执行。

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

直接 `pod lib lint --subspec=SQLCipher` 在 Xcode 27 会因官方依赖原始部署目标低于 SDK 支持范围失败。`Scripts/validate_cocoapods.rb` 将 SQLCipher 及其 Privacy bundle 的目标对齐本库下限，保持构建、导入和 RuntimeTests 启用。远端 tag 校验使用 `All --remote`；`publish_cocoapods.rb` 在 trunk 的远端源码全量校验中使用同样设置。GitHub tag 尚未创建，因此远端 spec lint、CI 与 trunk 发布仍待执行。

Xcode 的 AppIntents 无依赖提示、当前工具链 Swift 搜索路径提示及 XCTest 最低版本链接提示不影响本次构建/测试结果。负向错误密钥测试产生的 SQLCipher HMAC 错误输出符合预期。

本次尚未进行真机、大文件/空间不足、App Group 跨进程、进程中断恢复、宿主账户与 Keychain 生命周期验收；这些限制不应从模拟器或编译通过推断为已验证。
