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
  IntColumn get repeatDays => integer().nullable()(); // recurrence interval in days (null = one-off)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(tank_id) REFERENCES tanks(id) ON DELETE CASCADE',
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

@DriftDatabase(tables: [Tanks, Inhabitants, Plants, Logs, TankPhotos, Tasks, ChatSessions])
class AppDb extends _$AppDb {
  AppDb() : super(_openConnection());

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE TABLE IF NOT EXISTS dismissed_tasks (task_key TEXT PRIMARY KEY)',
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

  Future<void> insertLog(LogsCompanion entry) => into(logs).insert(entry);

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

  Future<Task?> getTaskById(int id) async {
    final rows = await (select(tasks)..where((r) => r.id.equals(id))).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> dismissTaskById(int id) async {
    await (update(tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(
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

  Future<void> clearAll() async {
    await delete(chatSessions).go();
    await delete(tasks).go();
    await delete(logs).go();
    await delete(inhabitants).go();
    await delete(plants).go();
    await customStatement('DELETE FROM dismissed_tasks');
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