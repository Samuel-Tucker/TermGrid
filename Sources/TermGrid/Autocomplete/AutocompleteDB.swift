import Foundation
import GRDB

// MARK: - Records

struct CorpusRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "corpus"

    var id: Int64?
    var content: String
    var domain: String
    var timestamp: Double
    var acceptedFromSuggestion: Int
    var workingDirectory: String

    enum CodingKeys: String, CodingKey {
        case id, content, domain, timestamp
        case acceptedFromSuggestion = "accepted_from_suggestion"
        case workingDirectory = "working_directory"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct TrigramRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "trigrams"

    var w1: String
    var w2: String
    var w3: String
    var count: Int
    var lastUsed: Double
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case w1, w2, w3, count
        case lastUsed = "last_used"
        case confidence
    }
}

struct PrefixRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "prefixes"

    var prefix: String
    var completion: String
    var frequency: Int
    var lastUsed: Double
    var domain: String

    enum CodingKeys: String, CodingKey {
        case prefix, completion, frequency
        case lastUsed = "last_used"
        case domain
    }
}

// MARK: - Database

final class AutocompleteDB: Sendable {
    let dbQueue: DatabaseQueue

    /// Production init: ~/Library/Application Support/TermGrid/autocomplete.db
    convenience init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("TermGrid")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try self.init(path: dir.appendingPathComponent("autocomplete.db").path)
    }

    /// Testable init: use `:memory:` or any path.
    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "corpus") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull()
                t.column("domain", .text).notNull().defaults(to: "shell")
                t.column("timestamp", .double).notNull()
                t.column("accepted_from_suggestion", .integer).defaults(to: 0)
                t.column("working_directory", .text).defaults(to: "")
            }

            try db.create(table: "trigrams") { t in
                t.column("w1", .text).notNull()
                t.column("w2", .text).notNull()
                t.column("w3", .text).notNull()
                t.column("count", .integer).notNull().defaults(to: 1)
                t.column("last_used", .double).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0.5)
                t.primaryKey(["w1", "w2", "w3"])
            }

            try db.create(table: "prefixes") { t in
                t.column("prefix", .text).notNull()
                t.column("completion", .text).notNull()
                t.column("frequency", .integer).notNull().defaults(to: 1)
                t.column("last_used", .double).notNull()
                t.column("domain", .text).notNull().defaults(to: "shell")
                t.primaryKey(["prefix", "completion", "domain"])
            }

            try db.create(index: "idx_prefix", on: "prefixes", columns: ["prefix", "domain"])
            try db.create(index: "idx_trigram", on: "trigrams", columns: ["w1", "w2"])
            try db.create(index: "idx_corpus_timestamp", on: "corpus", columns: ["timestamp"])
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Corpus

    func insertCorpus(_ record: CorpusRecord) throws {
        try dbQueue.write { db in
            var r = record
            try r.insert(db)
        }
    }

    func recentCorpus(limit: Int = 100) throws -> [CorpusRecord] {
        try dbQueue.read { db in
            try CorpusRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Trigrams

    func upsertTrigram(_ record: TrigramRecord) throws {
        try dbQueue.write { db in
            if var existing = try TrigramRecord.fetchOne(db, key: ["w1": record.w1, "w2": record.w2, "w3": record.w3]) {
                existing.count += record.count
                existing.lastUsed = max(existing.lastUsed, record.lastUsed)
                try existing.update(db)
            } else {
                try record.insert(db)
            }
        }
    }

    func queryTrigrams(w1: String, w2: String) throws -> [TrigramRecord] {
        try dbQueue.read { db in
            try TrigramRecord
                .filter(Column("w1") == w1 && Column("w2") == w2)
                .order(Column("count").desc)
                .fetchAll(db)
        }
    }

    func updateTrigramConfidence(w1: String, w2: String, w3: String, confidence: Double) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trigrams SET confidence = ? WHERE w1 = ? AND w2 = ? AND w3 = ?",
                arguments: [confidence, w1, w2, w3]
            )
        }
    }

    // MARK: - Prefixes

    func upsertPrefix(_ record: PrefixRecord) throws {
        try dbQueue.write { db in
            if var existing = try PrefixRecord.fetchOne(db, key: ["prefix": record.prefix, "completion": record.completion, "domain": record.domain]) {
                existing.frequency += record.frequency
                existing.lastUsed = max(existing.lastUsed, record.lastUsed)
                try existing.update(db)
            } else {
                try record.insert(db)
            }
        }
    }

    func queryPrefixes(prefix: String, domain: String, limit: Int = 10) throws -> [PrefixRecord] {
        try dbQueue.read { db in
            try PrefixRecord
                .filter(Column("prefix") == prefix && Column("domain") == domain)
                .order(Column("frequency").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func allPrefixes() throws -> [PrefixRecord] {
        try dbQueue.read { db in
            try PrefixRecord.fetchAll(db)
        }
    }

    func allTrigrams() throws -> [TrigramRecord] {
        try dbQueue.read { db in
            try TrigramRecord.fetchAll(db)
        }
    }

    // MARK: - Maintenance

    func pruneOldEntries(olderThan days: Double = 90, minConfidence: Double = 0.1) throws {
        let cutoff = Date().timeIntervalSince1970 - (days * 86400)
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM trigrams WHERE last_used < ? AND confidence < ?",
                arguments: [cutoff, minConfidence]
            )
            try db.execute(
                sql: "DELETE FROM prefixes WHERE last_used < ?",
                arguments: [cutoff]
            )
        }
    }
}
