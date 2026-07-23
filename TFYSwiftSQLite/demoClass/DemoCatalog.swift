import Foundation
import TFYSwiftSQLiteKit

enum DemoSection: Int, CaseIterable {
    case connection
    case schema
    case crud
    case query
    case types
    case transaction
    case migration
    case lowLevel
    case benchmark

    var title: String {
        switch self {
        case .connection: return "1. 连接与配置"
        case .schema: return "2. 模型与建表"
        case .crud: return "3. CRUD"
        case .query: return "4. 类型安全查询"
        case .types: return "5. JSON / 类型映射"
        case .transaction: return "6. 事务"
        case .migration: return "7. 迁移"
        case .lowLevel: return "8. 底层 API"
        case .benchmark: return "9. 性能与日志"
        }
    }
}

struct DemoItem {
    let section: DemoSection
    let title: String
    let subtitle: String
    let run: () throws -> String
}

enum DemoCatalog {
    static let databaseNames = ["demo_main", "channel", "audit", "demo_config"]

    static let items: [DemoItem] = [
        // MARK: Connection
        DemoItem(section: .connection, title: "打开命名数据库", subtitle: "TFYSwiftDatabaseCenter.open") {
            try reset()
            let center = TFYSwiftDatabaseCenter.shared
            let path = try center.path(named: "demo_main")
            let conn = try center.open(named: "demo_main")
            return ok([
                "path: \(path)",
                "isOpen: \(conn.isOpen)",
                "journal: \(conn.configuration.journalMode.rawValue)"
            ])
        },
        DemoItem(section: .connection, title: "自定义 Configuration", subtitle: "WAL / busyTimeout / FK") {
            try reset()
            let center = TFYSwiftDatabaseCenter.shared
            let config = TFYSwiftDBConfiguration(
                foreignKeysEnabled: true,
                journalMode: .wal,
                synchronousMode: .normal,
                busyTimeout: 3,
                walAutoCheckpoint: 500
            )
            let conn = try center.open(named: "demo_config", configuration: config)
            let mode = try conn.scalar("PRAGMA journal_mode;")
            return ok([
                "busyTimeout: \(conn.configuration.busyTimeout)",
                "walAutoCheckpoint: \(String(describing: conn.configuration.walAutoCheckpoint))",
                "PRAGMA journal_mode: \(String(describing: mode))"
            ])
        },
        DemoItem(section: .connection, title: "路径 / 关闭 / 删除", subtitle: "path · close · removeDatabase") {
            try reset()
            let center = TFYSwiftDatabaseCenter.shared
            let dir = try TFYSwiftDatabaseCenter.databaseDirectory()
            let path = try center.path(named: "demo_main")
            _ = try center.open(named: "demo_main")
            center.close(named: "demo_main")
            try center.removeDatabase(named: "demo_main")
            let exists = FileManager.default.fileExists(atPath: path)
            return ok([
                "directory: \(dir.path)",
                "removed path existed: \(exists == false)"
            ])
        },
        DemoItem(section: .connection, title: "SQL Logger", subtitle: "redacted binding policy") {
            try reset()
            var traces: [String] = []
            TFYSwiftDBRuntime.setSQLLogger({ event in
                if traces.count < 8 {
                    let sql = event.sql.replacingOccurrences(of: "\n", with: " ")
                    traces.append("\(event.succeeded ? "OK" : "ERR") \(String(format: "%.3f", event.duration))s \(sql)")
                }
            }, bindingPolicy: .redacted)
            defer { TFYSwiftDBRuntime.setSQLLogger(nil) }
            _ = try User.createTable()
            try makeUser(username: "logger", email: "logger@demo.com").insert()
            return ok(["trace count: \(traces.count)"] + traces)
        },

        // MARK: Schema
        DemoItem(section: .schema, title: "注解模型建表", subtitle: "PK/Index/Unique/Default/Ignore/JSON") {
            try reset()
            let report = try User.createTable()
            let schema = try TFYSwiftModelMirror.schema(for: User.self)
            return ok([
                "columns: \(schema.persistedColumns.map(\.name).joined(separator: ", "))",
                "pk: \(schema.primaryKeyColumn?.name ?? "?")"
            ] + report.formattedLines())
        },
        DemoItem(section: .schema, title: "复合唯一索引 · 多库", subtitle: "Order @ channel.db") {
            try reset()
            let report = try Order.createTable()
            try Order(id: 0, userID: 1, orderNo: "ORD-001", amount: 9.9).insert()
            do {
                try Order(id: 0, userID: 1, orderNo: "ORD-001", amount: 1).insert()
                throw DemoAssertError("composite unique should block duplicate")
            } catch is DemoAssertError {
                throw DemoAssertError("composite unique should block duplicate")
            } catch {
                return ok(report.formattedLines() + ["duplicate blocked: \(error)"])
            }
        },
        DemoItem(section: .schema, title: "Schema / Index SQL 预览", subtitle: "TableBuilder + IndexBuilder") {
            try reset()
            let schema = try TFYSwiftModelMirror.schema(for: User.self)
            let createSQL = TFYSwiftTableBuilder.createTableSQL(for: schema)
            let indexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
            let indexSQL = indexes.map { TFYSwiftIndexBuilder.createIndexSQL(for: $0) }
            return ok(["CREATE:", createSQL, "INDEXES:"] + indexSQL)
        },

        // MARK: CRUD
        DemoItem(section: .crud, title: "单条 Insert · 自增 PK", subtitle: "id == 0 → AUTOINCREMENT") {
            try prepareUsers()
            let user = makeUser(username: "alice", email: "alice@demo.com", age: 28)
            try user.insert()
            guard let fetched = try User.fetchAll(where: "username = ?", bindings: [.text("alice")]).first else {
                throw DemoAssertError("insert fetch failed")
            }
            return ok(["inserted id: \(fetched.id)", "row: \(fetched)"])
        },
        DemoItem(section: .crud, title: "批量 Insert", subtitle: "insert([Model]) 事务批写") {
            try prepareUsers()
            try User.insert([
                makeUser(username: "u1", email: "u1@demo.com", age: 21),
                makeUser(username: "u2", email: "u2@demo.com", age: 22),
                makeUser(username: "u3", email: "u3@demo.com", age: 23)
            ])
            return ok(["count: \(try User.count())"])
        },
        DemoItem(section: .crud, title: "InsertOrReplace", subtitle: "冲突时替换") {
            try prepareUsers()
            var user = makeUser(username: "rep", email: "rep@demo.com", age: 30)
            try user.insert()
            guard let first = try User.fetchAll(where: "email = ?", bindings: [.text("rep@demo.com")]).first else {
                throw DemoAssertError("missing row")
            }
            var replaced = first
            replaced.username = "rep2"
            replaced.age = 31
            try replaced.insertOrReplace()
            let rows = try User.fetchAll(where: "email = ?", bindings: [.text("rep@demo.com")])
            return ok(["rows: \(rows)"])
        },
        DemoItem(section: .crud, title: "Fetch · Update · Delete", subtitle: "byPrimaryKey / update / delete") {
            try prepareUsers()
            try makeUser(username: "bob", email: "bob@demo.com", age: 40).insert()
            guard var bob = try User.fetchAll(where: "username = ?", bindings: [.text("bob")]).first else {
                throw DemoAssertError("bob missing")
            }
            bob.nickname = "vip"
            bob.age = 41
            try bob.update()
            let byPK = try User.fetch(byPrimaryKey: bob.id)
            try bob.delete()
            let after = try User.fetch(byPrimaryKey: bob.id)
            return ok([
                "updated: \(String(describing: byPK))",
                "after delete: \(String(describing: after))"
            ])
        },
        DemoItem(section: .crud, title: "Count / Exists / Page", subtitle: "分页 + 条件统计") {
            try prepareUsers()
            try User.insert((1...5).map { makeUser(username: "p\($0)", email: "p\($0)@demo.com", age: 20 + $0) })
            let count = try User.count(where: "age >= ?", bindings: [.integer(23)])
            let exists = try User.exists(where: "username = ?", bindings: [.text("p3")])
            let page = try User.fetchPage(orderBy: "\"id\" ASC", limit: 2, offset: 1)
            return ok(["count>=23: \(count)", "exists p3: \(exists)", "page: \(page)"])
        },
        DemoItem(section: .crud, title: "按 Query 删除", subtitle: "delete(query) 必须有谓词") {
            try prepareUsers()
            try User.insert([
                makeUser(username: "del1", email: "del1@demo.com", age: 10),
                makeUser(username: "del2", email: "del2@demo.com", age: 11)
            ])
            try User.delete(User.query().where(User.ageField < 20))
            return ok(["remaining: \(try User.count())"])
        },
        DemoItem(section: .crud, title: "Unique 约束失败", subtitle: "重复 email 应报错") {
            try prepareUsers()
            try makeUser(username: "a1", email: "dup@demo.com").insert()
            do {
                try makeUser(username: "a2", email: "dup@demo.com").insert()
                throw DemoAssertError("unique should fail")
            } catch is DemoAssertError {
                throw DemoAssertError("unique should fail")
            } catch {
                return ok(["blocked: \(error)"])
            }
        },

        // MARK: Query
        DemoItem(section: .query, title: "Typed Field 查询", subtitle: "ageField / usernameField") {
            try seedQueryUsers()
            let q = User.query()
                .where((User.ageField >= 20) && User.usernameField.starts(with: "a"))
                .orderBy(User.ageField.descending())
                .limit(10)
            return ok(["rows: \(try User.fetchAll(q))"])
        },
        DemoItem(section: .query, title: "Dynamic fields", subtitle: "User.fields.age") {
            try seedQueryUsers()
            let q = User.query()
                .where((User.fields.age >= 20) && User.fields.username.starts(with: "b"))
                .orderBy(User.fields.age.descending())
            return ok(["rows: \(try User.fetchAll(q))"])
        },
        DemoItem(section: .query, title: "AND / OR / NOT · in · like", subtitle: "谓词组合") {
            try seedQueryUsers()
            let orQ = User.query().where(
                (User.usernameField == "alice").or(User.usernameField == "bruce")
            )
            let inQ = User.query().where(try User.ageField.in([28, 35]))
            let likeQ = User.query().where(User.emailField.like("%@example.com"))
            let notQ = User.query().where(User.usernameField.starts(with: "a").not())
            return ok([
                "OR: \(try User.fetchAll(orQ).map(\.username))",
                "IN: \(try User.fetchAll(inQ).map(\.username))",
                "LIKE: \(try User.fetchAll(likeQ).map(\.username))",
                "NOT starts a: \(try User.fetchAll(notQ).map(\.username))"
            ])
        },
        DemoItem(section: .query, title: "contains / isNull / isNotNull", subtitle: "字符串与空值") {
            try seedQueryUsers()
            let contains = User.query().where(User.usernameField.contains("ru"))
            let notNull = User.query().where(User.emailField.isNotNull())
            return ok([
                "contains ru: \(try User.fetchAll(contains).map(\.username))",
                "email not null count: \(try User.count(notNull))"
            ])
        },
        DemoItem(section: .query, title: "非法字段延迟报错", subtitle: "fields.noSuchColumn") {
            try prepareUsers()
            do {
                _ = try User.fetchAll(User.query().where(User.fields.noSuchColumn == "x"))
                throw DemoAssertError("invalid field should throw")
            } catch is DemoAssertError {
                throw DemoAssertError("invalid field should throw")
            } catch {
                return ok(["deferred error: \(error)"])
            }
        },

        // MARK: Types
        DemoItem(section: .types, title: "JSON 列读写", subtitle: "@TFYColumn(.json) DemoAddress") {
            try prepareUsers()
            var user = makeUser(username: "json", email: "json@demo.com")
            user.address = DemoAddress(city: "Shanghai", zipCode: "200000")
            try user.insert()
            guard var fetched = try User.fetchAll(where: "username = ?", bindings: [.text("json")]).first else {
                throw DemoAssertError("json user missing")
            }
            fetched.address.city = "Shenzhen"
            try fetched.update()
            let again = try User.fetch(byPrimaryKey: fetched.id)
            return ok(["address: \(String(describing: again?.address))"])
        },
        DemoItem(section: .types, title: "Bool / Date / Data / Double", subtitle: "TypeSample 往返") {
            try reset()
            _ = try TypeSample.createTable()
            let date = Date(timeIntervalSinceReferenceDate: 12345)
            let blob = Data([0x01, 0x02, 0xFF])
            try TypeSample(id: 0, flag: true, createdAt: date, blob: blob, score: 3.14).insert()
            guard let row = try TypeSample.fetchAll().first else {
                throw DemoAssertError("type sample missing")
            }
            let okFlag = row.flag == true
            let okDate = abs(row.createdAt.timeIntervalSinceReferenceDate - 12345) < 0.001
            let okBlob = row.blob == blob
            let okScore = abs(row.score - 3.14) < 0.0001
            guard okFlag && okDate && okBlob && okScore else {
                throw DemoAssertError("type round-trip failed: \(row)")
            }
            return ok(["row: \(row)"])
        },
        DemoItem(section: .types, title: "@TFYIgnore 不落库", subtitle: "cacheOnlyField") {
            try prepareUsers()
            var user = makeUser(username: "ign", email: "ign@demo.com")
            user.cacheOnlyField = "transient"
            try user.insert()
            guard let fetched = try User.fetchAll(where: "username = ?", bindings: [.text("ign")]).first else {
                throw DemoAssertError("ignore user missing")
            }
            guard fetched.cacheOnlyField.isEmpty else {
                throw DemoAssertError("ignored field should not persist")
            }
            return ok(["cacheOnlyField after fetch: '\(fetched.cacheOnlyField)'"])
        },

        // MARK: Transaction
        DemoItem(section: .transaction, title: "Model.transaction", subtitle: "批量写入包裹事务") {
            try prepareUsers()
            try User.transaction {
                try User.insert([
                    makeUser(username: "t1", email: "t1@demo.com"),
                    makeUser(username: "t2", email: "t2@demo.com")
                ])
            }
            return ok(["count: \(try User.count())"])
        },
        DemoItem(section: .transaction, title: "抛错回滚", subtitle: "事务失败数据不残留") {
            try prepareUsers()
            try makeUser(username: "keep", email: "keep@demo.com").insert()
            do {
                try User.transaction {
                    try makeUser(username: "roll", email: "roll@demo.com").insert()
                    throw DemoAssertError("force rollback")
                }
            } catch is DemoAssertError {
                // expected
            }
            let names = try User.fetchAll().map(\.username)
            guard names == ["keep"] else {
                throw DemoAssertError("rollback leaked rows: \(names)")
            }
            return ok(["after rollback: \(names)"])
        },
        DemoItem(section: .transaction, title: "嵌套 Savepoint", subtitle: "connection.withTransaction") {
            try prepareUsers()
            let conn = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            try conn.withTransaction {
                try makeUser(username: "outer", email: "outer@demo.com").insert()
                do {
                    try conn.withTransaction {
                        try makeUser(username: "inner", email: "inner@demo.com").insert()
                        throw DemoAssertError("inner rollback")
                    }
                } catch is DemoAssertError {
                    // inner rolled back via savepoint
                }
            }
            let names = try User.fetchAll().map(\.username)
            guard names == ["outer"] else {
                throw DemoAssertError("nested savepoint unexpected: \(names)")
            }
            return ok(["names: \(names)"])
        },

        // MARK: Migration
        DemoItem(section: .migration, title: "Legacy → ADD COLUMN", subtitle: "safe 升级") {
            try reset()
            let legacy = try LegacyUser.createTable()
            try LegacyUser(id: 0, username: "legacy_user").insert()
            let upgrade = try User.createTable()
            let second = try User.createTable()
            let conn = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            let raw = try conn.query("SELECT id, username, email, age FROM \"user\";")
            // New non-optional columns are NULL on legacy rows — fetch via typed ORM only where email IS NOT NULL.
            try makeUser(username: "fresh", email: "fresh@demo.com", age: 26).insert()
            let typed = try User.fetchAll(where: "\"email\" IS NOT NULL")
            return ok(
                ["legacy:"] + legacy.formattedLines()
                + ["upgrade:"] + upgrade.formattedLines()
                + ["idempotent:"] + second.formattedLines()
                + ["raw after ADD COLUMN: \(raw)", "typed (email NOT NULL): \(typed)"]
            )
        },
        DemoItem(section: .migration, title: "rebuildTable 迁移", subtitle: "rename + expression + validate") {
            try reset()
            _ = try LegacyAuditEvent.createTable()
            try LegacyAuditEvent(id: 0, city: "Wuhan", legacyFlag: 1).insert()
            let report = try AuditEvent.createTable()
            let rows = try AuditEvent.fetchAll(AuditEvent.query().where(AuditEvent.messageField == "migrated"))
            guard let first = rows.first, first.payload.city == "Wuhan" else {
                throw DemoAssertError("rebuild payload unexpected: \(rows)")
            }
            return ok(report.formattedLines() + ["rows: \(rows)"])
        },
        DemoItem(section: .migration, title: "Migration Journal", subtitle: "__tfy_schema_journal") {
            try reset()
            _ = try User.createTable()
            _ = try Order.createTable()
            let main = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            let journal = try main.query(
                "SELECT table_name, schema_signature FROM \(TFYSwiftSQL.escapeIdentifier(TFYSwiftSchemaMigrator.journalTableName)) ORDER BY table_name;"
            )
            return ok(["journal: \(journal)"])
        },

        // MARK: Low-level
        DemoItem(section: .lowLevel, title: "Connection query / scalar / execute", subtitle: "原始 SQL") {
            try prepareUsers()
            try makeUser(username: "raw", email: "raw@demo.com", age: 33).insert()
            let conn = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            let rows = try conn.query(
                "SELECT username, age FROM \"user\" WHERE username = ?;",
                bindings: [.text("raw")]
            )
            let count = try conn.scalar("SELECT COUNT(*) FROM \"user\";")
            try conn.execute("UPDATE \"user\" SET age = ? WHERE username = ?;", bindings: [.integer(34), .text("raw")])
            return ok(["rows: \(rows)", "count: \(String(describing: count))", "lastRowID: \(conn.lastInsertedRowID)"])
        },
        DemoItem(section: .lowLevel, title: "Prepared Statement 复用", subtitle: "prepare · bind · step") {
            try prepareUsers()
            let conn = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            let statement = try conn.prepare(
                "INSERT INTO \"user\" (\"username\", \"email\", \"nickname\", \"age\", \"address\") VALUES (?, ?, ?, ?, ?);"
            )
            for i in 1...3 {
                try conn.execute(
                    statement,
                    bindings: [
                        .text("stmt_\(i)"),
                        .text("stmt_\(i)@demo.com"),
                        .text("guest"),
                        .integer(Int64(i)),
                        .text("{\"city\":\"X\",\"zipCode\":\"0\"}")
                    ]
                )
            }
            return ok(["count: \(try User.count())", "lastRowID: \(conn.lastInsertedRowID)"])
        },
        DemoItem(section: .lowLevel, title: "Introspection", subtitle: "tableExists / pragmaTableInfo / indexList") {
            try prepareUsers()
            let conn = try TFYSwiftDatabaseCenter.shared.open(named: "demo_main")
            let exists = try conn.tableExists("user")
            let columns = try conn.pragmaTableInfo(tableName: "user")
            let indexes = try conn.pragmaIndexList(tableName: "user")
            return ok([
                "exists: \(exists)",
                "columns: \(columns.map(\.name))",
                "indexes: \(indexes.map { "\($0.name) unique=\($0.unique)" })"
            ])
        },
        DemoItem(section: .lowLevel, title: "错误类型示例", subtitle: "TFYSwiftDBError.notFound 等") {
            try prepareUsers()
            let missing = try User.fetch(byPrimaryKey: 999_999)
            do {
                try User.delete(User.query())
                throw DemoAssertError("empty predicate delete should fail")
            } catch is DemoAssertError {
                throw DemoAssertError("empty predicate delete should fail")
            } catch {
                return ok([
                    "missing PK: \(String(describing: missing))",
                    "empty delete error: \(error)"
                ])
            }
        },

        // MARK: Benchmark
        DemoItem(section: .benchmark, title: "Write Benchmark", subtitle: "bulk insert ops/s") {
            try prepareUsers()
            let report = try TFYSwiftBenchmark.write(
                User.self,
                name: "bulk_user_insert",
                iterations: 4,
                batchSize: 25
            ) { index in
                makeUser(
                    username: "bench_\(index)",
                    email: "bench_\(index)@demo.com",
                    age: 18 + (index % 10)
                )
            }
            guard report.operationsPerSecond > 0 else {
                throw DemoAssertError("ops/s should be > 0")
            }
            return ok([
                "\(report.name): \(report.iterations * report.batchSize) ops",
                "elapsed: \(String(format: "%.3f", report.elapsed))s",
                "ops/s: \(Int(report.operationsPerSecond))"
            ])
        },
        DemoItem(section: .benchmark, title: "Read Benchmark", subtitle: "重复 fetchAll") {
            try prepareUsers()
            try User.insert((0..<40).map {
                makeUser(username: "r\($0)", email: "r\($0)@demo.com", age: 20 + ($0 % 5))
            })
            let report = try TFYSwiftBenchmark.read(
                User.self,
                name: "user_read",
                iterations: 20,
                query: User.query().where(User.ageField >= 20).limit(20)
            )
            return ok([
                "\(report.name): iterations=\(report.iterations)",
                "elapsed: \(String(format: "%.3f", report.elapsed))s",
                "ops/s: \(Int(report.operationsPerSecond))"
            ])
        },
        DemoItem(section: .benchmark, title: "Run All Demos", subtitle: "全量自检（含本项外全部）") {
            try runAll(excludingTitles: ["Run All Demos"])
        }
    ]

