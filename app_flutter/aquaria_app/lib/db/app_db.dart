import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

class Tanks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get gallons => integer()();
  TextColumn get waterType => text()(); // 'freshwater' or 'saltwater'
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  // JSON object: {"gh":8,"kh":4,"ph":7.2,"ammonia":0,"nitrite":0,"nitrate":5,"tds":200}
  TextColumn get tapWaterJson => text().nullable()();
  // JSON object for equipment config (filter, lighting, substrate, etc.)
  TextColumn get equipmentJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Inhabitants extends Table {
  // IMPORTANT: int autoincrement id (do NOT set manually)
  IntColumn get id => integer().autoIncrement()();

  TextColumn get tankId => text()();
  TextColumn get name => text()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  // Type: fish | invertebrate | coral | polyp | anemone | plant
  TextColumn get type => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
      ];
}

class Plants extends Table {
  // IMPORTANT: int autoincrement id (do NOT set manually)
  IntColumn get id => integer().autoIncrement()();

  TextColumn get tankId => text()();
  TextColumn get name => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
      ];
}

class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cloudId => integer().nullable()();
  TextColumn get tankId => text()();
  TextColumn get rawText => text()();
  TextColumn get parsedJson => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
      ];
}

class TankPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tankId => text()();
  TextColumn get filePath => text()();
  TextColumn get remotePath => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
      ];
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tankId => text()();
  TextColumn get description => text()();
  TextColumn get dueDate => text().nullable()(); // ISO date string YYYY-MM-DD
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  TextColumn get source => text().withDefault(const Constant('ai'))(); // 'ai' or 'alert'
  BoolColumn get isDismissed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  BoolColumn get isComplete => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get repeatDays => integer().nullable()(); // recurrence interval in days (null = one-off)
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
      ];
}

class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cloudId => integer().nullable()();
  TextColumn get tankId => text()();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get category => text()(); // 'measurements', 'actions', 'notes'
  TextColumn get data => text()(); // JSON (object for measurements, array for actions/notes)
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
        'UNIQUE(tank_id, date, category)',
      ];
}

class ChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tankId => text().nullable()();
  TextColumn get summary => text()();
  IntColumn get messageCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();
}

