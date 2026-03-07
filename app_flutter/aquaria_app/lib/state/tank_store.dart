import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_db.dart' as db;
import '../models/tank.dart';
import '../services/notification_service.dart';

class TankStore {
  static final TankStore instance = TankStore._internal();
  TankStore._internal();

  Future<void> saveTank({
  required TankModel tank,
  }) async {
  await _db.upsertTank(
    db.TanksCompanion.insert(
      id: tank.id,
      name: tank.name,
      gallons: tank.gallons,
      waterType: tank.waterType.name,
      createdAt: tank.createdAt,
    ),
  );
  await load();
 }

  static const _uuid = Uuid();
  String _newId() => _uuid.v4();

  final db.AppDb _db = db.AppDb();
  List<TankModel> _tanks = [];

  List<TankModel> get tanks => List.unmodifiable(_tanks);

  Future<void> load() async {
    final rows = await _db.getActiveTanks();
    _tanks = rows
        .map((db.Tank r) => TankModel(
              id: r.id,
              name: r.name,
              gallons: r.gallons,
              waterType: WaterType.fromString(r.waterType),
              createdAt: r.createdAt,
            ))
        .toList();
    // Restore persisted dismissed task keys
    final saved = await _db.getDismissedTaskKeys();
    _dismissedTaskKeys
      ..clear()
      ..addAll(saved);
  }
Future<void> addFromParse({
  required Map<String, dynamic> parseData,
  String? fallbackName,
}) async {
  final tank = (parseData['tank'] as Map?)?.cast<String, dynamic>() ?? {};
  final initial = (parseData['initial'] as Map?)?.cast<String, dynamic>() ?? {};

  final name = (tank['name'] ?? fallbackName ?? 'My Tank').toString().trim();

  int gallons = 0;
  final g = tank['gallons'];
  if (g is int) gallons = g;
  if (g is String) gallons = int.tryParse(g) ?? 0;

  final wt = (tank['waterType'] ?? 'freshwater').toString();
  final waterType = WaterType.fromString(wt);

  final inhabitantsRaw = (initial['inhabitants'] as List?) ?? const [];
  final inhabitants = inhabitantsRaw.map((e) {
    if (e is Map) return Map<String, dynamic>.from(e as Map);
    return <String, dynamic>{};
  }).toList();

  final plantsRaw = (initial['plants'] as List?) ?? const [];
  final plants = plantsRaw.map((e) => e.toString()).toList();

  final model = TankModel(
    id: _newId(),
    name: name.isEmpty ? 'My Tank' : name,
    gallons: gallons,
    waterType: waterType,
    createdAt: DateTime.now(),
  );

  await saveParsedDetails(
    tank: model,
    inhabitants: inhabitants,
    plants: plants,
  );
}

  Future<void> add(TankModel tank) async {
  await _db.upsertTank(
    db.TanksCompanion(
      id: Value(tank.id),
      name: Value(tank.name),
      gallons: Value(tank.gallons),
      waterType: Value(tank.waterType.name),
      createdAt: Value(tank.createdAt),
    ),
  );
  await load();
}

  Future<void> archive(String id) async {
    await _db.archiveTankById(id);
    await load();
  }

  Future<void> delete(String id) async {
    await _db.deleteTankById(id);
    await load();
  }

  Future<List<TankModel>> getArchived() async {
    final rows = await _db.getArchivedTanks();
    return rows
        .map((r) => TankModel(
              id: r.id,
              name: r.name,
              gallons: r.gallons,
              waterType: WaterType.fromString(r.waterType),
              createdAt: r.createdAt,
            ))
        .toList();
  }

  Future<void> restore(String id) async {
    await _db.restoreTankById(id);
    await load();
  }

  // ----------------------------------------------------------------
  // AI summary cache — avoids redundant API calls
  // Invalidated when log count or latest log timestamp changes,
  // or after 6 hours regardless.
  // ----------------------------------------------------------------
  final Map<String, _SummaryCache> _summaryCache = {};

  _SummaryCache? getCachedSummary(String tankId, List<db.Log> currentLogs) {
    final cache = _summaryCache[tankId];
    if (cache == null) return null;
    final latestCreatedAt = currentLogs.isNotEmpty ? currentLogs.first.createdAt : null;
    final stale = DateTime.now().difference(cache.generatedAt).inHours >= 6;
    final logsChanged = cache.logCount != currentLogs.length ||
        cache.latestLogCreatedAt != latestCreatedAt;
    if (stale || logsChanged) return null;
    return cache;
  }

  void cacheSummary(String tankId, String text, List<db.Log> logs) {
    _summaryCache[tankId] = _SummaryCache(
      text: text,
      logCount: logs.length,
      latestLogCreatedAt: logs.isNotEmpty ? logs.first.createdAt : null,
      generatedAt: DateTime.now(),
    );
  }

  void invalidateSummary(String tankId) => _summaryCache.remove(tankId);

  // ----------------------------------------------------------------
  // Dismissed tasks (in-memory, shared across all screens)
  // Key: "<tankId>|<description>|<dueDate>"
  // ----------------------------------------------------------------
  final Set<String> _dismissedTaskKeys = {};

