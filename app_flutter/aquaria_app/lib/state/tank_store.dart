import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/app_db.dart' as db;
import '../models/tank.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

/// Fire-and-forget cloud write. Never throws — errors are logged only.
Future<void> _cloudSync(Future<void> Function() action) async {
  if (!SupabaseService.isLoggedIn) return;
  try {
    await action();
  } catch (e) {
    debugPrint('[CloudSync] $e');
  }
}

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
    _cloudSync(() => SupabaseService.upsertTank(
      id: tank.id,
      name: tank.name,
      gallons: tank.gallons,
      waterType: tank.waterType.name,
      createdAt: tank.createdAt,
    ));
    await load();
  }

  static const _uuid = Uuid();
  String _newId() => _uuid.v4();

  final db.AppDb _db = db.AppDb();
  List<TankModel> _tanks = [];

  List<TankModel> get tanks => List.unmodifiable(_tanks);

  /// Pull from cloud and merge into local SQLite, then reload.
  Future<void> pullFromCloud() async {
    if (!SupabaseService.isLoggedIn) return;
    try {
      final data = await SupabaseService.pullAll();
      final cloudTanks = (data['tanks'] as List?) ?? [];
      for (final ct in cloudTanks) {
        final m = ct as Map<String, dynamic>;
        await _db.upsertTank(db.TanksCompanion.insert(
          id: m['id'] as String,
          name: m['name'] as String,
          gallons: m['gallons'] as int,
          waterType: m['water_type'] as String,
          createdAt: DateTime.parse(m['created_at'] as String),
          isArchived: Value(m['is_archived'] as bool? ?? false),
        ));
        if (m['tap_water_json'] != null) {
          await _db.updateTapWater(m['id'] as String, m['tap_water_json'] as String);
        }

        final tankId = m['id'] as String;

        // Inhabitants
        final cloudInhMap = (data['inhabitants'] as Map?) ?? {};
        final cloudInhs = (cloudInhMap[tankId] as List?) ?? [];
        if (cloudInhs.isNotEmpty) {
          final rows = <db.InhabitantsCompanion>[];
          for (final i in cloudInhs) {
            final im = i as Map<String, dynamic>;
            rows.add(db.InhabitantsCompanion.insert(
              tankId: tankId,
              name: im['name'] as String,
              count: Value((im['count'] as int?) ?? 1),
              type: Value(im['type'] as String?),
            ));
          }
          await _db.replaceInhabitantsForTank(tankId, rows);
        }

        // Plants
        final cloudPlantMap = (data['plants'] as Map?) ?? {};
        final cloudPlants = (cloudPlantMap[tankId] as List?) ?? [];
        if (cloudPlants.isNotEmpty) {
          final rows = cloudPlants
              .map((p) => db.PlantsCompanion.insert(
                    tankId: tankId,
                    name: (p as Map<String, dynamic>)['name'] as String,
                  ))
              .toList();
          await _db.replacePlantsForTank(tankId, rows);
        }

        // Logs — use exact timestamp to avoid re-inserting deleted logs
        final cloudLogMap = (data['logs'] as Map?) ?? {};
        final cloudLogs = (cloudLogMap[tankId] as List?) ?? [];
        for (final l in cloudLogs) {
          final lm = l as Map<String, dynamic>;
          final createdAt = DateTime.parse(lm['created_at'] as String);
          final exists = await _db.logExistsForTankAt(tankId, createdAt);
          if (!exists) {
            await _db.insertLog(db.LogsCompanion.insert(
              tankId: tankId,
              rawText: lm['raw_text'] as String,
              parsedJson: Value(lm['parsed_json'] as String?),
              createdAt: Value(createdAt),
            ));
          }
        }
        // Remove any duplicate logs for this tank
        await _db.deduplicateLogsForTank(tankId);
      }

      // Dismissed tasks (legacy)
      final cloudDismissed = (data['dismissed_tasks'] as Set?) ?? <String>{};
      for (final key in cloudDismissed) {
        await _db.insertDismissedTask(key);
      }

      // Tasks — check for duplicates before inserting
      final cloudTasks = (data['tasks'] as List?) ?? [];
      for (final ct in cloudTasks) {
        final tm = ct as Map<String, dynamic>;
        final desc = tm['description'] as String;
        final tankId2 = tm['tank_id'] as String;
        // Skip if we already have this task locally
        final isDup = await _db.hasDuplicateTask(tankId2, desc, tm['due_date'] as String?);
        if (isDup) continue;
        await _db.insertTask(db.TasksCompanion.insert(
          tankId: tankId2,
          description: desc,
          dueDate: Value(tm['due_date'] as String?),
          priority: Value((tm['priority'] as String?) ?? 'normal'),
          source: Value((tm['source'] as String?) ?? 'ai'),
          repeatDays: Value(tm['repeat_days'] as int?),
          isPaused: Value(tm['is_paused'] as bool? ?? false),
          createdAt: Value(DateTime.parse(tm['created_at'] as String)),
        ));
      }
    } catch (e) {
      debugPrint('[CloudSync] pullFromCloud failed: $e');
    }
  }

  /// Push all local data to cloud for initial sync after login.
  Future<void> pushToCloud() async {
    if (!SupabaseService.isLoggedIn) return;
    debugPrint('[CloudSync] pushToCloud starting for user ${SupabaseService.userId}');
    try {
      // Fetch existing cloud tank IDs so we skip duplicates
      final cloudTanks = await SupabaseService.fetchTanks();
      final cloudTankIds = cloudTanks.map((t) => t['id'] as String).toSet();

      for (final tank in _tanks) {
        if (!SupabaseService.isLoggedIn) return; // abort if signed out mid-push
        if (cloudTankIds.contains(tank.id)) {
          // Already in cloud for this user — update it
          await SupabaseService.upsertTank(
            id: tank.id,
            name: tank.name,
            gallons: tank.gallons,
            waterType: tank.waterType.name,
            createdAt: tank.createdAt,
          );
        } else {
          // New to cloud — insert (skip if ID conflict from another user)
          try {
            await SupabaseService.insertTank(
              id: tank.id,
              name: tank.name,
              gallons: tank.gallons,
              waterType: tank.waterType.name,
              createdAt: tank.createdAt,
            );
          } catch (e) {
            debugPrint('[CloudSync] insert tank ${tank.id} failed (may exist for another user): $e');
            continue;
          }
        }

        final tapJson = await tapWaterJsonFor(tank.id);
        if (tapJson != null) {
          await SupabaseService.updateTapWater(tank.id, tapJson);
        }

        final inhs = await _db.inhabitantsForTank(tank.id);
        if (inhs.isNotEmpty) {
          await SupabaseService.replaceInhabitants(
            tank.id,
            inhs.map((i) => {
              'name': i.name,
              'count': i.count,
              'type': i.type,
            }).toList(),
          );
        }

        final plants = await _db.plantsForTank(tank.id);
        if (plants.isNotEmpty) {
          await SupabaseService.replacePlants(
            tank.id,
            plants.map((p) => p.name).toList(),
          );
        }

        final logs = await _db.logsForTank(tank.id);
        for (final log in logs) {
          await SupabaseService.insertLog(
            tankId: tank.id,
            rawText: log.rawText,
            parsedJson: log.parsedJson,
            createdAt: log.createdAt,
          );
        }
      }

      for (final key in _dismissedTaskKeys) {
        await SupabaseService.dismissTask(key);
      }

      // Push tasks
      final allTasks = await _db.allActiveTasks();
      for (final task in allTasks) {
        await SupabaseService.insertTask(
          tankId: task.tankId,
          description: task.description,
          dueDate: task.dueDate,
          priority: task.priority,
          source: task.source,
        );
      }
    } catch (e) {
      debugPrint('[CloudSync] pushToCloud failed: $e');
    }
  }

  /// Clear all local data (used on sign-out so next user starts fresh).
  Future<void> clearLocal() async {
    await _db.clearAll();
    _tanks = [];
    _dismissedTaskKeys.clear();
    _summaryCache.clear();
  }

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
    // One-time dedup of existing duplicate tasks
    final removed = await _db.deduplicateActiveTasks();
    if (removed > 0) {
      debugPrint('[TankStore] Removed $removed duplicate task(s)');
    }
    // Dedup logs for all tanks
    for (final tank in _tanks) {
      final logRemoved = await _db.deduplicateLogsForTank(tank.id);
      if (logRemoved > 0) {
        debugPrint('[TankStore] Removed $logRemoved duplicate log(s) for ${tank.name}');
      }
    }
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
    _cloudSync(() => SupabaseService.upsertTank(
      id: tank.id,
      name: tank.name,
      gallons: tank.gallons,
      waterType: tank.waterType.name,
      createdAt: tank.createdAt,
    ));
    await load();
  }

  Future<void> archive(String id) async {
    final tank = _tanks.firstWhere((t) => t.id == id, orElse: () => TankModel(name: '', gallons: 0, waterType: WaterType.freshwater));
    await _db.archiveTankById(id);
    _cloudSync(() => SupabaseService.upsertTank(
      id: id,
      name: tank.name,
      gallons: tank.gallons,
      waterType: tank.waterType.name,
      isArchived: true,
      createdAt: tank.createdAt,
    ));
    await load();
  }

  Future<void> delete(String id) async {
    await _db.deleteTankById(id);
    _cloudSync(() => SupabaseService.deleteTank(id));
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
    // Re-read the tank to sync the restored state to cloud
    final rows = await _db.getActiveTanks();
    final restored = rows.where((r) => r.id == id).firstOrNull;
    if (restored != null) {
      _cloudSync(() => SupabaseService.upsertTank(
        id: restored.id,
        name: restored.name,
        gallons: restored.gallons,
        waterType: restored.waterType,
        isArchived: false,
        createdAt: restored.createdAt,
      ));
    }
    await load();
  }

  // ----------------------------------------------------------------
  // AI summary cache
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
  // Dismissed tasks (legacy)
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
    _cloudSync(() => SupabaseService.dismissTask(key));
  }

  // ----------------------------------------------------------------
  // Tasks table (new)
  // ----------------------------------------------------------------
  Future<List<db.Task>> tasksForTank(String tankId) => _db.tasksForTank(tankId);
  Future<List<db.Task>> allActiveTasks() => _db.allActiveTasks();

  Future<void> addTask({
    required String tankId,
    required String description,
    String? dueDate,
    String priority = 'normal',
    String source = 'ai',
    int? repeatDays,
  }) async {
    // Prevent duplicate tasks for the same tank + description + due date
    final isDuplicate = await _db.hasDuplicateTask(tankId, description, dueDate);
    if (isDuplicate) {
      debugPrint('[TankStore] addTask: skipping duplicate task "$description" due=$dueDate');
      return;
    }
    await _db.insertTask(db.TasksCompanion.insert(
      tankId: tankId,
      description: description,
      dueDate: Value(dueDate),
      priority: Value(priority),
      source: Value(source),
      repeatDays: Value(repeatDays),
      createdAt: Value(DateTime.now()),
    ));
    // Schedule device notification
    final tankName = _tanks.firstWhere(
      (t) => t.id == tankId,
      orElse: () => TankModel(name: 'Aquaria', gallons: 0, waterType: WaterType.freshwater),
    ).name;
    await NotificationService.scheduleForTask(
      tankId: tankId,
      tankName: tankName,
      task: {'description': description, 'due_date': dueDate},
    );
    // Cloud sync
    debugPrint('[TankStore] addTask: syncing to cloud, loggedIn=${SupabaseService.isLoggedIn}');
    _cloudSync(() async {
      debugPrint('[TankStore] insertTask calling Supabase...');
      await SupabaseService.insertTask(
        tankId: tankId,
        description: description,
        dueDate: dueDate,
        priority: priority,
        source: source,
        repeatDays: repeatDays,
      );
      debugPrint('[TankStore] insertTask success');
    });
  }

  Future<void> dismissTaskById(int id) async {
    // Check if this is a recurring task before dismissing
    final task = await _db.getTaskById(id);
    await _db.dismissTaskById(id);
    if (task != null) {
      _cloudSync(() => SupabaseService.dismissTaskByKey(
        tankId: task.tankId,
        description: task.description,
        createdAt: task.createdAt,
      ));
    }

    // Auto-create next occurrence for recurring tasks (skip if paused)
    if (task != null && task.repeatDays != null && task.repeatDays! > 0 && !task.isPaused) {
      final nextDue = DateTime.now().add(Duration(days: task.repeatDays!));
      final nextDueStr = '${nextDue.year}-${nextDue.month.toString().padLeft(2, '0')}-${nextDue.day.toString().padLeft(2, '0')}';
      await addTask(
        tankId: task.tankId,
        description: task.description,
        dueDate: nextDueStr,
        priority: task.priority,
        source: task.source,
        repeatDays: task.repeatDays,
      );
    }
  }

  /// Mark a task as complete, log the action, cancel its notification,
  /// and auto-create next occurrence if recurring.
  Future<void> completeTaskById(int id) async {
    final task = await _db.getTaskById(id);
    if (task == null) return;

    await _db.completeTaskById(id);

    // Cancel notification
    NotificationService.cancelForTask(
      tankId: task.tankId,
      task: {'description': task.description, 'due_date': task.dueDate ?? ''},
    );

    // Log as an action
    final now = DateTime.now();
    final parsedJson = '{"actions":["${task.description}"],"notes":[],"measurements":{},"tasks":[]}';
    await addLog(
      tankId: task.tankId,
      rawText: task.description,
      parsedJson: parsedJson,
      date: now,
    );
    invalidateSummary(task.tankId);

    // Cloud sync
    _cloudSync(() => SupabaseService.dismissTaskByKey(
      tankId: task.tankId,
      description: task.description,
      createdAt: task.createdAt,
    ));

    // Auto-create next occurrence for recurring tasks (skip if paused)
    if (task.repeatDays != null && task.repeatDays! > 0 && !task.isPaused) {
      final nextDue = now.add(Duration(days: task.repeatDays!));
      final nextDueStr = '${nextDue.year}-${nextDue.month.toString().padLeft(2, '0')}-${nextDue.day.toString().padLeft(2, '0')}';
      await addTask(
        tankId: task.tankId,
        description: task.description,
        dueDate: nextDueStr,
        priority: task.priority,
        source: task.source,
        repeatDays: task.repeatDays,
      );
    }
  }

  /// Find and complete an open task matching the given description for a tank.
  /// Used when the AI detects the user performed an action that matches a task.
  /// Returns true if a matching task was found and completed.
  Future<bool> completeMatchingTask({
    required String tankId,
    required String actionDescription,
  }) async {
    final tasks = await _db.tasksForTank(tankId);
    final actionLower = actionDescription.toLowerCase().trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final task in tasks) {
      // Only match tasks due today or in the past (never future)
      if (task.dueDate != null) {
        final due = DateTime.tryParse(task.dueDate!);
        if (due != null && due.isAfter(today)) continue;
      }
      final taskLower = task.description.toLowerCase().trim();
      // Fuzzy match: check if the action contains the task description or vice versa
      if (taskLower.contains(actionLower) ||
          actionLower.contains(taskLower) ||
          _fuzzyTaskMatch(taskLower, actionLower)) {
        await completeTaskById(task.id);
        return true;
      }
    }
    return false;
  }

  /// Simple fuzzy match: check if key words from the task appear in the action.
  bool _fuzzyTaskMatch(String taskDesc, String actionDesc) {
    // Common task/action keyword mappings
    const synonyms = {
      'water change': ['water change', 'wc', 'changed water', 'change water'],
      'check': ['test', 'check', 'measure', 'tested', 'checked', 'measured'],
      'clean': ['clean', 'cleaned', 'scrub', 'scrubbed', 'wipe', 'wiped'],
      'feed': ['feed', 'fed', 'feeding'],
      'trim': ['trim', 'trimmed', 'prune', 'pruned'],
      'dose': ['dose', 'dosed', 'dosing', 'added'],
    };

    for (final entry in synonyms.entries) {
      final taskHasKey = taskDesc.contains(entry.key) ||
          entry.value.any((s) => taskDesc.contains(s));
      final actionHasKey = actionDesc.contains(entry.key) ||
          entry.value.any((s) => actionDesc.contains(s));
      if (taskHasKey && actionHasKey) return true;
    }
    return false;
  }

  Future<List<db.Task>> getRecurringTasks({String? tankId}) =>
      _db.allActiveRecurringTasks(tankId: tankId);

  Future<void> updateTaskFrequency(int id, int newRepeatDays) async {
    await _db.updateTaskRepeatDays(id, newRepeatDays);
  }

  Future<void> toggleTaskPaused(int id, bool paused) async {
    await _db.setTaskPaused(id, paused);
  }

  Future<void> deleteTask(int id) async {
    await _db.deleteTask(id);
  }

  // ----------------------------------------------------------------
  // Inhabitants / Plants / Logs
  // ----------------------------------------------------------------
  Future<String?> tapWaterJsonFor(String tankId) async {
    final rows = await ((_db.select(_db.tanks))..where((t) => t.id.equals(tankId))).get();
    return rows.isEmpty ? null : rows.first.tapWaterJson;
  }

  Future<void> saveTapWater(String tankId, String? tapWaterJson) async {
    await _db.updateTapWater(tankId, tapWaterJson);
    _cloudSync(() => SupabaseService.updateTapWater(tankId, tapWaterJson));
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
    // Re-sync full inhabitants list to cloud
    _cloudSync(() async {
      final all = await _db.inhabitantsForTank(tankId);
      await SupabaseService.replaceInhabitants(
        tankId,
        all.map((i) => {'name': i.name, 'count': i.count, 'type': i.type}).toList(),
      );
    });
  }

  Future<List<db.Inhabitant>> inhabitantsFor(String tankId) {
    return _db.inhabitantsForTank(tankId);
  }

  Future<void> addPlant({
    required String tankId,
    required String name,
  }) async {
    await _db.insertPlant(
      db.PlantsCompanion.insert(
        tankId: tankId,
        name: name,
      ),
    );
    // Re-sync full plants list to cloud
    _cloudSync(() async {
      final all = await _db.plantsForTank(tankId);
      await SupabaseService.replacePlants(
        tankId,
        all.map((p) => p.name).toList(),
      );
    });
  }

  Future<List<db.Plant>> plantsFor(String tankId) {
    return _db.plantsForTank(tankId);
  }

  Future<List<db.Log>> logsFor(String tankId) {
    return _db.logsForTank(tankId);
  }

  // ---------- Tank Photos ----------
  Future<List<db.TankPhoto>> photosFor(String tankId) {
    return _db.photosForTank(tankId);
  }

  Future<void> addPhoto({
    required String tankId,
    required String filePath,
    String? note,
  }) async {
    await _db.insertPhoto(
      db.TankPhotosCompanion.insert(
        tankId: tankId,
        filePath: filePath,
        note: Value(note),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deletePhoto(int id) async {
    await _db.deletePhoto(id);
  }

  // ---------- Chat Sessions ----------
  Future<void> saveChatSession({
    String? tankId,
    required String summary,
    int messageCount = 0,
  }) async {
    await _db.insertChatSession(
      db.ChatSessionsCompanion.insert(
        tankId: Value(tankId),
        summary: summary,
        messageCount: Value(messageCount),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<db.ChatSession>> recentSessions(String? tankId, {int limit = 5}) {
    return _db.recentSessionsForTank(tankId, limit: limit);
  }

  Future<void> addLog({
    required String tankId,
    required String rawText,
    String? parsedJson,
    DateTime? date,
  }) async {
    // Skip duplicate log entries (same parsed content within 2 minutes)
    if (await _db.hasDuplicateLog(tankId, parsedJson)) return;
    final ts = date ?? DateTime.now();
    await _db.insertLog(
      db.LogsCompanion.insert(
        tankId: tankId,
        rawText: rawText,
        parsedJson: Value(parsedJson),
        createdAt: Value(ts),
      ),
    );
    _cloudSync(() => SupabaseService.insertLog(
      tankId: tankId,
      rawText: rawText,
      parsedJson: parsedJson,
      createdAt: ts,
    ));
  }

  Future<db.Log?> logForTodayForTank(String tankId) {
    return _db.logForTankOnDate(tankId, DateTime.now());
  }

  Future<db.Log?> logForDateForTank(String tankId, DateTime date) {
    return _db.logForTankOnDate(tankId, date);
  }

  Future<void> updateLog(int id, String rawText, String? parsedJson) async {
    final log = await _db.getLogById(id);
    await _db.updateLog(id, rawText, parsedJson);
    if (log != null) {
      _cloudSync(() => SupabaseService.updateLogByKey(log.tankId, log.createdAt, rawText, parsedJson));
    }
  }

  Future<void> deleteLog(int id) async {
    final log = await _db.getLogById(id);
    await _db.deleteLog(id);
    if (log != null) {
      await _cloudSync(() => SupabaseService.deleteLogByKey(log.tankId, log.createdAt));
    }
  }

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
  // Save tank + parsed details
  // ----------------------------------------------------------------
  Future<void> saveParsedDetails({
    required TankModel tank,
    required List<Map<String, dynamic>> inhabitants,
    required List<String> plants,
  }) async {
    // Auto-mark as planted if plants are present (freshwater only)
    final hasPlants = plants.where((p) => p.trim().isNotEmpty).isNotEmpty;
    WaterType effectiveType = tank.waterType;
    if (hasPlants && effectiveType == WaterType.freshwater) {
      effectiveType = WaterType.planted;
    } else if (!hasPlants && effectiveType == WaterType.planted) {
      effectiveType = WaterType.freshwater;
    }

    // upsert tank locally
    await _db.upsertTank(
      db.TanksCompanion.insert(
        id: tank.id,
        name: tank.name,
        gallons: tank.gallons,
        waterType: effectiveType.name,
        createdAt: tank.createdAt,
      ),
    );

    final inhRows = <db.InhabitantsCompanion>[];
    final inhMaps = <Map<String, dynamic>>[];
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
      inhMaps.add({'name': name, 'count': count <= 0 ? 1 : count, 'type': type});
    }

    final plantNames = plants.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final plantRows = plantNames
        .map(
          (p) => db.PlantsCompanion.insert(
            tankId: tank.id,
            name: p,
          ),
        )
        .toList();

    await _db.replaceInhabitantsForTank(tank.id, inhRows);
    await _db.replacePlantsForTank(tank.id, plantRows);

    // Cloud sync
    _cloudSync(() async {
      await SupabaseService.upsertTank(
        id: tank.id,
        name: tank.name,
        gallons: tank.gallons,
        waterType: effectiveType.name,
        createdAt: tank.createdAt,
      );
      await SupabaseService.replaceInhabitants(tank.id, inhMaps);
      await SupabaseService.replacePlants(tank.id, plantNames);
    });

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