@DriftDatabase(tables: [Tanks, Inhabitants, Plants, Logs, TankPhotos, Tasks, JournalEntries, ChatSessions])
class AppDb extends _$AppDb {
  AppDb() : super(_openConnection());

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE TABLE IF NOT EXISTS dismissed_tasks (task_key TEXT PRIMARY KEY)',
          );
          await customStatement(
            'CREATE TABLE IF NOT EXISTS deleted_log_keys '
            '(tank_id TEXT NOT NULL, created_at_utc TEXT NOT NULL, '
            'PRIMARY KEY(tank_id, created_at_utc))',
          );
          await customStatement(
            'CREATE TABLE IF NOT EXISTS synced_log_keys '
            '(tank_id TEXT NOT NULL, created_at_utc TEXT NOT NULL, '
            'PRIMARY KEY(tank_id, created_at_utc))',
          );
        },
        onUpgrade: (migrator, from, to) async {
          if (from == 1) {
            await migrator.addColumn(tanks, tanks.isArchived);
            await migrator.addColumn(tanks, tanks.archivedAt);
          }
          if (from <= 2) {
            await migrator.createTable(inhabitants);
            await migrator.createTable(plants);
          }
          if (from <= 3) {
            await migrator.createTable(logs);
          }
          if (from <= 4) {
            await migrator.addColumn(inhabitants, inhabitants.type);
          }
          if (from <= 5) {
            await migrator.addColumn(tanks, tanks.tapWaterJson);
          }
          if (from <= 6) {
            await customStatement(
              'CREATE TABLE IF NOT EXISTS dismissed_tasks (task_key TEXT PRIMARY KEY)',
            );
          }
          if (from <= 7) {
            await migrator.createTable(tankPhotos);
          }
          if (from <= 8) {
            await migrator.createTable(tasks);
          }
          if (from <= 9) {
            await migrator.createTable(chatSessions);
          }
          if (from <= 10) {
            await migrator.addColumn(tasks, tasks.repeatDays);
          }
          if (from <= 11) {
            await migrator.addColumn(tasks, tasks.isPaused);
          }
          if (from <= 12) {
            await migrator.addColumn(tasks, tasks.isComplete);
            await migrator.addColumn(tasks, tasks.completedAt);
          }
          if (from <= 13) {
            await customStatement(
              'CREATE TABLE IF NOT EXISTS deleted_log_keys '
              '(tank_id TEXT NOT NULL, created_at_utc TEXT NOT NULL, '
              'PRIMARY KEY(tank_id, created_at_utc))',
            );
          }
          if (from <= 14) {
            await customStatement(
              'CREATE TABLE IF NOT EXISTS synced_log_keys '
              '(tank_id TEXT NOT NULL, created_at_utc TEXT NOT NULL, '
              'PRIMARY KEY(tank_id, created_at_utc))',
            );
          }
          if (from <= 15) {
            await migrator.addColumn(logs, logs.cloudId);
          }
          if (from <= 16) {
            await migrator.createTable(journalEntries);
          }
          if (from <= 17) {
            await migrator.addColumn(tanks, tanks.equipmentJson);
          }
          if (from <= 18) {
            await migrator.addColumn(tankPhotos, tankPhotos.remotePath);
          }
        },
      );

  // ---------- Tanks ----------
  Future<List<Tank>> getActiveTanks() {
    return (select(tanks)..where((t) => t.isArchived.equals(false))).get();
  }

  Future<List<Tank>> getArchivedTanks() {
    return (select(tanks)..where((t) => t.isArchived.equals(true))).get();
  }

  Future<void> archiveTankById(String id) async {
    await (update(tanks)..where((t) => t.id.equals(id))).write(
      TanksCompanion(
        isArchived: const Value(true),
        archivedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> restoreTankById(String id) async {
    await (update(tanks)..where((t) => t.id.equals(id))).write(
      const TanksCompanion(
        isArchived: Value(false),
        archivedAt: Value(null),
      ),
    );
  }

  Future<void> upsertTank(TanksCompanion entry) =>
      into(tanks).insertOnConflictUpdate(entry);

  Future<void> deleteTankById(String id) async {
    await (delete(tanks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateTapWater(String id, String? tapWaterJson) async {
    await (update(tanks)..where((t) => t.id.equals(id))).write(
      TanksCompanion(tapWaterJson: Value(tapWaterJson)),
    );
  }

  Future<void> updateEquipment(String id, String? equipmentJson) async {
    await (update(tanks)..where((t) => t.id.equals(id))).write(
      TanksCompanion(equipmentJson: Value(equipmentJson)),
    );
  }

  // ---------- Inhabitants ----------
  Future<List<Inhabitant>> inhabitantsForTank(String tankId) {
    return (select(inhabitants)..where((r) => r.tankId.equals(tankId))).get();
  }

  Future<void> replaceInhabitantsForTank(
    String tankId,
    List<InhabitantsCompanion> rows,
  ) async {
    await transaction(() async {
      await (delete(inhabitants)..where((r) => r.tankId.equals(tankId))).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAll(inhabitants, rows));
      }
    });
  }

  Future<void> insertInhabitant(InhabitantsCompanion entry) =>
      into(inhabitants).insert(entry);

  // ---------- Plants ----------
  Future<List<Plant>> plantsForTank(String tankId) {
    return (select(plants)..where((r) => r.tankId.equals(tankId))).get();
  }

  Future<void> insertPlant(PlantsCompanion entry) =>
      into(plants).insert(entry);

  Future<int> deletePlantByName(String tankId, String name) {
    return (delete(plants)..where((r) =>
        r.tankId.equals(tankId) & r.name.equals(name))).go();
  }

  Future<int> renamePlant(String tankId, String oldName, String newName) {
    return (update(plants)..where((r) =>
        r.tankId.equals(tankId) & r.name.equals(oldName)))
        .write(PlantsCompanion(name: Value(newName)));
  }

  Future<void> replacePlantsForTank(
    String tankId,
    List<PlantsCompanion> rows,
  ) async {
    await transaction(() async {
      await (delete(plants)..where((r) => r.tankId.equals(tankId))).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAll(plants, rows));
      }
    });
  }

  // ---------- Logs ----------
  Future<List<Log>> logsForTank(String tankId) {
    return (select(logs)
          ..where((r) => r.tankId.equals(tankId))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }

  Future<int> insertLog(LogsCompanion entry) => into(logs).insert(entry);

  /// Replace all logs for a tank with the given rows (cloud wins).
  Future<void> replaceLogsForTank(String tankId, List<LogsCompanion> rows) async {
    await transaction(() async {
      await (delete(logs)..where((r) => r.tankId.equals(tankId))).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAll(logs, rows));
      }
    });
  }

  /// Check if a log with the same parsedJson already exists for this tank
  /// within the last 2 minutes (prevents duplicate parse results).
  Future<bool> hasDuplicateLog(String tankId, String? parsedJson) async {
    if (parsedJson == null || parsedJson.isEmpty) return false;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    final recent = await (select(logs)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.createdAt.isBiggerOrEqualValue(cutoff)))
        .get();
    for (final l in recent) {
      if (l.parsedJson == parsedJson) return true;
    }
    return false;
  }

  Future<Log?> logForTankOnDate(String tankId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final results = await (select(logs)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.createdAt.isBiggerOrEqualValue(startOfDay) &
              r.createdAt.isSmallerThanValue(endOfDay)))
        .get();
    return results.isEmpty ? null : results.first;
  }

  /// Check if a log with the exact created_at timestamp exists for this tank.
  Future<bool> logExistsForTankAt(String tankId, DateTime createdAt) async {
    final results = await (select(logs)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.createdAt.equals(createdAt)))
        .get();
    return results.isNotEmpty;
  }

  /// Set the cloud (Supabase) ID on a local log row.
  Future<void> setLogCloudId(int localId, int cloudId) async {
    await (update(logs)..where((r) => r.id.equals(localId))).write(
      LogsCompanion(cloudId: Value(cloudId)),
    );
  }

  /// Insert or update a log by tank + timestamp. Updates content if exists.
  Future<void> upsertLogByTimestamp(String tankId, DateTime createdAt, String rawText, String? parsedJson, {int? cloudId}) async {
    final existing = await (select(logs)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.createdAt.equals(createdAt)))
        .get();
    if (existing.isEmpty) {
      await insertLog(LogsCompanion.insert(
        tankId: tankId,
        rawText: rawText,
        parsedJson: Value(parsedJson),
        createdAt: Value(createdAt),
        cloudId: Value(cloudId),
      ));
    } else {
      await (update(logs)..where((r) => r.id.equals(existing.first.id))).write(
        LogsCompanion(
          rawText: Value(rawText),
          parsedJson: Value(parsedJson),
          cloudId: Value(cloudId),
        ),
      );
    }
  }

  /// Remove duplicate logs for a tank — keep only the oldest per (parsedJson, date).
  Future<int> deduplicateLogsForTank(String tankId) async {
    final all = await (select(logs)
          ..where((r) => r.tankId.equals(tankId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
    final seen = <String>{};
    int removed = 0;
    for (final l in all) {
      // Key by date + parsedJson content (or rawText if no parsed)
      final dateKey = '${l.createdAt.year}-${l.createdAt.month}-${l.createdAt.day}';
      final contentKey = l.parsedJson ?? l.rawText;
      final key = '$dateKey|$contentKey';
      if (seen.contains(key)) {
        await deleteLog(l.id);
        removed++;
      } else {
        seen.add(key);
      }
    }
    return removed;
  }

  Future<void> updateLog(int id, String rawText, String? parsedJson) async {
    await (update(logs)..where((r) => r.id.equals(id))).write(
      LogsCompanion(
        rawText: Value(rawText),
        parsedJson: Value(parsedJson),
      ),
    );
  }

  Future<Log?> getLogById(int id) async {
    final results = await (select(logs)..where((r) => r.id.equals(id))).get();
    return results.isEmpty ? null : results.first;
  }

  Future<void> deleteLog(int id) async {
    await (delete(logs)..where((r) => r.id.equals(id))).go();
  }

  // ---------- Dismissed tasks ----------
  Future<Set<String>> getDismissedTaskKeys() async {
    final rows = await customSelect('SELECT task_key FROM dismissed_tasks').get();
    return rows.map((r) => r.read<String>('task_key')).toSet();
  }

  Future<void> insertDismissedTask(String key) async {
    await customStatement(
      'INSERT OR IGNORE INTO dismissed_tasks (task_key) VALUES (?)',
      [key],
    );
  }

  // ---------- Tasks ----------
  Future<List<Task>> tasksForTank(String tankId) {
    return (select(tasks)
          ..where((r) => r.tankId.equals(tankId) & r.isDismissed.equals(false))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }

  Future<List<Task>> allActiveTasks() {
    return (select(tasks)
          ..where((r) => r.isDismissed.equals(false))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }

  Future<void> insertTask(TasksCompanion entry) => into(tasks).insert(entry);

  Future<bool> hasActiveRecurringTask(String tankId, String description) async {
    final rows = await (select(tasks)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.description.equals(description) &
              r.isDismissed.equals(false) &
              r.repeatDays.isNotNull()))
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> hasDuplicateTask(String tankId, String description, String? dueDate) async {
    // Check both active AND recently dismissed tasks (last 7 days) to avoid
    // re-creating the same task that was just dismissed or already exists.
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final allMatches = await (select(tasks)
          ..where((r) => r.tankId.equals(tankId)))
        .get();
    final descLower = description.toLowerCase().trim();
    for (final t in allMatches) {
      if (t.description.toLowerCase().trim() != descLower) continue;
      // Active (not dismissed) task with same description = duplicate
      if (!t.isDismissed) return true;
      // Recently dismissed task with same description = duplicate
      if (t.dismissedAt != null && t.dismissedAt!.isAfter(cutoff)) return true;
    }
    return false;
  }

  Future<Task?> getTaskById(int id) async {
    final rows = await (select(tasks)..where((r) => r.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Task>> allActiveRecurringTasks({String? tankId}) {
    final q = select(tasks)
      ..where((r) => r.isDismissed.equals(false) & r.repeatDays.isNotNull())
      ..orderBy([(r) => OrderingTerm.asc(r.dueDate)]);
    if (tankId != null) {
      q.where((r) => r.tankId.equals(tankId));
    }
    return q.get();
  }

  Future<void> updateTaskRepeatDays(int id, int repeatDays) async {
    await (update(tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(repeatDays: Value(repeatDays)),
    );
  }

  Future<void> setTaskPaused(int id, bool paused) async {
    await (update(tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(isPaused: Value(paused)),
    );
  }

  Future<void> dismissTaskById(int id) async {
    await (update(tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(
        isDismissed: const Value(true),
        dismissedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> completeTaskById(int id) async {
    await (update(tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(
        isComplete: const Value(true),
        completedAt: Value(DateTime.now()),
        isDismissed: const Value(true),
        dismissedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteTask(int id) async {
    await (delete(tasks)..where((r) => r.id.equals(id))).go();
  }

  // ---------- Tank Photos ----------
  Future<List<TankPhoto>> photosForTank(String tankId) {
    return (select(tankPhotos)
          ..where((r) => r.tankId.equals(tankId))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }

  Future<void> insertPhoto(TankPhotosCompanion entry) =>
      into(tankPhotos).insert(entry);

  Future<void> deletePhoto(int id) async {
    await (delete(tankPhotos)..where((r) => r.id.equals(id))).go();
  }

  Future<void> setPhotoRemotePath(int id, String remotePath) async {
    await (update(tankPhotos)..where((r) => r.id.equals(id)))
        .write(TankPhotosCompanion(remotePath: Value(remotePath)));
  }

  Future<List<TankPhoto>> photosWithoutRemotePath() {
    return (select(tankPhotos)
          ..where((r) => r.remotePath.isNull()))
        .get();
  }

  Future<TankPhoto?> photoByRemotePath(String remotePath) {
    return (select(tankPhotos)
          ..where((r) => r.remotePath.equals(remotePath))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> insertPhotoReturningId(TankPhotosCompanion entry) =>
      into(tankPhotos).insert(entry);

  Future<TankPhoto?> photoById(int id) {
    return (select(tankPhotos)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  // ---------- Chat Sessions ----------
  Future<List<ChatSession>> recentSessionsForTank(String? tankId, {int limit = 5}) {
    final q = select(chatSessions)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
      ..limit(limit);
    if (tankId != null) {
      q.where((r) => r.tankId.equals(tankId));
    }
    return q.get();
  }

  Future<void> insertChatSession(ChatSessionsCompanion entry) =>
      into(chatSessions).insert(entry);

  /// Remove duplicate active tasks — keep only the oldest per (tankId, description).
  Future<int> deduplicateActiveTasks() async {
    final allActive = await (select(tasks)
          ..where((r) => r.isDismissed.equals(false))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
    final seen = <String>{};
    int removed = 0;
    for (final t in allActive) {
      final key = '${t.tankId}|${t.description.toLowerCase().trim()}';
      if (seen.contains(key)) {
        await (delete(tasks)..where((r) => r.id.equals(t.id))).go();
        removed++;
      } else {
        seen.add(key);
      }
    }
    return removed;
  }

  // ---------- Journal Entries ----------
  Future<List<JournalEntry>> journalForTank(String tankId) {
    return (select(journalEntries)
          ..where((r) => r.tankId.equals(tankId))
          ..orderBy([
            (r) => OrderingTerm.desc(r.date),
            (r) => OrderingTerm.asc(r.category),
          ]))
        .get();
  }

  Future<List<JournalEntry>> journalForTankOnDate(String tankId, String date) {
    return (select(journalEntries)
          ..where((r) => r.tankId.equals(tankId) & r.date.equals(date)))
        .get();
  }

  /// Upsert a journal entry by (tankId, date, category).
  /// Returns the local row ID.
  Future<int> upsertJournalEntry({
    required String tankId,
    required String date,
    required String category,
    required String data,
    int? cloudId,
  }) async {
    final now = DateTime.now();
    final existing = await (select(journalEntries)
          ..where((r) =>
              r.tankId.equals(tankId) &
              r.date.equals(date) &
              r.category.equals(category)))
        .get();
    if (existing.isEmpty) {
      return into(journalEntries).insert(JournalEntriesCompanion.insert(
        tankId: tankId,
        date: date,
        category: category,
        data: data,
        updatedAt: now,
        cloudId: Value(cloudId),
      ));
    } else {
      final row = existing.first;
      await (update(journalEntries)..where((r) => r.id.equals(row.id))).write(
        JournalEntriesCompanion(
          data: Value(data),
          updatedAt: Value(now),
          cloudId: Value(cloudId ?? row.cloudId),
        ),
      );
      return row.id;
    }
  }

  Future<JournalEntry?> getJournalEntryById(int id) async {
    final rows = await (select(journalEntries)..where((r) => r.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setJournalCloudId(int localId, int cloudId) async {
    await (update(journalEntries)..where((r) => r.id.equals(localId))).write(
      JournalEntriesCompanion(cloudId: Value(cloudId)),
    );
  }

  Future<void> deleteJournalEntry(int id) async {
    await (delete(journalEntries)..where((r) => r.id.equals(id))).go();
  }

  Future<void> deleteJournalByKey(String tankId, String date, String category) async {
    await (delete(journalEntries)..where((r) =>
        r.tankId.equals(tankId) &
        r.date.equals(date) &
        r.category.equals(category))).go();
  }

  /// Remove local journal entries for a tank that are not in the cloud.
  /// Keeps entries with null cloudId (not yet synced upstream).
  Future<int> removeJournalNotInCloud(String tankId, Set<int> cloudIds) async {
    final local = await (select(journalEntries)
      ..where((r) => r.tankId.equals(tankId) & r.cloudId.isNotNull()))
      .get();
    int removed = 0;
    for (final entry in local) {
      if (!cloudIds.contains(entry.cloudId)) {
        await (delete(journalEntries)..where((r) => r.id.equals(entry.id))).go();
        removed++;
      }
    }
    return removed;
  }

  /// Remove local logs for a tank that are not in the cloud.
  /// Keeps logs with null cloudId (not yet synced upstream).
  Future<int> removeLogsNotInCloud(String tankId, Set<int> cloudIds) async {
    final local = await (select(logs)
      ..where((r) => r.tankId.equals(tankId) & r.cloudId.isNotNull()))
      .get();
    int removed = 0;
    for (final log in local) {
      if (!cloudIds.contains(log.cloudId)) {
        await (delete(logs)..where((r) => r.id.equals(log.id))).go();
        removed++;
      }
    }
    return removed;
  }

  // ---------- Deleted log tombstones ----------
  /// Record a tombstone so pullFromCloud won't re-insert this log.
  Future<void> insertDeletedLogKey(String tankId, DateTime createdAt) async {
    final utcStr = createdAt.toUtc().toIso8601String();
    await customStatement(
      'INSERT OR IGNORE INTO deleted_log_keys (tank_id, created_at_utc) VALUES (?, ?)',
      [tankId, utcStr],
    );
  }

  /// Check if a log was locally deleted (tombstone exists).
  Future<bool> isDeletedLog(String tankId, DateTime createdAt) async {
    final utcStr = createdAt.toUtc().toIso8601String();
    final rows = await customSelect(
      'SELECT 1 FROM deleted_log_keys WHERE tank_id = ? AND created_at_utc = ?',
      variables: [Variable.withString(tankId), Variable.withString(utcStr)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Get all deleted log keys for a tank (for push-back filtering).
  Future<Set<String>> deletedLogKeysForTank(String tankId) async {
    final rows = await customSelect(
      'SELECT created_at_utc FROM deleted_log_keys WHERE tank_id = ?',
      variables: [Variable.withString(tankId)],
    ).get();
    return rows.map((r) => r.read<String>('created_at_utc')).toSet();
  }

  // ---------- Synced log keys (tracks logs known to be in cloud) ----------
  Future<void> markLogSynced(String tankId, DateTime createdAt) async {
    final utcStr = createdAt.toUtc().toIso8601String();
    await customStatement(
      'INSERT OR IGNORE INTO synced_log_keys (tank_id, created_at_utc) VALUES (?, ?)',
      [tankId, utcStr],
    );
  }

  Future<bool> isLogSynced(String tankId, DateTime createdAt) async {
    final utcStr = createdAt.toUtc().toIso8601String();
    final rows = await customSelect(
      'SELECT 1 FROM synced_log_keys WHERE tank_id = ? AND created_at_utc = ?',
      variables: [Variable.withString(tankId), Variable.withString(utcStr)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<Set<String>> syncedLogKeysForTank(String tankId) async {
    final rows = await customSelect(
      'SELECT created_at_utc FROM synced_log_keys WHERE tank_id = ?',
      variables: [Variable.withString(tankId)],
    ).get();
    return rows.map((r) => r.read<String>('created_at_utc')).toSet();
  }

  Future<void> removeSyncedLogKey(String tankId, DateTime createdAt) async {
    final utcStr = createdAt.toUtc().toIso8601String();
    await customStatement(
      'DELETE FROM synced_log_keys WHERE tank_id = ? AND created_at_utc = ?',
      [tankId, utcStr],
    );
  }

  /// Bulk-mark all cloud log timestamps as synced for a tank.
  Future<void> markLogsSyncedBulk(String tankId, Set<String> utcStrings) async {
    for (final utcStr in utcStrings) {
      await customStatement(
        'INSERT OR IGNORE INTO synced_log_keys (tank_id, created_at_utc) VALUES (?, ?)',
        [tankId, utcStr],
      );
    }
  }

  Future<void> clearAll() async {
    await delete(chatSessions).go();
    await delete(tasks).go();
    await delete(journalEntries).go();
    await delete(logs).go();
    await delete(inhabitants).go();
    await delete(plants).go();
    await customStatement('DELETE FROM dismissed_tasks');
    await customStatement('DELETE FROM deleted_log_keys');
    await customStatement('DELETE FROM synced_log_keys');
    await delete(tanks).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'aquaria.sqlite'));
    return NativeDatabase(file);
  });
}