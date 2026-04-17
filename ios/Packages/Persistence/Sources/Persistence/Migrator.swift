import Foundation
import GRDB
import Core

enum Migrator {
    static func register(on pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        try migrator.registerFromResources()
        try migrator.migrate(pool)
        AppLog.persistence.info("GRDB migrations applied")
    }
}

private extension DatabaseMigrator {
    mutating func registerFromResources() throws {
        let bundle = Bundle.module
        guard let folderURL = bundle.url(forResource: "Migrations", withExtension: nil) else {
            AppLog.persistence.error("Migrations resource folder not found in bundle")
            return
        }

        let fm = FileManager.default
        let files = (try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension.lowercased() == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            let sql = try String(contentsOf: url, encoding: .utf8)
            registerMigration(name) { db in
                try db.execute(sql: sql)
            }
        }
    }
}