  static String taskKey(String tankId, Map<String, dynamic> task) {
    final desc = task['description']?.toString() ?? '';
    final due = (task['due_date'] ?? task['due'])?.toString() ?? '';
    return '$tankId|$desc|$due';
  }

  bool isTaskDismissed(String key) => _dismissedTaskKeys.contains(key);

  void dismissTask(String key) {
    _dismissedTaskKeys.add(key);
    NotificationService.cancelForKey(key);
    _db.insertDismissedTask(key);
  }

  // ----------------------------------------------------------------
  // These method names MUST match what main.dart is calling:
  // TankStore.instance.inhabitantsFor(tank.id)
  // TankStore.instance.plantsFor(tank.id)
  // ----------------------------------------------------------------
  Future<String?> tapWaterJsonFor(String tankId) async {
    final rows = await ((_db.select(_db.tanks))..where((t) => t.id.equals(tankId))).get();
    return rows.isEmpty ? null : rows.first.tapWaterJson;
  }

  Future<void> saveTapWater(String tankId, String? tapWaterJson) async {
    await _db.updateTapWater(tankId, tapWaterJson);
  }

  Future<void> addInhabitant({
    required String tankId,
    required String name,
    String? type,
    int count = 1,
  }) async {
    await _db.insertInhabitant(
      db.InhabitantsCompanion.insert(
        tankId: tankId,
        name: name,
        type: Value(type),
        count: Value(count <= 0 ? 1 : count),
      ),
    );
  }

  Future<List<db.Inhabitant>> inhabitantsFor(String tankId) {
    return _db.inhabitantsForTank(tankId);
  }

  Future<List<db.Plant>> plantsFor(String tankId) {
    return _db.plantsForTank(tankId);
  }

  Future<List<db.Log>> logsFor(String tankId) {
    return _db.logsForTank(tankId);
  }

  Future<void> addLog({
    required String tankId,
    required String rawText,
    String? parsedJson,
    DateTime? date,
  }) async {
    await _db.insertLog(
      db.LogsCompanion.insert(
        tankId: tankId,
        rawText: rawText,
        parsedJson: Value(parsedJson),
        createdAt: date != null ? Value(date) : const Value.absent(),
      ),
    );
    // Schedule device notifications for any tasks with a due date
    if (parsedJson != null) {
      try {
        final decoded = jsonDecode(parsedJson);
        if (decoded is Map) {
          final tasks = (decoded['tasks'] as List?) ?? [];
          final tankName = _tanks.firstWhere(
            (t) => t.id == tankId,
            orElse: () => TankModel(name: 'Aquaria', gallons: 0, waterType: WaterType.freshwater),
          ).name;
          for (final task in tasks) {
            if (task is Map<String, dynamic>) {
              await NotificationService.scheduleForTask(
                tankId: tankId,
                tankName: tankName,
                task: task,
              );
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<db.Log?> logForTodayForTank(String tankId) {
    return _db.logForTankOnDate(tankId, DateTime.now());
  }

  Future<db.Log?> logForDateForTank(String tankId, DateTime date) {
    return _db.logForTankOnDate(tankId, date);
  }

  Future<void> updateLog(int id, String rawText, String? parsedJson) {
    return _db.updateLog(id, rawText, parsedJson);
  }

  Future<void> deleteLog(int id) {
    return _db.deleteLog(id);
  }

  // Invalidate summary when a new log is added so the next page load refetches.
  Future<void> addLogAndInvalidateSummary({
    required String tankId,
    required String rawText,
    String? parsedJson,
    DateTime? date,
  }) async {
    await addLog(tankId: tankId, rawText: rawText, parsedJson: parsedJson, date: date);
    invalidateSummary(tankId);
  }

  // ----------------------------------------------------------------
  // Save tank + parsed details (optional; use it if your UI calls it)
  // ----------------------------------------------------------------
  Future<void> saveParsedDetails({
    required TankModel tank,
    required List<Map<String, dynamic>> inhabitants,
    required List<String> plants,
  }) async {
    // upsert tank
    await _db.upsertTank(
      db.TanksCompanion.insert(
        id: tank.id,
        name: tank.name,
        gallons: tank.gallons,
        waterType: tank.waterType.name,
        createdAt: tank.createdAt,
      ),
    );

    final inhRows = <db.InhabitantsCompanion>[];
    for (final m in inhabitants) {
      final name = (m['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final count = int.tryParse('${m['count'] ?? 1}') ?? 1;
      final type = m['type']?.toString();

      inhRows.add(
        db.InhabitantsCompanion.insert(
          tankId: tank.id,
          name: name,
          count: Value(count <= 0 ? 1 : count),
          type: Value(type),
        ),
      );
    }

    final plantRows = plants
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map(
          (p) => db.PlantsCompanion.insert(
            tankId: tank.id,
            name: p,
            // createdAt omitted because table default handles it
          ),
        )
        .toList();

    await _db.replaceInhabitantsForTank(tank.id, inhRows);
    await _db.replacePlantsForTank(tank.id, plantRows);

    await load();
  }
}

class _SummaryCache {
  final String text;
  final int logCount;
  final DateTime? latestLogCreatedAt;
  final DateTime generatedAt;

  const _SummaryCache({
    required this.text,
    required this.logCount,
    required this.latestLogCreatedAt,
    required this.generatedAt,
  });
}