import Foundation
import SQLite3
import os

private let log = Logger(subsystem: "com.librering.app", category: "Storage")

final class LocalStore: @unchecked Sendable {
    private let db: DatabaseHandle
    private let queue = DispatchQueue(label: "com.librering.store", qos: .utility)

    static let shared = LocalStore()

    private init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("librering.sqlite3")

        var handle: OpaquePointer?
        if sqlite3_open(url.path, &handle) != SQLITE_OK {
            log.error("Failed to open database")
        }
        db = DatabaseHandle(handle)
        sqlite3_exec(db.ptr, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db.ptr, "PRAGMA foreign_keys=ON", nil, nil, nil)

        let tables = """
        CREATE TABLE IF NOT EXISTS heart_rate (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL UNIQUE,
            bpm REAL NOT NULL,
            ibi_ms INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_hr_ts ON heart_rate(timestamp);

        CREATE TABLE IF NOT EXISTS spo2 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL UNIQUE,
            percent INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_spo2_ts ON spo2(timestamp);

        CREATE TABLE IF NOT EXISTS temperature (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL UNIQUE,
            celsius REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_temp_ts ON temperature(timestamp);

        CREATE TABLE IF NOT EXISTS sleep_phase (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL UNIQUE,
            phase INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sleep_ts ON sleep_phase(timestamp);

        CREATE TABLE IF NOT EXISTS steps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL UNIQUE,
            count INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_steps_ts ON steps(timestamp);

        CREATE TABLE IF NOT EXISTS baselines (
            metric TEXT PRIMARY KEY,
            mean REAL NOT NULL,
            deviation REAL NOT NULL,
            sample_count INTEGER NOT NULL,
            last_updated REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS daily_summary (
            date TEXT PRIMARY KEY,
            total_steps INTEGER DEFAULT 0,
            avg_hr REAL DEFAULT 0,
            min_hr REAL DEFAULT 0,
            avg_hrv REAL DEFAULT 0,
            avg_spo2 REAL DEFAULT 0,
            avg_temp REAL DEFAULT 0,
            sleep_score INTEGER DEFAULT 0,
            readiness_score INTEGER DEFAULT 0,
            activity_score INTEGER DEFAULT 0
        );
        """
        sqlite3_exec(db.ptr, tables, nil, nil, nil)
    }

    // MARK: - Insert

    func insertHeartRate(_ readings: [IBIReading]) {
        let db = self.db
        queue.async {
            guard !readings.isEmpty else { return }
            let sql = "INSERT OR IGNORE INTO heart_rate (timestamp, bpm, ibi_ms) VALUES (?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_exec(db.ptr, "BEGIN TRANSACTION", nil, nil, nil)
            for r in readings {
                sqlite3_bind_double(stmt, 1, r.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, r.bpm)
                sqlite3_bind_int(stmt, 3, Int32(r.intervalMs))
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db.ptr, "COMMIT", nil, nil, nil)
            sqlite3_finalize(stmt)
        }
    }

    func insertSpO2(_ readings: [SpO2Reading]) {
        let db = self.db
        queue.async {
            guard !readings.isEmpty else { return }
            let sql = "INSERT OR IGNORE INTO spo2 (timestamp, percent) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_exec(db.ptr, "BEGIN TRANSACTION", nil, nil, nil)
            for r in readings {
                sqlite3_bind_double(stmt, 1, r.timestamp.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(r.percent))
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db.ptr, "COMMIT", nil, nil, nil)
            sqlite3_finalize(stmt)
        }
    }

    func insertTemperature(_ readings: [TemperatureReading]) {
        let db = self.db
        queue.async {
            guard !readings.isEmpty else { return }
            let sql = "INSERT OR IGNORE INTO temperature (timestamp, celsius) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_exec(db.ptr, "BEGIN TRANSACTION", nil, nil, nil)
            for r in readings {
                sqlite3_bind_double(stmt, 1, r.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, r.celsius)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db.ptr, "COMMIT", nil, nil, nil)
            sqlite3_finalize(stmt)
        }
    }

    func insertSleepPhases(_ phases: [SleepPhaseReading]) {
        let db = self.db
        queue.async {
            guard !phases.isEmpty else { return }
            let sql = "INSERT OR IGNORE INTO sleep_phase (timestamp, phase) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_exec(db.ptr, "BEGIN TRANSACTION", nil, nil, nil)
            for p in phases {
                sqlite3_bind_double(stmt, 1, p.timestamp.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(p.phase.rawValue))
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db.ptr, "COMMIT", nil, nil, nil)
            sqlite3_finalize(stmt)
        }
    }

    func insertSteps(_ readings: [StepReading]) {
        let db = self.db
        queue.async {
            guard !readings.isEmpty else { return }
            let sql = "INSERT OR IGNORE INTO steps (timestamp, count) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_exec(db.ptr, "BEGIN TRANSACTION", nil, nil, nil)
            for r in readings {
                sqlite3_bind_double(stmt, 1, r.timestamp.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 2, Int32(r.count))
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db.ptr, "COMMIT", nil, nil, nil)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Baselines

    func saveBaseline(_ baseline: BaselineValue, metric: String) {
        let db = self.db
        queue.async {
            let sql = "INSERT OR REPLACE INTO baselines (metric, mean, deviation, sample_count, last_updated) VALUES (?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, (metric as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, baseline.mean)
            sqlite3_bind_double(stmt, 3, baseline.deviation)
            sqlite3_bind_int(stmt, 4, Int32(baseline.sampleCount))
            sqlite3_bind_double(stmt, 5, baseline.lastUpdated.timeIntervalSince1970)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func loadBaseline(metric: String) -> BaselineValue? {
        let db = self.db
        return queue.sync {
            let sql = "SELECT mean, deviation, sample_count, last_updated FROM baselines WHERE metric = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, (metric as NSString).utf8String, -1, nil)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return BaselineValue(
                mean: sqlite3_column_double(stmt, 0),
                deviation: sqlite3_column_double(stmt, 1),
                sampleCount: Int(sqlite3_column_int(stmt, 2)),
                lastUpdated: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            )
        }
    }

    // MARK: - Daily summary

    func saveDailySummary(date: String, steps: Int, avgHR: Double, minHR: Double, avgHRV: Double, avgSpO2: Double, avgTemp: Double, sleepScore: Int, readinessScore: Int, activityScore: Int) {
        let db = self.db
        queue.async {
            let sql = """
            INSERT OR REPLACE INTO daily_summary
            (date, total_steps, avg_hr, min_hr, avg_hrv, avg_spo2, avg_temp, sleep_score, readiness_score, activity_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(steps))
            sqlite3_bind_double(stmt, 3, avgHR)
            sqlite3_bind_double(stmt, 4, minHR)
            sqlite3_bind_double(stmt, 5, avgHRV)
            sqlite3_bind_double(stmt, 6, avgSpO2)
            sqlite3_bind_double(stmt, 7, avgTemp)
            sqlite3_bind_int(stmt, 8, Int32(sleepScore))
            sqlite3_bind_int(stmt, 9, Int32(readinessScore))
            sqlite3_bind_int(stmt, 10, Int32(activityScore))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func loadDailySummaries(days: Int = 14) -> [(date: String, steps: Int, avgHR: Double, avgHRV: Double, avgSpO2: Double, sleepScore: Int, readinessScore: Int, activityScore: Int)] {
        let db = self.db
        return queue.sync {
            let sql = "SELECT date, total_steps, avg_hr, avg_hrv, avg_spo2, sleep_score, readiness_score, activity_score FROM daily_summary ORDER BY date DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(days))
            defer { sqlite3_finalize(stmt) }
            var results: [(date: String, steps: Int, avgHR: Double, avgHRV: Double, avgSpO2: Double, sleepScore: Int, readinessScore: Int, activityScore: Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = String(cString: sqlite3_column_text(stmt, 0))
                results.append((
                    date: date,
                    steps: Int(sqlite3_column_int(stmt, 1)),
                    avgHR: sqlite3_column_double(stmt, 2),
                    avgHRV: sqlite3_column_double(stmt, 3),
                    avgSpO2: sqlite3_column_double(stmt, 4),
                    sleepScore: Int(sqlite3_column_int(stmt, 5)),
                    readinessScore: Int(sqlite3_column_int(stmt, 6)),
                    activityScore: Int(sqlite3_column_int(stmt, 7))
                ))
            }
            return results.reversed()
        }
    }

    // MARK: - CSV Export

    func exportCSV(from startDate: Date, to endDate: Date) -> Data? {
        let db = self.db
        return queue.sync {
            let start = startDate.timeIntervalSince1970
            let end = endDate.timeIntervalSince1970
            let fmt = ISO8601DateFormatter()

            var csv = "type,timestamp,value,extra\n"

            func appendRows(_ sql: String, type: String, valueCol: Int, extraCol: Int? = nil) {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return }
                sqlite3_bind_double(stmt, 1, start)
                sqlite3_bind_double(stmt, 2, end)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let ts = fmt.string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)))
                    let val = sqlite3_column_double(stmt, Int32(valueCol))
                    let extra = extraCol.map { String(sqlite3_column_double(stmt, Int32($0))) } ?? ""
                    csv += "\(type),\(ts),\(val),\(extra)\n"
                }
                sqlite3_finalize(stmt)
            }

            appendRows("SELECT timestamp, bpm, ibi_ms FROM heart_rate WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                       type: "heart_rate", valueCol: 1, extraCol: 2)
            appendRows("SELECT timestamp, percent FROM spo2 WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                       type: "spo2", valueCol: 1)
            appendRows("SELECT timestamp, celsius FROM temperature WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                       type: "temperature", valueCol: 1)
            appendRows("SELECT timestamp, phase FROM sleep_phase WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                       type: "sleep_phase", valueCol: 1)
            appendRows("SELECT timestamp, count FROM steps WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                       type: "steps", valueCol: 1)

            return csv.data(using: .utf8)
        }
    }

    // MARK: - Cloud sync snapshots

    /// Rows formatted for Supabase `push_sync_batch` RPC.
    func syncBatches(limitPerTable: Int = 500) -> [(table: String, records: [[String: Any]])] {
        let db = self.db
        return queue.sync {
            func queryDoubles(_ sql: String, columns: [String]) -> [[String: Any]] {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
                sqlite3_bind_int(stmt, 1, Int32(limitPerTable))
                var rows: [[String: Any]] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: Any] = [:]
                    for (i, col) in columns.enumerated() {
                        row[col] = sqlite3_column_double(stmt, Int32(i))
                    }
                    rows.append(row)
                }
                sqlite3_finalize(stmt)
                return rows
            }

            return [
                ("heart_rate", queryDoubles(
                    "SELECT timestamp, bpm, ibi_ms FROM heart_rate ORDER BY timestamp DESC LIMIT ?",
                    columns: ["timestamp", "bpm", "ibi_ms"]
                )),
                ("spo2", queryDoubles(
                    "SELECT timestamp, percent FROM spo2 ORDER BY timestamp DESC LIMIT ?",
                    columns: ["timestamp", "percent"]
                )),
                ("steps", queryDoubles(
                    "SELECT timestamp, count FROM steps ORDER BY timestamp DESC LIMIT ?",
                    columns: ["timestamp", "count"]
                )),
            ]
        }
    }

    // MARK: - Export

    func exportJSON(from startDate: Date, to endDate: Date) -> Data? {
        let db = self.db
        return queue.sync {
            var export: [String: Any] = [
                "exported_at": ISO8601DateFormatter().string(from: Date()),
                "source": "LibreRing",
                "format_version": 1,
                "range": [
                    "start": ISO8601DateFormatter().string(from: startDate),
                    "end": ISO8601DateFormatter().string(from: endDate),
                ],
            ]

            let start = startDate.timeIntervalSince1970
            let end = endDate.timeIntervalSince1970

            func queryRows(_ sql: String, params: [Double], columns: [String]) -> [[String: Any]] {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
                for (i, param) in params.enumerated() {
                    sqlite3_bind_double(stmt, Int32(i + 1), param)
                }
                var rows: [[String: Any]] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: Any] = [:]
                    for (i, col) in columns.enumerated() {
                        row[col] = sqlite3_column_double(stmt, Int32(i))
                    }
                    rows.append(row)
                }
                sqlite3_finalize(stmt)
                return rows
            }

            export["heart_rate"] = queryRows(
                "SELECT timestamp, bpm, ibi_ms FROM heart_rate WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                params: [start, end], columns: ["timestamp", "bpm", "ibi_ms"]
            )
            export["spo2"] = queryRows(
                "SELECT timestamp, percent FROM spo2 WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                params: [start, end], columns: ["timestamp", "percent"]
            )
            export["temperature"] = queryRows(
                "SELECT timestamp, celsius FROM temperature WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                params: [start, end], columns: ["timestamp", "celsius"]
            )
            export["sleep"] = queryRows(
                "SELECT timestamp, phase FROM sleep_phase WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                params: [start, end], columns: ["timestamp", "phase"]
            )
            export["steps"] = queryRows(
                "SELECT timestamp, count FROM steps WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                params: [start, end], columns: ["timestamp", "count"]
            )

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let startStr = fmt.string(from: startDate)
            let endStr = fmt.string(from: endDate)

            func queryStringRows(_ sql: String, dateParams: [String], columns: [String]) -> [[String: Any]] {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
                for (i, param) in dateParams.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
                }
                var rows: [[String: Any]] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: Any] = [:]
                    for (i, col) in columns.enumerated() {
                        if col == "date" {
                            row[col] = String(cString: sqlite3_column_text(stmt, Int32(i)))
                        } else if col == "metric" {
                            row[col] = String(cString: sqlite3_column_text(stmt, Int32(i)))
                        } else {
                            row[col] = sqlite3_column_double(stmt, Int32(i))
                        }
                    }
                    rows.append(row)
                }
                sqlite3_finalize(stmt)
                return rows
            }

            export["daily_summary"] = queryStringRows(
                "SELECT date, total_steps, avg_hr, min_hr, avg_hrv, avg_spo2, avg_temp, sleep_score, readiness_score, activity_score FROM daily_summary WHERE date BETWEEN ? AND ? ORDER BY date",
                dateParams: [startStr, endStr],
                columns: ["date", "total_steps", "avg_hr", "min_hr", "avg_hrv", "avg_spo2", "avg_temp", "sleep_score", "readiness_score", "activity_score"]
            )

            export["baselines"] = queryRows(
                "SELECT mean, deviation, sample_count, last_updated FROM baselines",
                params: [],
                columns: ["mean", "deviation", "sample_count", "last_updated"]
            )
            // Add metric name to baselines (queryRows only handles doubles)
            var baselineRows: [[String: Any]] = []
            var bstmt: OpaquePointer?
            if sqlite3_prepare_v2(db.ptr, "SELECT metric, mean, deviation, sample_count, last_updated FROM baselines", -1, &bstmt, nil) == SQLITE_OK {
                while sqlite3_step(bstmt) == SQLITE_ROW {
                    baselineRows.append([
                        "metric": String(cString: sqlite3_column_text(bstmt, 0)),
                        "mean": sqlite3_column_double(bstmt, 1),
                        "deviation": sqlite3_column_double(bstmt, 2),
                        "sample_count": sqlite3_column_double(bstmt, 3),
                        "last_updated": sqlite3_column_double(bstmt, 4),
                    ])
                }
                sqlite3_finalize(bstmt)
            }
            export["baselines"] = baselineRows

            return try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        }
    }
}

// Sendable wrapper for OpaquePointer (single-writer via DispatchQueue)
private final class DatabaseHandle: @unchecked Sendable {
    let ptr: OpaquePointer?
    init(_ ptr: OpaquePointer?) { self.ptr = ptr }
}