    static func items(in section: DemoSection) -> [DemoItem] {
        items.filter { $0.section == section }
    }

    static func runAll(excludingTitles: Set<String> = []) throws -> String {
        var lines: [String] = ["=== TFYSwiftSQLiteKit Full Demo ==="]
        var passed = 0
        var failed = 0
        let started = CFAbsoluteTimeGetCurrent()

        for item in items where !excludingTitles.contains(item.title) {
            do {
                let output = try item.run()
                passed += 1
                lines.append("✅ [\(item.section.title)] \(item.title)")
                lines.append(output)
                lines.append("")
            } catch {
                failed += 1
                lines.append("❌ [\(item.section.title)] \(item.title)")
                lines.append("ERROR: \(error)")
                lines.append("")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - started
        lines.insert(
            "summary: passed=\(passed) failed=\(failed) elapsed=\(String(format: "%.3f", elapsed))s",
            at: 1
        )
        if failed > 0 {
            throw DemoAssertError(lines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helpers

private struct DemoAssertError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func ok(_ lines: [String]) -> String {
    (["PASS"] + lines).joined(separator: "\n")
}

private func reset() throws {
    TFYSwiftDBRuntime.setSQLLogger(nil)
    TFYSwiftModelMirror.clearSchemaCache()
    let center = TFYSwiftDatabaseCenter.shared
    center.closeAll()
    for name in DemoCatalog.databaseNames {
        try? center.removeDatabase(named: name)
    }
}

private func prepareUsers() throws {
    try reset()
    _ = try User.createTable()
}

private func seedQueryUsers() throws {
    try prepareUsers()
    try User.insert([
        makeUser(username: "alice", email: "alice@example.com", age: 28, city: "Shanghai"),
        makeUser(username: "bruce", email: "bruce@example.com", age: 35, city: "Shenzhen"),
        makeUser(username: "cara", email: "cara@demo.com", age: 19, city: "Beijing")
    ])
}

private func makeUser(
    username: String,
    email: String,
    age: Int = 20,
    city: String = "DemoCity"
) -> User {
    User(
        id: 0,
        username: username,
        email: email,
        nickname: "guest",
        age: age,
        cacheOnlyField: "not persisted",
        address: DemoAddress(city: city, zipCode: "000000")
    )
}
