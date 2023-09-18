//
//  Copyright © 2023 Embrace Mobile, Inc. All rights reserved.
//

import Foundation
import GRDB

/// Class in charge of storing all the data colected by the Embrace SDK.
/// It provides an abstraction layer over a GRDB SQLite database.
public class EmbraceStorage {

    public private(set) var options: EmbraceStorageOptions
    public private(set) var dbQueue: DatabaseQueue

    /// Returns an EmbraceStorage instance initialized on the given path.
    /// - Parameters:
    ///   - baseUrl: URL containing the path when the database will be stored.
    init(options: EmbraceStorageOptions) throws {

        self.options = options

        // create base directory if necessary
        try FileManager.default.createDirectory(at: options.baseUrl, withIntermediateDirectories: true)

        // create sqlite file
        dbQueue = try DatabaseQueue(path: options.filePath)

        // define tables
        try dbQueue.write { db in
            try SessionRecord.defineTable(db: db)
            try SpanRecord.defineTable(db: db)
        }
    }

}

// MARK: - Sync operations
extension EmbraceStorage {
    /// Updates a record in the storage synchronously.
    /// - Parameter record: `PersistableRecord` to update
    public func update(record: PersistableRecord) throws {
        try dbQueue.write { db in
            try record.update(db)
        }
    }

    /// Deletes a record from the storage synchronously.
    /// - Parameter record: `PersistableRecord` to delete
    /// - Returns: Boolean indicating if the record was successfuly deleted
    public func delete(record: PersistableRecord) throws -> Bool {
        try dbQueue.write { db in
            return try record.delete(db)
        }
    }

    /// Fetches all the records of the given type in the storage synchronously.
    /// - Returns: Array containing all the records of the given type
    public func fetchAll<T: FetchableRecord & TableRecord>() throws -> [T] {
        try dbQueue.read { db in
            return try T.fetchAll(db)
        }
    }

    /// Executes the given SQL query synchronously.
    /// - Parameters:
    ///   - sql: SQL query to execute
    ///   - arguments: Arguments for the query, if any
    public func executeQuery(_ sql: String, arguments: StatementArguments?) throws {
        try dbQueue.write { db in
            try db.execute(sql: sql, arguments: arguments ?? StatementArguments())
        }
    }
}

// MARK: - Async operations
extension EmbraceStorage {
    /// Updates a record in the storage asynchronously.
    /// - Parameters:
    ///   - record: `PersistableRecord` to update
    ///   - completion: Completion block called with an `Error` on failure
    public func updateAsync(record: PersistableRecord, completion: ((Result<(), Error>) -> Void)?) {
        dbWriteAsync(block: { db in
            try record.update(db)
        }, completion: completion)
    }

    /// Deletes a record from the storage asynchronously.
    /// - Parameters:
    ///   - record: `PersistableRecord` to delete
    ///   - completion: Completion block called with an `Error` on failure
    /// - Returns: Boolean indicating if the record was successfuly deleted
    public func deleteAsync(record: PersistableRecord, completion: ((Result<Void, Error>) -> Void)?) {
        dbWriteAsync(block: { db in
            try record.delete(db)
        }, completion: completion)
    }

    /// Fetches all the records of the given type in the storage asynchronously.
    /// - Parameter completion: Completion block called with an array `[T]` with the fetch result on success, or an `Error` on failure
    /// - Returns: Array containing all the records of the given type
    public func fetchAllAsync<T: FetchableRecord & TableRecord>(completion: @escaping (Result<[T], Error>) -> Void) {
        dbFetchAsync(block: { db in
            return try T.fetchAll(db)
        }, completion: completion)
    }

    /// Executes the given SQL query asynchronously.
    /// - Parameters:
    ///   - sql: SQL query to execute
    ///   - arguments: Arguments for the query, if any
    ///   - completion: Completion block called with an `Error` on failure
    public func executeQueryAsync(_ sql: String, arguments: StatementArguments?, completion: ((Result<Void, Error>) -> Void)?) {
        dbWriteAsync(block: { db in
            try db.execute(sql: sql, arguments: arguments ?? StatementArguments())
        }, completion: completion)
    }
}
