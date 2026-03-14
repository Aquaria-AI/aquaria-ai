import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';

import 'package:drift/drift.dart' show Value;
import 'db/app_db.dart' as db;
import 'models/tank.dart';
import 'screens/auth_screen.dart';
import 'screens/legal_acceptance_screen.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'state/tank_store.dart';

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final TankModel? newTank; // set when a tank was just created
  const _ChatMessage({required this.role, required this.content, this.newTank});
}

// In-memory chat history cache: keyed by tank ID (or '__none__' for no tank).
// Cleared after 24 hours of inactivity.
class _ChatCache {
  static const _ttl = Duration(hours: 24);
  static final Map<String, ({DateTime updatedAt, List<_ChatMessage> messages})> _store = {};

  static String _key(String? tankId) => tankId ?? '__none__';

  static List<_ChatMessage>? load(String? tankId) {
    final entry = _store[_key(tankId)];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.updatedAt) > _ttl) {
      _store.remove(_key(tankId));
      return null;
    }
    return List.of(entry.messages);
  }

  static void save(String? tankId, List<_ChatMessage> messages) {
    _store[_key(tankId)] = (updatedAt: DateTime.now(), messages: List.of(messages));
  }

  static void clear(String? tankId) => _store.remove(_key(tankId));
}

// ── Backend URL ─────────────────────────────────────────────────────────────
// Override at build/run time:
//   flutter run --dart-define=API_BASE_URL=https://your-api.railway.app
//   flutter build ipa --dart-define=API_BASE_URL=https://your-api.railway.app
const String _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://aquaria-ai-production.up.railway.app',
);

/// Build HTTP headers with Supabase JWT for authenticated API calls.
Map<String, String> _apiHeaders() {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

// Brand palette
const _cDark    = Color(0xFF0E5A66);
const _cMid     = Color(0xFF1FA2A8);
const _cLight   = Color(0xFF7FE2D5);
const _cMint    = Color(0xFFD9F7F0);
const _cBeige   = Color(0xFFE7D8C7);

/// Show a floating snackbar at the top of the screen.
void _showTopSnack(BuildContext context, String message, {Color? backgroundColor}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - 130,
        left: 20,
        right: 20,
      ),
    ));
}

/// Formal parameter display names with units.
const _paramDisplayNames = <String, String>{
  'ph': 'pH',
  'ammonia': 'Ammonia (ppm)',
  'nitrite': 'Nitrite (ppm)',
  'nitrate': 'Nitrate (ppm)',
  'gh': 'GH (dGH)',
  'kh': 'KH (dKH)',
  'temp': 'Temp (°F)',
  'salinity': 'Salinity (SG)',
  'phosphate': 'Phosphate (ppm)',
  'calcium': 'Calcium (ppm)',
  'magnesium': 'Magnesium (ppm)',
  'potassium': 'Potassium (ppm)',
  'tds': 'TDS (ppm)',
  'alkalinity': 'Alkalinity (dKH)',
  'copper': 'Copper (ppm)',
  'iron': 'Iron (ppm)',
  'co2': 'CO2 (ppm)',
};

/// Short label (no units) for tight spaces like chips.
const _paramShortNames = <String, String>{
  'ph': 'pH', 'ammonia': 'Ammonia', 'nitrite': 'Nitrite', 'nitrate': 'Nitrate',
  'gh': 'GH', 'kh': 'KH', 'temp': 'Temp', 'salinity': 'Salinity',
  'phosphate': 'Phosphate', 'calcium': 'Calcium', 'magnesium': 'Magnesium',
  'potassium': 'Potassium', 'tds': 'TDS', 'alkalinity': 'Alkalinity',
  'copper': 'Copper', 'iron': 'Iron', 'co2': 'CO2', 'ca_mg_ratio': 'Ca:Mg',
};

/// Get the formal display name for a parameter key.
String _paramLabel(String key) => _paramDisplayNames[key.toLowerCase()] ?? key;

/// Get the short name (no units) for a parameter key.
String _paramShortLabel(String key) => _paramShortNames[key.toLowerCase()] ?? key;

/// Title-case a species / plant name: "neon tetra" → "Neon Tetra"
String _titleCase(String s) =>
    s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

const double _kFooterHeight = 15.0;

class _AquariaFooter extends StatelessWidget {
  final VoidCallback? onAiTap;
  /// Extra height added at the bottom (e.g. system nav bar on Android).
  /// Pass [MediaQuery.of(context).padding.bottom] when not inside a Scaffold
  /// that already handles safe area (e.g. inside a modal sheet).
  final double extraBottomPadding;
  /// Alert level: 'none', 'yellow', or 'red'
  final String alertLevel;
  const _AquariaFooter({this.onAiTap, this.extraBottomPadding = 0, this.alertLevel = 'none'});

  static const _buttonSize = 68.0;

  @override
  Widget build(BuildContext context) {
    if (onAiTap == null) return const SizedBox.shrink();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ColoredBox(
      color: Colors.transparent,
      child: SizedBox(
        height: _buttonSize + bottomInset + 12,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _buttonSize,
            height: _buttonSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: const Color(0xFF1FA2A8),
                  shape: const CircleBorder(),
                  elevation: 3,
                  shadowColor: Colors.black38,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onAiTap,
                    child: const SizedBox(
                      width: _buttonSize,
                      height: _buttonSize,
                      child: Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                    ),
                  ),
                ),
                if (alertLevel != 'none')
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: alertLevel == 'red' ? Colors.red : Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.priority_high,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _cLogoTeal = Color(0xFF2297A8);

Future<DateTime> _communityLastSeen() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.community_last_seen');
    if (f.existsSync()) return DateTime.parse(f.readAsStringSync().trim());
  } catch (_) {}
  return DateTime(2000);
}

Future<void> _setCommunityLastSeen() async {
  final dir = await getApplicationDocumentsDirectory();
  await File('${dir.path}/.community_last_seen').writeAsString(DateTime.now().toUtc().toIso8601String());
}

class _CommunityBadgeIcon extends StatefulWidget {
  const _CommunityBadgeIcon();
  @override
  State<_CommunityBadgeIcon> createState() => _CommunityBadgeIconState();
}

class _CommunityBadgeIconState extends State<_CommunityBadgeIcon> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _communityLastSeen(),
        SupabaseService.fetchBlockedUserIds(),
      ]);
      final since = results[0] as DateTime;
      final blocked = results[1] as Set<String>;
      final count = await SupabaseService.countNewPosts(since, excludeUserIds: blocked);
      if (mounted) setState(() => _count = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Community',
      icon: Badge(
        isLabelVisible: true,
        label: _count > 0
            ? Text('$_count', style: const TextStyle(fontSize: 10))
            : const Text('New', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
        backgroundColor: _count > 0 ? null : const Color(0xFF1FA2A8),
        child: const Icon(Icons.groups_outlined),
      ),
      onPressed: () async {
        await _setCommunityLastSeen();
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const _CommunityScreen()),
        );
        _refresh();
      },
    );
  }
}

class _NotificationBellIcon extends StatefulWidget {
  const _NotificationBellIcon();
  @override
  State<_NotificationBellIcon> createState() => _NotificationBellIconState();
}

class _NotificationBellIconState extends State<_NotificationBellIcon> {
  Map<String, List<db.Task>> _tasksByTank = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final result = <String, List<db.Task>>{};
    for (final tank in TankStore.instance.tanks) {
      final tasks = await TankStore.instance.tasksForTank(tank.id);
      if (tasks.isNotEmpty) result[tank.id] = tasks;
    }
    if (mounted) setState(() => _tasksByTank = result);
  }

  int get _count {
    int c = 0;
    for (final tasks in _tasksByTank.values) c += tasks.length;
    return c;
  }

  void _showSheet() {
    final tanks = TankStore.instance.tanks;
    final items = <({TankModel tank, db.Task task})>[];
    for (final tank in tanks) {
      for (final t in (_tasksByTank[tank.id] ?? [])) {
        items.add((tank: tank, task: t));
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  const Icon(Icons.notifications, size: 18, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Text('Notifications (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
              ),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('No notifications', style: TextStyle(color: Colors.grey)))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.task.description, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(item.tank.name, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                            builder: (_) => _AddTaskSheet(tankName: item.tank.name, existing: item.task),
                          );
                          if (result != null && result.desc.isNotEmpty) {
                            if (result.completeAndStopRecurring) {
                              await TankStore.instance.completeAndStopRecurring(item.task.id);
                            } else if (result.dismissAndStopRecurring) {
                              await TankStore.instance.dismissAndStopRecurring(item.task.id);
                            } else if (result.dismiss) {
                              await TankStore.instance.dismissTaskById(item.task.id);
                            } else if (result.markComplete) {
                              await TankStore.instance.completeTaskById(item.task.id);
                            } else {
                              await TankStore.instance.updateTask(
                                item.task.id,
                                description: result.desc,
                                dueDate: Value(result.dueDate),
                                repeatDays: Value(result.repeatDays),
                              );
                            }
                            _loadTasks();
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 10)),
        backgroundColor: const Color(0xFFE65100),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: _showSheet,
    );
  }
}

AppBar _buildAppBar(BuildContext context, String title, {List<Widget>? actions, bool showCommunity = true}) => AppBar(
      title: Text(title, style: const TextStyle(color: _cDark, fontWeight: FontWeight.bold, fontSize: 17)),
      centerTitle: false,
      iconTheme: const IconThemeData(color: _cDark),
      actionsIconTheme: const IconThemeData(color: _cDark),
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.white,
      toolbarHeight: kToolbarHeight,
      actions: [
        ...(actions ?? []),
        if (showCommunity && SupabaseService.isLoggedIn)
          const _CommunityBadgeIcon(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: 'Account',
          onSelected: (value) async {
            if (value == 'invite') {
              try {
                await Share.share('Check out Aquaria — an AI-powered aquarium companion app!');
              } catch (e) {
                debugPrint('[Share] error: $e');
              }
            } else if (value == 'feedback') {
              _showFeedbackSheet(context);
            } else if (value == 'experience') {
              _showExperiencePicker(context);
            } else if (value == 'profile') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _ProfileScreen()),
              );
            } else if (value == 'onboarding') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            } else if (value == 'discord') {
              _showDiscordSheet(context);
            } else if (value == 'donate') {
              launchUrl(Uri.parse('https://buy.stripe.com/00wcN6a8f9TM5QKaxw2sM01'), mode: LaunchMode.externalApplication);
            } else if (value == 'sign_out') {
              await SupabaseService.signOut();
              await TankStore.instance.clearLocal();
              await _clearOnboardingDone();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const _AppEntry()),
                  (_) => false,
                );
              }
            }
          },
          itemBuilder: (_) => [
            if (SupabaseService.isLoggedIn) ...[
              PopupMenuItem(
                enabled: false,
                child: Text(
                  SupabaseService.userEmail ?? '',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
              PopupMenuItem(
                value: 'experience',
                child: FutureBuilder<String>(
                  future: _loadExperienceLevel(),
                  builder: (_, snap) {
                    final level = (snap.data ?? 'beginner').isEmpty ? 'beginner' : snap.data!;
                    final label = level[0].toUpperCase() + level.substring(1);
                    return Text('Level: $label', style: const TextStyle(color: Colors.black54, fontSize: 13));
                  },
                ),
              ),
              const PopupMenuDivider(),
            ],
            if (SupabaseService.isLoggedIn)
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
            const PopupMenuItem(value: 'invite', child: Text('Invite Friends')),
            if (SupabaseService.isLoggedIn)
              const PopupMenuItem(value: 'discord', child: Text('Discord')),
            if (SupabaseService.userEmail == 'maugliera@gmail.com' || SupabaseService.isAdmin)
              const PopupMenuItem(value: 'onboarding', child: Text('Onboarding')),
            const PopupMenuItem(value: 'feedback', child: Text('Feedback')),
            const PopupMenuItem(value: 'donate', child: Text('Support Aquaria')),
            if (SupabaseService.isLoggedIn)
              const PopupMenuItem(value: 'sign_out', child: Text('Sign Out')),
          ],
        ),
      ],
      flexibleSpace: Builder(
        builder: (ctx) {
          final hasBackButton = Navigator.of(ctx).canPop();
          return Container(
            color: Colors.white,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: hasBackButton ? 47 : 16),
                  child: Image.asset('assets/images/logo-side.png', height: 39, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      ),
    );

void _showExperiencePicker(BuildContext context) {
  showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Experience Level',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _cDark)),
            const SizedBox(height: 16),
            for (final entry in [
              ('beginner', 'Beginner', 'New to fishkeeping'),
              ('intermediate', 'Intermediate', 'Comfortable with the basics'),
              ('expert', 'Expert', 'Advanced reefing & breeding'),
            ])
              ListTile(
                leading: FutureBuilder<String>(
                  future: _loadExperienceLevel(),
                  builder: (_, snap) => Icon(
                    (snap.data ?? 'beginner') == entry.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _cDark,
                  ),
                ),
                title: Text(entry.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(entry.$3, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                onTap: () async {
                  await _saveExperienceLevel(entry.$1);
                  if (ctx.mounted) Navigator.of(ctx).pop(entry.$1);
                },
              ),
          ],
        ),
      ),
    ),
  ).then((selected) {
    if (selected != null) {
      // Find the TankListScreen state and update experience
      final state = context.findAncestorStateOfType<_TankListScreenState>();
      if (state != null && state.mounted) {
        state.setState(() => state._experience = selected);
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Discord integration
// ---------------------------------------------------------------------------

void _showDiscordSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _DiscordSheet(),
  );
}

class _DiscordSheet extends StatefulWidget {
  const _DiscordSheet();
  @override
  State<_DiscordSheet> createState() => _DiscordSheetState();
}

class _DiscordSheetState extends State<_DiscordSheet> {
  bool _loading = true;
  bool _linked = false;
  String _username = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/discord/status'),
        headers: _apiHeaders(),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _linked = data['linked'] == true;
          _username = data['discord_username'] ?? '';
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Failed to check status'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Connection error'; });
    }
  }

  Future<void> _linkDiscord() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/discord/auth-url'),
        headers: _apiHeaders(),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final url = jsonDecode(resp.body)['url'] as String;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        // Poll for completion
        setState(() => _loading = false);
        _pollForLink();
      } else {
        setState(() { _loading = false; _error = 'Failed to start linking'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Connection error'; });
    }
  }

  void _pollForLink() {
    int attempts = 0;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      attempts++;
      if (attempts > 40) return false; // 2 min max
      try {
        final resp = await http.get(
          Uri.parse('$_kBaseUrl/discord/status'),
          headers: _apiHeaders(),
        ).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data['linked'] == true) {
            if (mounted) {
              setState(() {
                _linked = true;
                _username = data['discord_username'] ?? '';
              });
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(const SnackBar(content: Text('Discord linked!')));
            }
            return false;
          }
        }
      } catch (_) {}
      return true;
    });
  }

  Future<void> _unlinkDiscord() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Discord?'),
        content: Text('Disconnect $_username from Aquaria?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unlink')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await http.delete(
        Uri.parse('$_kBaseUrl/discord/unlink'),
        headers: _apiHeaders(),
      ).timeout(const Duration(seconds: 10));
      setState(() { _linked = false; _username = ''; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed to unlink'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.discord, color: Color(0xFF5865F2), size: 28),
              const SizedBox(width: 10),
              const Text('Discord', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 22, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            )
          else if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(_error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _checkStatus, child: const Text('Retry')),
              ]),
            )
          else if (_linked) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Color(0xFF5865F2)),
                const SizedBox(width: 12),
                Expanded(child: Text('Connected as $_username',
                    style: const TextStyle(fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 12),
            const Text(
              'Share tank photos to Discord from the photo action menu on any tank.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _unlinkDiscord,
              child: const Text('Unlink Discord', style: TextStyle(color: Colors.red)),
            ),
          ] else ...[
            const Text(
              'Link your Discord account to share tank photos directly to your favorite aquarium servers.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _linkDiscord,
                icon: const Icon(Icons.link),
                label: const Text('Link Discord'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5865F2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Show Discord share flow: pick server → channel → title → post
Future<void> _showDiscordShareFlow(BuildContext context, String photoStoragePath) async {
  final headers = _apiHeaders();

  // Check linked status — if not linked, start OAuth inline
  final statusResp = await http.get(
    Uri.parse('$_kBaseUrl/discord/status'),
    headers: headers,
  ).timeout(const Duration(seconds: 10));
  if (statusResp.statusCode != 200 || jsonDecode(statusResp.body)['linked'] != true) {
    if (!context.mounted) return;
    // Start OAuth flow inline
    final authResp = await http.get(
      Uri.parse('$_kBaseUrl/discord/auth-url'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));
    if (authResp.statusCode != 200 || !context.mounted) return;
    final url = jsonDecode(authResp.body)['url'] as String;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    // Poll until linked
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Linking Discord — authorize in your browser, then come back...')));
    }
    bool linked = false;
    for (int i = 0; i < 40; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!context.mounted) return;
      try {
        final poll = await http.get(
          Uri.parse('$_kBaseUrl/discord/status'),
          headers: headers,
        ).timeout(const Duration(seconds: 5));
        if (poll.statusCode == 200 && jsonDecode(poll.body)['linked'] == true) {
          linked = true;
          break;
        }
      } catch (_) {}
    }
    if (!linked || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Discord linking timed out. Try again.')));
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Discord linked!')));
    }
  }

  if (!context.mounted) return;

  // Fetch guilds
  final guildsResp = await http.get(
    Uri.parse('$_kBaseUrl/discord/guilds'),
    headers: headers,
  ).timeout(const Duration(seconds: 10));
  if (guildsResp.statusCode != 200 || !context.mounted) return;
  final guildsData = jsonDecode(guildsResp.body);
  final guilds = (guildsData['guilds'] as List?) ?? [];
  final botInviteUrl = guildsData['bot_invite_url'] as String? ?? '';

  if (guilds.isEmpty) {
    if (!context.mounted) return;
    final invited = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Aquaria bot to a server'),
        content: const Text(
          'To share photos, the Aquaria bot needs to be in one of your Discord servers. '
          'Tap below to invite it, then come back here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          if (botInviteUrl.isNotEmpty)
            TextButton(
              onPressed: () async {
                await launchUrl(Uri.parse(botInviteUrl), mode: LaunchMode.externalApplication);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Invite Bot'),
            ),
        ],
      ),
    );
    if (invited != true || !context.mounted) return;
    // Show a follow-up dialog telling user to continue
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bot invited?'),
        content: const Text(
          'Once you\'ve added the Aquaria bot to your server in Discord, tap Continue to share your photo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5865F2)),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (retry != true || !context.mounted) return;
    // Retry the share flow from the top
    _showDiscordShareFlow(context, photoStoragePath);
    return;
  }

  // Pick server
  final guild = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pick a server', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...guilds.map((g) => ListTile(
            leading: const Icon(Icons.dns, color: Color(0xFF5865F2)),
            title: Text(g['name'] ?? ''),
            onTap: () => Navigator.pop(ctx, g),
          )),
          if (botInviteUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.add, color: Colors.grey),
              title: const Text('Add bot to another server', style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(botInviteUrl), mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    ),
  );
  if (guild == null || !context.mounted) return;

  // Fetch channels
  final chResp = await http.get(
    Uri.parse('$_kBaseUrl/discord/channels?guild_id=${guild['id']}'),
    headers: headers,
  ).timeout(const Duration(seconds: 10));
  if (chResp.statusCode != 200 || !context.mounted) return;
  final channels = (jsonDecode(chResp.body)['channels'] as List?) ?? [];

  if (channels.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('No text channels found in this server')));
    }
    return;
  }

  // Pick channel
  final channel = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pick a channel in ${guild['name']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: channels.map<Widget>((ch) => ListTile(
                leading: const Text('#', style: TextStyle(fontSize: 18, color: Colors.grey)),
                title: Text(ch['name'] ?? ''),
                onTap: () => Navigator.pop(ctx, ch),
              )).toList(),
            ),
          ),
        ],
      ),
    ),
  );
  if (channel == null || !context.mounted) return;

  // Title + caption dialog
  final titleCtrl = TextEditingController();
  final captionCtrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Post to #${channel['name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'My reef tank'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: captionCtrl,
            decoration: const InputDecoration(labelText: 'Caption (optional)'),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Share')),
      ],
    ),
  );
  if (confirmed != true || titleCtrl.text.trim().isEmpty || !context.mounted) return;

  // Post to Discord
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text('Sharing to Discord...')));
  try {
    final shareResp = await http.post(
      Uri.parse('$_kBaseUrl/discord/share'),
      headers: headers,
      body: jsonEncode({
        'channel_id': channel['id'],
        'title': titleCtrl.text.trim(),
        'caption': captionCtrl.text.trim(),
        'photo_storage_path': photoStoragePath,
      }),
    ).timeout(const Duration(seconds: 30));
    if (context.mounted) {
      if (shareResp.statusCode == 200) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Shared to Discord!')));
      } else {
        final err = jsonDecode(shareResp.body)['detail'] ?? 'Share failed';
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Error: $err')));
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Failed to share')));
    }
  }
}

void _showFeedbackSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _FeedbackSheet(),
  );
}

/// Picks source (camera/gallery), then asks Tank or Community, and routes accordingly.
Future<void> pickPhotoFlow(BuildContext context, {String? tankId}) async {
  // 1. Source picker: camera or gallery
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take Photo'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  // 2. Pick image
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
  } catch (e) {
    debugPrint('[PhotoPick] error picking image: $e');
    return;
  }
  if (picked == null || !context.mounted) return;

  // 3. Destination picker: Tank or Community
  final dest = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Save to', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.water, color: Color(0xFF1FA2A8)),
            title: const Text('My Tank'),
            onTap: () => Navigator.of(ctx).pop('tank'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined, color: Color(0xFF1FA2A8)),
            title: const Text('Community'),
            onTap: () => Navigator.of(ctx).pop('community'),
          ),
        ],
      ),
    ),
  );
  if (dest == null || !context.mounted) return;

  if (dest == 'community') {
    await _sharePickedToCommunity(context, picked.path);
  } else {
    await pickAndSavePhoto(context, tankId: tankId, pickedPath: picked.path);
  }
}

/// Uploads a picked photo to community with channel + caption selection.
Future<void> _sharePickedToCommunity(BuildContext context, String filePath) async {
  // Channel picker
  final channel = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Share to Channel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.public, color: Color(0xFF1FA2A8)),
            title: const Text('General'),
            onTap: () => Navigator.pop(ctx, 'general'),
          ),
          ListTile(
            leading: const Icon(Icons.water_drop, color: Colors.blue),
            title: const Text('Freshwater'),
            onTap: () => Navigator.pop(ctx, 'freshwater'),
          ),
          ListTile(
            leading: const Icon(Icons.waves, color: Colors.indigo),
            title: const Text('Saltwater'),
            onTap: () => Navigator.pop(ctx, 'saltwater'),
          ),
        ],
      ),
    ),
  );
  if (channel == null || !context.mounted) return;

  // Caption dialog
  final caption = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Add a caption'),
        content: TextField(
          controller: ctrl,
          maxLength: 150,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Say something about this photo...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _cDark),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Share'),
          ),
        ],
      );
    },
  );
  if (caption == null || !context.mounted) return;

  // Upload
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Sharing...')])))),
  );
  try {
    final storagePath = await SupabaseService.uploadCommunityPhoto(filePath);
    await SupabaseService.createPost(photoUrl: storagePath, caption: caption, channel: channel);
    if (context.mounted) {
      Navigator.of(context).pop(); // dismiss overlay
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _CommunityScreen(initialChannel: channel)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop(); // dismiss overlay
      _showTopSnack(context, 'Failed to share: $e');
    }
  }
}

/// Shows a save dialog with preview, notes, and tank selector for a pre-picked image.
Future<void> pickAndSavePhoto(BuildContext context, {String? tankId, String? pickedPath}) async {
  final tanks = TankStore.instance.tanks;
  if (tanks.isEmpty) {
    _showTopSnack(context, 'Add a tank first');
    return;
  }

  String imagePath;
  if (pickedPath != null) {
    imagePath = pickedPath;
  } else {
    // Source picker: camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (e) {
      debugPrint('[PhotoPick] error picking image: $e');
      return;
    }
    if (picked == null || !context.mounted) return;
    imagePath = picked.path;
  }

  // 3. Save to a temp location first (we'll move to tank folder after tank is chosen)
  try {
    final dir = await getApplicationDocumentsDirectory();
    final ext = imagePath.split('.').last;
    final tmpPath = '${dir.path}/tank_photos/_tmp_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final tmpDir = Directory('${dir.path}/tank_photos');
    if (!tmpDir.existsSync()) tmpDir.createSync(recursive: true);
    await File(imagePath).copy(tmpPath);

    if (!context.mounted) return;

    // Brief delay to let the image file settle before showing the dialog
    await Future.delayed(const Duration(milliseconds: 150));
    if (!context.mounted) return;

    // 4. Show save dialog with preview, note, and tank dropdown
    final needsTankPicker = tankId == null && tanks.length > 1;
    final defaultTankId = tankId ?? tanks.first.id;

    final result = await showDialog<_PhotoSaveResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _PhotoSaveDialog(
        imagePath: tmpPath,
        tanks: tanks,
        initialTankId: defaultTankId,
        showTankPicker: needsTankPicker,
      ),
    );

    if (result == null || !context.mounted) {
      // Clean up temp file
      try { await File(tmpPath).delete(); } catch (_) {}
      return;
    }

    // 5. Move to final tank folder
    final resolvedTankId = result.tankId;
    final imgDir = Directory('${dir.path}/tank_photos/$resolvedTankId');
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final savedPath = '${imgDir.path}/$fileName';
    await File(tmpPath).rename(savedPath);

    await TankStore.instance.addPhoto(
      tankId: resolvedTankId,
      filePath: savedPath,
      note: result.note,
    );

    if (context.mounted) {
      _showTopSnack(context, 'Photo saved');
    }
  } catch (e) {
    debugPrint('[PhotoPick] error saving photo: $e');
    if (context.mounted) {
      _showTopSnack(context, 'Error saving photo: $e');
    }
  }
}

class _PhotoSaveResult {
  final String tankId;
  final String? note;
  const _PhotoSaveResult({required this.tankId, this.note});
}

class _PhotoSaveDialog extends StatefulWidget {
  final String imagePath;
  final List<TankModel> tanks;
  final String initialTankId;
  final bool showTankPicker;
  const _PhotoSaveDialog({
    required this.imagePath,
    required this.tanks,
    required this.initialTankId,
    required this.showTankPicker,
  });
  @override
  State<_PhotoSaveDialog> createState() => _PhotoSaveDialogState();
}

class _PhotoSaveDialogState extends State<_PhotoSaveDialog> {
  late String _selectedTankId;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTankId = widget.initialTankId;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Save Photo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(widget.imagePath),
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Add a note (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (widget.showTankPicker) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedTankId,
                decoration: const InputDecoration(
                  labelText: 'Tank',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.tanks.map((t) => DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => _selectedTankId = v); },
              ),
            ],
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final note = _noteCtrl.text.trim();
            Navigator.of(context).pop(_PhotoSaveResult(
              tankId: _selectedTankId,
              note: note.isNotEmpty ? note : null,
            ));
          },
          style: FilledButton.styleFrom(backgroundColor: _cDark),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;
  PlatformFile? _attachment;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _attachment = result.files.first);
    }
  }

  Future<void> _submit() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_kBaseUrl/feedback/upload'));
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields['message'] = msg;
      if (_attachment != null && _attachment!.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'attachment',
          _attachment!.bytes!,
          filename: _attachment!.name,
        ));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (streamed.statusCode == 200) {
        setState(() { _sent = true; _sending = false; });
      } else {
        setState(() { _error = 'Server error (${streamed.statusCode})'; _sending = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not reach server. Try again later.'; _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Send Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Have a suggestion or found a bug? Let us know.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            if (_sent) ...[
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text('Thanks for your feedback!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ] else ...[
              TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe your feedback…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  _attachment != null ? _attachment!.name : 'Attach a file',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cDark,
                  side: const BorderSide(color: _cMid),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_attachment != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _attachment = null),
                    child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _sending ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: _cDark),
                child: _sending
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Onboarding persistence ────────────────────────────────────────────────────
Future<bool> _isOnboardingDone() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/.onboarding_done').existsSync();
  } catch (_) {
    return false;
  }
}

Future<void> _markOnboardingDone() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/.onboarding_done').writeAsString('1');
  } catch (_) {}
}

Future<void> _clearOnboardingDone() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.onboarding_done');
    if (f.existsSync()) await f.delete();
  } catch (_) {}
}

Future<void> _saveExperienceLevel(String level) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/.experience_level').writeAsString(level);
  } catch (_) {}
}

Future<String> _loadExperienceLevel() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.experience_level');
    if (f.existsSync()) return f.readAsStringSync().trim();
  } catch (_) {}
  return 'beginner';
}

Future<bool> _shouldShowDailyTip() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.daily_tip_shown');
    if (f.existsSync()) {
      final stored = f.readAsStringSync().trim();
      final now = DateTime.now();
      final today = '${now.year}-${now.month}-${now.day}';
      return stored != today;
    }
  } catch (_) {}
  return true;
}

Future<void> _markDailyTipShown() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    await File('${dir.path}/.daily_tip_shown').writeAsString('${now.year}-${now.month}-${now.day}');
  } catch (_) {}
}

/// Returns the next tip index for the given experience level and advances it.
Future<int> _nextTipIndex(String level) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.tip_index_$level');
    int idx = 0;
    if (f.existsSync()) {
      idx = int.tryParse(f.readAsStringSync().trim()) ?? 0;
    }
    final tips = _kDailyTips[level] ?? _kDailyTips['beginner']!;
    final current = idx % tips.length;
    await f.writeAsString('${idx + 1}');
    return current;
  } catch (_) {
    return 0;
  }
}

/// Returns the current tip index (without advancing).
Future<int> _currentTipIndex(String level) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/.tip_index_$level');
    if (f.existsSync()) {
      final idx = int.tryParse(f.readAsStringSync().trim()) ?? 0;
      final tips = _kDailyTips[level] ?? _kDailyTips['beginner']!;
      // Index points to next tip, so current shown is idx - 1
      return idx > 0 ? (idx - 1) % tips.length : 0;
    }
  } catch (_) {}
  return 0;
}

// ── Daily tip catalogue ───────────────────────────────────────────────────────

const _kDailyTips = <String, List<({String category, String tip})>>{
  'beginner': [
    (category: 'Water', tip: 'Test your water weekly — even when everything looks fine. Problems are much easier to fix early.'),
    (category: 'Filter', tip: 'Your filter is home to billions of helpful bacteria. Never rinse it with tap water — use old tank water only.'),
    (category: 'New Fish', tip: 'When adding new fish, float the bag in your tank for 15 minutes first so they can adjust to the temperature.'),
    (category: 'Feeding', tip: 'Overfeeding is the #1 beginner mistake. Only feed what your fish can eat in 2–3 minutes.'),
    (category: 'Water Change', tip: 'Never change all the water at once. Replace 10–25% weekly to keep your good bacteria alive and thriving.'),
    (category: 'Ammonia', tip: 'Ammonia is invisible and deadly. It spikes in new tanks — always test before adding fish.'),
    (category: 'Temperature', tip: 'Cold tap water can shock fish. Let replacement water reach room temperature before adding it to the tank.'),
    (category: 'Lighting', tip: 'Aquarium lights should be on 8–10 hours a day — not 24/7. Fish need a dark period to rest.'),
    (category: 'Heater', tip: 'Check your thermometer daily. Heaters can fail silently — a working thermometer is your early warning system.'),
    (category: 'Stocking', tip: "Don't add too many fish at once. Your filter needs time to adjust — add a few fish at a time."),
    (category: 'Plants', tip: 'Live plants naturally absorb ammonia and nitrates. Even a single plant helps keep your tank healthier.'),
    (category: 'Water Change', tip: 'When in doubt, do a water change. It solves most problems and is never the wrong move.'),
    (category: 'Sick Fish', tip: 'Move a sick fish to a separate quarantine tank rather than treating the whole system. It\'s safer for everyone.'),
    (category: 'Oxygen', tip: 'Fish gasping at the surface usually means low oxygen. Check your filter flow and consider an air stone.'),
    (category: 'Algae', tip: 'A little algae is completely normal and actually a sign of a healthy, established tank. Don\'t panic.'),
    (category: 'Research', tip: 'Always research a fish\'s adult size and temperament before buying. A cute juvenile can become a monster.'),
    (category: 'Snails', tip: 'Snails are great cleaners and won\'t harm your fish. Finding one in your tank is generally good news.'),
    (category: 'Cleaning', tip: 'A gravel vacuum is one of the most useful tools you can own. Use it during water changes to remove hidden waste.'),
    (category: 'New Fish', tip: 'New fish are often shy and hide for the first week. Give them time to settle before worrying about behavior.'),
    (category: 'The Cycle', tip: 'The nitrogen cycle is the most important concept in fishkeeping: Ammonia → Nitrite → Nitrate. Learn it well.'),
    (category: 'Medications', tip: 'Medications can kill beneficial bacteria. Only medicate when necessary, and ideally in a hospital tank.'),
    (category: 'pH', tip: 'Most freshwater fish are happy at pH 6.5–7.2. Small deviations are usually fine — stability matters more than perfection.'),
    (category: 'Temperature', tip: 'Consistent temperature is more important than a perfect number. Fluctuations stress fish far more than being a degree off.'),
    (category: 'Schooling Fish', tip: 'Schooling fish need companions. A single neon tetra is a stressed neon tetra — keep 6 or more.'),
    (category: 'Plants', tip: 'Some fish eat plants. Research your species before adding live plants to avoid finding them shredded overnight.'),
    (category: 'Patience', tip: 'Rushing the cycle, the stocking, or the setup is the fastest route to losing fish. Aquariums reward patience.'),
    (category: 'Space', tip: 'Bigger tanks are actually easier to maintain than small ones. Water quality stays stable for longer.'),
    (category: 'Betta', tip: 'Bettas need at least 5 gallons. Small bowls cause chronic stress and shorten their lives significantly.'),
    (category: 'Feeding', tip: 'Fasting your fish one day a week keeps them healthier and helps prevent digestive issues. They can handle it.'),
    (category: 'Community', tip: 'Not all fish get along. Check compatibility charts before mixing species — aggression is hard to undo.'),
    (category: 'Testing', tip: 'Test your water regularly and log the results in Aquaria. Ariel uses your history to spot trends and give better advice over time.'),
    (category: 'Observation', tip: 'Observe your tank daily — behavior changes, water color, and any unusual smells. Report what you see to Ariel so she can help you act early.'),
    (category: 'Reporting', tip: "After each water test, tell Ariel the results. Even 'everything looks normal' is valuable data that helps her track your tank's health."),
    (category: 'Ariel', tip: 'Ariel gets smarter the more you share. Describe what you see, smell, and measure — she can connect dots you might miss.'),
    (category: 'Smell', tip: "A healthy tank smells earthy or neutral. A strong sulfur or rotten egg smell usually means something is wrong — tell Ariel right away."),
    (category: 'Behavior', tip: 'Fish behavior is the earliest warning system. Hiding, gasping, or erratic swimming are signs something is off. Log it in Aquaria.'),
    (category: 'Tap Water', tip: "Your tap water is the starting point for everything in your tank. Test it for pH, GH, and KH, then add the results to your tank's profile so Ariel can factor them in."),
    (category: 'Tap Water', tip: "A water change only brings your tank closer to your tap water chemistry — not to zero. If your tap water has high GH or pH, Ariel needs to know so her advice accounts for it."),
  ],
  'intermediate': [
    (category: 'Nitrates', tip: 'Aim for nitrates below 20 ppm. Above 40 ppm causes chronic stress and leaves fish more vulnerable to disease.'),
    (category: 'KH', tip: 'KH (carbonate hardness) is your pH buffer. If KH drops below 4 dKH, your pH can crash suddenly.'),
    (category: 'Phosphates', tip: 'High phosphates fuel algae growth. Increase surface agitation, reduce feeding, and consider a phosphate reactor.'),
    (category: 'Carbon', tip: 'Activated carbon removes medications and tannins — but also trace minerals. Use it with intention, not indefinitely.'),
    (category: 'Cycling', tip: 'A cycled sponge filter from an established tank can instantly cycle a new one. Keep a spare running.'),
    (category: 'Cycling', tip: 'The nitrogen cycle runs faster at warmer temperatures. Set your heater to 82–84°F when cycling a new tank.'),
    (category: 'CO2', tip: 'CO2 injection dramatically improves plant growth but lowers pH. Monitor carefully in tanks with sensitive inhabitants.'),
    (category: 'Fertilizers', tip: 'When dosing fertilizers, target the limiting nutrient. Adding more of what\'s already sufficient does nothing.'),
    (category: 'Potassium', tip: 'Potassium is the most commonly deficient nutrient in heavily planted tanks. Look for yellow leaf edges with holes.'),
    (category: 'Filtration', tip: 'Beneficial bacteria colonize filter media, not water. Prioritize media volume when sizing your filtration.'),
    (category: 'Algae', tip: 'Algae is a symptom, not the problem. Find the imbalance — nutrients, light duration, or CO2 — and fix that.'),
    (category: 'Old Tank', tip: 'Old Tank Syndrome: pH drops slowly over time from acid buildup. Regular water changes and KH checks prevent it.'),
    (category: 'GH', tip: 'GH (general hardness) affects mineral absorption in fish. Soft water species suffer in hard water long-term.'),
    (category: 'Flow', tip: 'Most fish prefer 5–10x tank volume per hour of filtration. Cichlids and discus like the lower end of that range.'),
    (category: 'Acclimation', tip: 'Drip acclimation is far superior to floating the bag, especially for sensitive fish and invertebrates.'),
    (category: 'Quarantine', tip: 'Quarantine all new fish for at least 2 weeks before adding them to your display tank. Every single time.'),
    (category: 'Driftwood', tip: 'Pre-soak driftwood for several days before adding it. This removes tannins that would otherwise stain your water.'),
    (category: 'Fasting', tip: 'Fasting fish one day a week keeps them leaner, clears mild constipation, and reduces waste load.'),
    (category: 'Disease', tip: 'Most fish diseases are stress-triggered. Identify and fix the stressor before reaching for a medication.'),
    (category: 'Nitrite', tip: 'Don\'t forget to test nitrites in new tanks — they spike after ammonia clears and are equally lethal.'),
    (category: 'Breeding', tip: 'For most egg-scatterers, a temperature drop of 2–4°F mimics the rainy season and triggers spawning behavior.'),
    (category: 'Epsom Salt', tip: 'Epsom salt (magnesium sulfate) raises GH without affecting KH or pH — useful for soft water mineral supplementation.'),
    (category: 'Stocking', tip: 'Don\'t stock by gallons alone — surface area determines oxygen availability in the tank.'),
    (category: 'Aggression', tip: 'Thick plant cover and broken sightlines reduce aggression in cichlid tanks more than extra space does.'),
    (category: 'Sponge Filter', tip: 'Sponge filters are often overlooked — great biological filtration and perfect gentle flow for fry and shrimp tanks.'),
    (category: 'Salt', tip: 'When treating with aquarium salt, measure by weight not volume. Different salt brands have different densities.'),
    (category: 'Surface', tip: 'Surface agitation increases oxygen but drives off CO2. Balance it based on whether your focus is fish or plants.'),
    (category: 'Substrate', tip: 'Bottom-up planting works well: plant substrate plants first in a dry tank, then add water slowly.'),
    (category: 'Zeolite', tip: 'Zeolite removes ammonia in emergencies but stops working in saltwater. It can become dangerous if reused improperly.'),
    (category: 'Parameters', tip: 'Log your water parameters over time, not just in the moment. Trends reveal problems before they become crises.'),
    (category: 'Planted Tanks', tip: 'Live plants do much more than look great. They consume ammonia and nitrates, produce oxygen, and create natural hiding spaces that reduce fish stress.'),
    (category: 'Planted Tanks', tip: 'A well-planted tank often needs fewer water changes — plants are constantly processing waste that would otherwise require manual removal.'),
    (category: 'Planted Tanks', tip: 'Plants compete with algae for nutrients and light. A healthy planted tank naturally suppresses algae growth without chemicals.'),
    (category: 'Planted Tanks', tip: 'Fish thrive in planted tanks. Natural cover mimics their wild environment, reduces aggression, and encourages natural behaviors like breeding.'),
    (category: 'Potassium Test', tip: 'Potassium is critical for plant health but rarely tested. A Salifert Potassium test will reveal deficiencies that cause yellow leaves and poor plant growth.'),
    (category: 'Calcium Test', tip: 'In planted freshwater tanks, calcium supports both plant cell walls and fish bone density. Test with a calcium test kit to confirm adequate levels (20–40 ppm for freshwater).'),
    (category: 'GH Testing', tip: 'General Hardness (GH) measures calcium and magnesium. Too soft and plants struggle to absorb nutrients; too hard and some fish species suffer long-term.'),
    (category: 'KH Testing', tip: 'KH (carbonate hardness) is your pH buffer. Test it monthly and share results with Ariel — sudden KH drops often predict pH crashes before they happen.'),
    (category: 'Tap Water', tip: 'Your tap water parameters are the foundation of your tank chemistry. Test it and share the results with Ariel so her recommendations account for what you\'re actually starting with.'),
    (category: 'Tap Water', tip: 'Tap water chemistry varies by season and region. Re-test your tap water a few times a year and update Ariel — your water supply can change without warning.'),
    (category: 'Reporting Tests', tip: 'Share your test results with Ariel after each session — not just problem readings. She builds a picture of your tank over time and can spot patterns you might miss.'),
  ],
  'expert': [
    (category: 'ICP Testing', tip: 'ICP testing gives a complete elemental profile of your reef water. Run it quarterly and compare trends over time.'),
    (category: 'Reef Chemistry', tip: 'Ca:Mg:Alk balance matters as much as individual levels. Imbalances can cause spontaneous precipitation in your sump.'),
    (category: 'RTN', tip: 'Coral tissue necrosis spreads in minutes. Immediately frag above the recession line and move frags to a separate system.'),
    (category: 'SPS Health', tip: 'Acropora polyp extension is one of the most reliable indicators of overall reef health — more so than any single parameter.'),
    (category: 'Carbon Dosing', tip: 'Carbon dosing (vodka, sugar) drives bacterial growth to consume nutrients. Ramp up slowly to avoid bacterial blooms.'),
    (category: 'Refugium', tip: 'Macro algae in a refugium is one of the most stable nutrient export methods. Chaeto is resilient; Ulva grows faster.'),
    (category: 'ATO', tip: 'ATO systems are essential for salinity stability. Without one, evaporation concentrates salt rapidly in small systems.'),
    (category: 'Safety', tip: 'Palytoxin is among the most toxic biological substances known. Always wear gloves and eye protection with zoanthids.'),
    (category: 'Dosing', tip: 'Two-part dosing requires recalibration as coral biomass grows. Kalkwasser is simpler for lower-demand systems.'),
    (category: 'Alkalinity', tip: 'Alkalinity consumption rate is a more accurate proxy for coral growth rate than any visual assessment.'),
    (category: 'Skimmer', tip: 'Clean your skimmer neck weekly. Protein buildup on the neck drastically reduces skimming efficiency.'),
    (category: 'Lighting', tip: 'Ramp LED intensity slowly over several weeks when introducing SPS corals. Sudden intensity causes bleaching.'),
    (category: 'Multi-Tank', tip: 'Cross-contamination is the greatest risk in multi-tank systems. Dedicated equipment per tank is non-negotiable.'),
    (category: 'Copepods', tip: 'Mandarin dragonets decimate pod populations. Maintain a seeded refugium or replenish pods regularly.'),
    (category: 'Anthias', tip: 'Lyretail anthias harems maintain one male. When the male is lost, the dominant female will sex-change to replace him.'),
    (category: 'UV Sterilizer', tip: 'UV sterilizers kill pathogens but also beneficial planktonic life. Use selectively during outbreaks, not full-time.'),
    (category: 'Breeding', tip: 'Breeding dwarf cichlids like Apistogramma is best triggered by dropping pH to 5.5–6.0 and performing large water changes.'),
    (category: 'Coral Spawning', tip: 'Captive coral spawning is possible with simulated lunar cycles using timed moonlight LEDs over several months.'),
    (category: 'ORP', tip: 'Reef water ORP should ideally sit between 350–400 mV. Values below 250 indicate significantly degraded water quality.'),
    (category: 'Salt Mix', tip: 'Mixing different salt brands in the same system can cause precipitation. Choose one and stick with it.'),
    (category: 'Mandarin', tip: 'Mandarins can be trained to eat frozen mysis, but it takes weeks of patient conditioning starting with live food.'),
    (category: 'Monitoring', tip: 'Remote pH, temperature, and ATO alerts are standard practice for serious reefers. Failures always happen when you\'re away.'),
    (category: 'Diatoms', tip: 'Silicate in tap water drives brown diatom algae in new systems. RO/DI with silicate-specific resin eliminates the source.'),
    (category: 'Fragging', tip: 'Frag corals in a shallow container of tank water. Air exposure and temperature spikes stress tissue rapidly.'),
    (category: 'Filtration', tip: 'Biological filtration alone can\'t handle heavy organic load. Mechanical pre-filtration (filter socks, roller mats) is critical.'),
    (category: 'Salinity', tip: 'Specific gravity drift between water changes causes osmotic stress. Calibrate your refractometer regularly with NIST fluid.'),
    (category: 'Acropora', tip: 'pH stability below the decimal point makes a measurable difference in Acropora growth rate over time.'),
    (category: 'Bacterial Bloom', tip: 'A milky white water bacterial bloom in a new tank is harmless and self-resolving. Do not do a water change.'),
    (category: 'Frag Swaps', tip: 'Frag swaps are one of the best ways to diversify your collection and build relationships with local reefers.'),
    (category: 'Tap Water', tip: 'Municipal water treatment changes seasonally and varies by source. Test your tap water quarterly for TDS, chloramine, phosphate, and silicate — and update your tank profile so Ariel\'s advice stays accurate.'),
    (category: 'Tap Water', tip: 'Even RO/DI systems need source water profiles. Log the pre-filter TDS and post-filter readings in Aquaria so Ariel can track membrane degradation over time.'),
  ],
};

// ── Onboarding Screen ─────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;
  int _maxPage = 0; // highest page reached — prevents swiping forward past this
  int get _totalPages => 6;

  String _experience = '';
  final _tankNameCtrl = TextEditingController(text: 'New Tank');
  double _gallons = 30;
  WaterType _waterType = WaterType.freshwater;
  List<({String name, String type, int count})> _inhabitants = [];
  List<String> _plants = [];
  Map<String, dynamic> _equipment = {};
  bool _finishing = false;
  final List<Map<String, dynamic>> _pendingTasks = [];
  String? _pendingCsvContent;
  Map<int, String?>? _pendingCsvMapping;
  int? _pendingCsvDateCol;
  String? _createdTankId;

  /// Create (or update) the tank in the DB so Meet Ariel can operate on a real tank.
  Future<void> _ensureTankCreated() async {
    final name = _tankNameCtrl.text.trim().isEmpty ? 'New Tank' : _tankNameCtrl.text.trim();
    final tank = TankModel(
      id: _createdTankId,
      name: name,
      gallons: _gallons.round(),
      waterType: _waterType,
    );
    await TankStore.instance.saveParsedDetails(
      tank: tank,
      inhabitants: _inhabitants
          .map((i) => {'name': i.name, 'type': i.type, 'count': i.count})
          .toList(),
      plants: _plants,
    );
    if (_equipment.isNotEmpty) {
      await TankStore.instance.saveEquipment(tank.id, jsonEncode(_equipment));
    }
    _createdTankId = tank.id;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _tankNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _importCsvForTank(String tankId, String csvContent) async {
    try {
      final allRows = const CsvToListConverter(eol: '\n').convert(csvContent);
      if (allRows.length < 2) return;

      // Use user-confirmed mapping if available, otherwise auto-detect
      int? dateCol = _pendingCsvDateCol;
      final paramMapping = <int, String>{};

      // Find the real header row (skip junk rows at the top)
      final headerIdx = _pendingCsvMapping != null ? 0 : _CsvImportScreenState._findHeaderRow(allRows);
      final rows = allRows.sublist(headerIdx);
      if (rows.length < 2) return;

      if (_pendingCsvMapping != null) {
        for (final e in _pendingCsvMapping!.entries) {
          if (e.value != null) paramMapping[e.key] = e.value!;
        }
      } else {
        final headers = rows.first.map((e) => e.toString().trim()).toList();
        for (int i = 0; i < headers.length; i++) {
          final h = headers[i].toLowerCase().trim();
          if (h == 'date' || h == 'timestamp' || h == 'time' ||
              h.contains('date') || h == 'day' || h == 'logged') {
            dateCol ??= i;
          } else {
            final mapped = _CsvImportScreenState._matchHeader(h);
            if (mapped != null) paramMapping[i] = mapped;
          }
        }
      }
      if (paramMapping.isEmpty) return;
      for (final row in rows.sublist(1)) {
        if (row.length <= 1 && row.first.toString().trim().isEmpty) continue;
        DateTime? logDate;
        if (dateCol != null && dateCol < row.length) {
          logDate = _CsvImportScreenState._parseFlexDate(row[dateCol].toString());
        }
        logDate ??= DateTime.now();
        final measurements = <String, dynamic>{};
        for (final e in paramMapping.entries) {
          if (e.key >= row.length) continue;
          final raw = row[e.key].toString().trim();
          if (raw.isEmpty) continue;
          final val = num.tryParse(raw.replaceAll(RegExp(r'[^\d.\-]'), ''));
          measurements[e.value] = val ?? raw;
        }
        if (measurements.isEmpty) continue;
        final csvDate = '${logDate.year}-${logDate.month.toString().padLeft(2,'0')}-${logDate.day.toString().padLeft(2,'0')}';
        await TankStore.instance.addLog(
          tankId: tankId,
          rawText: 'CSV import',
          parsedJson: jsonEncode({
            'schemaVersion': 1,
            'measurements': measurements,
            'actions': <String>[],
            'notes': <String>[],
            'tasks': <Map>[],
            'date': csvDate,
          }),
          date: logDate,
        );
        // Write to journal
        final existing = await TankStore.instance.journalForDate(tankId, csvDate);
        final measEntry = existing.where((e) => e.category == 'measurements').toList();
        Map<String, dynamic> merged = {};
        if (measEntry.isNotEmpty) {
          try { merged = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
        }
        merged.addAll(measurements);
        await TankStore.instance.upsertJournal(
          tankId: tankId,
          date: csvDate,
          category: 'measurements',
          data: jsonEncode(merged),
        );
      }
      TankStore.instance.invalidateSummary(tankId);
    } catch (_) {}
  }

  void _goNext() {
    if (_page < _totalPages - 1) {
      // Create/update the tank in DB before entering Meet Ariel (page 5)
      // so the chat can operate on a real tank.
      if (_page == 4) _ensureTankCreated();
      final next = _page + 1;
      if (next > _maxPage) _maxPage = next;
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      // Final save — updates the tank already created before Meet Ariel
      await _ensureTankCreated();
      final tankId = _createdTankId!;
      // Save any reminder tasks collected during the water quality chat
      if (_pendingTasks.isNotEmpty) {
        for (final task in _pendingTasks) {
          await TankStore.instance.addTask(
            tankId: tankId,
            description: (task['description'] ?? '').toString(),
            dueDate: (task['due_date'] ?? task['due'])?.toString(),
            priority: (task['priority'] ?? 'normal').toString(),
            source: 'ai',
          );
        }
      }
      // Import pending CSV data
      if (_pendingCsvContent != null) {
        await _importCsvForTank(tankId, _pendingCsvContent!);
      }
      await _markOnboardingDone();
      await _saveExperienceLevel(_experience);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TankListScreen(showWelcome: true)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      _showTopSnack(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const PageScrollPhysics(),
              onPageChanged: (p) {
                if (p > _maxPage) {
                  // User swiped forward past allowed page — snap back
                  _pageCtrl.animateToPage(_maxPage,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut);
                } else {
                  setState(() => _page = p);
                }
              },
              children: [
                _ObExperiencePage(
                    selected: _experience,
                    onSelect: (e) {
                      setState(() => _experience = e);
                      Future.delayed(const Duration(milliseconds: 300), _goNext);
                    },
                    onNext: _experience.isEmpty ? null : _goNext,
                  ),
                  _ObWelcomePage(experience: _experience, onNext: _goNext),
                  _ObTankSetupPage(
                    nameCtrl: _tankNameCtrl,
                    gallons: _gallons,
                    waterType: _waterType,
                    onGallonsChanged: (v) => setState(() => _gallons = v),
                    onWaterTypeChanged: (v) => setState(() => _waterType = v),
                    onNext: _goNext,
                    experience: _experience,
                    equipment: _equipment,
                    onEquipmentChanged: (eq) => setState(() => _equipment = eq),
                  ),
                  _ObInhabitantsPage(
                    initialInhabitants: _inhabitants,
                    initialPlants: _plants,
                    waterType: _waterType,
                    onNext: (inhs, plts) {
                      setState(() { _inhabitants = inhs; _plants = plts; });
                      _goNext();
                    },
                  ),
                  _ObInhabitantSummaryPage(
                    inhabitants: _inhabitants,
                    plants: _plants,
                    waterType: _waterType,
                    onNext: _goNext,
                  ),
                  _ObWaterQualityPage(
                    tankName: _tankNameCtrl.text,
                    gallons: _gallons,
                    waterType: _waterType,
                    inhabitants: _inhabitants,
                    plants: _plants,
                    equipment: _equipment,
                    onNext: _finish,
                    onReminderTask: (t) => _pendingTasks.add(t),
                    onCsvPending: (content, {Map<int, String?>? mapping, int? dateCol}) {
                      _pendingCsvContent = content;
                      _pendingCsvMapping = mapping;
                      _pendingCsvDateCol = dateCol;
                    },
                    onInhabitantsAdded: (added) { debugPrint('[Onboard] onInhabitantsAdded: ${added.map((a) => a.name).toList()}'); setState(() => _inhabitants = [..._inhabitants, ...added]); },
                    onInhabitantsRemoved: (names) { debugPrint('[Onboard] onInhabitantsRemoved: $names'); setState(() => _inhabitants = _inhabitants.where((i) => !names.contains(i.name.toLowerCase())).toList()); },
                    onPlantsAdded: (added) { debugPrint('[Onboard] onPlantsAdded: $added'); setState(() => _plants = [..._plants, ...added]); },
                    tankId: _createdTankId,
                    experience: _experience,
                    isActive: _page == 5,
                    finishing: _finishing,
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? _cDark : _cLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Onboarding page widgets ─────────────────────────────────────────────────


class _ObLogoBar extends StatelessWidget {
  const _ObLogoBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.center,
            child: Image.asset('assets/images/logo-side.png', height: 39, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ObHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  const _ObHeader({required this.emoji, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cDark, _cMid],
        ),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _inhEmoji(String type) {
  switch (type) {
    case 'invertebrate': return '🦐';
    case 'coral':        return '🪸';
    case 'polyp':        return '🪼';
    case 'anemone':      return '🌺';
    default:             return '🐟';
  }
}

Widget _obNextButton({required String label, required VoidCallback? onPressed}) => Padding(
  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
  child: SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _cDark,
        disabledBackgroundColor: Colors.grey.shade300,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 16)),
    ),
  ),
);

// Page 2 — Welcome (dynamic content based on experience)
class _ObWelcomePage extends StatelessWidget {
  final String experience;
  final VoidCallback onNext;
  const _ObWelcomePage({required this.experience, required this.onNext});

  static const _content = {
    'beginner': (
      emoji: '🌱',
      title: 'We\'ll learn together',
      subtitle: 'No experience needed — Aquaria is here to guide you every step of the way',
      features: [
        (icon: Icons.lightbulb_outline, text: 'Learning made fun and simple.'),
        (icon: Icons.chat_bubble_outline, text: 'Ask Ariel anything. She\'s our AI sidekick.'),
        (icon: Icons.checklist, text: 'Simple steps to help with the upkeep.'),
        (icon: Icons.school_outlined, text: 'You\'ll learn as you go, at your own pace. Aquaria grows with you.'),
      ],
    ),
    'intermediate': (
      emoji: '🐠',
      title: 'Take your tanks further',
      subtitle: 'Smart tools built for the way you already think',
      features: [
        (icon: Icons.edit_note, text: 'Log water parameters in natural language — just type what you tested, and we handle the rest.'),
        (icon: Icons.show_chart, text: 'Spot trends before they become problems with clean parameter charts over time.'),
        (icon: Icons.auto_awesome, text: 'AI advice tuned to your specific fish, tank size, and your actual log history.'),
        (icon: Icons.notifications_none, text: 'Stay ahead of maintenance with smart reminders based on your schedule.'),
      ],
    ),
    'expert': (
      emoji: '🦈',
      title: 'Your precision companion',
      subtitle: 'Serious tools for serious keepers',
      features: [
        (icon: Icons.dashboard_outlined, text: 'Manage multiple tanks from one clean dashboard — each with its own log history and inhabitant profiles.'),
        (icon: Icons.science_outlined, text: 'Inhabitant-aware chemistry advice. The AI knows which species are sensitive to copper, pH swings, and more.'),
        (icon: Icons.analytics_outlined, text: 'Deep parameter analytics to catch drift and anomalies before your livestock does.'),
        (icon: Icons.auto_awesome, text: 'An AI that reads your full log history and gets smarter about your specific setups over time.'),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = _content[experience] ?? _content['intermediate']!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _BeginnerVideoHeader(title: c.title),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                  child: Column(
                    children: [
                      for (final f in c.features) ...[
                        _ObFeatureRow(icon: f.icon, text: f.text),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _obNextButton(label: 'Get Started', onPressed: onNext),
      ],
    );
  }
}

class _ObFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ObFeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _cDark, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black87))),
      ],
    );
  }
}

class _BeginnerVideoHeader extends StatefulWidget {
  final String title;
  const _BeginnerVideoHeader({this.title = 'No Experience Needed!'});
  @override
  State<_BeginnerVideoHeader> createState() => _BeginnerVideoHeaderState();
}

class _BeginnerVideoHeaderState extends State<_BeginnerVideoHeader> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.asset('assets/images/clownie-random-silent.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.setVolume(0);
        _ctrl.addListener(_onVideoUpdate);
        _ctrl.play();
      }).catchError((_) {});
  }

  void _onVideoUpdate() {
    if (!_ctrl.value.isInitialized || _seeking) return;
    final dur = _ctrl.value.duration;
    if (dur == Duration.zero) return;
    if (_ctrl.value.position >= dur - const Duration(milliseconds: 150)) {
      _seeking = true;
      _ctrl.seekTo(Duration.zero).then((_) { _ctrl.play(); _seeking = false; });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onVideoUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ObLogoBar(),
        SizedBox(
          width: double.infinity,
          child: _ready
              ? AspectRatio(
                  aspectRatio: _ctrl.value.aspectRatio,
                  child: VideoPlayer(_ctrl),
                )
              : Container(
                  height: 120,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_cDark, _cMid],
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            widget.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _PouringVideoHeader extends StatefulWidget {
  const _PouringVideoHeader();
  @override
  State<_PouringVideoHeader> createState() => _PouringVideoHeaderState();
}

class _PouringVideoHeaderState extends State<_PouringVideoHeader> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _seeking = false;
  static const _loopStart = Duration(milliseconds: 9333);

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.asset('assets/images/pouring-silent.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.setVolume(0);
        _ctrl.addListener(_onVideoUpdate);
        _ctrl.play();
      }).catchError((_) {});
  }

  void _onVideoUpdate() {
    if (!_ctrl.value.isInitialized || _seeking) return;
    final dur = _ctrl.value.duration;
    if (dur == Duration.zero) return;
    if (_ctrl.value.position >= dur - const Duration(milliseconds: 150)) {
      _seeking = true;
      _ctrl.seekTo(_loopStart).then((_) { _ctrl.play(); _seeking = false; });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onVideoUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: _ready
          ? ClipRect(
              child: SizedBox(
                width: double.infinity,
                height: 180,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ctrl.value.size.width,
                    height: _ctrl.value.size.height,
                    child: VideoPlayer(_ctrl),
                  ),
                ),
              ),
            )
          : Container(
              height: 150,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_cDark, _cMid],
                ),
              ),
            ),
    );
  }
}

// Page 1 — Experience Level (first screen the user sees)
class _ObExperiencePage extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  final VoidCallback? onNext;
  const _ObExperiencePage({required this.selected, required this.onSelect, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ObLogoBar(),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Text(
            'Welcome to Aquaria',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              children: [
                const SizedBox(height: 36),
                _ObExpCard(
                  emoji: '🌱', title: 'Just starting out',
                  subtitle: 'New to fishkeeping — I want to learn as I go',
                  selected: selected == 'beginner',
                  onTap: () => onSelect('beginner'),
                ),
                const SizedBox(height: 12),
                _ObExpCard(
                  emoji: '🐠', title: 'Some experience',
                  subtitle: 'I\'ve kept fish before and know the basics',
                  selected: selected == 'intermediate',
                  onTap: () => onSelect('intermediate'),
                ),
                const SizedBox(height: 12),
                _ObExpCard(
                  emoji: '🦈', title: 'Advanced keeper',
                  subtitle: 'I run complex or multiple tanks and want full control',
                  selected: selected == 'expert',
                  onTap: () => onSelect('expert'),
                ),
                const Expanded(
                  child: Center(child: Text('🐠', style: TextStyle(fontSize: 60))),
                ),
              ],
            ),
          ),
        ),
        _obNextButton(label: 'Continue', onPressed: onNext),
      ],
    );
  }
}

class _ObExpCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ObExpCard({required this.emoji, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _cMint : Colors.white,
          border: Border.all(color: selected ? _cDark : Colors.grey.shade300, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [BoxShadow(color: _cDark.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: selected ? _cDark : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: selected ? _cDark.withOpacity(0.75) : Colors.grey)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: _cDark),
          ],
        ),
      ),
    );
  }
}

// Page 3b — Equipment (optional, skippable)
class _ObEquipmentPage extends StatelessWidget {
  final WaterType waterType;
  final Map<String, dynamic> equipment;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onNext;
  final bool showSkip;

  const _ObEquipmentPage({
    required this.waterType,
    required this.equipment,
    required this.onChanged,
    required this.onNext,
    this.showSkip = true,
  });

  bool get _isSaltwater => [WaterType.saltwater, WaterType.reef].contains(waterType);

  void _set(String key, dynamic value) {
    final updated = Map<String, dynamic>.from(equipment);
    updated[key] = value;
    onChanged(updated);
  }

  Widget _chipRow(String label, String key, List<String> options, List<String> labels) {
    final current = equipment[key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: List.generate(options.length, (i) {
            final selected = current == options[i];
            return ChoiceChip(
              label: Text(labels[i]),
              selected: selected,
              showCheckmark: false,
              selectedColor: const Color(0xFF1FA2A8),
              labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 13),
              onSelected: (_) => _set(key, options[i]),
            );
          }),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _multiChipRow(String label, String key, List<String> options, List<String> labels) {
    final current = List<String>.from((equipment[key] as List?) ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: List.generate(options.length, (i) {
            final selected = current.contains(options[i]);
            return FilterChip(
              label: Text(labels[i]),
              selected: selected,
              showCheckmark: true,
              selectedColor: const Color(0xFFD9F7F0),
              checkmarkColor: const Color(0xFF0E5A66),
              labelStyle: TextStyle(color: selected ? const Color(0xFF0E5A66) : Colors.black87, fontSize: 13),
              onSelected: (on) {
                if (on) { current.add(options[i]); } else { current.remove(options[i]); }
                _set(key, current);
              },
            );
          }),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _multiDropdownRow(BuildContext context, String label, String key, List<String> options, List<String> labels) {
    final current = List<String>.from((equipment[key] as List?) ?? []);
    final displayText = current.isEmpty
        ? 'Select'
        : current.map((v) {
            final idx = options.indexOf(v);
            return idx >= 0 ? labels[idx] : v.replaceAll('_', ' ');
          }).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) {
                var selected = List<String>.from(current);
                return StatefulBuilder(
                  builder: (ctx, setDialogState) => AlertDialog(
                    title: Text(label),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(options.length, (i) =>
                          CheckboxListTile(
                            title: Text(labels[i], style: const TextStyle(fontSize: 14)),
                            value: selected.contains(options[i]),
                            activeColor: const Color(0xFF1FA2A8),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) { selected.add(options[i]); } else { selected.remove(options[i]); }
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () { _set(key, selected); Navigator.pop(ctx); },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText,
                    style: TextStyle(fontSize: 14, color: current.isEmpty ? Colors.grey.shade500 : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _dropdownRow(BuildContext context, String label, String key, List<String> options, List<String> labels) {
    final current = equipment[key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        DropdownButtonFormField<String>(
          value: options.contains(current) ? current : null,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          hint: const Text('Select', style: TextStyle(fontSize: 14)),
          items: List.generate(options.length, (i) =>
            DropdownMenuItem(value: options[i], child: Text(labels[i], style: const TextStyle(fontSize: 14))),
          ),
          onChanged: (v) { if (v != null) _set(key, v); },
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _toggle(String label, String key) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: equipment[key] == true,
      activeColor: const Color(0xFF1FA2A8),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (v) => _set(key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final freshFilterTypes = ['canister', 'hob', 'sponge', 'internal', 'undergravel'];
    final freshFilterLabels = ['Canister', 'Hanging', 'Sponge', 'Internal', 'Undergravel'];
    final saltFilterTypes = ['sump', 'canister', 'hob'];
    final saltFilterLabels = ['Sump', 'Canister', 'Hanging'];

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _ObLogoBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const Text('Equipment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0E5A66))),
                      const SizedBox(height: 8),
                      Text('Tell us about your setup so Ariel can give better advice.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _multiChipRow('Substrate', 'substrate',
                      _isSaltwater
                        ? ['sand', 'gravel', 'bare_bottom', 'crushed_coral', 'other']
                        : ['sand', 'gravel', 'bare_bottom', 'soil', 'crushed_coral', 'other'],
                      _isSaltwater
                        ? ['Sand', 'Gravel', 'Bare', 'Crushed Coral', 'Other']
                        : ['Sand', 'Gravel', 'Bare', 'Aqua Soil', 'Crushed Coral', 'Other'],
                    ),
                    if ((equipment['substrate'] as List?)?.contains('other') ?? false)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          initialValue: equipment['substrate_other'] as String? ?? '',
                          decoration: InputDecoration(
                            hintText: 'Enter substrate name',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (v) => _set('substrate_other', v),
                        ),
                      ),
                    _dropdownRow(context, 'Filter Type', 'filter_type',
                      _isSaltwater ? saltFilterTypes : freshFilterTypes,
                      _isSaltwater ? saltFilterLabels : freshFilterLabels,
                    ),
                    _multiDropdownRow(context, 'Filter Media', 'filter_media',
                      _isSaltwater
                        ? ['carbon', 'gfo', 'aragonite', 'bio_media', 'filter_floss', 'ceramic_rings', 'zeolite', 'ion_exchange_resin']
                        : ['carbon', 'phosphate_pad', 'aragonite', 'bio_media', 'sponge', 'filter_floss', 'ceramic_rings', 'zeolite', 'ion_exchange_resin'],
                      _isSaltwater
                        ? ['Carbon', 'GFO', 'Aragonite', 'Bio Media', 'Filter Floss', 'Ceramic Rings', 'Zeolite', 'Ion Exchange Resin']
                        : ['Carbon', 'Phosphate Pad', 'Aragonite', 'Bio Media', 'Sponge', 'Filter Floss', 'Ceramic Rings', 'Zeolite', 'Ion Exchange Resin'],
                    ),
                    _chipRow('Lighting', 'lighting_type',
                      ['led', 't5', 'metal_halide', 'none'],
                      ['LED', 'T5', 'Metal Halide', 'None'],
                    ),
                    _toggle('Heater', 'has_heater'),
                    _toggle('Air pump / Bubbler', 'has_air_pump'),
                    if (!_isSaltwater) ...[
                      _toggle('CO2 Injection', 'has_co2'),
                    ],
                    if (_isSaltwater) ...[
                      _toggle('Protein Skimmer', 'has_protein_skimmer'),
                      _toggle('ATO (Auto Top-Off)', 'has_ato'),
                      _toggle('Dosing Pump', 'has_dosing_pump'),
                      _toggle('Live Rock', 'has_live_rock'),
                      _toggle('Calcium Reactor', 'has_calcium_reactor'),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('Additional Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Additional Details'),
                                content: const Text(
                                  'Include any extra info that helps Ariel give better advice:\n\n'
                                  '• Equipment brand & model (e.g. Fluval 307, AI Prime 16HD)\n'
                                  '• Filter capacity or flow rate\n'
                                  '• Tank dimensions or shape\n'
                                  '• Dosing schedule or products used\n'
                                  '• Substrate depth\n'
                                  '• Stocking notes or plans\n'
                                  '• Any known issues or concerns',
                                ),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                              ),
                            );
                          },
                          child: const Icon(Icons.info_outline, size: 16, color: Color(0xFF1FA2A8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: equipment['notes'] as String? ?? '',
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'e.g. Fluval 307 canister, AI Prime 16HD light, 3" sand bed...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => _set('notes', v),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            ],
          ),
        ),
        if (showSkip)
          TextButton(
            onPressed: onNext,
            child: const Text('Skip for now', style: TextStyle(color: Colors.grey)),
          ),
        _obNextButton(label: showSkip ? 'Continue' : 'Done', onPressed: onNext),
        const SizedBox(height: 8),
      ],
    );
  }
}

// Page 3 — Tank Setup
class _ObTankSetupPage extends StatefulWidget {
  final TextEditingController nameCtrl;
  final double gallons;
  final WaterType waterType;
  final void Function(double) onGallonsChanged;
  final void Function(WaterType) onWaterTypeChanged;
  final VoidCallback onNext;
  final String experience;
  final Map<String, dynamic> equipment;
  final void Function(Map<String, dynamic>)? onEquipmentChanged;
  const _ObTankSetupPage({
    required this.nameCtrl, required this.gallons, required this.waterType,
    required this.onGallonsChanged, required this.onWaterTypeChanged, required this.onNext,
    this.experience = '',
    this.equipment = const {},
    this.onEquipmentChanged,
  });

  @override
  State<_ObTankSetupPage> createState() => _ObTankSetupPageState();
}

class _ObTankSetupPageState extends State<_ObTankSetupPage> {
  late final TextEditingController _sizeCtrl;
  String _unit = 'gal'; // 'gal' | 'L'

  static const double _lPerGal = 3.78541;

  // Water type two-step state
  String? _waterBase; // 'freshwater' | 'saltwater' | 'pond'
  bool _hasPlants = false;
  final Set<String> _saltFeatures = {}; // 'reef', 'coral', 'polyps'

  @override
  void initState() {
    super.initState();
    _sizeCtrl = TextEditingController(text: widget.gallons.round().toString());
    _sizeCtrl.addListener(_onSizeTextChanged);
    switch (widget.waterType) {
      case WaterType.saltwater:  _waterBase = 'saltwater';
      case WaterType.reef:       _waterBase = 'saltwater'; _saltFeatures.add('reef');
      case WaterType.planted:    _waterBase = 'freshwater'; _hasPlants = true;
      case WaterType.pond:       _waterBase = 'pond';
      case WaterType.freshwater: _waterBase = null;
    }
  }

  void _onSizeTextChanged() {
    final val = double.tryParse(_sizeCtrl.text);
    if (val == null || val <= 0) return;
    final gallons = _unit == 'L' ? val / _lPerGal : val;
    widget.onGallonsChanged(gallons);
  }

  void _switchUnit(String unit) {
    if (unit == _unit) return;
    final current = double.tryParse(_sizeCtrl.text) ?? 0;
    setState(() { _unit = unit; });
    if (current > 0) {
      final converted = unit == 'L' ? current * _lPerGal : current / _lPerGal;
      _sizeCtrl.text = converted.toStringAsFixed(1);
      _sizeCtrl.selection = TextSelection.collapsed(offset: _sizeCtrl.text.length);
    }
  }

  void _pushWaterType() {
    final WaterType wt;
    if (_waterBase == 'saltwater') {
      wt = _saltFeatures.isNotEmpty ? WaterType.reef : WaterType.saltwater;
    } else if (_waterBase == 'pond') {
      wt = WaterType.pond;
    } else {
      wt = _hasPlants ? WaterType.planted : WaterType.freshwater;
    }
    widget.onWaterTypeChanged(wt);
  }

  void _selectBase(String base) {
    setState(() {
      _waterBase = base;
      _hasPlants = false;
      _saltFeatures.clear();
    });
    _pushWaterType();
  }

  void _toggleSaltFeature(String f) {
    setState(() {
      if (_saltFeatures.contains(f)) {
        _saltFeatures.remove(f);
      } else {
        _saltFeatures.add(f);
      }
    });
    _pushWaterType();
  }

  @override
  void dispose() {
    _sizeCtrl.removeListener(_onSizeTextChanged);
    _sizeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ObLogoBar(),
                const SizedBox(height: 12),
                const _PouringVideoHeader(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // Tank Name
                const Text('Give your tank a name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Living Room Tank',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Tank Size
                const Text('What size is the tank?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sizeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _UnitBtn(label: 'gal', selected: _unit == 'gal', onTap: () => _switchUnit('gal')),
                          Container(width: 1, height: 44, color: Colors.grey.shade300),
                          _UnitBtn(label: 'L', selected: _unit == 'L', onTap: () => _switchUnit('L')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Water base question
                const Text('What kind of water?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _WaterBaseCard(
                      emoji: '💧', label: 'Freshwater',
                      selected: _waterBase == 'freshwater',
                      onTap: () => _selectBase('freshwater'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _WaterBaseCard(
                      emoji: '🌊', label: 'Saltwater',
                      selected: _waterBase == 'saltwater',
                      onTap: () => _selectBase('saltwater'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _WaterBaseCard(
                      emoji: '🪷', label: 'Pond',
                      selected: _waterBase == 'pond',
                      onTap: () => _selectBase('pond'),
                    )),
                  ],
                ),
                // Follow-up question — swings in when base is selected
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: (_waterBase == null || _waterBase == 'pond')
                      ? const SizedBox.shrink()
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          ),
                          child: _waterBase == 'freshwater'
                              ? _FreshwaterFollowUp(
                                  key: const ValueKey('fw'),
                                  hasPlants: _hasPlants,
                                  onChanged: (v) { setState(() => _hasPlants = v); _pushWaterType(); },
                                )
                              : _SaltwaterFollowUp(
                                  key: const ValueKey('sw'),
                                  selected: _saltFeatures,
                                  onToggle: _toggleSaltFeature,
                                ),
                        ),
                ),
              ],
            ),
                ),
              ],
            ),
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => SizedBox(
                      height: MediaQuery.of(context).size.height * 0.85,
                      child: _ObEquipmentPage(
                        waterType: widget.waterType,
                        equipment: widget.equipment,
                        showSkip: false,
                        onChanged: (eq) => widget.onEquipmentChanged?.call(eq),
                        onNext: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.build_outlined, size: 16),
                label: const Text('Add Equipment', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cDark,
                  side: BorderSide(color: _cMid, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        _obNextButton(label: 'Continue', onPressed: widget.onNext),
      ],
    );
  }
}

class _WaterBaseCard extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _WaterBaseCard({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _cDark : Colors.white,
          border: Border.all(color: selected ? _cDark : Colors.grey.shade300, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: _cDark.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: selected ? Colors.white : Colors.black87,
            )),
          ],
        ),
      ),
    );
  }
}

class _FreshwaterFollowUp extends StatelessWidget {
  final bool hasPlants;
  final void Function(bool) onChanged;
  const _FreshwaterFollowUp({super.key, required this.hasPlants, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Will it have live plants?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _FollowUpOption(
                emoji: '🌿', label: 'Yes, with plants',
                selected: hasPlants,
                onTap: () => onChanged(true),
              )),
              const SizedBox(width: 10),
              Expanded(child: _FollowUpOption(
                emoji: '🪨', label: 'No, just fish',
                selected: !hasPlants,
                onTap: () => onChanged(false),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaltwaterFollowUp extends StatelessWidget {
  final Set<String> selected;
  final void Function(String) onToggle;
  const _SaltwaterFollowUp({super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Will it contain any of these?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Text('Select all that apply', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _FollowUpOption(emoji: '🪸', label: 'Coral', selected: selected.contains('coral'), onTap: () => onToggle('coral'))),
              const SizedBox(width: 8),
              Expanded(child: _FollowUpOption(emoji: '🪨', label: 'Reef rock', selected: selected.contains('reef'), onTap: () => onToggle('reef'))),
              const SizedBox(width: 8),
              Expanded(child: _FollowUpOption(emoji: '🪼', label: 'Polyps', selected: selected.contains('polyps'), onTap: () => onToggle('polyps'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowUpOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FollowUpOption({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _cMint : Colors.white,
          border: Border.all(color: selected ? _cDark : Colors.grey.shade300, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? _cDark : Colors.black54,
            ), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _UnitBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _UnitBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 52,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? _cDark : Colors.white,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _DropInVideoHeader extends StatefulWidget {
  const _DropInVideoHeader();
  @override
  State<_DropInVideoHeader> createState() => _DropInVideoHeaderState();
}

class _DropInVideoHeaderState extends State<_DropInVideoHeader> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _seeking = false;
  static const _loopStart = Duration(milliseconds: 4000);

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.asset('assets/images/dropin-silent.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.setVolume(0);
        _ctrl.addListener(_onVideoUpdate);
        _ctrl.play();
      }).catchError((_) {});
  }

  void _onVideoUpdate() {
    if (!_ctrl.value.isInitialized || _seeking) return;
    final dur = _ctrl.value.duration;
    if (dur == Duration.zero) return;
    final pos = _ctrl.value.position;
    if (pos >= dur - const Duration(milliseconds: 150)) {
      _seeking = true;
      _ctrl.seekTo(_loopStart).then((_) { _ctrl.play(); _seeking = false; });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onVideoUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _ready
          ? AspectRatio(
              aspectRatio: _ctrl.value.aspectRatio,
              child: VideoPlayer(_ctrl),
            )
          : Container(
              height: 150,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_cDark, _cMid],
                ),
              ),
            ),
    );
  }
}

class _IconCarousel extends StatefulWidget {
  const _IconCarousel();
  @override
  State<_IconCarousel> createState() => _IconCarouselState();
}

class _IconCarouselState extends State<_IconCarousel> {
  static const _icons = ['🐟', '🦐', '🌿', '🪸'];
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (mounted) setState(() => _idx = (_idx + 1) % _icons.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      child: ColorFiltered(
        key: ValueKey(_idx),
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      0.35, 0,
        ]),
        child: Text(_icons[_idx], style: const TextStyle(fontSize: 80)),
      ),
    );
  }
}

// ── Compatibility warnings (shared between onboarding & inhabitants screen) ──
List<({String icon, String message})> _compatibilityWarnings(
  List<({String name, String type, int count})> inhabitants,
  WaterType waterType, {
  List<String> plants = const [],
}) {
  final warnings = <({String icon, String message})>[];
  final names = inhabitants.map((i) => i.name.toLowerCase()).toList();
  final types = inhabitants.map((i) => i.type.toLowerCase()).toList();
  final plantNames = plants.map((p) => p.toLowerCase()).toList();

  final aggressiveCichlids = names.where((n) =>
      n.contains('cichlid') || n.contains('oscar') || n.contains('flowerhorn') ||
      n.contains('jaguar') || n.contains('dovii') || n.contains('managuense') ||
      n.contains('jack dempsey') || n.contains('dempsey') || n.contains('convict') ||
      n.contains('green terror') || n.contains('red devil') || n.contains('midas') ||
      n.contains('texas cichlid') || n.contains('jewel cichlid') || n.contains('umbee')).toList();
  final communityFish = names.where((n) =>
      n.contains('tetra') || n.contains('guppy') || n.contains('platy') ||
      n.contains('molly') || n.contains('danio') || n.contains('rasbora') ||
      n.contains('corydora') || n.contains('harlequin') || n.contains('neon')).toList();
  if (aggressiveCichlids.isNotEmpty && communityFish.isNotEmpty) {
    warnings.add((icon: '⚠️', message: 'Cichlids can be aggressive toward small community fish. Ensure plenty of hiding spaces — caves, rocks, and dense plants help reduce territorial behavior.'));
  }

  final hasBetta = names.any((n) => n.contains('betta') || n.contains('siamese fighting'));
  final fishCount = inhabitants.where((i) => i.type == 'fish').length;
  if (hasBetta && fishCount > 1) {
    warnings.add((icon: '⚠️', message: 'Bettas are territorial and may attack fish with flowing fins or similar body shapes. Choose tank mates carefully — bottom-dwellers and fast schooling fish tend to work best.'));
  }

  final predators = names.where((n) =>
      n.contains('pike') || n.contains('snakehead') || n.contains('arowana') ||
      n.contains('predator') || n.contains('puffer')).toList();
  final hasInvertebrates = types.any((t) => t == 'invertebrate');
  if (predators.isNotEmpty && (communityFish.isNotEmpty || hasInvertebrates)) {
    warnings.add((icon: '⚠️', message: 'Predatory fish may hunt smaller fish and invertebrates. Monitor closely and ensure prey-sized tank mates have adequate shelter.'));
  }

  final hasPuffer = names.any((n) => n.contains('puffer'));
  if (hasPuffer && hasInvertebrates) {
    warnings.add((icon: '⚠️', message: 'Puffer fish will eat snails, shrimp, and other invertebrates — this can actually be used intentionally, but avoid mixing if you want to keep invertebrates.'));
  }

  final hasCoral = types.any((t) => t == 'coral' || t == 'anemone' || t == 'polyp');
  if (waterType == WaterType.freshwater && hasCoral) {
    warnings.add((icon: '🚨', message: 'Coral, anemones, and polyps require saltwater. These will not survive in a freshwater tank.'));
  }

  final bettaCount = inhabitants.where((i) => i.name.toLowerCase().contains('betta')).fold(0, (sum, i) => sum + i.count);
  if (bettaCount > 1) {
    warnings.add((icon: '🚨', message: 'Multiple bettas will fight. Male bettas should never share a tank — they will injure or kill each other.'));
  }

  // ── Plant compatibility checks ──

  if (plantNames.isNotEmpty) {
    // Freshwater plants in saltwater
    const freshwaterOnlyPlants = [
      'java fern', 'java moss', 'anubias', 'amazon sword', 'vallisneria',
      'hornwort', 'water wisteria', 'water sprite', 'cryptocoryne', 'crypt',
      'dwarf sagittaria', 'monte carlo', 'dwarf hairgrass', 'rotala',
      'ludwigia', 'bacopa', 'hygrophila', 'cabomba', 'elodea',
      'duckweed', 'frogbit', 'red root floater', 'salvinia',
      'pogostemon', 'staurogyne', 'alternanthera', 'bucephalandra',
      'moss ball', 'marimo', 'riccia', 'bolbitis', 'microsorum',
      's repens', 'pearl weed', 'pennywort',
    ];
    if (waterType == WaterType.saltwater) {
      final fwPlants = plantNames.where(
        (p) => freshwaterOnlyPlants.any((fw) => p.contains(fw)),
      ).toList();
      if (fwPlants.isNotEmpty) {
        warnings.add((icon: '🚨', message: 'Freshwater plants will not survive in a saltwater tank. Consider marine macroalgae like Chaetomorpha or Caulerpa instead.'));
      }
    }

    // Saltwater macroalgae in freshwater
    const saltwaterPlants = [
      'chaetomorpha', 'chaeto', 'caulerpa', 'halimeda', 'gracilaria',
      'ulva', 'sea lettuce', 'dragon breath', "dragon's breath",
      'red mangrove', 'mangrove',
    ];
    if (waterType == WaterType.freshwater || waterType == WaterType.planted) {
      final swPlants = plantNames.where(
        (p) => saltwaterPlants.any((sw) => p.contains(sw)),
      ).toList();
      if (swPlants.isNotEmpty) {
        warnings.add((icon: '🚨', message: 'Marine macroalgae require saltwater and will not survive in a freshwater tank.'));
      }
    }

    // Plant-diggers: goldfish, large cichlids, silver dollar, etc.
    const plantDiggers = [
      'goldfish', 'koi', 'oscar', 'silver dollar', 'buenos aires tetra',
      'tinfoil barb', 'severum', 'jack dempsey', 'texas cichlid',
      'pleco', 'common pleco',
    ];
    final diggers = names.where(
      (n) => plantDiggers.any((d) => n.contains(d)),
    ).toList();
    if (diggers.isNotEmpty) {
      warnings.add((icon: '⚠️', message: 'Some of your fish are known to uproot or eat live plants. Sturdy, well-anchored plants like Anubias and Java Fern (attached to hardscape) tend to survive best.'));
    }

    // High-light plants without CO2 note
    const highLightPlants = [
      'dwarf baby tears', 'hc cuba', 'monte carlo', 'glossostigma',
      'rotala macrandra', 'pogostemon helferi', 'downoi',
      'alternanthera reineckii', 'ar mini',
    ];
    final hasHighLight = plantNames.any(
      (p) => highLightPlants.any((hl) => p.contains(hl)),
    );
    if (hasHighLight) {
      warnings.add((icon: '💡', message: 'Some of your plants need high light and CO2 injection to thrive. Without CO2, they may grow slowly, melt, or be outcompeted by algae.'));
    }
  }

  return warnings;
}

// Page 4 — Inhabitants
class _ObInhabitantsPage extends StatefulWidget {
  final List<({String name, String type, int count})> initialInhabitants;
  final List<String> initialPlants;
  final void Function(List<({String name, String type, int count})> inhabitants, List<String> plants) onNext;
  final WaterType waterType;
  final bool showSkip;
  const _ObInhabitantsPage({
    required this.initialInhabitants,
    this.initialPlants = const [],
    required this.onNext,
    required this.waterType,
    this.showSkip = true,
  });

  @override
  State<_ObInhabitantsPage> createState() => _ObInhabitantsPageState();
}

class _ObInhabitantsPageState extends State<_ObInhabitantsPage> {
  static const _types = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  late List<_InhEdit> _inhs;
  late List<_PlantEdit> _plts;

  @override
  void initState() {
    super.initState();
    _inhs = widget.initialInhabitants.map((i) => _InhEdit(nameText: i.name, type: i.type, count: i.count)).toList();
    _plts = widget.initialPlants.map((p) => _PlantEdit(nameText: p)).toList();
  }

  @override
  void didUpdateWidget(covariant _ObInhabitantsPage old) {
    super.didUpdateWidget(old);
    // Sync inhabitants/plants added externally — deferred to avoid build scope conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool changed = false;
      final currentNames = _inhs.map((i) => i.name.text.trim().toLowerCase()).toSet();
      for (final inh in widget.initialInhabitants) {
        if (!currentNames.contains(inh.name.toLowerCase())) {
          _inhs.add(_InhEdit(nameText: inh.name, type: inh.type, count: inh.count));
          currentNames.add(inh.name.toLowerCase());
          changed = true;
        }
      }
      final currentPlants = _plts.map((p) => p.name.text.trim().toLowerCase()).toSet();
      for (final plant in widget.initialPlants) {
        if (!currentPlants.contains(plant.toLowerCase())) {
          _plts.add(_PlantEdit(nameText: plant));
          currentPlants.add(plant.toLowerCase());
          changed = true;
        }
      }
      if (changed) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final i in _inhs) i.dispose();
    for (final p in _plts) p.dispose();
    super.dispose();
  }

  void _continue() {
    final inhabitants = _inhs
        .where((i) => i.name.text.trim().isNotEmpty)
        .map((i) => (name: i.name.text.trim(), type: i.type, count: i.count))
        .toList();
    final plants = _plts.map((p) => p.name.text.trim()).where((n) => n.isNotEmpty).toList();
    widget.onNext(inhabitants, plants);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _ObLogoBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              const SliverToBoxAdapter(child: _DropInVideoHeader()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Inhabitants section
                      const Text('INHABITANTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      ...List.generate(_inhs.length, (idx) {
                        final inh = _inhs[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              DropdownButton<String>(
                                value: inh.type,
                                underline: const SizedBox(),
                                isDense: true,
                                items: _types.map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(_typeEmoji[t] ?? '🐠', style: const TextStyle(fontSize: 20)),
                                )).toList(),
                                onChanged: (v) => setState(() => inh.type = v!),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final result = await showModalBottomSheet<({String name, String type, int count})>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => _SpeciesPickerSheet(isPlant: false, waterType: widget.waterType),
                                    );
                                    if (result != null && mounted) {
                                      setState(() { inh.name.text = result.name; inh.type = result.type; });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            inh.name.text.isEmpty ? 'Tap to choose…' : inh.name.text,
                                            style: TextStyle(fontSize: 14, color: inh.name.text.isEmpty ? Colors.grey : Colors.black87),
                                          ),
                                        ),
                                        const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.remove, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: inh.count > 1 ? () => setState(() => inh.count--) : null,
                              ),
                              SizedBox(
                                width: 24,
                                child: Text('${inh.count}', textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => setState(() => inh.count++),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => setState(() { _inhs[idx].dispose(); _inhs.removeAt(idx); }),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () async {
                          final result = await showModalBottomSheet<({String name, String type, int count})>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _SpeciesPickerSheet(isPlant: false, waterType: widget.waterType),
                          );
                          if (result != null && mounted) {
                            setState(() => _inhs.add(_InhEdit(nameText: result.name, type: result.type, count: result.count)));
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add inhabitant'),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      // Plants section
                      const Text('PLANTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      ...List.generate(_plts.length, (idx) {
                        final plt = _plts[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Text('🌿', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final result = await showModalBottomSheet<({String name, String type, int count})>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const _SpeciesPickerSheet(isPlant: true),
                                    );
                                    if (result != null && mounted) setState(() => plt.name.text = result.name);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            plt.name.text.isEmpty ? 'Tap to choose…' : plt.name.text,
                                            style: TextStyle(fontSize: 14, color: plt.name.text.isEmpty ? Colors.grey : Colors.black87),
                                          ),
                                        ),
                                        const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => setState(() { _plts[idx].dispose(); _plts.removeAt(idx); }),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () async {
                          final result = await showModalBottomSheet<({String name, String type, int count})>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const _SpeciesPickerSheet(isPlant: true),
                          );
                          if (result != null && mounted) {
                            setState(() => _plts.add(_PlantEdit(nameText: result.name)));
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add plant'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.showSkip)
          TextButton(
            onPressed: () => widget.onNext([], []),
            child: const Text('Skip for now', style: TextStyle(color: Colors.grey)),
          ),
        _obNextButton(label: 'Continue', onPressed: _continue),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Inhabitant descriptions ───────────────────────────────────────────────────

const _kSpeciesDescriptions = <String, String>{
  // Freshwater Fish
  'Betta': 'Vibrant and territorial, bettas thrive alone in calm, warm water with hiding spots. Males are stunning but will fight each other on sight.',
  'Neon Tetra': 'Peaceful schooling fish that dazzle in groups of 6+. They prefer soft, slightly acidic water and are a classic community fish.',
  'Cardinal Tetra': 'Like neon tetras but with more vivid red coloring extending the full length of their body. Peaceful schoolers that love soft, warm water.',
  'Guppy': 'Hardy, colorful, and great for beginners. Males are flashy showmen; they breed readily and adapt to most water conditions.',
  'Molly': 'Adaptable livebearers that tolerate a wide range of conditions including slightly brackish water. Peaceful and active community fish.',
  'Platy': 'Hardy, colorful livebearers that are easy to keep and breed. One of the best starter fish for any community tank.',
  'Swordtail': 'Active livebearers named for the sword-like extension on the male\'s tail. Peaceful in groups but males can be scrappy with each other.',
  'Angelfish': 'Elegant cichlids with flowing fins and complex personalities. Semi-aggressive — they may snack on small tankmates like neon tetras.',
  'Discus': 'Considered the king of the aquarium. Discus form pair bonds, are sensitive to water quality, and reward patient keepers with stunning color.',
  'Oscar': 'Large, intelligent cichlids with dog-like personalities — they recognize their owners. They need big tanks and will eat anything that fits in their mouth.',
  'Corydoras': 'Cheerful bottom-dwellers that love company of their own kind. They busily scavenge the substrate and make excellent, peaceful tank cleaners.',
  'Panda Corydoras': 'A popular corydoras with charming panda-like black and white markings. Peaceful, active in groups, and a great substrate cleaner.',
  'Plecostomus': 'Hardy algae eaters that can grow very large (over 12"). Mostly nocturnal and peaceful, though territorial with other plecos.',
  'Bristlenose Pleco': 'A smaller, beginner-friendly pleco that stays under 5". A great algae eater that won\'t outgrow most tanks.',
  'Otocinclus': 'Tiny, gentle algae eaters perfect for planted tanks. They need an established tank with algae growth and do best in groups.',
  'Clown Loach': 'Playful, social loaches that love company and hiding spots. Known to "play dead" dramatically — don\'t panic, it\'s completely normal.',
  'Kuhli Loach': 'Eel-like and secretive, kuhli loaches are nocturnal burrowers. Peaceful and fascinating; do best in groups with sandy substrate.',
  'Dojo Loach': 'Curious and personable, dojo loaches are known to become restless before storms due to barometric pressure changes. Peaceful and entertaining.',
  'Zebra Danio': 'Hardy, energetic schooling fish perfect for beginners. Fast, playful, and tolerant of a wide range of temperatures.',
  'Pearl Danio': 'Delicate and shimmering, pearl danios are peaceful schoolers with a soft iridescent glow. Hardy and easy to care for.',
  'Harlequin Rasbora': 'Peaceful schoolers with a striking copper-and-black color pattern. They prefer soft, warm water and look best in groups of 8+.',
  'Chili Rasbora': 'Tiny, brilliant nano fish best kept in groups of 10+. Males display vivid color and they\'re ideal for planted tanks.',
  'White Cloud Minnow': 'Hardy, colorful coldwater fish that don\'t need a heater. Peaceful schoolers and one of the easiest fish to keep.',
  'Goldfish': 'Long-lived and personable, goldfish are social and often recognize their owners. They produce a lot of waste and need strong filtration.',
  'Koi': 'Majestic, long-lived pond fish that can grow enormous. They\'re social, recognize their owners, and can live for decades.',
  'Boesemani Rainbowfish': 'Stunning fish with a vibrant half-orange, half-blue color split. Peaceful, active schoolers that look best in larger groups.',
  'Killifish': 'Vivid and diverse, killifish are often short-lived but brilliantly colored. Many species breed readily and are perfect for biotope setups.',
  'Dwarf Gourami': 'Peaceful, colorful labyrinth fish that breathe surface air. Males can be shy and sensitive; they prefer calm, well-planted tanks.',
  'Pearl Gourami': 'Elegant and gentle with a delicate pearl-patterned body. One of the most peaceful gouramis, ideal for community tanks.',
  'Honey Gourami': 'The gentlest of all gouramis — shy, peaceful, and beautiful in warm, planted tanks. A wonderful choice for a calm community.',
  'Rummy Nose Tetra': 'Famous for their bright red nose and tight, synchronized schooling. Sensitive to water quality; best in a mature, stable tank.',
  'Black Skirt Tetra': 'Hardy, active tetras with flowing black fins. Peaceful in groups but may nip the fins of slower, long-finned tankmates.',
  'Ember Tetra': 'Tiny, vivid orange nano tetras that are peaceful and effortless to keep. They glow like embers in a densely planted tank.',
  'Cherry Barb': 'Males turn brilliant red when showing off. Unlike tiger barbs, they\'re non-nippy and make great, peaceful community fish.',
  'Tiger Barb': 'Active and semi-aggressive, tiger barbs are known fin-nippers. Keep them in groups of 6+ to distribute their energy.',
  'African Cichlid': 'Vibrant and bold, African cichlids need hard, alkaline water. Males are territorial — they do best in species-specific tanks with lots of rockwork.',
  'Ram Cichlid': 'Beautiful dwarf cichlids that form strong pair bonds. They prefer warm, soft, slightly acidic water and are a bit more delicate.',
  'Apistogramma': 'Colorful dwarf cichlids with fascinating courtship and breeding displays. Males are territorial; best kept as a pair in a planted tank.',
  'Flowerhorn': 'A man-made hybrid cichlid famous for its dramatic head hump. Bold, intelligent, and highly personable — but strictly a solo fish.',
  'Electric Yellow Cichlid': 'Brilliant yellow cichlid from Lake Malawi with a bold, confident personality. Needs hard, alkaline water and plenty of rockwork.',
  'Endler\'s Livebearer': 'Colorful nano fish closely related to guppies. Hardy, prolific breeders that are perfect for small, planted tanks.',
  'Peacock Gudgeon': 'A rare gem with vibrant peacock-like coloring. Peaceful and unusual, they prefer cool, soft water and planted environments.',
  'Scarlet Badis': 'Tiny jewels with stunning red and blue coloring. Males are territorial but peaceful with other species in nano planted tanks.',
  'GloFish Tetra': 'Fluorescent black skirt tetras that glow under blue light. Same care as regular tetras — peaceful schoolers best kept in groups of 6+.',
  'GloFish Danio': 'Fluorescent zebra danios — the original GloFish. Hardy, active schoolers that are perfect for beginners and glow brilliantly under blue light.',
  'GloFish Barb': 'Fluorescent tiger barbs with the same semi-aggressive temperament. Keep in groups of 6+ to reduce fin-nipping; stunning under blue LEDs.',
  'GloFish Shark': 'A fluorescent rainbow shark — semi-aggressive and territorial toward bottom-dwellers. Needs hiding spots and room to establish territory.',
  'GloFish Betta': 'A fluorescent betta with the same care needs as standard bettas. Keep alone or with peaceful tankmates; glows under blue light.',
  // Saltwater Fish
  'Ocellaris Clownfish': 'The iconic "Finding Nemo" fish. Hardy, personable, and reef-safe; they form a symbiotic bond with anemones over time.',
  'Percula Clownfish': 'Nearly identical to ocellaris but slightly more vivid. Hardy, reef-safe, and one of the most beloved marine fish in the hobby.',
  'Blue Tang': 'The famous "Dory" fish — active, reef-safe, and full of personality. Needs lots of swimming room and is prone to ich when stressed.',
  'Yellow Tang': 'Hardy, active, and one of the best natural algae grazers. A beloved reef fish that needs open water and regular grazing opportunities.',
  'Hippo Tang': 'Peaceful and adored, but needs a large tank. Active swimmers prone to ich; they benefit from a low-stress, well-established system.',
  'Green Chromis': 'One of the easiest saltwater fish to keep — peaceful, schooling, and hardy. A perfect starter fish for reef tanks.',
  'Blue Damselfish': 'Hardy and strikingly colored, but territorial and aggressive as they mature. Often used to cycle tanks; can become a bully.',
  'Royal Gramma': 'Beautiful purple and yellow basslet that\'s peaceful and reef-safe. Secretive at first but bold and personable once comfortable.',
  'Firefish Goby': 'Shy, elegant, and reef-safe. They hover near their burrow and are notorious jumpers — a secure lid is absolutely essential.',
  'Mandarin Dragonet': 'Arguably the most beautiful fish in the hobby. Notoriously picky eaters that usually only accept live copepods — for experienced reefers.',
  'Tailspot Blenny': 'Hardy, reef-safe, and endlessly entertaining with their perching and curious expressions. Good algae grazers.',
  'Lawnmower Blenny': 'Excellent algae grazers that methodically patrol the rockwork. Hardy and peaceful, with a wonderfully comical face.',
  'Watchman Goby': 'Bold and personable, watchman gobies form fascinating symbiotic burrows with pistol shrimp. Hardy and reef-safe.',
  'Hawkfish': 'Bold, perching fish with sharp eyes and lots of personality. Not fully reef-safe — they may snack on small shrimp.',
  'Anthias': 'Colorful, active schooling fish that need frequent feeding. Social fish that do best in groups with one dominant male.',
  'Sixline Wrasse': 'Beautifully striped and actively hunts flatworms and small pests. Can be feisty with smaller, more timid fish.',
  'Cleaner Wrasse': 'Sets up "cleaning stations" and picks parasites off other fish. An ecologically fascinating fish that needs frequent feeding.',
  'Flame Angelfish': 'Stunning dwarf angel with brilliant red and orange coloring. Generally reef-safe but may occasionally nip at large-polyp corals.',
  'Coral Beauty': 'Hardy dwarf angel with rich purple and orange coloring. May nip at corals occasionally; best in larger, established reef systems.',
  'Foxface Rabbitfish': 'Peaceful, distinctive, and an excellent algae grazer. Their venomous dorsal spines discourage nipping from tankmates.',
  'Neon Dottyback': 'Vivid magenta fish with a bold personality for their small size. May be aggressive toward similarly shaped fish.',
  'Lemonpeel Angelfish': 'Striking bright yellow dwarf angel with electric blue accents. May nip at corals; does best in fish-only or FOWLR systems.',
  // Shrimp & Invertebrates
  'Cherry Shrimp': 'Easy-to-keep freshwater shrimp that graze algae and biofilm. Red color intensifies with good water quality; great for planted tanks.',
  'Amano Shrimp': 'The most effective freshwater algae-eating shrimp — peaceful, hardy, and won\'t breed in freshwater. Larger than cherry shrimp.',
  'Ghost Shrimp': 'Transparent and fascinating to watch as they feed. Hardy, affordable cleaners but may be eaten by larger fish.',
  'Blue Velvet Shrimp': 'A vibrant neocaridina shrimp with the same easy care as cherry shrimp. Striking blue color pops in a planted tank.',
  'Crystal Red Shrimp': 'Beautiful red-and-white caridina shrimp. More demanding than neocaridinas — they require pristine, soft, acidic water.',
  'Blue Dream Shrimp': 'A vivid blue neocaridina variety that\'s just as hardy as cherry shrimp. Stunning in a planted tank with dark substrate.',
  'Tiger Shrimp': 'Bold striped caridina shrimp with intermediate care requirements. They prefer cooler, slightly acidic water conditions.',
  'Bamboo Shrimp': 'Unique filter-feeding shrimp that fan-feed from the water current. Peaceful giants that need established tanks with good flow.',
  'Vampire Shrimp': 'Large, fascinating filter-feeders with a striking appearance. Peaceful and unusual; they need flow and a mature tank.',
  'Cleaner Shrimp': 'Bold and personable, cleaner shrimp set up cleaning stations and pick parasites off fish. Reef-safe and entertaining.',
  'Fire Shrimp': 'Striking blood-red shrimp that are secretive but beautiful. Hardy and reef-safe; they also act as occasional cleaners.',
  'Pistol Shrimp': 'Famous for their snapping claw that stuns prey. Often pairs with gobies in a fascinating symbiotic relationship.',
  'Peppermint Shrimp': 'Hardy reef shrimp that actively hunt and eat pest aiptasia anemones. A natural, chemical-free solution for reef keepers.',
  'Harlequin Shrimp': 'Spectacularly colored but specialized — they eat only starfish. Beautiful but require a dedicated feeding plan.',
  'Nerite Snail': 'The best algae-eating snail — voracious cleaners that won\'t overpopulate since they can\'t breed in freshwater.',
  'Mystery Snail': 'Large, colorful, and active snails with a gentle temperament. Come in many colors and are endearing additions to planted tanks.',
  'Assassin Snail': 'Predatory snails that hunt and eliminate pest snails. A natural solution for controlling snail infestations in the tank.',
  'Ramshorn Snail': 'Small, spiral-shaped snails that graze algae and detritus. They can breed quickly — useful in moderation, a pest in excess.',
  'Malaysian Trumpet Snail': 'Burrowing snails that aerate substrate and eat detritus. Breed prolifically but are highly beneficial in planted tanks.',
  'Rabbit Snail': 'Slow-moving, distinctive snails with a long conical shell. Peaceful, don\'t breed quickly, and add character to the tank.',
  'Turbo Snail': 'Powerhouse saltwater algae eaters that work fast. Essential for reef cleanup crews but can knock over rockwork.',
  'Cerith Snail': 'Prolific algae and detritus eaters that burrow into sand. A great, low-profile addition to a reef cleanup crew.',
  'Nassarius Snail': 'Burrowing saltwater snails that emerge to feast on meaty waste. Excellent sand sifters and scavengers for reef tanks.',
  'Astrea Snail': 'Efficient saltwater algae grazers, especially on glass. They can\'t right themselves if flipped, so check on them periodically.',
  'Blue Leg Hermit': 'Small, active hermit crabs that are a staple of the reef cleanup crew. They eat algae and detritus but may bicker over shells.',
  'Red Leg Hermit': 'Similar to blue leg hermits but slightly larger. Hardy, active cleaners that help keep sand beds and rocks tidy.',
  'Emerald Crab': 'One of the few reliable eaters of bubble algae in reef tanks. Generally reef-safe but may occasionally bother corals.',
  'Fiddler Crab': 'Fascinating semi-terrestrial crabs with one oversized claw on males. Best in paludarium or brackish setups, not fully submerged.',
  'Vampire Crab': 'Striking purple and yellow terrestrial crabs best kept in paludarium setups. Not fully aquatic — they need land area.',
  'Porcelain Crab': 'Tiny, peaceful crabs that often live in anemones alongside clownfish. They filter-feed and are completely reef-safe.',
  'Crayfish': 'Bold, intelligent freshwater crustaceans with big personalities. Best kept alone — they\'ll catch and eat fish and shrimp.',
  'Sea Urchin': 'Effective algae grazers that mechanically scrub rock surfaces. Some species can displace rockwork; research your specific species.',
  'Starfish': 'Fascinating, slow-moving reef inhabitants. Species vary widely in care and reef-compatibility — always research your specific species.',
  'Feather Duster': 'Elegant tube worms with feathery crowns that filter-feed from the water. Peaceful and reef-safe; retract instantly when startled.',
  // Corals & Polyps
  'Zoanthids': 'Hardy, colorful polyp colonies available in an incredible range of colors. Great beginner corals — but some contain palytoxin, so handle carefully.',
  'Mushroom Coral': 'Soft, forgiving corals that tolerate lower light and flow. Great for beginners; they can spread aggressively in good conditions.',
  'Hammer Coral': 'A popular LPS coral with a distinct hammer-shaped head and flowing movement. Has aggressive sweeper tentacles — give it space.',
  'Torch Coral': 'Long-tentacled LPS coral with beautiful flowing movement. Stunning but aggressive with sweeper tentacles; needs room from neighbors.',
  'Frogspawn': 'LPS coral with grape-like tips and flowing movement. Peaceful for an LPS; clownfish will sometimes host in them.',
  'Brain Coral': 'Hardy LPS coral with a distinctive ridged, brain-like pattern. Generally straightforward to keep with moderate light and flow.',
  'Bubble Coral': 'Distinctive LPS coral with bubble-like vesicles during the day. Moderately aggressive; give it space and moderate flow.',
  'Elegance Coral': 'Stunning LPS coral with long sweeping tentacles. Can be temperamental — needs pristine water and the right tank placement.',
  'Acropora': 'The crown jewel of SPS reef-keeping. Fast-growing and vibrant but demanding in water quality, flow, and lighting — for experienced reefers.',
  'Montipora': 'Popular SPS coral that\'s more forgiving than Acropora. Comes in plating and encrusting forms with vivid, diverse colors.',
  'Chalice Coral': 'Striking LPS coral with vivid colors and intricate patterns. Has aggressive sweeper tentacles — give it plenty of space.',
  'Duncan Coral': 'Easy-to-keep LPS coral with long, flowing tentacles. Extends fully to feed and grows quickly in good conditions.',
  'Candycane Coral': 'Hardy LPS coral with candy-cane color stripes. Peaceful and great for beginners; extends at night to feed.',
  'Xenia': 'Fast-growing soft coral that pulses rhythmically in the water flow — hypnotic to watch. Can spread aggressively; divides opinions.',
  'Star Polyps': 'Fast-growing, beginner-friendly soft coral. Can cover rockwork quickly — great coverage coral but hard to remove once established.',
  'Leather Coral': 'Hardy, beginner-friendly soft corals. They may periodically close and shed a waxy coating — this is completely normal behavior.',
  'Trumpet Coral': 'Hardy LPS coral with tubular polyps that extend to feed. Easy to care for and a good choice for LPS beginners.',
  'Anemone': 'Natural hosts for clownfish with mesmerizing flowing tentacles. Require strong lighting, pristine water, and a mature, stable reef.',
  'Bubble Tip Anemone': 'The most popular clownfish host anemone and the hardiest of the bunch. Still requires excellent reef conditions and strong lighting.',
  'Carpet Anemone': 'Large, impressive anemones that can host many clownfish. Powerful stingers — they can consume small fish. For experienced reefers only.',
  'Long Tentacle Anemone': 'A popular clownfish host with long, graceful tentacles. Needs strong lighting and stable water; likes to bury its foot in sand.',
};

String _speciesDescription(String name, String type) {
  if (_kSpeciesDescriptions.containsKey(name)) return _kSpeciesDescriptions[name]!;
  switch (type) {
    case 'coral':   return 'A reef coral that adds color and structure to your tank. Maintain stable water parameters and appropriate lighting for best results.';
    case 'polyp':   return 'A colonial polyp organism that grows in clusters. Generally hardy and a great addition to reef tanks with stable chemistry.';
    case 'anemone': return 'A sea anemone that adds movement and natural beauty to reef tanks. Requires strong lighting and pristine, stable water conditions.';
    case 'invertebrate': return 'An invertebrate that contributes to the tank\'s ecosystem. Research specific care requirements for water chemistry and compatibility.';
    default:        return 'A fascinating fish that will bring life and personality to your tank. Ensure water parameters match their natural habitat for best health.';
  }
}

// Page 5 — Inhabitant Summary
class _ObInhabitantSummaryPage extends StatelessWidget {
  final List<({String name, String type, int count})> inhabitants;
  final WaterType waterType;
  final VoidCallback onNext;
  final List<String> plants;
  const _ObInhabitantSummaryPage({
    required this.inhabitants,
    this.plants = const [],
    this.waterType = WaterType.freshwater,
    required this.onNext,
  });

  static String _emoji(String type) {
    switch (type) {
      case 'invertebrate': return '🦐';
      case 'coral':        return '🪸';
      case 'polyp':        return '🪼';
      case 'anemone':      return '🌺';
      default:             return '🐟';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ObLogoBar(),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Text(
            'Meet Your Crew!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
          ),
        ),
        Expanded(
          child: inhabitants.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('🐟', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 16),
                        Text('No inhabitants added yet.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        SizedBox(height: 6),
                        Text('You can add them from the home screen later.', style: TextStyle(fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    ...inhabitants.map((inh) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: _cMint, borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: Text(_emoji(inh.type), style: const TextStyle(fontSize: 22)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inh.count > 1 ? '${inh.count}× ${_titleCase(inh.name)}' : _titleCase(inh.name),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _speciesDescription(inh.name, inh.type),
                                  style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                    // Compatibility warnings
                    ..._compatibilityWarnings(inhabitants, waterType).map((w) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: w.icon == '🚨' ? const Color(0xFFFFEBEE) : const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: w.icon == '🚨' ? Colors.red.shade200 : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.icon, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(w.message,
                              style: TextStyle(
                                fontSize: 13,
                                color: w.icon == '🚨' ? Colors.red.shade800 : Colors.orange.shade900,
                                height: 1.4,
                              ))),
                        ],
                      ),
                    )),
                    // Plants section
                    if (plants.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8),
                        child: Text('PLANTS',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                      ),
                      ...plants.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: _cMint, borderRadius: BorderRadius.circular(8)),
                              alignment: Alignment.center,
                              child: const Text('🌿', style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 10),
                            Text(_titleCase(p), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
        ),
        _obNextButton(label: 'Continue', onPressed: onNext),
        const SizedBox(height: 8),
      ],
    );
  }
}

// Page 6 — Water Quality Chat
class _ObWaterQualityPage extends StatefulWidget {
  final String tankName;
  final double gallons;
  final WaterType waterType;
  final List<({String name, String type, int count})> inhabitants;
  final List<String> plants;
  final Map<String, dynamic> equipment;
  final VoidCallback onNext;
  final void Function(Map<String, dynamic> task)? onReminderTask;
  final void Function(String csvContent, {Map<int, String?>? mapping, int? dateCol})? onCsvPending;
  final void Function(List<({String name, String type, int count})> added)? onInhabitantsAdded;
  final void Function(List<String> names)? onInhabitantsRemoved;
  final void Function(List<String> added)? onPlantsAdded;
  final String? tankId;
  final String experience;
  final bool isActive;
  final bool finishing;

  const _ObWaterQualityPage({
    required this.tankName,
    required this.gallons,
    required this.waterType,
    required this.inhabitants,
    this.plants = const [],
    this.equipment = const {},
    required this.onNext,
    this.onReminderTask,
    this.onCsvPending,
    this.onInhabitantsAdded,
    this.onInhabitantsRemoved,
    this.onPlantsAdded,
    this.tankId,
    this.experience = 'beginner',
    this.isActive = false,
    this.finishing = false,
  });

  @override
  State<_ObWaterQualityPage> createState() => _ObWaterQualityPageState();
}

class _ObWaterQualityPageState extends State<_ObWaterQualityPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _csvPromptShown = false;

  late final List<({String role, String content})> _messages = [
    (
      role: 'assistant',
      content: widget.experience == 'beginner'
          ? "Hey! I'm Ariel — your AI aquarium assistant 🐠\n\n"
            "🛠️ Need help setting up? Tell me what you have and I'll walk you through everything.\n\n"
            "🧠 I learn your tank — your fish, your water, your gear. The more you share, the smarter I get.\n\n"
            "📊 Tell me your test results and I'll track trends, spot problems early, and tell you what to do.\n\n"
            "🔮 Thinking about a change? I can predict how it'll affect your water chemistry.\n\n"
            "⏰ I'll remind you when it's time to test, do water changes, or dose.\n\n"
            "Give it a try!"
          : "Hey! I'm Ariel — your AI aquarium assistant 🐠\n\n"
            "🛠️ Planning a new build? I can help with equipment, cycling, stocking, and compatibility.\n\n"
            "🧠 I learn your tank — inhabitants, water history, equipment, tap water. Every detail sharpens my recommendations.\n\n"
            "📊 Drop your test results and I'll log them, track trends, and flag anything drifting.\n\n"
            "🔮 Considering a change? I can model the impact on your water chemistry.\n\n"
            "⏰ Set up automated reminders for testing, water changes, dosing — I'll keep your routine tight.\n\n"
            "Give it a try!",
    ),
  ];

  @override
  void didUpdateWidget(covariant _ObWaterQualityPage old) {
    super.didUpdateWidget(old);
    // Import CSV prompt disabled — the Import Data button is available in the chat instead
  }

  void _showCsvPrompt() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cMint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.upload_file, size: 28, color: _cDark),
              ),
              const SizedBox(height: 16),
              const Text('Import Historical Data',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _cDark)),
              const SizedBox(height: 10),
              const Text(
                'Have a spreadsheet with your water parameter history? '
                'You can import it to start with all your data.\n\n'
                'All you need are columns for dates and the parameters you\'ve been tracking.',
                style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Import CSV', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Later', style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    ).then((accepted) {
      if (accepted == true && mounted) {
        // We don't have a tank yet during onboarding, so we'll note this
        // and show a reminder after onboarding completes. For now, launch
        // a simplified file picker that stores the file path for later.
        _launchCsvPickerDuringOnboarding();
      }
    });
  }

  Future<void> _launchCsvPickerDuringOnboarding() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
        readSequential: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.single;
      debugPrint('[CSV] picked: name=${picked.name} path=${picked.path} bytes=${picked.bytes?.length}');
      final String content;
      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        content = utf8.decode(picked.bytes!, allowMalformed: true);
      } else if (picked.path != null) {
        final file = File(picked.path!);
        if (await file.exists()) {
          content = await file.readAsString();
        } else {
          throw Exception('File not found at ${picked.path}');
        }
      } else {
        throw Exception('No file data available');
      }
      final allRows = const CsvToListConverter(eol: '\n').convert(content);
      if (allRows.length < 2) {
        if (mounted) {
          _showTopSnack(context, 'CSV must have a header row and at least one data row.');
        }
        return;
      }

      // Find the real header row (skip junk rows at the top)
      final headerIdx = _CsvImportScreenState._findHeaderRow(allRows);
      final rows = allRows.sublist(headerIdx);
      if (rows.length < 2) {
        if (mounted) {
          _showTopSnack(context, 'Could not find a recognizable header row.');
        }
        return;
      }
      debugPrint('[CSV/Onboard] detected header at row $headerIdx');

      // Parse headers and auto-detect mapping
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final mapping = <int, String?>{};
      int? dateCol;
      for (int i = 0; i < headers.length; i++) {
        final h = headers[i].toLowerCase().replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
        if (h == 'date' || h == 'timestamp' || h == 'time' ||
            h.contains('date') || h == 'day' || h == 'logged') {
          dateCol ??= i;
        } else {
          mapping[i] = _CsvImportScreenState._matchHeader(h);
        }
      }

      if (!mounted) return;

      // Show column mapping screen
      final confirmed = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => _CsvMappingScreen(
            headers: headers,
            rows: rows.sublist(1),
            initialMapping: mapping,
            dateColIndex: dateCol,
          ),
        ),
      );

      if (confirmed == null || !mounted) return;

      // Pass the CSV content and confirmed mapping to onboarding state via callback
      final confirmedMapping = confirmed['mapping'] as Map<int, String?>;
      final confirmedDateCol = confirmed['dateCol'] as int?;
      _pendingCsvContent = content;
      widget.onCsvPending?.call(content, mapping: confirmedMapping, dateCol: confirmedDateCol);
      final dataRows = rows.length - 1;
      if (mounted) {
        _showTopSnack(context, '$dataRows rows ready to import after setup.', backgroundColor: _cDark);
      }
    } catch (e) {
      if (mounted) {
        _showTopSnack(context, 'Failed to read file: $e');
      }
    }
  }

  String? _pendingCsvContent;

  String get _baseUrl => _kBaseUrl;

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() {
      _messages.add((role: 'user', content: text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final history = _messages.take(_messages.length - 1)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final tank = {
        'name': widget.tankName.isNotEmpty ? widget.tankName : 'my tank',
        'gallons': widget.gallons,
        'water_type': widget.waterType.label,
        'inhabitants': widget.inhabitants
            .map((i) => '${i.count > 1 ? "${i.count}x " : ""}${i.name}')
            .toList(),
        if (widget.plants.isNotEmpty) 'plants': widget.plants,
        if (widget.equipment.isNotEmpty) 'equipment': widget.equipment,
      };

      // Fire log-parse in parallel with chat (extracts measurements, actions, notes)
      final now = DateTime.now();
      final clientDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final recentContext = _messages
          .take(6)
          .map((m) => '${m.role}: ${m.content}')
          .join('\n');
      Future<void> parseAndSaveLog() async {
        if (widget.tankId == null) return;
        try {
          final parseResp = await http
              .post(Uri.parse('$_baseUrl/parse/tank-log'),
                  headers: _apiHeaders(),
                  body: jsonEncode({
                    'text': text,
                    if (recentContext.isNotEmpty) 'context': recentContext,
                    'client_date': clientDate,
                  }))
              .timeout(const Duration(seconds: 20));
          if (parseResp.statusCode == 200) {
            final parsed = jsonDecode(parseResp.body);
            final logEntries = (parsed is Map && parsed['logs'] is List)
                ? (parsed['logs'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[];
            // Detect tap water mentions
            final isTapWater = RegExp(
              r'\btap\s+water\b|\bfrom\s+the\s+tap\b|\bsource\s+water\b|\bfaucet\b|\bmunicipal\s+water\b',
              caseSensitive: false,
            ).hasMatch(text);
            if (isTapWater) {
              for (final entry in logEntries) {
                entry['source'] = 'tap_water';
              }
            }
            for (final entry in logEntries) {
              final hasMeasurements = (entry['measurements'] as Map?)?.isNotEmpty == true;
              final hasActions = (entry['actions'] as List?)?.isNotEmpty == true;
              final hasNotes = (entry['notes'] as List?)?.isNotEmpty == true;
              if (!hasMeasurements && !hasActions && !hasNotes) continue;
              entry.remove('tasks');
              final dateStr = entry['date'] as String?;
              final logDate = (dateStr != null ? DateTime.tryParse(dateStr) : null) ?? now;
              final journalDate = '${logDate.year}-${logDate.month.toString().padLeft(2, '0')}-${logDate.day.toString().padLeft(2, '0')}';
              // Save audit log
              await TankStore.instance.addLog(
                tankId: widget.tankId!,
                rawText: logEntries.length == 1 ? text : '',
                parsedJson: jsonEncode(entry),
                date: logDate,
              );
              // Save measurements
              if (hasMeasurements) {
                final existing = await TankStore.instance.journalForDate(widget.tankId!, journalDate);
                final measEntry = existing.where((e) => e.category == 'measurements').toList();
                Map<String, dynamic> measurements = {};
                if (measEntry.isNotEmpty) {
                  try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
                }
                measurements.addAll((entry['measurements'] as Map).cast<String, dynamic>());
                await TankStore.instance.upsertJournal(
                  tankId: widget.tankId!, date: journalDate, category: 'measurements', data: jsonEncode(measurements),
                );
              }
              // Save actions
              if (hasActions) {
                final existing = await TankStore.instance.journalForDate(widget.tankId!, journalDate);
                final actEntry = existing.where((e) => e.category == 'actions').toList();
                List<String> actions = [];
                if (actEntry.isNotEmpty) {
                  try { actions = (jsonDecode(actEntry.first.data) as List).cast<String>(); } catch (_) {}
                }
                for (final a in (entry['actions'] as List).cast<String>()) {
                  if (!actions.contains(a)) actions.add(a);
                }
                await TankStore.instance.upsertJournal(
                  tankId: widget.tankId!, date: journalDate, category: 'actions', data: jsonEncode(actions),
                );
              }
              // Save notes
              if (hasNotes) {
                final existing = await TankStore.instance.journalForDate(widget.tankId!, journalDate);
                final noteEntry = existing.where((e) => e.category == 'notes').toList();
                List<String> notes = [];
                if (noteEntry.isNotEmpty) {
                  try { notes = (jsonDecode(noteEntry.first.data) as List).cast<String>(); } catch (_) {}
                }
                for (final n in (entry['notes'] as List).cast<String>()) {
                  if (!notes.contains(n)) notes.add(n);
                }
                await TankStore.instance.upsertJournal(
                  tankId: widget.tankId!, date: journalDate, category: 'notes', data: jsonEncode(notes),
                );
              }
            }
            // Update tap water profile if tap water was mentioned
            if (isTapWater) {
              const logToTapKey = {
                'pH': 'ph', 'GH': 'gh', 'KH': 'kh', 'ammonia': 'ammonia',
                'nitrite': 'nitrite', 'nitrate': 'nitrate', 'TDS': 'tds', 'tds': 'tds',
                'calcium': 'calcium', 'Calcium': 'calcium', 'Ca': 'calcium',
                'potassium': 'potassium', 'Potassium': 'potassium', 'K': 'potassium',
                'magnesium': 'magnesium', 'Magnesium': 'magnesium', 'Mg': 'magnesium',
              };
              final tapData = <String, dynamic>{};
              for (final entry in logEntries) {
                final measurements = entry['measurements'];
                if (measurements is Map) {
                  for (final kv in measurements.entries) {
                    final tapKey = logToTapKey[kv.key];
                    if (tapKey != null && kv.value != null) tapData[tapKey] = kv.value;
                  }
                }
              }
              if (tapData.isNotEmpty) {
                final jsonStr = jsonEncode(tapData);
                await TankStore.instance.saveTapWater(widget.tankId!, jsonStr);
                debugPrint('[Onboard/TapWater] parse-extracted: $tapData');
              }
            }
          }
        } catch (e) {
          debugPrint('[Onboard/ParseLog] error: $e');
        }
      }

      // Only fire log-parse for messages that likely contain loggable data
      // (measurements, water changes, dosing, observations) — not conversational chat.
      final _hasLoggableContent = RegExp(
        r'\d'                                        // contains a number (measurements)
        r'|(?:water\s+change|dosed|added .+ salt|added .+ buffer|trimmed|cleaned|fed|replaced|refilled)'  // actions
        r'|(?:cloudy|murky|algae|died|sick|bloat|ich|fungus|fin rot|stress|lethargic)',                    // observations
        caseSensitive: false,
      ).hasMatch(text);
      final logFuture = _hasLoggableContent ? parseAndSaveLog() : Future<void>.value();
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/chat/tank'),
            headers: _apiHeaders(),
            body: jsonEncode({
              'tank': tank,
              'available_tanks': <String>[],
              'message': text,
              'history': history,
              'recent_logs': <Map>[],
              'system_context': (() {
                final parts = <String>[];
                if (widget.tankName.isNotEmpty) parts.add('Tank name: "${widget.tankName}"');
                if (widget.gallons > 0) parts.add('Size: ${widget.gallons} gallons');
                parts.add('Water type: ${widget.waterType.label}');
                if (widget.inhabitants.isNotEmpty) {
                  final inhStr = widget.inhabitants.map((i) => '${i.count > 1 ? "${i.count}x " : ""}${i.name} (${i.type})').join(', ');
                  parts.add('Inhabitants: $inhStr');
                }
                if (widget.plants.isNotEmpty) parts.add('Plants: ${widget.plants.join(", ")}');
                if (widget.equipment.isNotEmpty) {
                  final eqStr = widget.equipment.entries.map((e) => '${e.key}: ${e.value}').join(', ');
                  parts.add('Equipment: $eqStr');
                }
                final tankSummary = parts.isNotEmpty
                    ? 'TANK DETAILS ALREADY PROVIDED — you KNOW these facts, do NOT ask about them again: ${parts.join(". ")}. '
                    : '';
                return tankSummary;
              })() + (widget.experience == 'beginner'
                  ? 'ONBOARDING CONTEXT — Meet Ariel page (BEGINNER). '
                    'INHABITANT RULE: When the user mentions an inhabitant (fish, coral, invert, plant) during onboarding, ADD IT IMMEDIATELY. Do NOT ask "should I add it?" or "I don\'t see it in your profile." Just confirm: "Added [name]!" Only ask clarifying questions if genuinely needed (e.g. "how many?" or species disambiguation). '
                    'IMPORTANT: Do NOT assume the tank is already set up, filled, or cycled just because the user selected inhabitants or a tank name. Many beginners are planning ahead before they even have a tank. '
                    'When the user asks a broad question like "where should we start?" or "what should I do?", ask clarifying questions first. For example: '
                    '"Are you still planning your tank, or do you already have one set up?" '
                    'Tailor your guidance based on their actual stage:\n'
                    '- PLANNING stage (no tank yet): Help with choosing equipment, tank size, substrate, etc. Walk them through what they need before filling.\n'
                    '- SETUP stage (have tank, not filled/cycled): Guide them through filling, dechlorinating, cycling. Ask if they have a filter, heater, etc.\n'
                    '- FILLED stage (tank has water): Ask if they have tested the water yet.\n'
                    '- MIGRATING from another app or spreadsheet: Let them know they can import a CSV using the Import Data button below, or just paste their historical data right into any of the chat windows and you\'ll log it.\n'
                    '- CYCLED/ESTABLISHED stage: Help with monitoring — suggest logging parameters.\n'
                    'When the user shares test results: interpret each value clearly, flag anything concerning, and encourage them to keep logging results regularly so you can track trends.\n'
                    'If they need a test kit: recommend the API Master Test Kit as a great all-in-one option covering ammonia, nitrite, nitrate, and pH.\n'
                    'At appropriate moments, offer to set up a recurring reminder to test water parameters.\n'
                    'LANGUAGE RULE: Never say "here", "in this chat", or "below" when referring to where the user can enter information. Always say "in any of the chat windows" or "just let me know in any of the chat windows".\n'
                    'Keep every reply short and friendly. One question per response — no exceptions.'
                  : 'ONBOARDING CONTEXT — Meet Ariel page (EXPERIENCED keeper). '
                    'INHABITANT RULE: When the user mentions an inhabitant (fish, coral, invert, plant) during onboarding, ADD IT IMMEDIATELY. Do NOT ask "should I add it?" or "I don\'t see it in your profile." Just confirm: "Added [name]!" Only ask clarifying questions if genuinely needed (e.g. "how many?" or species disambiguation). '
                    'The user has aquarium experience but do NOT assume they already have a tank set up. They may be planning a new build. '
                    'Do NOT explain basics like cycling, what ammonia is, or why testing matters — they know.\n'
                    'IMPORTANT: When the user asks a broad question like "where should we start?" or "what should I do?", ask clarifying questions first. For example: '
                    '"Are you setting up a new tank or migrating an existing one?" '
                    'Tailor your guidance based on their actual stage:\n'
                    '- PLANNING/NEW BUILD: Help with equipment choices, stocking plan, cycling strategy. Keep it peer-level — skip the basics.\n'
                    '- MIGRATING from another app or spreadsheet: Let them know they can import a CSV using the Import Data button below, or just paste their historical data right into any of the chat windows and you\'ll log it.\n'
                    '- ESTABLISHED TANK: Jump to water parameters — ask if they have recent test results to log.\n'
                    'When the user shares test results: log them, briefly note anything out of range, and mention any trends worth watching. Keep it concise.\n'
                    'If they don\'t have numbers right now: let them know they can drop results in any of the chat windows anytime.\n'
                    'At appropriate moments, offer to set up a recurring reminder to log parameters. Suggest weekly or biweekly.\n'
                    'LANGUAGE RULE: Never say "here", "in this chat", or "below". Always say "in any of the chat windows".\n'
                    'Keep replies concise and peer-level. One question per response — no exceptions.'),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final reply = (data is Map
                ? data['response'] ?? data['message'] ?? data.toString()
                : resp.body)
            as String;
        setState(() => _messages.add((role: 'assistant', content: reply)));
        _scrollToBottom();
        // Save any reminder tasks the AI scheduled
        if (data is Map && widget.onReminderTask != null) {
          final tasks = (data['tasks'] as List?) ?? [];
          for (final t in tasks) {
            if (t is Map<String, dynamic>) widget.onReminderTask!(t);
          }
        }
        // Process new inhabitants from chat response
        if (data is Map && data['new_inhabitant'] != null && widget.onInhabitantsAdded != null) {
          final inhData = data['new_inhabitant'] as Map<String, dynamic>;
          debugPrint('[Onboard/Chat] new_inhabitant payload: $inhData');
          final inhList = (inhData['inhabitants'] as List?) ?? [];
          final existingNames = widget.inhabitants.map((i) => i.name.toLowerCase()).toSet();
          final added = <({String name, String type, int count})>[];
          final plantsToAdd = <String>[];
          for (final inh in inhList) {
            if (inh is Map && inh['name'] != null) {
              final name = inh['name'].toString();
              final type = inh['type']?.toString() ?? 'fish';
              if (type == 'plant') {
                if (!widget.plants.map((p) => p.toLowerCase()).contains(name.toLowerCase())) {
                  plantsToAdd.add(name);
                }
              } else if (!existingNames.contains(name.toLowerCase())) {
                existingNames.add(name.toLowerCase());
                added.add((name: name, type: type, count: (inh['count'] as num?)?.toInt() ?? 1));
              }
            }
          }
          if (added.isNotEmpty) widget.onInhabitantsAdded!(added);
          if (plantsToAdd.isNotEmpty && widget.onPlantsAdded != null) widget.onPlantsAdded!(plantsToAdd);
        }
        // Process inhabitant removals
        if (data is Map && data['remove_inhabitants'] != null && widget.onInhabitantsRemoved != null) {
          final remData = data['remove_inhabitants'] as Map<String, dynamic>;
          final remList = (remData['inhabitants'] as List?) ?? [];
          final names = <String>[];
          for (final inh in remList) {
            if (inh is Map && inh['name'] != null) {
              names.add(inh['name'].toString().toLowerCase());
            }
          }
          if (names.isNotEmpty) widget.onInhabitantsRemoved!(names);
        }
        // Process new plants
        debugPrint('[Onboard/Chat] data keys: ${data is Map ? (data as Map).keys.toList() : "not a map"}');
        if (data is Map && data['new_plants'] != null && widget.onPlantsAdded != null) {
          final plantData = data['new_plants'] as Map<String, dynamic>;
          final plantList = (plantData['plants'] as List?) ?? [];
          final existingPlants = widget.plants.map((p) => p.toLowerCase()).toSet();
          final added = <String>[];
          for (final p in plantList) {
            final name = (p is Map ? p['name']?.toString() : p?.toString()) ?? '';
            if (name.isNotEmpty && !existingPlants.contains(name.toLowerCase())) {
              existingPlants.add(name.toLowerCase());
              added.add(name);
            }
          }
          if (added.isNotEmpty) widget.onPlantsAdded!(added);
        }
        // Apply tap water profile updates
        if (data is Map && data['tap_water_update'] != null && widget.tankId != null) {
          try {
            final tapUpdate = data['tap_water_update'] as Map<String, dynamic>;
            if (tapUpdate.isNotEmpty) {
              final jsonStr = jsonEncode(tapUpdate);
              await TankStore.instance.saveTapWater(widget.tankId!, jsonStr);
              debugPrint('[Onboard/TapWater] updated: $tapUpdate');
            }
          } catch (e) {
            debugPrint('[Onboard/TapWater] ERROR: $e');
          }
        }
      }
      // Ensure log parsing completes
      await logFuture;
    } catch (_) {
      if (mounted) {
        setState(() => _messages.add((
          role: 'assistant',
          content: "Sorry, I couldn't reach the server right now. "
              "You can always chat with me from the home screen once you're set up!",
        )));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        const _ObLogoBar(),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Meet Ariel',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Your AI assistant for everything aquarium related.',
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
            ),
          ),
        ),
        // Chat area
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              // +1 for the Import Data button after the first message
              itemCount: _messages.length + 1 + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                // First item is always Ariel's intro
                if (i == 0) {
                  final msg = _messages[0];
                  return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        msg.content,
                        style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                      ),
                  );
                }
                // Import Data button right after intro
                if (i == 1) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _showCsvPrompt,
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('Import Data', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cDark,
                          side: BorderSide(color: _cMid, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ),
                  );
                }
                // Sending indicator
                final msgIdx = i - 1; // offset by 1 for the import button
                if (_sending && msgIdx == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final msg = _messages[msgIdx];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? _cDark : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: isUser ? null : Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: isUser ? Colors.white : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Input row
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ask Ariel about water quality…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: _cMid, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: _cDark, width: 2),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              height: 38,
              child: IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: _cDark,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _cDark,
                disabledBackgroundColor: _cDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: widget.finishing ? null : widget.onNext,
              child: widget.finishing
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Start Exploring', style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// Page 7 — Congratulations + AI Tips
class _ObCongratsPage extends StatelessWidget {
  final String experience;
  final bool finishing;
  final VoidCallback onDone;
  final String title;
  final String buttonLabel;
  const _ObCongratsPage({
    required this.experience,
    required this.finishing,
    required this.onDone,
    this.title = "It's ready!",
    this.buttonLabel = 'Start Exploring',
  });

  String get _experienceTip {
    switch (experience) {
      case 'beginner':
        return 'As a beginner, ask the AI to explain any parameter or care concept — it always responds in plain language.';
      case 'intermediate':
        return 'The AI remembers your tank\'s inhabitants and history, so advice is always specific to your setup.';
      case 'expert':
        return 'Log detailed notes and the AI will track trends across all your tanks, flagging anomalies early.';
      default:
        return 'The AI learns from your tank\'s history to give increasingly personalized advice.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ObLogoBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _cDark),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("I'm Ariel and happy to help!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const _ObTipRow(
                  icon: Icons.auto_awesome, color: Color(0xFFC8A97E),
                  title: 'Tap the sparkle button',
                  body: 'Ariel is your AI guide here to help.',
                ),
                const _ObTipRow(
                  icon: Icons.water_drop, color: Colors.blue,
                  title: 'Ask for water advice',
                  body: 'Concerned about water quality? Ask for Ariel\'s help.',
                ),
                const _ObTipRow(
                  icon: Icons.visibility_outlined, color: _cMid,
                  title: 'Tell Ariel what you see',
                  body: 'Is the water cloudy? Do any tankmates look different? Is algae growing? Ariel will guide you.',
                ),
                const _ObTipRow(
                  icon: Icons.science_outlined, color: Color(0xFF6A5ACD),
                  title: 'Share test results',
                  body: 'Share your numbers and Ariel will track trends and flag anything off.',
                ),
                const _ObTipRow(
                  icon: Icons.notifications_active_outlined, color: Colors.green,
                  title: 'Automated Maintenance Reminders',
                  body: 'Ariel will let you know when things need fixing, like a water change.',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Image.asset('assets/images/fish-smile-v2.png', height: 60),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _cDark,
                disabledBackgroundColor: _cDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: finishing ? null : onDone,
              child: finishing
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(buttonLabel, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ObTipRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _ObTipRow({required this.icon, required this.color, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  await TankStore.instance.load();
  // If already logged in from a previous session, pull cloud data
  if (SupabaseService.isLoggedIn) {
    SupabaseService.logSession();
    TankStore.instance.pullFromCloud().then((_) => TankStore.instance.load());
  }
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('[Notifications] init failed: $e');
  }
  runApp(const AquariaApp());
}

class SplashVideoScreen extends StatefulWidget {
  const SplashVideoScreen({super.key});
  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/images/pre-video.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.play();
        _controller.addListener(_onVideoUpdate);
      }).catchError((_) {
        // If video fails to load, skip straight to WelcomeScreen
        _goNext();
      });
  }

  void _onVideoUpdate() {
    if (!_controller.value.isPlaying &&
        _controller.value.isInitialized &&
        _controller.value.position >= _controller.value.duration) {
      _controller.removeListener(_onVideoUpdate);
      _goNext();
    }
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    final done = await _isOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => done ? const TankListScreen() : const OnboardingScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _initialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}


class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    _resolveStartScreen().then((screen) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
    });
  }

  Future<void> _enterApp() async {
    await TankStore.instance.clearLocal();
    await SupabaseService.cloneSampleTank();
    await TankStore.instance.pullFromCloud();
    await TankStore.instance.load();
    final screen = await _resolveMainScreen();
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  Future<void> _onAuthSuccess() async {
    SupabaseService.logSession();
    // Check if user has accepted current legal terms
    final accepted = await SupabaseService.hasAcceptedCurrentTerms();
    if (!accepted) {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LegalAcceptanceScreen(onAccepted: () async {
            await _enterApp();
          }),
        ),
        (_) => false,
      );
      return;
    }
    await _enterApp();
  }

  Future<Widget> _resolveStartScreen() async {
    // Require authentication before entering the app
    if (!SupabaseService.isLoggedIn) {
      return AuthScreen(onAuthSuccess: _onAuthSuccess);
    }
    // Already logged in — block closed accounts
    if (await SupabaseService.isAccountClosed()) {
      await SupabaseService.signOut();
      return AuthScreen(onAuthSuccess: _onAuthSuccess);
    }
    // Already logged in — check legal acceptance
    final accepted = await SupabaseService.hasAcceptedCurrentTerms();
    if (!accepted) {
      return LegalAcceptanceScreen(onAccepted: () async {
        await _enterApp();
      });
    }
    return _resolveMainScreen();
  }

  Future<Widget> _resolveMainScreen() async {
    final store = TankStore.instance;
    await store.load();
    // Show onboarding unless the user has a real (non-sample) tank
    final hasRealTank = store.tanks.any((t) => t.name != 'Sample Tank');
    if (hasRealTank) return const TankListScreen();
    return const OnboardingScreen();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.white, body: SizedBox.shrink());
}

class AquariaApp extends StatefulWidget {
  const AquariaApp({super.key});

  @override
  State<AquariaApp> createState() => _AquariaAppState();
}

class _AquariaAppState extends State<AquariaApp> {
  @override
  void initState() {
    super.initState();
    NotificationService.navigatorKey = _navigatorKey;
    NotificationService.requestPermissions();

    // When a notification is tapped, navigate to the relevant tank's detail page.
    NotificationService.onTap = (String tankId) {
      final tank = TankStore.instance.tanks.firstWhere(
        (t) => t.id == tankId,
        orElse: () => TankStore.instance.tanks.first,
      );
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => TankDetailScreen(tank: tank)),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aquaria',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _cDark),
        useMaterial3: true,
        textTheme: GoogleFonts.nunitoSansTextTheme(),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const _AppEntry(),
    );
  }
}

class TankListScreen extends StatefulWidget {
  final bool showWelcome;
  const TankListScreen({super.key, this.showWelcome = false});

  @override
  State<TankListScreen> createState() => _TankListScreenState();
}

class _TankListScreenState extends State<TankListScreen> {
  bool _loading = false;
  String? _error;
  String _experience = 'beginner';
  // tankId → list of active tasks
  Map<String, List<db.Task>> _tasksByTank = {};
  // tankId → set of type strings present
  Map<String, Set<String>> _typesByTank = {};
  // tankId → has plants
  Map<String, bool> _hasPlantsByTank = {};
  // tankId → has compatibility warnings
  Set<String> _tanksWithWarnings = {};
  DateTime? _lastLogDate;
  Set<String> _tanksWithoutInhabitants = {};
  Set<String> _tanksWithoutLogs = {};
  Set<String> _allInhabitantNames = {};
  String _tankSort = 'newest'; // 'newest' | 'oldest' | 'az' | 'za'
  int _tipCardIndex = 0; // current tip shown on the card
  int _communityReactionCount = 0;

  bool _expReady = false;
  bool _refreshReady = false;
  bool _dailyPopupPending = false;

  @override
  void initState() {
    super.initState();
    _loadExperienceLevel().then((v) async {
      if (!mounted) return;
      setState(() => _experience = v);
      final tipIdx = await _currentTipIndex(v);
      if (mounted) setState(() => _tipCardIndex = tipIdx);
      if (await _shouldShowDailyTip()) {
        final newIdx = await _nextTipIndex(v);
        await _markDailyTipShown();
        if (mounted) setState(() => _tipCardIndex = newIdx);
        _dailyPopupPending = true;
      }
      _expReady = true;
      _tryShowDailyPopup();
    });
    _refresh().then((_) {
      _refreshReady = true;
      _tryShowDailyPopup();
      // Welcome dialog disabled — user lands directly on home screen
      _checkUserNotifications();
    });
  }

  void _tryShowDailyPopup() {
    if (!_expReady || !_refreshReady || !_dailyPopupPending || !mounted) return;
    _dailyPopupPending = false;
    _showDailyTipOverlay();
  }

  Future<void> _checkUserNotifications() async {
    if (!SupabaseService.isLoggedIn || !mounted) return;
    try {
      final notifications = await SupabaseService.fetchUnreadNotifications();
      for (final n in notifications) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(n['title'] as String? ?? 'Notice', style: const TextStyle(fontSize: 16))),
              ],
            ),
            content: Text(n['message'] as String? ?? ''),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _cDark),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('I understand'),
              ),
            ],
          ),
        );
        await SupabaseService.markNotificationRead(n['id'] as int);
      }
    } catch (_) {}
  }

  /// Reads the last card mode and toggles it for next login.
  /// Returns true if this login should show the nudge.
  void _showDailyTipOverlay() {
    // Check if this login shows a nudge instead of a tip
    final nudge = _buildHomeNudge();
    if (nudge != null) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => _DailyTipDialog(
          tip: (category: 'Quick Reminder', tip: nudge.text),
          emoji: nudge.emoji,
        ),
      );
      return;
    }
    final allTips = _kDailyTips[_experience] ?? _kDailyTips['beginner']!;
    final waterTypes = TankStore.instance.tanks.map((t) => t.waterType).toSet();
    final tips = _filterTips(allTips, waterTypes, _allInhabitantNames);
    if (tips.isEmpty) return;
    final tip = tips[_tipCardIndex % tips.length];
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _DailyTipDialog(tip: tip),
    );
  }

  /// Build a nudge for the home page (same logic as _MergedTopCard).
  ({String emoji, String text})? _buildHomeNudge() {
    final tanks = TankStore.instance.tanks;
    if (tanks.isEmpty) {
      return (emoji: '🐠', text: 'Welcome! Add your first tank to get started.');
    }
    if (_tanksWithoutInhabitants.isNotEmpty) {
      final count = _tanksWithoutInhabitants.length;
      if (count == tanks.length && count > 1) {
        return (emoji: '🐟', text: 'None of your tanks have inhabitants yet — add some so Ariel can help care for them.');
      } else if (count > 1) {
        return (emoji: '🐟', text: '$count of your tanks have no inhabitants — add some so Ariel can give tailored advice.');
      } else {
        final name = tanks.firstWhere((t) => _tanksWithoutInhabitants.contains(t.id), orElse: () => tanks.first).name;
        return (emoji: '🐟', text: '$name has no inhabitants yet — add some so Ariel can help care for them.');
      }
    }
    if (_tanksWithoutLogs.isNotEmpty) {
      final noLogCount = _tanksWithoutLogs.length;
      if (noLogCount == tanks.length && noLogCount > 1) {
        return (emoji: '📋', text: 'None of your tanks have test results logged yet — test your water and tell Ariel.');
      } else if (noLogCount > 1) {
        return (emoji: '📋', text: '$noLogCount of your tanks have no test results logged — test your water and tell Ariel.');
      } else {
        final name = tanks.firstWhere((t) => _tanksWithoutLogs.contains(t.id), orElse: () => tanks.first).name;
        return (emoji: '📋', text: '$name has no logs yet — test your water and log the results to start tracking.');
      }
    }
    // Inactive for 3+ days
    if (_lastLogDate != null) {
      final daysSince = DateTime.now().difference(_lastLogDate!).inDays;
      if (daysSince >= 7) {
        return (emoji: '👋', text: 'It\'s been a week — how are your tanks doing? Log an update or ask Ariel.');
      }
      if (daysSince >= 3) {
        return (emoji: '💧', text: 'It\'s been $daysSince days since your last log. Time for a check-in?');
      }
    }
    return null;
  }

  static List<({String category, String tip})> _filterTips(
    List<({String category, String tip})> tips, Set<WaterType> waterTypes, Set<String> inhabitantNames,
  ) {
    if (waterTypes.isEmpty && inhabitantNames.isEmpty) return tips;
    final hasFW = waterTypes.contains(WaterType.freshwater) ||
        waterTypes.contains(WaterType.planted) ||
        waterTypes.contains(WaterType.pond);
    final hasSW = waterTypes.contains(WaterType.saltwater) ||
        waterTypes.contains(WaterType.reef);
    return tips.where((t) {
      if (hasFW && !hasSW && _TipCard._isSaltwaterTip(t)) return false;
      if (hasSW && !hasFW && _TipCard._isFreshwaterTip(t)) return false;
      if (_TipCard._isIrrelevantSpeciesTip(t, inhabitantNames)) return false;
      return true;
    }).toList();
  }

  void _showWelcomeDialog() {
    final tanks = TankStore.instance.tanks;
    final tank = tanks.isNotEmpty ? tanks.first : null;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('You\'re all set!', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your tank is ready. What would you like to do next?',
              style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 20),
            if (tank != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showRecurringTaskDialog(tank);
                  },
                  icon: const Icon(Icons.repeat, size: 18),
                  label: const Text('Set Recurring Task'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TankJournalScreen(tank: tank)),
                    );
                  },
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('View Daily Logs'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChartsScreen(tank: tank)),
                    );
                  },
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: const Text('View Charts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load local data first so the UI renders immediately
      await TankStore.instance.load();

      // Show local data right away, then load extras in parallel
      if (mounted) setState(() => _loading = false);

      await Future.wait([
        _loadAllTasks(),
        _loadAllInhabitantTypes(),
        if (SupabaseService.isLoggedIn) ...[
          // Cloud sync in background — don't block the UI
          TankStore.instance.pullFromCloud().then((_) async {
            await TankStore.instance.load();
            if (mounted) {
              await Future.wait([_loadAllTasks(), _loadAllInhabitantTypes()]);
            }
          }).catchError((_) {}),
          SupabaseService.countMyReactions().then((count) {
            if (mounted) setState(() => _communityReactionCount = count);
          }).catchError((_) {}),
        ],
      ]);
    } catch (e) {
      _error = e.toString();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAllTasks() async {
    final tanks = TankStore.instance.tanks;
    final futures = tanks.map((tank) async {
      final logs = await TankStore.instance.logsFor(tank.id);
      final tasks = await TankStore.instance.tasksForTank(tank.id);
      return (id: tank.id, logs: logs, tasks: tasks);
    });
    final results = await Future.wait(futures);
    final result = <String, List<db.Task>>{};
    final noLogs = <String>{};
    DateTime? latestLog;
    for (final r in results) {
      if (r.logs.isEmpty) {
        noLogs.add(r.id);
      } else {
        final newest = r.logs.first.createdAt;
        if (latestLog == null || newest.isAfter(latestLog)) latestLog = newest;
      }
      if (r.tasks.isNotEmpty) result[r.id] = r.tasks;
    }
    if (mounted) setState(() { _tasksByTank = result; _lastLogDate = latestLog; _tanksWithoutLogs = noLogs; });
  }

  static const _typeEmojiList = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  Future<void> _loadAllInhabitantTypes() async {
    final tanks = TankStore.instance.tanks;
    final results = await Future.wait(tanks.map((tank) async {
      final inhs = await TankStore.instance.inhabitantsFor(tank.id);
      final plts = await TankStore.instance.plantsFor(tank.id);
      return (tank: tank, inhs: inhs, plts: plts);
    }));
    final types = <String, Set<String>>{};
    final plants = <String, bool>{};
    final noInhab = <String>{};
    final hasWarnings = <String>{};
    final allNames = <String>{};
    for (final r in results) {
      types[r.tank.id] = r.inhs.map((i) => i.type ?? 'fish').toSet();
      plants[r.tank.id] = r.plts.isNotEmpty;
      for (final i in r.inhs) { allNames.add(i.name.toLowerCase()); }
      if (r.inhs.isEmpty) {
        noInhab.add(r.tank.id);
      } else {
        final mapped = r.inhs.map((i) => (name: i.name, type: i.type ?? 'fish', count: i.count)).toList();
        if (_compatibilityWarnings(mapped, r.tank.waterType, plants: r.plts.map((p) => p.name).toList()).isNotEmpty) {
          hasWarnings.add(r.tank.id);
        }
      }
    }
    if (mounted) setState(() { _typesByTank = types; _hasPlantsByTank = plants; _tanksWithoutInhabitants = noInhab; _tanksWithWarnings = hasWarnings; _allInhabitantNames = allNames; });
  }

  int _notificationCount(String tankId) {
    final tasks = _tasksByTank[tankId];
    if (tasks == null) return 0;
    return tasks.length;
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddTankFlowScreen()),
    );
    await _refresh();
  }

  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  Future<void> _openArchived() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArchivedTanksScreen()),
    );
    await _refresh();
  }

  Future<void> _openEditFromList(TankModel tank) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EditTankFlowScreen(tank: tank)),
  );
  await _refresh(); // or _load() if that’s your method name in this file
}
  
  Future<void> _openDetail(TankModel tank) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TankJournalScreen(tank: tank)),
    );
    await _refresh();
  }

  Future<void> _showAddNoteDialog(TankModel tank) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final noteResult = await showModalBottomSheet<({String text, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddNoteSheet(tankName: tank.name),
    );
    if (noteResult != null && noteResult.text.isNotEmpty && mounted) {
      final noteText = noteResult.text;
      final date = noteResult.date;
      // Merge with existing journal notes for the selected date
      final existing = await TankStore.instance.journalForDate(tank.id, date);
      final notesEntry = existing.where((e) => e.category == 'notes').toList();
      List<String> notes = [];
      if (notesEntry.isNotEmpty) {
        try { notes = List<String>.from(jsonDecode(notesEntry.first.data) as List); } catch (_) {}
      }
      if (!notes.contains(noteText)) notes.add(noteText);
      await TankStore.instance.upsertJournal(
        tankId: tank.id, date: date, category: 'notes', data: jsonEncode(notes),
      );
      // Also save to logs (audit trail)
      await TankStore.instance.addLog(
        tankId: tank.id,
        rawText: noteText,
        parsedJson: jsonEncode({'source': 'manual_note', 'notes': [noteText]}),
        date: DateTime.tryParse(date),
      );
      _processNoteForTasks(tank, noteText);
      await _refresh();
      _showTopSnack(context, 'Note saved');
    }
  }

  Future<void> _processNoteForTasks(TankModel tank, String noteText) async {
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/chat/tank'),
        headers: _apiHeaders(),
        body: jsonEncode({
          'tank': {
            'name': tank.name,
            'gallons': tank.gallons,
            'water_type': tank.waterType.label,
          },
          'message': noteText,
          'history': [],
          'extract_tasks_only': true,
        }),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final rawTasks = data is Map ? (data['tasks'] as List?)?.cast<Map<String, dynamic>>() : null;
        if (rawTasks != null && rawTasks.isNotEmpty) {
          for (final task in rawTasks) {
            await TankStore.instance.addTask(
              tankId: tank.id,
              description: (task['description'] ?? '').toString(),
              dueDate: (task['due_date'] ?? task['due'])?.toString(),
              priority: (task['priority'] ?? 'normal').toString(),
              source: 'note',
            );
          }
          await _refresh();
        }
      }
    } catch (_) {}
  }

  Future<void> _showRecurringTaskDialog(TankModel tank) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String task, int days, DateTime startDate})>(
      context: context,
      builder: (ctx) => _RecurringTaskPicker(tankName: tank.name, waterType: tank.waterType),
    );
    if (result != null && mounted) {
      final due = result.startDate;
      final dueStr = '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
      await TankStore.instance.addTask(
        tankId: tank.id,
        description: result.task,
        dueDate: dueStr,
        source: 'recurring',
        repeatDays: result.days,
      );
      await _refresh();
      _showTopSnack(context, 'Recurring task added');
    }
  }

  Future<void> _showAddTaskDialog(TankModel tank) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTaskSheet(tankName: tank.name),
    );
    if (result != null && result.desc.isNotEmpty && mounted) {
      if (result.markComplete) {
        await TankStore.instance.addTask(
          tankId: tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
        final tasks = await TankStore.instance.tasksForTank(tank.id);
        final match = tasks.where((t) => t.description == result.desc && !t.isComplete).toList();
        if (match.isNotEmpty) {
          await TankStore.instance.completeTaskById(match.last.id);
        }
      } else {
        await TankStore.instance.addTask(
          tankId: tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
      }
      // Only log to journal if marked complete at creation
      if (result.markComplete) {
        final date = result.dueDate ?? '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
        final existing = await TankStore.instance.journalForDate(tank.id, date);
        final actEntry = existing.where((e) => e.category == 'actions').toList();
        List<String> actions = [];
        if (actEntry.isNotEmpty) {
          try { actions = (jsonDecode(actEntry.first.data) as List).cast<String>(); } catch (_) {}
        }
        if (!actions.contains(result.desc)) actions.add(result.desc);
        await TankStore.instance.upsertJournal(
          tankId: tank.id, date: date, category: 'actions', data: jsonEncode(actions),
        );
      }
      await _refresh();
      _showTopSnack(context, result.markComplete ? 'Task completed & logged' : 'Task added');
    }
  }

  Future<void> _showEditTaskDialog(TankModel tank, db.Task task, {VoidCallback? onDone}) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTaskSheet(tankName: tank.name, existing: task),
    );
    if (result != null && result.desc.isNotEmpty && mounted) {
      if (result.completeAndStopRecurring) {
        await TankStore.instance.completeAndStopRecurring(task.id);
        await _refresh();
        onDone?.call();
        _showTopSnack(context, 'Task completed — recurrence stopped');
      } else if (result.dismissAndStopRecurring) {
        await TankStore.instance.dismissAndStopRecurring(task.id);
        await _refresh();
        onDone?.call();
        _showTopSnack(context, 'Task dismissed — recurrence stopped');
      } else if (result.dismiss) {
        await TankStore.instance.dismissTaskById(task.id);
        await _refresh();
        onDone?.call();
        _showTopSnack(context, 'Task dismissed');
      } else if (result.markComplete) {
        await TankStore.instance.completeTaskById(task.id);
        await _refresh();
        onDone?.call();
        _showTopSnack(context, 'Task completed');
      } else {
        await TankStore.instance.updateTask(
          task.id,
          description: result.desc,
          dueDate: Value(result.dueDate),
          repeatDays: Value(result.repeatDays),
        );
        await _refresh();
        onDone?.call();
        _showTopSnack(context, 'Task updated');
      }
    }
  }

  Future<void> _showAddMeasurementDialog(TankModel tank) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({Map<String, dynamic> measurements, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddMeasurementSheet(tankName: tank.name),
    );
    if (result != null && result.measurements.isNotEmpty && mounted) {
      final date = result.date;
      // Merge with existing journal measurements for the selected date
      final existing = await TankStore.instance.journalForDate(tank.id, date);
      final measEntry = existing.where((e) => e.category == 'measurements').toList();
      Map<String, dynamic> measurements = {};
      if (measEntry.isNotEmpty) {
        try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
      }
      measurements.addAll(result.measurements);
      await TankStore.instance.upsertJournal(
        tankId: tank.id, date: date, category: 'measurements', data: jsonEncode(measurements),
      );
      // Also save to logs (audit trail)
      final parsedJson = jsonEncode({
        'measurements': result.measurements,
        'actions': <String>[],
        'notes': <String>[],
        'tasks': <dynamic>[],
      });
      final parts = result.measurements.entries.map((e) => '${_paramShortLabel(e.key)}: ${e.value}').join(', ');
      await TankStore.instance.addLog(
        tankId: tank.id,
        rawText: parts,
        parsedJson: parsedJson,
        date: DateTime.tryParse(date),
      );
      await _refresh();
      _showTopSnack(context, 'Measurement saved');
    }
  }

  Future<void> _archiveTank(String id) async {
    try {
      await TankStore.instance.archive(id);
      if (!mounted) return;
      setState(() {});
      _showTopSnack(context, 'Archived tank');
    } catch (e) {
      if (!mounted) return;
      _showTopSnack(context, 'Archive failed: $e');
    }
  }

  Future<void> _deleteTank(TankModel tank) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete tank?'),
        content: Text('Permanently delete "${tank.name}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await TankStore.instance.delete(tank.id);
      if (!mounted) return;
      setState(() {});
      _showTopSnack(context, 'Tank deleted');
    } catch (e) {
      if (!mounted) return;
      _showTopSnack(context, 'Delete failed: $e');
    }
  }

  int get _totalNotifCount {
    int count = 0;
    for (final tasks in _tasksByTank.values) {
      count += tasks.length;
    }
    return count;
  }

  void _showNotificationsSheet(List<TankModel> tanks) {
    final items = <({TankModel tank, db.Task task})>[];
    for (final tank in tanks) {
      final tasks = _tasksByTank[tank.id] ?? [];
      for (final t in tasks) {
        items.add((tank: tank, task: t));
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          // Rebuild items from current state
          final liveItems = <({TankModel tank, db.Task task})>[];
          for (final tank in tanks) {
            final tasks = _tasksByTank[tank.id] ?? [];
            for (final t in tasks) {
              liveItems.add((tank: tank, task: t));
            }
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications, size: 18, color: Color(0xFFE65100)),
                        const SizedBox(width: 8),
                        Text(
                          'Notifications (${liveItems.length})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (liveItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No notifications', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: liveItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 14),
                        itemBuilder: (_, i) {
                          final item = liveItems[i];
                          final desc = item.task.description;
                          final label = desc.isEmpty ? '' : desc[0].toUpperCase() + desc.substring(1);
                          final rawDue = item.task.dueDate;
                          final dueLabel = (rawDue != null && rawDue.isNotEmpty) ? _fmtNotifDue(rawDue) : null;
                          final isRecurring = item.task.repeatDays != null && item.task.repeatDays! > 0;
                          return ListTile(
                            dense: true,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await Future.delayed(const Duration(milliseconds: 300));
                              _showEditTaskDialog(item.tank, item.task);
                            },
                            leading: Icon(
                              isRecurring ? Icons.repeat : Icons.task_alt,
                              size: 18,
                              color: const Color(0xFFE65100),
                            ),
                            title: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                children: [
                                  TextSpan(
                                    text: '${item.tank.name}  ',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(text: label),
                                  if (dueLabel != null)
                                    TextSpan(
                                      text: ' — $dueLabel',
                                      style: const TextStyle(color: Color(0xFF8D6E63)),
                                    ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4CAF50)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: 'Mark complete',
                                  onPressed: () async {
                                    await TankStore.instance.completeTaskById(item.task.id);
                                    await _refresh();
                                    setS(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF8D6E63)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: 'Dismiss',
                                  onPressed: () {
                                    showDialog<bool>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('Did you complete this task?'),
                                        content: Text(item.task.description),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: const Text('No'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: const Text('Yes, completed'),
                                          ),
                                        ],
                                      ),
                                    ).then((completed) async {
                                      if (completed == null) return;
                                      if (completed) {
                                        await TankStore.instance.completeTaskById(item.task.id);
                                      } else {
                                        await TankStore.instance.dismissTaskById(item.task.id);
                                      }
                                      await _refresh();
                                      setS(() {});
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.repeat, size: 18),
                        label: const Text('Recurring Tasks'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cDark,
                          side: const BorderSide(color: _cLight),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _ManageRecurringTasksScreen(),
                          )).then((_) => _refresh());
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  static String _fmtNotifDue(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${ms[dt.month - 1]} ${dt.day}';
  }

  Widget _buildNotificationBell(List<TankModel> tanks) {
    final count = _totalNotifCount;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 10)),
        backgroundColor: const Color(0xFFE65100),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () => _showNotificationsSheet(tanks),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tanks = () {
      final list = [...TankStore.instance.tanks];
      switch (_tankSort) {
        case 'newest': list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case 'oldest': list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        case 'az': list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        case 'za': list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      }
      return list;
    }();

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: _buildAppBar(context, '', actions: [
          _buildNotificationBell(tanks),
          IconButton(
            tooltip: 'Add photo',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () => pickPhotoFlow(context),
          ),
        ]),
      body: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Error loading tanks:\n\n$_error'),
                      ),
                    )
                  : Column(
                      children: [
                        if (tanks.isEmpty)
                          Expanded(
                            child: Column(
                              children: [
                                _MergedTopCard(
                                  experience: _experience,
                                  tipIndex: _tipCardIndex,
                                  onIndexChanged: (i) => setState(() => _tipCardIndex = i),
                                  userWaterTypes: tanks.map((t) => t.waterType).toSet(),
                                  userInhabitantNames: _allInhabitantNames,
                                  tanks: tanks,
                                  tanksWithoutInhabitants: _tanksWithoutInhabitants,
                                  tanksWithoutLogs: _tanksWithoutLogs,
                                  lastLogDate: _lastLogDate,
                                ),
                                Expanded(
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'No tanks yet.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 18),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _cDark,
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: _openOnboarding,
                                          icon: const Icon(Icons.add, size: 20),
                                          label: const Text('Set Up Your First Tank', style: TextStyle(fontSize: 15)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                                // +3 for merged tips card, community card, and "My Tanks" header
                                itemCount: tanks.length + 3,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _MergedTopCard(
                                      experience: _experience,
                                      tipIndex: _tipCardIndex,
                                      onIndexChanged: (i) => setState(() => _tipCardIndex = i),
                                      userWaterTypes: tanks.map((t) => t.waterType).toSet(),
                                      userInhabitantNames: _allInhabitantNames,
                                      tanks: tanks,
                                      tanksWithoutInhabitants: _tanksWithoutInhabitants,
                                      tanksWithoutLogs: _tanksWithoutLogs,
                                      lastLogDate: _lastLogDate,
                                    );
                                  }
                                  if (index == 1) {
                                    if (!SupabaseService.isLoggedIn) return const SizedBox.shrink();
                                    return GestureDetector(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const _CommunityScreen(initialChannel: 'mine')),
                                      ).then((_) => _refresh()),
                                      child: Card(
                                        color: Colors.white,
                                        margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                                        elevation: 0.5,
                                        shadowColor: Colors.black12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: const BorderSide(color: Color(0xFFD8D8D8)),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.groups_outlined, color: Color(0xFF1FA2A8), size: 24),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _communityReactionCount > 0
                                                      ? '$_communityReactionCount reaction${_communityReactionCount == 1 ? '' : 's'} on your posts'
                                                      : 'Share photos with the community',
                                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1FA2A8),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text('New', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (index == 2) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'My Tanks',
                                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, color: Colors.black54),
                                            onSelected: (value) async {
                                              if (value == 'add_tank') {
                                                Navigator.of(context).push(MaterialPageRoute(
                                                  builder: (_) => const AddTankFlowScreen(),
                                                )).then((_) => _refresh());
                                              } else if (value == 'charts') {
                                                Navigator.of(context).push(MaterialPageRoute(
                                                  builder: (_) => AllChartsScreen(tanks: TankStore.instance.tanks),
                                                ));
                                              } else if (value == 'recurring_tasks') {
                                                Navigator.of(context).push(MaterialPageRoute(
                                                  builder: (_) => const _ManageRecurringTasksScreen(),
                                                )).then((_) => _refresh());
                                              } else if (value == 'archived') {
                                                Navigator.of(context).push(MaterialPageRoute(
                                                  builder: (_) => const ArchivedTanksScreen(),
                                                )).then((_) => _refresh());
                                              } else {
                                                setState(() => _tankSort = value);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'add_tank', child: Text('Add Tank')),
                                              const PopupMenuDivider(),
                                              const PopupMenuItem(value: 'newest', child: Text('Sort: Newest First')),
                                              const PopupMenuItem(value: 'oldest', child: Text('Sort: Oldest First')),
                                              const PopupMenuItem(value: 'az', child: Text('Sort: A → Z')),
                                              const PopupMenuItem(value: 'za', child: Text('Sort: Z → A')),
                                              const PopupMenuDivider(),
                                              const PopupMenuItem(value: 'charts', child: Text('View All Charts')),
                                              const PopupMenuItem(value: 'recurring_tasks', child: Text('Recurring Tasks')),
                                              const PopupMenuItem(value: 'archived', child: Text('Archived Tanks')),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  // Tank cards start at index 3
                                  final tankIndex = index - 3;
                                  final t = tanks[tankIndex];
                        final notifCount = _notificationCount(t.id);
                        return Card(
                            color: Colors.white,
                            margin: const EdgeInsets.only(top: 8),
                            elevation: 0.5,
                            shadowColor: Colors.black12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFFD8D8D8)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                            onTap: () => _openDetail(t),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name row: name + icons on the same line
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                                      ),
                                      if (notifCount > 0)
                                        GestureDetector(
                                          onTap: () => _showNotificationsSheet([t]),
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 10),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                const Icon(Icons.notifications, size: 22, color: Color(0xFFE65100)),
                                                Positioned(
                                                  top: -4,
                                                  right: -4,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(3),
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFE65100),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Text(
                                                      '$notifCount',
                                                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700, height: 1),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      PopupMenuButton<String>(
                                        tooltip: 'Add',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onSelected: (value) async {
                                          switch (value) {
                                            case 'add_task':
                                              await _showAddTaskDialog(t);
                                              break;
                                            case 'add_measurement':
                                              await _showAddMeasurementDialog(t);
                                              break;
                                            case 'add_note':
                                              await _showAddNoteDialog(t);
                                              break;
                                            case 'add_photo':
                                              await pickPhotoFlow(context, tankId: t.id);
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem<String>(value: 'add_task', child: Text('Add Task')),
                                          PopupMenuItem<String>(value: 'add_measurement', child: Text('Add Measurement')),
                                          PopupMenuItem<String>(value: 'add_note', child: Text('Add Note')),
                                          PopupMenuItem<String>(value: 'add_photo', child: Text('Add Photo')),
                                        ],
                                        child: const Icon(Icons.add, size: 22, color: _cDark),
                                      ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        tooltip: 'More',
                                        onSelected: (value) async {
                                          switch (value) {
                                            case 'edit':
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(builder: (_) => _TankAttributesScreen(tank: t)),
                                              );
                                              _refresh();
                                              break;
                                            case 'tap_water':
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(builder: (_) => TapWaterProfileScreen(tank: t)),
                                              );
                                              _refresh();
                                              break;
                                            case 'archive':
                                              await _archiveTank(t.id);
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem<String>(
                                            value: 'edit',
                                            child: Text('Tank Details'),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'tap_water',
                                            child: Text('Tap Water Profile'),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'archive',
                                            child: Text('Archive', style: TextStyle(color: Colors.orange)),
                                          ),
                                        ],
                                        child: const Icon(Icons.more_vert, size: 22),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  // Subtitle row: gallons, type, inhabitant emojis
                                  Row(
                                    children: [
                                      Text(
                                        '${t.gallons} gal • ${t.waterType.label}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w400),
                                      ),
                                      if ((_typesByTank[t.id]?.isNotEmpty ?? false) || (_hasPlantsByTank[t.id] ?? false)) ...[
                                        const SizedBox(width: 8),
                                        for (final type in _typeEmojiList)
                                          if (_typesByTank[t.id]?.contains(type) ?? false) ...[
                                            Text(_typeEmoji[type]!, style: const TextStyle(fontSize: 18)),
                                            const SizedBox(width: 4),
                                          ],
                                        if (_hasPlantsByTank[t.id] ?? false)
                                          const Text('🌿', style: TextStyle(fontSize: 18)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // Quick-nav buttons
                                  Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          _NavIconButton(
                                            child: const _FishPlantIcon(),
                                            tooltip: 'Inhabitants',
                                            color: const Color(0xFF2E86AB),
                                            onTap: () => Navigator.of(context).push(
                                              MaterialPageRoute(builder: (_) => InhabitantsScreen(tank: t)),
                                            ).then((_) => _loadAllInhabitantTypes()),
                                          ),
                                          if (_tanksWithWarnings.contains(t.id))
                                            const Positioned(
                                              top: -2,
                                              right: -2,
                                              child: Text('⚠️', style: TextStyle(fontSize: 12)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      _NavIconButton(
                                        icon: Icons.menu_book_outlined,
                                        tooltip: 'Daily Logs',
                                        color: const Color(0xFF5B8C5A),
                                        onTap: () async {
                                          final logs = await TankStore.instance.logsFor(t.id);
                                          if (!mounted) return;
                                          Navigator.of(context).push(MaterialPageRoute(
                                            builder: (_) => DailyLogsScreen(tank: t, logs: logs),
                                          ));
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _NavIconButton(
                                        icon: Icons.show_chart,
                                        tooltip: 'Charts',
                                        color: const Color(0xFFE07A2F),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => ChartsScreen(tank: t)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _NavIconButton(
                                        icon: Icons.photo_library_outlined,
                                        tooltip: 'Photos',
                                        color: const Color(0xFF8B5DAF),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => TankGalleryScreen(tank: t)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _NavIconButton(
                                        child: const _TuneSearchIcon(),
                                        tooltip: 'Attributes',
                                        color: const Color(0xFF607D8B),
                                        onTap: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => _TankAttributesScreen(tank: t)),
                                          );
                                          _refresh();
                                        },
                                      ),
                                    ],
                                  ),
                                  // Contextual nudges
                                  if (_tanksWithoutInhabitants.contains(t.id))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Add inhabitants so Ariel can give tailored advice',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                  if (_tanksWithoutLogs.contains(t.id))
                                    Padding(
                                      padding: EdgeInsets.only(top: _tanksWithoutInhabitants.contains(t.id) ? 2 : 6),
                                      child: Text(
                                        'Log your first water test to start tracking',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
      bottomNavigationBar: _AquariaFooter(
        onAiTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChatSheet(
            allTanks: TankStore.instance.tanks,
            onLogsChanged: _refresh,
          ),
        ).then((_) => _refresh()),
      ),
    );
  }
}

class _NotificationsCard extends StatefulWidget {
  final List<TankModel> tanks;
  final Map<String, List<db.Task>> tasksByTank;
  final VoidCallback onDismissed;
  final void Function(TankModel tank, db.Task task)? onTapTask;
  const _NotificationsCard({
    required this.tanks,
    required this.tasksByTank,
    required this.onDismissed,
    this.onTapTask,
  });

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  static const _kLimit = 2;
  bool _expanded = false;

  static String _fmtDue(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${ms[dt.month - 1]} ${dt.day}';
  }

  /// Whether a task's due date is in the future (after today).
  static bool _isFutureTask(db.Task task) {
    if (task.dueDate == null || task.dueDate!.isEmpty) return false;
    final due = DateTime.tryParse(task.dueDate!);
    if (due == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return due.isAfter(today);
  }

  void _onComplete(db.Task task) {
    TankStore.instance.completeTaskById(task.id);
    widget.onDismissed();
  }

  void _onDismiss(db.Task task) {
    // Ask whether the task was completed
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Did you complete this task?'),
        content: Text(task.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, completed'),
          ),
        ],
      ),
    ).then((completed) {
      if (completed == null) return; // dialog dismissed
      if (completed) {
        TankStore.instance.completeTaskById(task.id);
      } else {
        TankStore.instance.dismissTaskById(task.id);
      }
      widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = <({TankModel tank, db.Task task})>[];
    for (final tank in widget.tanks) {
      final tasks = widget.tasksByTank[tank.id] ?? [];
      for (final t in tasks) {
        items.add((tank: tank, task: t));
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length <= _kLimit) _expanded = false;

    final showAll = _expanded || items.length <= _kLimit;
    final visible = showAll ? items : items.take(_kLimit).toList();
    final hidden = items.length - _kLimit;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFFCC80), width: 1),
      ),
      color: const Color(0xFFFFF8F0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.notifications, size: 16, color: Color(0xFFE65100)),
                const SizedBox(width: 6),
                Text(
                  'Notifications  ${items.length}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE65100), letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFFFCC80)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _expanded ? 200 : double.infinity),
            child: ListView(
              shrinkWrap: true,
              physics: _expanded ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: visible.map((item) {
                final desc = item.task.description;
                final label = desc.isEmpty ? '' : desc[0].toUpperCase() + desc.substring(1);
                final rawDue = item.task.dueDate;
                final dueLabel = (rawDue != null && rawDue.isNotEmpty) ? _fmtDue(rawDue) : null;
                final isRecurring = item.task.repeatDays != null && item.task.repeatDays! > 0;
                final isFuture = _isFutureTask(item.task);
                return InkWell(
                  onTap: widget.onTapTask != null ? () => widget.onTapTask!(item.tank, item.task) : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isRecurring)
                          const Padding(
                            padding: EdgeInsets.only(right: 4, top: 1),
                            child: Icon(Icons.repeat, size: 13, color: Color(0xFF8D6E63)),
                          ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                              children: [
                                TextSpan(
                                  text: '${item.tank.name}  ',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(text: label),
                                if (dueLabel != null)
                                  TextSpan(
                                    text: ' — $dueLabel',
                                    style: TextStyle(
                                      color: isFuture ? const Color(0xFF6D8B74) : const Color(0xFF8D6E63),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      // Complete (checkmark) button — always available
                      IconButton(
                        onPressed: () => _onComplete(item.task),
                        icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4CAF50)),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                        tooltip: 'Mark complete',
                      ),
                      // Dismiss (X) button — asks if completed
                      IconButton(
                        onPressed: () => _onDismiss(item.task),
                        icon: const Icon(Icons.close, size: 16, color: Color(0xFF8D6E63)),
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                        tooltip: 'Dismiss',
                      ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (items.length > _kLimit)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  _expanded ? '…Less' : '…More ($hidden)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DailyTipDialog extends StatelessWidget {
  final ({String category, String tip}) tip;
  final String? emoji;
  const _DailyTipDialog({required this.tip, this.emoji});

  @override
  Widget build(BuildContext context) {
    final isNudge = emoji != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _cMint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(emoji ?? '💡', style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isNudge ? 'Heads Up' : "Let's Learn!",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _cDark)),
                      Text(tip.category,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF888888), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(tip.tip,
                style: const TextStyle(fontSize: 15, color: Color(0xFF2A2A2A), height: 1.55)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _cDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add Task Dialog
// ─────────────────────────────────────────────
class _AddTaskSheet extends StatefulWidget {
  final String tankName;
  final db.Task? existing; // non-null when editing
  const _AddTaskSheet({required this.tankName, this.existing});
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  late final TextEditingController _descCtrl;
  DateTime? _dueDate;
  int? _repeatDays;
  bool _markComplete = false;
  bool get _isEditing => widget.existing != null;

  static const _repeatOptions = <int?, String>{
    null: 'No repeat',
    1: 'Daily',
    7: 'Weekly',
    14: 'Every 2 weeks',
    30: 'Monthly',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _descCtrl = TextEditingController(text: e?.description ?? '');
    if (e?.dueDate != null && e!.dueDate!.isNotEmpty) {
      _dueDate = DateTime.tryParse(e.dueDate!);
    }
    _repeatDays = e?.repeatDays;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  bool get _isFutureDue {
    if (_dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _dueDate!.isAfter(today);
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    String? dueStr;
    if (_dueDate != null) {
      dueStr = '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}';
    }
    Navigator.pop(context, (
      desc: desc,
      dueDate: dueStr,
      repeatDays: _repeatDays,
      markComplete: _isFutureDue ? false : _markComplete,
      completeAndStopRecurring: false,
      dismiss: false,
      dismissAndStopRecurring: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dueFmt = _dueDate != null
        ? '${_dueDate!.month}/${_dueDate!.day}/${_dueDate!.year}'
        : null;
    final topPad = MediaQuery.of(context).viewPadding.top;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - topPad - 16),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).viewPadding.top + 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: Text(_isEditing ? 'Edit Task — ${widget.tankName}' : 'Add Task — ${widget.tankName}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(backgroundColor: _cMid),
                child: Text(_isEditing ? 'Save' : (_markComplete && !_isFutureDue ? 'Complete' : 'Add')),
              ),
            ]),
            const Divider(height: 24),
            TextField(
              controller: _descCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Change filter, Clean glass...',
                labelText: 'Task description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(dueFmt ?? 'Due date (optional)'),
                    onPressed: _pickDate,
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _dueDate = null),
                    tooltip: 'Clear date',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _repeatDays,
              decoration: const InputDecoration(
                labelText: 'Recurrence',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _repeatOptions.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value)),
              ).toList(),
              onChanged: (v) => setState(() => _repeatDays = v),
            ),
            const SizedBox(height: 12),
            if (!_isEditing)
              CheckboxListTile(
                value: _isFutureDue ? false : _markComplete,
                onChanged: _isFutureDue ? null : (v) => setState(() => _markComplete = v ?? false),
                title: const Text('Mark as completed now', style: TextStyle(fontSize: 14)),
                subtitle: _isFutureDue
                    ? const Text('Future tasks cannot be completed', style: TextStyle(fontSize: 12, color: Colors.grey))
                    : const Text('Logs as an action immediately', style: TextStyle(fontSize: 12, color: Colors.grey)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            if (_isEditing) ...[
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Complete Task'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                  onPressed: () {
                    Navigator.pop(context, (
                      desc: _descCtrl.text.trim().isEmpty ? widget.existing!.description : _descCtrl.text.trim(),
                      dueDate: null as String?,
                      repeatDays: widget.existing!.repeatDays,
                      markComplete: true,
                      completeAndStopRecurring: false,
                      dismiss: false,
                      dismissAndStopRecurring: false,
                    ));
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  label: const Text('Dismiss'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                  onPressed: () {
                    Navigator.pop(context, (
                      desc: _descCtrl.text.trim().isEmpty ? widget.existing!.description : _descCtrl.text.trim(),
                      dueDate: null as String?,
                      repeatDays: widget.existing!.repeatDays,
                      markComplete: false,
                      completeAndStopRecurring: false,
                      dismiss: true,
                      dismissAndStopRecurring: false,
                    ));
                  },
                ),
              ),
              if (widget.existing!.repeatDays != null && widget.existing!.repeatDays! > 0) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Complete & Stop Recurring'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE65100),
                      side: const BorderSide(color: Color(0xFFE65100)),
                    ),
                    onPressed: () {
                      Navigator.pop(context, (
                        desc: _descCtrl.text.trim().isEmpty ? widget.existing!.description : _descCtrl.text.trim(),
                        dueDate: null as String?,
                        repeatDays: null as int?,
                        markComplete: true,
                        completeAndStopRecurring: true,
                        dismiss: false,
                        dismissAndStopRecurring: false,
                      ));
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Dismiss & Stop Recurring'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red[300]!),
                    ),
                    onPressed: () {
                      Navigator.pop(context, (
                        desc: _descCtrl.text.trim().isEmpty ? widget.existing!.description : _descCtrl.text.trim(),
                        dueDate: null as String?,
                        repeatDays: null as int?,
                        markComplete: false,
                        completeAndStopRecurring: false,
                        dismiss: false,
                        dismissAndStopRecurring: true,
                      ));
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      ),
    );
  }
}

// ── Add Note Sheet ───────────────────────────────────────────────────────────

class _AddNoteSheet extends StatefulWidget {
  final String tankName;
  const _AddNoteSheet({required this.tankName});
  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _ctrl = TextEditingController();
  late DateTime _selectedDate = DateTime.now();

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).viewPadding.top;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - topPad - 16),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).viewPadding.top + 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text('Add Note — ${widget.tankName}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  final text = _ctrl.text.trim();
                  if (text.isNotEmpty) Navigator.pop(context, (text: text, date: _dateKey(_selectedDate)));
                },
                style: FilledButton.styleFrom(backgroundColor: _cMid),
                child: const Text('Save'),
              ),
            ]),
            const Divider(height: 24),
            GestureDetector(
              onTap: _pickDate,
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDate.month.toString().padLeft(2,'0')}/${_selectedDate.day.toString().padLeft(2,'0')}/${_selectedDate.year}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black54),
                if (_dateKey(_selectedDate) == _dateKey(DateTime.now()))
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('Today', style: TextStyle(fontSize: 12, color: Colors.black45)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 5,
              minLines: 3,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What did you observe?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringTaskPicker extends StatefulWidget {
  final String tankName;
  final WaterType waterType;
  const _RecurringTaskPicker({required this.tankName, required this.waterType});

  @override
  State<_RecurringTaskPicker> createState() => _RecurringTaskPickerState();
}

class _RecurringTaskPickerState extends State<_RecurringTaskPicker> {
  static const _presets = [
    'Change water',
    'Test water parameters',
    'Clean filter',
    'Replace filter media',
    'Clean glass',
    'Dose fertilizer',
    'Feed specialty food',
    'Check equipment',
    'Trim plants',
    'Gravel vacuum',
  ];

  static const _frequencies = [
    (label: 'Daily', days: 1),
    (label: 'Every 3 days', days: 3),
    (label: 'Weekly', days: 7),
    (label: 'Every 2 weeks', days: 14),
    (label: 'Monthly', days: 30),
    (label: 'Every 3 months', days: 90),
  ];

  static const _freshwaterFertilizers = [
    'All-in-one',
    'Macro (NPK)',
    'Micro (trace)',
    'Nitrogen',
    'Phosphorus',
    'Potassium',
    'Iron',
    'Carbon / Excel',
    'Root tabs',
    'Equilibrium',
  ];

  static const _saltwaterFertilizers = [
    'All-in-one',
    'Calcium',
    'Alkalinity (KH)',
    'Magnesium',
    'Trace elements',
    'Iodine',
    'Strontium',
    'Salt mix',
    'Amino acids',
    'Phytoplankton',
  ];

  String? _selectedTask;
  String? _selectedFertilizer;
  final _customController = TextEditingController();
  int _selectedFreqIndex = 2; // default: weekly
  bool _isCustom = false;
  DateTime _startDate = DateTime.now();

  bool get _isSaltwater =>
      widget.waterType == WaterType.saltwater || widget.waterType == WaterType.reef;

  List<String> get _fertilizerOptions =>
      _isSaltwater ? _saltwaterFertilizers : _freshwaterFertilizers;

  String get _taskName {
    if (_isCustom) return _customController.text.trim();
    if (_selectedTask == 'Dose fertilizer' && _selectedFertilizer != null) {
      return 'Dose $_selectedFertilizer';
    }
    return _selectedTask ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.repeat, color: _cDark, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Recurring Task — ${widget.tankName}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _isCustom ? '_custom_' : _selectedTask,
              decoration: const InputDecoration(
                labelText: 'Task',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                ..._presets.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                const DropdownMenuItem(value: '_custom_', child: Text('Custom...')),
              ],
              onChanged: (v) => setState(() {
                if (v == '_custom_') {
                  _isCustom = true;
                  _selectedTask = null;
                  _selectedFertilizer = null;
                } else {
                  _isCustom = false;
                  _selectedTask = v;
                  if (v != 'Dose fertilizer') _selectedFertilizer = null;
                }
              }),
            ),
            if (_selectedTask == 'Dose fertilizer' && !_isCustom) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedFertilizer,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _fertilizerOptions.map((f) =>
                  DropdownMenuItem(value: f, child: Text(f)),
                ).toList(),
                onChanged: (v) => setState(() => _selectedFertilizer = v),
              ),
            ],
            if (_isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Describe the task',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedFreqIndex,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: List.generate(_frequencies.length, (i) =>
                DropdownMenuItem(value: i, child: Text(_frequencies[i].label)),
              ),
              onChanged: (v) => setState(() => _selectedFreqIndex = v ?? 2),
            ),
            const SizedBox(height: 16),
            const Text('Starting on', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _startDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Color(0xFF666666)),
                    const SizedBox(width: 8),
                    Text(
                      '${_startDate.day}/${_startDate.month}/${_startDate.year}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (_startDate.difference(DateTime.now()).inDays == 0)
                      const Text('  (today)', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _cDark),
          onPressed: _taskName.isEmpty ? null : () {
            Navigator.pop(context, (
              task: _taskName,
              days: _frequencies[_selectedFreqIndex].days,
              startDate: _startDate,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _MergedTopCard extends StatelessWidget {
  final String experience;
  final int tipIndex;
  final ValueChanged<int> onIndexChanged;
  final Set<WaterType> userWaterTypes;
  final Set<String> userInhabitantNames;
  final List<TankModel> tanks;
  final Set<String> tanksWithoutInhabitants;
  final Set<String> tanksWithoutLogs;
  final DateTime? lastLogDate;

  const _MergedTopCard({
    required this.experience,
    required this.tipIndex,
    required this.onIndexChanged,
    this.userWaterTypes = const {},
    this.userInhabitantNames = const {},
    required this.tanks,
    this.tanksWithoutInhabitants = const {},
    this.tanksWithoutLogs = const {},
    this.lastLogDate,
  });

  /// Returns a contextual nudge if criteria are met.
  ({String emoji, String text, String? tankName})? _buildNudge() {
    if (tanks.isEmpty) {
      return (emoji: '🐠', text: 'Welcome! Add your first tank to get started.', tankName: null);
    }
    if (tanksWithoutInhabitants.isNotEmpty) {
      final count = tanksWithoutInhabitants.length;
      if (count == tanks.length && count > 1) {
        return (emoji: '🐟', text: 'None of your tanks have inhabitants yet — add some so Ariel can help care for them.', tankName: null);
      } else if (count > 1) {
        return (emoji: '🐟', text: '$count of your tanks have no inhabitants — add some so Ariel can give tailored advice.', tankName: null);
      } else {
        final name = tanks.firstWhere((t) => tanksWithoutInhabitants.contains(t.id), orElse: () => tanks.first).name;
        return (emoji: '🐟', text: ' has no inhabitants yet — add some so Ariel can help care for them.', tankName: name);
      }
    }
    if (tanksWithoutLogs.isNotEmpty) {
      final noLogCount = tanksWithoutLogs.length;
      if (noLogCount == tanks.length && noLogCount > 1) {
        return (emoji: '📋', text: 'None of your tanks have test results logged yet — test your water and tell Ariel.', tankName: null);
      } else if (noLogCount > 1) {
        return (emoji: '📋', text: '$noLogCount of your tanks have no test results logged — test your water and tell Ariel.', tankName: null);
      } else {
        final name = tanks.firstWhere((t) => tanksWithoutLogs.contains(t.id), orElse: () => tanks.first).name;
        return (emoji: '📋', text: ' has no logs yet — test your water and log the results to start tracking.', tankName: name);
      }
    }
    // Inactive for 3+ days
    if (lastLogDate != null) {
      final daysSince = DateTime.now().difference(lastLogDate!).inDays;
      if (daysSince >= 7) {
        return (emoji: '👋', text: 'It\'s been a week — how are your tanks doing? Log an update or ask Ariel.', tankName: null);
      }
      if (daysSince >= 3) {
        return (emoji: '💧', text: 'It\'s been $daysSince days since your last log. Time for a check-in?', tankName: null);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final nudge = _buildNudge();
    // Always show nudge if one exists; fall through to tip otherwise
    if (nudge != null) {
      return _TipCard(
        experience: experience,
        tipIndex: tipIndex,
        onIndexChanged: onIndexChanged,
        userWaterTypes: userWaterTypes,
        userInhabitantNames: userInhabitantNames,
        overrideContent: nudge,
      );
    }
    return _TipCard(
      experience: experience,
      tipIndex: tipIndex,
      onIndexChanged: onIndexChanged,
      userWaterTypes: userWaterTypes,
      userInhabitantNames: userInhabitantNames,
    );
  }
}

class _TipCard extends StatefulWidget {
  final String experience;
  final int tipIndex;
  final ValueChanged<int> onIndexChanged;
  final Set<WaterType> userWaterTypes;
  final Set<String> userInhabitantNames;
  final ({String emoji, String text, String? tankName})? overrideContent;

  const _TipCard({
    required this.experience,
    required this.tipIndex,
    required this.onIndexChanged,
    this.userWaterTypes = const {},
    this.userInhabitantNames = const {},
    this.overrideContent,
  });

  @override
  State<_TipCard> createState() => _TipCardState();

  static const _saltwaterKeywords = [
    'reef', 'coral', 'sps', 'lps', 'icp', 'salinity', 'salt mix',
    'skimmer', 'dosing', 'alkalinity', 'ato ', 'refugium', 'frag',
    'zoanthid', 'palytoxin', 'acropora', 'montipora', 'copepod',
    'anthias', 'mandarin', 'anemone', 'reefer', 'orp ',
  ];

  static const _freshwaterKeywords = [
    'betta', 'epsom salt', 'apistogramma', 'cichlid',
  ];

  /// Tips containing these keywords are only shown if the user has a matching
  /// inhabitant. Each keyword maps to a list of inhabitant name fragments that
  /// qualify the user for that tip.
  static const _speciesKeywords = <String, List<String>>{
    'betta': ['betta'],
    'apistogramma': ['apistogramma', 'dwarf cichlid'],
    'dwarf cichlid': ['apistogramma', 'dwarf cichlid', 'ram', 'kribensis'],
    'cichlid': ['cichlid', 'apistogramma', 'ram', 'kribensis', 'mbuna', 'peacock', 'oscar', 'angelfish', 'discus'],
    'discus': ['discus'],
    'neon tetra': ['neon tetra', 'cardinal tetra', 'tetra'],
    'mandarin': ['mandarin', 'dragonet'],
    'anthias': ['anthias'],
    'acropora': ['acropora', 'sps'],
    'montipora': ['montipora', 'sps'],
    'zoanthid': ['zoanthid', 'zoa', 'palythoa'],
    'corydoras': ['corydoras', 'cory', 'catfish'],
    'goldfish': ['goldfish'],
    'guppy': ['guppy', 'guppies'],
    'molly': ['molly', 'mollies'],
    'platy': ['platy', 'platies'],
    'swordtail': ['swordtail'],
    'loach': ['loach'],
    'shrimp': ['shrimp'],
    'snail': ['snail'],
  };

  static bool _isSaltwaterTip(({String category, String tip}) t) {
    final text = '${t.category} ${t.tip}'.toLowerCase();
    return _saltwaterKeywords.any((kw) => text.contains(kw));
  }

  static bool _isFreshwaterTip(({String category, String tip}) t) {
    final text = '${t.category} ${t.tip}'.toLowerCase();
    return _freshwaterKeywords.any((kw) => text.contains(kw));
  }

  /// Returns true if the tip mentions a specific species and the user does NOT
  /// have that species. Generic tips (no species mention) always pass.
  static bool _isIrrelevantSpeciesTip(({String category, String tip}) t, Set<String> userNames) {
    if (userNames.isEmpty) return false; // no inhabitants loaded yet — show all
    final text = '${t.category} ${t.tip}'.toLowerCase();
    for (final entry in _speciesKeywords.entries) {
      if (text.contains(entry.key)) {
        // Tip mentions this species — check if user has any matching inhabitant
        final hasMatch = entry.value.any((fragment) =>
            userNames.any((name) => name.contains(fragment)));
        if (!hasMatch) return true; // irrelevant — user doesn't have this species
      }
    }
    return false;
  }
}

class _TipCardState extends State<_TipCard> {
  bool _showingOverride = true;

  List<({String category, String tip})> _filteredTips() {
    final all = _kDailyTips[widget.experience] ?? _kDailyTips['beginner']!;
    final names = widget.userInhabitantNames;
    if (widget.userWaterTypes.isEmpty && names.isEmpty) return all;
    final hasFreshwater = widget.userWaterTypes.contains(WaterType.freshwater) ||
        widget.userWaterTypes.contains(WaterType.planted) ||
        widget.userWaterTypes.contains(WaterType.pond);
    final hasSaltwater = widget.userWaterTypes.contains(WaterType.saltwater) ||
        widget.userWaterTypes.contains(WaterType.reef);
    return all.where((t) {
      if (hasFreshwater && !hasSaltwater && _TipCard._isSaltwaterTip(t)) return false;
      if (hasSaltwater && !hasFreshwater && _TipCard._isFreshwaterTip(t)) return false;
      if (_TipCard._isIrrelevantSpeciesTip(t, names)) return false;
      return true;
    }).toList();
  }

  void _navigate(int delta) {
    final tips = _filteredTips();
    if (tips.isEmpty) return;
    setState(() => _showingOverride = false);
    widget.onIndexChanged((widget.tipIndex + delta) % tips.length);
  }

  @override
  Widget build(BuildContext context) {
    final tips = _filteredTips();
    if (tips.isEmpty && widget.overrideContent == null) return const SizedBox.shrink();

    final override = widget.overrideContent;
    final bool showNudge = _showingOverride && override != null;

    String emoji;
    String heading;
    String body;
    String? tankName;

    if (showNudge) {
      emoji = override.emoji;
      heading = 'Quick Reminder';
      body = override.text;
      tankName = override.tankName;
    } else {
      if (tips.isEmpty) return const SizedBox.shrink();
      final idx = widget.tipIndex % tips.length;
      final tip = tips[idx];
      emoji = '💡';
      heading = tip.category;
      body = tip.tip;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3ECFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7C4ED), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(heading,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _cDark)),
                ),
                GestureDetector(
                  onTap: () => _navigate(-1),
                  child: const Icon(Icons.chevron_left, size: 22, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _navigate(1),
                  child: const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tankName != null)
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: Color(0xFF444444), height: 1.45),
                  children: [
                    TextSpan(text: tankName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: body),
                  ],
                ),
              )
            else
              Text(body,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF444444), height: 1.45)),
          ],
        ),
      ),
    );
  }
}

class _AiSummaryEmptyHint extends StatelessWidget {
  final List<db.Inhabitant> inhabitants;
  final List<db.Log> logs;
  const _AiSummaryEmptyHint({required this.inhabitants, required this.logs});

  @override
  Widget build(BuildContext context) {
    final hasInhabitants = inhabitants.isNotEmpty;
    final hasLogs = logs.isNotEmpty;

    final steps = [
      if (!hasInhabitants)
        _HintStep(emoji: '🐠', text: 'Add your fish, corals, or plants so Ariel knows who she\'s looking after.'),
      _HintStep(emoji: '🧪', text: 'Run a test and share the results — ammonia, nitrite, nitrate, and pH are the big four. Ariel will interpret them for you.'),
      _HintStep(emoji: '👁️', text: 'Describe what you see: fish behavior, water color, cloudiness, algae, anything that looks off.'),
      _HintStep(emoji: '👃', text: 'Even smells matter. A sulfur or earthy odour can be an early sign of a problem worth catching.'),
      _HintStep(emoji: '✨', text: 'The more you share, the sharper Ariel\'s advice. A few entries go a long way.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Help Ariel get to know your tank:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF555555), height: 1.4),
        ),
        const SizedBox(height: 10),
        ...steps,
      ],
    );
  }
}

class _HintStep extends StatelessWidget {
  final String emoji;
  final String text;
  const _HintStep({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF444444), height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Fish + plant composite icon used for the Inhabitants button.
class _FishPlantIcon extends StatelessWidget {
  final double size;
  const _FishPlantIcon({this.size = 32});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
      child: Text('🐟', style: TextStyle(fontSize: size * 0.7)),
    );
  }
}

class _TuneSearchIcon extends StatelessWidget {
  const _TuneSearchIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.tune, size: 22, color: Color(0xFF607D8B)),
          Positioned(
            right: -2,
            bottom: -2,
            child: Icon(Icons.search, size: 14, color: Color(0xFF607D8B)),
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _NavIconButton({this.icon, this.child, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? _cDark;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: c.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child ?? Icon(icon, size: 24, color: c),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: _cMid.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _cDark),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 13, color: _cDark, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Add Tank Flow (reuses onboarding pages) ───────────────────────────────────
class AddTankFlowScreen extends StatefulWidget {
  const AddTankFlowScreen({super.key});
  @override
  State<AddTankFlowScreen> createState() => _AddTankFlowScreenState();
}

class _AddTankFlowScreenState extends State<AddTankFlowScreen> {
  final _pageCtrl = PageController();
  int _page = 0;
  static const _totalPages = 4;

  final _tankNameCtrl = TextEditingController(text: 'New Tank');
  double _gallons = 30;
  WaterType _waterType = WaterType.freshwater;
  List<({String name, String type, int count})> _inhabitants = [];
  List<String> _plants = [];
  Map<String, dynamic> _equipment = {};
  bool _finishing = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _tankNameCtrl.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_page < _totalPages - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      final name = _tankNameCtrl.text.trim().isEmpty ? 'New Tank' : _tankNameCtrl.text.trim();
      final tank = TankModel(name: name, gallons: _gallons.round(), waterType: _waterType);
      await TankStore.instance.saveParsedDetails(
        tank: tank,
        inhabitants: _inhabitants
            .map((i) => {'name': i.name, 'type': i.type, 'count': i.count})
            .toList(),
        plants: _plants,
      );
      if (_equipment.isNotEmpty) {
        await TankStore.instance.saveEquipment(tank.id, jsonEncode(_equipment));
      }
      await TankStore.instance.load();
      if (!mounted) return;
      // Navigate to the newly created tank's journal, replacing this screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TankJournalScreen(tank: tank)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      _showTopSnack(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: IconButton(
            icon: const Icon(Icons.close, color: _cDark),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                _ObTankSetupPage(
                    nameCtrl: _tankNameCtrl,
                    gallons: _gallons,
                    waterType: _waterType,
                    onGallonsChanged: (v) => setState(() => _gallons = v),
                    onWaterTypeChanged: (v) => setState(() => _waterType = v),
                    onNext: _goNext,
                    equipment: _equipment,
                    onEquipmentChanged: (eq) => setState(() => _equipment = eq),
                  ),
                  _ObInhabitantsPage(
                    initialInhabitants: _inhabitants,
                    initialPlants: _plants,
                    waterType: _waterType,
                    onNext: (inhs, plts) {
                      setState(() { _inhabitants = inhs; _plants = plts; });
                      _goNext();
                    },
                  ),
                  _ObInhabitantSummaryPage(
                    inhabitants: _inhabitants,
                    plants: _plants,
                    waterType: _waterType,
                    onNext: _goNext,
                  ),
                  _ObCongratsPage(
                    experience: 'beginner',
                    finishing: _finishing,
                    onDone: _finish,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? _cDark : _cLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),
          ],
        ),
    );
  }
}

class AddTankScreen extends StatefulWidget {
  const AddTankScreen({super.key});

  @override
  State<AddTankScreen> createState() => _AddTankScreenState();
}

class _AddTankScreenState extends State<AddTankScreen> {
  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();

  WaterType _waterType = WaterType.freshwater;
  String _sizeUnit = 'gallons';
  bool _saving = false;
  final List<({String name, String type, int count})> _inhabitants = [];
  final List<String> _plants = [];

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  Future<void> _pickInhabitant() async {
    final result = await showModalBottomSheet<({String name, String type, int count})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpeciesPickerSheet(isPlant: false, waterType: _waterType),
    );
    if (result != null) setState(() => _inhabitants.add(result));
  }

  Future<void> _pickPlant() async {
    final result = await showModalBottomSheet<({String name, String type, int count})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SpeciesPickerSheet(isPlant: true),
    );
    if (result != null) setState(() => _plants.add(result.name));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showTopSnack(context, 'Please enter a tank name.');
      return;
    }
    final sizeInput = int.tryParse(_sizeController.text.trim()) ?? 0;
    if (sizeInput <= 0) {
      _showTopSnack(context, 'Please enter a valid tank size.');
      return;
    }

    final gallons = _sizeUnit == 'liters' ? (sizeInput * 0.264172).round() : sizeInput;
    setState(() => _saving = true);

    await TankStore.instance.saveParsedDetails(
      tank: TankModel(name: name, gallons: gallons, waterType: _waterType),
      inhabitants: _inhabitants.map((i) => {'name': i.name, 'type': i.type, 'count': i.count}).toList(),
      plants: _plants,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, 'Add Tank'),
      bottomNavigationBar: _AquariaFooter(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Tank name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<WaterType>(
              value: _waterType,
              items: WaterType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _waterType = v ?? WaterType.freshwater),
              decoration: const InputDecoration(
                labelText: 'Water type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _sizeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Size',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _sizeUnit,
                    items: const [
                      DropdownMenuItem(value: 'gallons', child: Text('Gallons')),
                      DropdownMenuItem(value: 'liters', child: Text('Liters')),
                    ],
                    onChanged: (v) => setState(() => _sizeUnit = v ?? 'gallons'),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // ── Inhabitants ──────────────────────────────────────────────
            Row(
              children: [
                const Text('Inhabitants', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickInhabitant,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_inhabitants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('None added yet', style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            else
              ...List.generate(_inhabitants.length, (i) {
                final inh = _inhabitants[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(_inhEmoji(inh.type), style: const TextStyle(fontSize: 20)),
                  title: Text(inh.count > 1 ? '${inh.count}× ${_titleCase(inh.name)}' : _titleCase(inh.name)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () => setState(() => _inhabitants.removeAt(i)),
                  ),
                );
              }),
            const SizedBox(height: 16),
            // ── Plants ───────────────────────────────────────────────────
            Row(
              children: [
                const Text('Plants', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickPlant,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_plants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('None added yet', style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            else
              ...List.generate(_plants.length, (i) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Text('🌿', style: TextStyle(fontSize: 20)),
                title: Text(_titleCase(_plants[i])),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => setState(() => _plants.removeAt(i)),
                ),
              )),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save Tank'),
            ),
          ],
        ),
      ),
    );
  }
}

class TankJournalScreen extends StatefulWidget {
  final TankModel tank;
  const TankJournalScreen({super.key, required this.tank});

  @override
  State<TankJournalScreen> createState() => _TankJournalScreenState();
}

class _TankJournalScreenState extends State<TankJournalScreen> {
  static const _baseUrl = _kBaseUrl;

  late TankModel _tank;
  List<db.Log> _logs = [];
  List<db.JournalEntry> _journal = [];
  List<db.Inhabitant> _inhabitants = [];
  List<db.Plant> _plants = [];
  List<db.Task> _tasks = [];
  String? _summary;
  bool _summaryLoading = false;
  bool _summaryExpanded = false;
  List<String> _suggestions = [];
  bool _suggestionsLoading = false;
  String _alertLevel = 'none'; // 'none', 'yellow', 'red'
  Set<String> _reminderSuggestions = {};
  bool _actionsExpanded = false;
  String _experience = 'beginner';
  String? _equipmentJson;

  @override
  void initState() {
    super.initState();
    _tank = widget.tank;
    _load();
    _loadExperienceLevel().then((v) { if (mounted) setState(() => _experience = v); });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _showAddNoteDialog() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final noteResult = await showModalBottomSheet<({String text, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddNoteSheet(tankName: _tank.name),
    );
    if (noteResult != null && noteResult.text.isNotEmpty && mounted) {
      final noteText = noteResult.text;
      final date = noteResult.date;
      // Merge with existing journal notes for the selected date
      final existing = await TankStore.instance.journalForDate(_tank.id, date);
      final notesEntry = existing.where((e) => e.category == 'notes').toList();
      List<String> notes = [];
      if (notesEntry.isNotEmpty) {
        try { notes = List<String>.from(jsonDecode(notesEntry.first.data) as List); } catch (_) {}
      }
      if (!notes.contains(noteText)) notes.add(noteText);
      await TankStore.instance.upsertJournal(
        tankId: _tank.id, date: date, category: 'notes', data: jsonEncode(notes),
      );
      // Also save to logs (audit trail)
      await TankStore.instance.addLog(
        tankId: _tank.id,
        rawText: noteText,
        parsedJson: jsonEncode({'source': 'manual_note', 'notes': [noteText]}),
        date: DateTime.tryParse(date),
      );
      _processNoteForTasks(noteText);
      await _load();
      _showTopSnack(context, 'Note saved');
    }
  }

  Future<void> _processNoteForTasks(String noteText) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/chat/tank'),
        headers: _apiHeaders(),
        body: jsonEncode({
          'tank': {
            'name': _tank.name,
            'gallons': _tank.gallons,
            'water_type': _tank.waterType.label,
          },
          'message': noteText,
          'history': [],
          'extract_tasks_only': true,
        }),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final rawTasks = data is Map ? (data['tasks'] as List?)?.cast<Map<String, dynamic>>() : null;
        if (rawTasks != null && rawTasks.isNotEmpty) {
          for (final task in rawTasks) {
            await TankStore.instance.addTask(
              tankId: _tank.id,
              description: (task['description'] ?? '').toString(),
              dueDate: (task['due_date'] ?? task['due'])?.toString(),
              priority: (task['priority'] ?? 'normal').toString(),
              source: 'note',
            );
          }
          if (mounted) await _load();
        }
      }
    } catch (_) {}
  }

  Future<void> _showRecurringTaskDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String task, int days, DateTime startDate})>(
      context: context,
      builder: (ctx) => _RecurringTaskPicker(tankName: _tank.name, waterType: _tank.waterType),
    );
    if (result != null && mounted) {
      final due = result.startDate;
      final dueStr = '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
      await TankStore.instance.addTask(
        tankId: _tank.id,
        description: result.task,
        dueDate: dueStr,
        source: 'recurring',
        repeatDays: result.days,
      );
      await _load();
      _showTopSnack(context, 'Recurring task added');
    }
  }

  Future<void> _showAddTaskDialog() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTaskSheet(tankName: _tank.name),
    );
    if (result != null && result.desc.isNotEmpty && mounted) {
      if (result.markComplete) {
        await TankStore.instance.addTask(
          tankId: _tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
        final tasks = await TankStore.instance.tasksForTank(_tank.id);
        final match = tasks.where((t) => t.description == result.desc && !t.isComplete).toList();
        if (match.isNotEmpty) {
          await TankStore.instance.completeTaskById(match.last.id);
        }
      } else {
        await TankStore.instance.addTask(
          tankId: _tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
      }
      // Only log to journal if marked complete at creation
      if (result.markComplete) {
        final date = result.dueDate ?? '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
        final existing = await TankStore.instance.journalForDate(_tank.id, date);
        final actEntry = existing.where((e) => e.category == 'actions').toList();
        List<String> actions = [];
        if (actEntry.isNotEmpty) {
          try { actions = (jsonDecode(actEntry.first.data) as List).cast<String>(); } catch (_) {}
        }
        if (!actions.contains(result.desc)) actions.add(result.desc);
        await TankStore.instance.upsertJournal(
          tankId: _tank.id, date: date, category: 'actions', data: jsonEncode(actions),
        );
      }
      await _load();
      _showTopSnack(context, result.markComplete ? 'Task completed & logged' : 'Task added');
    }
  }

  Future<void> _showEditTaskSheet(TankModel tank, db.Task task, {VoidCallback? onDone}) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTaskSheet(tankName: tank.name, existing: task),
    );
    if (result != null && result.desc.isNotEmpty && mounted) {
      if (result.completeAndStopRecurring) {
        await TankStore.instance.completeAndStopRecurring(task.id);
      } else if (result.dismissAndStopRecurring) {
        await TankStore.instance.dismissAndStopRecurring(task.id);
      } else if (result.dismiss) {
        await TankStore.instance.dismissTaskById(task.id);
      } else if (result.markComplete) {
        await TankStore.instance.completeTaskById(task.id);
      } else {
        await TankStore.instance.updateTask(
          task.id,
          description: result.desc,
          dueDate: Value(result.dueDate),
          repeatDays: Value(result.repeatDays),
        );
      }
      final fresh = await TankStore.instance.tasksForTank(_tank.id);
      if (!mounted) return;
      setState(() => _tasks = fresh);
      onDone?.call();
      final msg = result.completeAndStopRecurring ? 'Task completed — recurrence stopped'
          : result.dismissAndStopRecurring ? 'Task dismissed — recurrence stopped'
          : result.dismiss ? 'Task dismissed'
          : result.markComplete ? 'Task completed'
          : 'Task updated';
      _showTopSnack(context, msg);
    }
  }

  Future<void> _showAddMeasurementDialog() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({Map<String, dynamic> measurements, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddMeasurementSheet(tankName: _tank.name),
    );
    if (result != null && result.measurements.isNotEmpty && mounted) {
      final date = result.date;
      // Merge with existing journal measurements for the selected date
      final existing = await TankStore.instance.journalForDate(_tank.id, date);
      final measEntry = existing.where((e) => e.category == 'measurements').toList();
      Map<String, dynamic> measurements = {};
      if (measEntry.isNotEmpty) {
        try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
      }
      measurements.addAll(result.measurements);
      await TankStore.instance.upsertJournal(
        tankId: _tank.id, date: date, category: 'measurements', data: jsonEncode(measurements),
      );
      // Also save to logs (audit trail)
      final parsedJson = jsonEncode({
        'measurements': result.measurements,
        'actions': <String>[],
        'notes': <String>[],
        'tasks': <dynamic>[],
      });
      final parts = result.measurements.entries.map((e) => '${_paramShortLabel(e.key)}: ${e.value}').join(', ');
      await TankStore.instance.addLog(
        tankId: _tank.id,
        rawText: parts,
        parsedJson: parsedJson,
        date: DateTime.tryParse(date),
      );
      await _load();
      if (mounted) _showTopSnack(context, 'Measurement saved');
    }
  }

  Future<void> _load() async {
    final logs = await TankStore.instance.logsFor(_tank.id);
    final journal = await TankStore.instance.journalFor(_tank.id);
    final inhabitants = await TankStore.instance.inhabitantsFor(_tank.id);
    final plants = await TankStore.instance.plantsFor(_tank.id);
    final tasks = await TankStore.instance.tasksForTank(_tank.id);
    final eqJson = await TankStore.instance.equipmentJsonFor(_tank.id);
    // Refresh tank model in case name/settings changed
    final updatedTank = TankStore.instance.tanks.cast<TankModel?>().firstWhere(
      (t) => t!.id == _tank.id,
      orElse: () => null,
    );
    if (!mounted) return;
    setState(() {
      if (updatedTank != null) _tank = updatedTank;
      _logs = logs;
      _journal = journal;
      _inhabitants = inhabitants;
      _plants = plants;
      _tasks = tasks;
      _equipmentJson = eqJson;
    });
    _persistCalculatedParams();
    _loadSummary();
    _loadSuggestions();
  }

  /// Persist calculated Mg and Ca:Mg ratio to journal so they appear in entries
  /// and are available to the AI summary. Recalculates when GH or Ca changes.
  Future<void> _persistCalculatedParams() async {
    final isFreshwater = _tank.waterType == WaterType.freshwater ||
        _tank.waterType == WaterType.planted ||
        _tank.waterType == WaterType.pond;
    if (!isFreshwater) return;

    // Group measurements by date
    final byDate = <String, Map<String, dynamic>>{};
    for (final j in _journal.where((j) => j.category == 'measurements')) {
      try {
        final m = (jsonDecode(j.data) as Map).cast<String, dynamic>();
        byDate[j.date] = m;
      } catch (_) {}
    }

    for (final entry in byDate.entries) {
      final date = entry.key;
      final m = entry.value;
      final ghRaw = m['gh'] ?? m['GH'];
      final caRaw = m['calcium'] ?? m['ca'] ?? m['Ca'];
      if (ghRaw == null || caRaw == null) continue;

      final ghVal = double.tryParse(ghRaw.toString().replaceAll(RegExp(r'[^\d.]'), ''));
      final caVal = double.tryParse(caRaw.toString().replaceAll(RegExp(r'[^\d.]'), ''));
      if (ghVal == null || caVal == null) continue;

      final ghPpm = ghVal * 17.85;
      final mgPpm = (ghPpm - caVal * 2.5) / 4.12;
      final mgStr = mgPpm <= 0 ? '0' : mgPpm.toStringAsFixed(1);
      final ratioStr = mgPpm > 0 ? '${(caVal / mgPpm).toStringAsFixed(1)}:1' : 'N/A';

      // Skip write if values haven't changed
      if (m['magnesium_calc'] == mgStr && m['ca_mg_ratio'] == ratioStr) continue;

      final updated = Map<String, dynamic>.from(m);
      updated['magnesium_calc'] = mgStr;
      updated['ca_mg_ratio'] = ratioStr;

      await TankStore.instance.upsertJournal(
        tankId: _tank.id,
        date: date,
        category: 'measurements',
        data: jsonEncode(updated),
      );
    }
  }

  Future<void> _loadSummary() async {
    if (_journal.isEmpty) return;
    if (_summaryLoading) return; // prevent concurrent calls

    // Use cached summary if journal hasn't changed and cache is fresh (6 days)
    final cached = await TankStore.instance.getCachedSummary(_tank.id, _journal);
    if (cached != null) {
      if (mounted) setState(() { _summary = cached.text; _summaryExpanded = false; });
      return;
    }

    setState(() => _summaryLoading = true);
    try {
      // Build summary data from journal entries
      // Measurements: last 2 weeks only. Actions/notes: all time.
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
      final twoWeeksKey = '${twoWeeksAgo.year}-${twoWeeksAgo.month.toString().padLeft(2,'0')}-${twoWeeksAgo.day.toString().padLeft(2,'0')}';
      final byDate = <String, List<db.JournalEntry>>{};
      for (final j in _journal) {
        // Skip old measurements, but keep all actions and notes
        if (j.category == 'measurements' && j.date.compareTo(twoWeeksKey) < 0) continue;
        byDate.putIfAbsent(j.date, () => []).add(j);
      }
      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final logsData = sortedDates.take(10).map((date) {
        final entries = byDate[date]!;
        final parts = <String>[];
        parts.add('Date: $date');
        for (final e in entries) {
          try {
            if (e.category == 'measurements') {
              final m = (jsonDecode(e.data) as Map).cast<String, dynamic>();
              parts.add('Measurements: ${m.entries.map((kv) => '${kv.key}=${kv.value}').join(', ')}');
            } else if (e.category == 'actions') {
              final a = (jsonDecode(e.data) as List).cast<String>();
              if (a.isNotEmpty) parts.add('Actions: ${a.join('; ')}');
            } else if (e.category == 'notes') {
              final n = (jsonDecode(e.data) as List).cast<String>();
              if (n.isNotEmpty) parts.add('Notes: ${n.join('; ')}');
            }
          } catch (_) {}
        }
        return <String, dynamic>{'text': parts.join(' | ')};
      }).toList();
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/summary/tank-logs'),
            headers: _apiHeaders(),
            body: jsonEncode({
              'logs': logsData,
              'water_type': _tank.waterType.label,
              'gallons': _tank.gallons,
              if (_equipmentJson != null) 'equipment': jsonDecode(_equipmentJson!),
              if (_inhabitants.isNotEmpty) 'inhabitants': _inhabitants.map((i) => i.name).toList(),
              if (_plants.isNotEmpty) 'plants': _plants.map((p) => p.name).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = data['summary'] as String?;
        final lower = raw?.trim().toLowerCase() ?? '';
        final isEmpty = lower.isEmpty ||
            lower.contains('no data') ||
            lower.contains('no entries') ||
            lower.contains('no logs') ||
            lower.contains('no journal') ||
            lower.contains('nothing logged') ||
            lower.contains('no information');
        final text = isEmpty ? null : raw;
        if (text != null) await TankStore.instance.cacheSummary(_tank.id, text, _journal);
        setState(() { _summary = text; _summaryExpanded = false; });
      }
    } catch (e) {
      debugPrint('[Summary] error loading summary: $e');
    }
    if (mounted) setState(() => _summaryLoading = false);
  }

  Future<void> _loadSuggestions() async {
    if (_suggestionsLoading) return; // prevent concurrent calls

    // Use cached suggestions if journal hasn't changed and cache is fresh
    final cachedSugg = await TankStore.instance.getCachedSuggestions(_tank.id, _journal);
    if (cachedSugg != null) {
      if (mounted) setState(() { _suggestions = cachedSugg.suggestions; _suggestionsLoading = false; });
      return;
    }

    setState(() => _suggestionsLoading = true);
    try {
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
      final twoWeeksKey = '${twoWeeksAgo.year}-${twoWeeksAgo.month.toString().padLeft(2,'0')}-${twoWeeksAgo.day.toString().padLeft(2,'0')}';

      // Check if there are any measurements in the last 2 weeks
      final hasRecentMeasurements = _journal.any((j) =>
          j.category == 'measurements' && j.date.compareTo(twoWeeksKey) >= 0);

      if (!hasRecentMeasurements) {
        if (mounted) setState(() {
          _suggestions = ['Add your latest test results so Ariel can evaluate your water quality.'];
          _suggestionsLoading = false;
        });
        return;
      }

      // Build the same data as summary
      final byDate = <String, List<db.JournalEntry>>{};
      for (final j in _journal) {
        if (j.category == 'measurements' && j.date.compareTo(twoWeeksKey) < 0) continue;
        byDate.putIfAbsent(j.date, () => []).add(j);
      }
      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final logsData = sortedDates.take(10).map((date) {
        final entries = byDate[date]!;
        final parts = <String>[];
        parts.add('Date: $date');
        for (final e in entries) {
          try {
            if (e.category == 'measurements') {
              final m = (jsonDecode(e.data) as Map).cast<String, dynamic>();
              parts.add('Measurements: ${m.entries.map((kv) => '${kv.key}=${kv.value}').join(', ')}');
            } else if (e.category == 'actions') {
              final a = (jsonDecode(e.data) as List).cast<String>();
              if (a.isNotEmpty) parts.add('Actions: ${a.join('; ')}');
            } else if (e.category == 'notes') {
              final n = (jsonDecode(e.data) as List).cast<String>();
              if (n.isNotEmpty) parts.add('Notes: ${n.join('; ')}');
            }
          } catch (_) {}
        }
        return <String, dynamic>{'text': parts.join(' | ')};
      }).toList();

      final resp = await http
          .post(
            Uri.parse('$_baseUrl/suggestions/tank'),
            headers: _apiHeaders(),
            body: jsonEncode({
              'logs': logsData,
              'water_type': _tank.waterType.label,
              'gallons': _tank.gallons,
              if (_equipmentJson != null) 'equipment': jsonDecode(_equipmentJson!),
              if (_inhabitants.isNotEmpty) 'inhabitants': _inhabitants.map((i) => i.name).toList(),
              if (_plants.isNotEmpty) 'plants': _plants.map((p) => p.name).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = data['suggestions'] as List<dynamic>?;
        if (raw != null) {
          final parsed = raw.map((s) => s.toString()).toList();
          await TankStore.instance.cacheSuggestions(_tank.id, parsed, _journal);
          setState(() {
            _suggestions = parsed;
            _alertLevel = (data['alert_level'] as String?) ?? 'none';
          });
        }
      }
    } catch (e) {
      debugPrint('[Suggestions] error: $e');
    }
    if (mounted) setState(() => _suggestionsLoading = false);
  }

  /// Most recent value + date for each known parameter from journal entries.
  /// Returns {canonical → (value, date, deduced)} in preferred display order.
  Map<String, ({String value, DateTime date, bool deduced})> _latestMeasurements() {
    const order = ['ammonia', 'nitrite', 'nitrate', 'ph', 'kh', 'gh',
                   'phosphate', 'potassium', 'calcium', 'magnesium', 'ca_mg_ratio', 'co2', 'temp', 'salinity',
                   'tds', 'iron', 'copper'];
    final raw = <String, ({String value, DateTime date, bool deduced})>{};
    final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
    final twoWeeksKey = '${twoWeeksAgo.year}-${twoWeeksAgo.month.toString().padLeft(2,'0')}-${twoWeeksAgo.day.toString().padLeft(2,'0')}';

    // Journal measurement entries, oldest-first so newer dates overwrite
    final measEntries = _journal.where((j) =>
        j.category == 'measurements' && j.date.compareTo(twoWeeksKey) >= 0).toList()
      ..sort((a, b) => a.date.compareTo(b.date)); // oldest first

    for (final entry in measEntries) {
      try {
        final m = (jsonDecode(entry.data) as Map).cast<String, dynamic>();
        final parts = entry.date.split('-');
        final entryDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        for (final e in m.entries) {
          final canonical = _paramAliases[e.key.toLowerCase()];
          if (canonical != null) raw[canonical] = (value: e.value.toString(), date: entryDate, deduced: false);
        }
      } catch (_) {}
    }
    // For planted/freshwater tanks: deduce Mg from GH and Ca, calculate Ca:Mg ratio
    final isFreshwater = _tank.waterType == WaterType.freshwater ||
        _tank.waterType == WaterType.planted ||
        _tank.waterType == WaterType.pond;
    if (isFreshwater && raw.containsKey('gh') && raw.containsKey('calcium') && !raw.containsKey('magnesium')
        && raw['gh']!.date == raw['calcium']!.date) {
      final ghVal = double.tryParse(raw['gh']!.value.replaceAll(RegExp(r'[^\d.]'), ''));
      final caVal = double.tryParse(raw['calcium']!.value.replaceAll(RegExp(r'[^\d.]'), ''));
      if (ghVal != null && caVal != null) {
        final ghPpm = ghVal * 17.85;
        final mgPpm = (ghPpm - caVal * 2.5) / 4.12;
        final date = raw['gh']!.date;
        if (mgPpm <= 0) {
          raw['magnesium'] = (value: '≈0', date: date, deduced: true);
        } else {
          raw['magnesium'] = (value: '≈${mgPpm.toStringAsFixed(1)}', date: date, deduced: true);
        }
      }
    }
    // Deduce Ca from GH and Mg if Ca is missing
    if (isFreshwater && raw.containsKey('gh') && raw.containsKey('magnesium') && !raw.containsKey('calcium')
        && raw['gh']!.date == raw['magnesium']!.date) {
      final ghVal = double.tryParse(raw['gh']!.value.replaceAll(RegExp(r'[^\d.]'), ''));
      final mgVal = double.tryParse(raw['magnesium']!.value.replaceAll(RegExp(r'[^\d.≈]'), ''));
      if (ghVal != null && mgVal != null) {
        final ghPpm = ghVal * 17.85;
        final caPpm = (ghPpm - mgVal * 4.12) / 2.5;
        final date = raw['gh']!.date;
        if (caPpm > 0) {
          raw['calcium'] = (value: '≈${caPpm.toStringAsFixed(1)}', date: date, deduced: true);
        }
      }
    }
    if (isFreshwater && raw.containsKey('calcium') && raw.containsKey('magnesium')) {
      final caVal = double.tryParse(raw['calcium']!.value.replaceAll(RegExp(r'[^\d.]'), ''));
      final mgVal = double.tryParse(raw['magnesium']!.value.replaceAll(RegExp(r'[^\d.]'), ''));
      if (caVal != null && mgVal != null && mgVal > 0) {
        final ratio = caVal / mgVal;
        raw['ca_mg_ratio'] = (value: '${ratio.toStringAsFixed(1)}:1', date: raw['calcium']!.date, deduced: true);
      } else if (mgVal == null || mgVal <= 0) {
        raw['ca_mg_ratio'] = (value: '⚠ no Mg', date: raw['calcium']!.date, deduced: true);
      }
    }
    // Return in preferred order, then any extras
    final result = <String, ({String value, DateTime date, bool deduced})>{};
    for (final k in order) {
      if (raw.containsKey(k)) result[k] = raw[k]!;
    }
    for (final e in raw.entries) {
      if (!result.containsKey(e.key)) result[e.key] = e.value;
    }
    return result;
  }

  static String _formatParamDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${months[d.month - 1]} ${d.day}';
  }

  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TankDetailScreen(tank: _tank)),
    );
  }

  static const _journalTypeOrder = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _journalTypeEmoji = {
    'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺', 'plant': '🌿',
  };
  static const _journalTypeLabel = {
    'fish': 'Fish', 'invertebrate': 'Invertebrates', 'coral': 'Coral', 'polyp': 'Polyps', 'anemone': 'Anemones',
  };

  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  List<Widget> _buildInhabitantIcons() {
    final types = _inhabitants.map((i) => i.type ?? 'fish').toSet();
    final widgets = <Widget>[];
    for (final type in ['fish', 'invertebrate', 'coral', 'polyp', 'anemone']) {
      if (types.contains(type)) {
        widgets.add(Text(_typeEmoji[type]!, style: const TextStyle(fontSize: 26)));
        widgets.add(const SizedBox(width: 10));
      }
    }
    if (_plants.isNotEmpty) {
      widgets.add(const Text('🌿', style: TextStyle(fontSize: 26)));
    }
    return widgets;
  }

  List<String> _measurementAlerts() {
    // Collect most recent value for each parameter across all logs
    final latest = <String, double>{};
    for (final log in _logs.reversed) {
      if (log.parsedJson == null) continue;
      try {
        final raw = jsonDecode(log.parsedJson!);
        if (raw is! Map) continue;
        if (raw['source'] == 'tap_water') continue;
        final m = (raw['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final e in m.entries) {
          final key = e.key.toLowerCase();
          final val = double.tryParse(e.value.toString().replaceAll(RegExp(r'[^\d.]'), ''));
          if (val != null) latest[key] = val;
        }
      } catch (_) {}
    }
    if (latest.isEmpty) return [];

    final isSalt = _tank.waterType == WaterType.saltwater || _tank.waterType == WaterType.reef;
    final alerts = <String>[];

    double? v;
    // Ammonia — both water types
    v = latest['ammonia'] ?? latest['nh3'];
    if (v != null && v > 0) alerts.add('Ammonia detected: ${_fmtVal(v)} ppm (should be 0)');

    // Nitrite — both
    v = latest['nitrite'] ?? latest['no2'];
    if (v != null && v > 0) alerts.add('Nitrite detected: ${_fmtVal(v)} ppm (should be 0)');

    if (isSalt) {
      // Nitrate
      v = latest['nitrate'] ?? latest['no3'];
      if (v != null && v > 20) alerts.add('Nitrate high: ${_fmtVal(v)} ppm (normal <20)');
      // pH
      v = latest['ph'];
      if (v != null && (v < 8.0 || v > 8.4)) alerts.add('pH out of range: ${_fmtVal(v)} (normal 8.1–8.3)');
      // Alkalinity / KH
      v = latest['kh'] ?? latest['alkalinity'] ?? latest['alk'];
      if (v != null && (v < 7 || v > 13)) alerts.add('Alkalinity out of range: ${_fmtVal(v)} dKH (normal 8–12)');
      // Calcium
      v = latest['ca'] ?? latest['calcium'];
      if (v != null && (v < 350 || v > 470)) alerts.add('Calcium out of range: ${_fmtVal(v)} ppm (normal 380–450)');
      // Magnesium
      v = latest['mg'] ?? latest['magnesium'];
      if (v != null && (v < 1200 || v > 1400)) alerts.add('Magnesium out of range: ${_fmtVal(v)} ppm (normal 1250–1350)');
      // Phosphate
      v = latest['phosphate'] ?? latest['po4'];
      if (v != null && v > 0.5) alerts.add('Phosphate high: ${_fmtVal(v)} ppm (normal 0.03–0.5 for saltwater)');
      // Potassium
      v = latest['k'] ?? latest['potassium'];
      if (v != null && (v < 350 || v > 450)) alerts.add('Potassium out of range: ${_fmtVal(v)} ppm (normal 380–420)');
    } else {
      // Nitrate
      v = latest['nitrate'] ?? latest['no3'];
      if (v != null && v > 40) alerts.add('Nitrate high: ${_fmtVal(v)} ppm (normal <20)');
      // pH
      v = latest['ph'];
      if (v != null && (v < 6.3 || v > 7.8)) alerts.add('pH out of range: ${_fmtVal(v)} (normal 6.5–7.5)');
      // Phosphate
      v = latest['phosphate'] ?? latest['po4'];
      if (v != null && v > 1.0) alerts.add('Phosphate high: ${_fmtVal(v)} ppm (normal <0.5)');
      // Potassium
      v = latest['k'] ?? latest['potassium'];
      if (v != null && v > 30) alerts.add('Potassium high: ${_fmtVal(v)} ppm (normal 5–20)');
    }

    return alerts;
  }

  String _fmtVal(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Widget _buildTankNotificationBell() {
    final activeTasks = _tasks.where((t) => !t.isDismissed).toList();
    final count = activeTasks.length;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 10)),
        backgroundColor: const Color(0xFFE65100),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () => _showTankNotificationsSheet(activeTasks),
    );
  }

  void _showTankNotificationsSheet(List<db.Task> activeTasks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          final liveTasks = _tasks.where((t) => !t.isDismissed).toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications, size: 18, color: Color(0xFFE65100)),
                        const SizedBox(width: 8),
                        Text(
                          'Notifications (${liveTasks.length})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (liveTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No notifications', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: liveTasks.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 14),
                        itemBuilder: (_, i) {
                          final task = liveTasks[i];
                          final desc = task.description;
                          final label = desc.isEmpty ? '' : desc[0].toUpperCase() + desc.substring(1);
                          final rawDue = task.dueDate;
                          final dueLabel = (rawDue != null && rawDue.isNotEmpty) ? _fmtNotifDue(rawDue) : null;
                          final isRecurring = task.repeatDays != null && task.repeatDays! > 0;
                          return ListTile(
                            dense: true,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await Future.delayed(const Duration(milliseconds: 300));
                              _showEditTaskSheet(_tank, task, onDone: () { _load(); });
                            },
                            leading: Icon(
                              isRecurring ? Icons.repeat : Icons.task_alt,
                              size: 18,
                              color: const Color(0xFFE65100),
                            ),
                            title: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                children: [
                                  TextSpan(text: label),
                                  if (dueLabel != null)
                                    TextSpan(
                                      text: ' — $dueLabel',
                                      style: const TextStyle(color: Color(0xFF8D6E63)),
                                    ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4CAF50)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: 'Mark complete',
                                  onPressed: () {
                                    TankStore.instance.completeTaskById(task.id);
                                    _load();
                                    setS(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF8D6E63)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: 'Dismiss',
                                  onPressed: () {
                                    showDialog<bool>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('Did you complete this task?'),
                                        content: Text(task.description),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: const Text('No'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: const Text('Yes, completed'),
                                          ),
                                        ],
                                      ),
                                    ).then((completed) {
                                      if (completed == null) return;
                                      if (completed) {
                                        TankStore.instance.completeTaskById(task.id);
                                      } else {
                                        TankStore.instance.dismissTaskById(task.id);
                                      }
                                      _load();
                                      setS(() {});
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.repeat, size: 18),
                        label: const Text('Recurring Tasks'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cDark,
                          side: const BorderSide(color: _cLight),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _ManageRecurringTasksScreen(tankId: _tank.id),
                          )).then((_) => _load());
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  static String _fmtNotifDue(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${ms[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, '', actions: [
        IconButton(
          tooltip: 'Add photo',
          icon: const Icon(Icons.add_a_photo_outlined),
          onPressed: () => pickPhotoFlow(context, tankId: _tank.id),
        ),
      ]),
      bottomNavigationBar: _AquariaFooter(
        alertLevel: _alertLevel,
        onAiTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChatSheet(
            initialTank: _tank,
            allTanks: TankStore.instance.tanks,
            onLogsChanged: _load,
            suggestions: _suggestions,
          ),
        ).then((_) => _load()),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (SupabaseService.isLoggedIn) await TankStore.instance.pullFromCloud();
          await TankStore.instance.load();
          await _load();
        },
        child: SingleChildScrollView(
        child: Column(
        children: [
          // tank name + menu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _tank.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
                  ),
                ),
                _buildTankNotificationBell(),
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'edit_tank') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _TankAttributesScreen(tank: _tank),
                      )).then((_) => _load());
                    }
                    if (value == 'tap_water') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TapWaterProfileScreen(tank: _tank),
                      )).then((_) => _load());
                    }
                    if (value == 'equipment') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _EquipmentScreen(tank: _tank),
                      )).then((_) => _load());
                    }
                    if (value == 'import_csv') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _CsvImportScreen(tank: _tank),
                      )).then((_) => _load());
                    }
                    if (value == 'manage_recurring') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _ManageRecurringTasksScreen(tankId: _tank.id),
                      )).then((_) => _load());
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit_tank', child: Text('Tank Details')),
                    PopupMenuItem(value: 'manage_recurring', child: Text('Recurring Tasks')),
                    PopupMenuItem(value: 'tap_water', child: Text('Tap Water Profile')),
                    PopupMenuItem(value: 'equipment', child: Text('Equipment')),
                    PopupMenuItem(value: 'import_csv', child: Text('Import Data')),
                  ],
                  icon: const Icon(Icons.more_vert, size: 20),
                ),
              ],
            ),
          ),
          // compact tank header
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_tank.gallons} gal • ${_tank.waterType.label}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (_inhabitants.isNotEmpty || _plants.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  const Text('·', style: TextStyle(color: Colors.grey)),
                  const SizedBox(width: 10),
                  ..._buildInhabitantIcons(),
                ],
              ],
            ),
          ),
          // nav buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _NavIconButton(child: const _FishPlantIcon(), tooltip: 'Inhabitants', color: const Color(0xFF2E86AB), onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InhabitantsScreen(tank: _tank)));
                      TankStore.instance.invalidateSummary(_tank.id);
                      await _load();
                    }),
                    if (_compatibilityWarnings(
                      _inhabitants.map((i) => (name: i.name, type: i.type ?? 'fish', count: i.count)).toList(),
                      _tank.waterType,
                      plants: _plants.map((p) => p.name).toList(),
                    ).isNotEmpty)
                      const Positioned(
                        top: -2,
                        right: -2,
                        child: Text('⚠️', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                _NavIconButton(icon: Icons.menu_book_outlined, tooltip: 'Daily Logs', color: const Color(0xFF5B8C5A), onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyLogsScreen(tank: _tank, logs: _logs)));
                  await _load();
                }),
                const SizedBox(width: 8),
                _NavIconButton(icon: Icons.show_chart, tooltip: 'Charts', color: const Color(0xFFE07A2F), onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChartsScreen(tank: _tank)));
                }),
                const SizedBox(width: 8),
                _NavIconButton(icon: Icons.photo_library_outlined, tooltip: 'Photos', color: const Color(0xFF8B5DAF), onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TankGalleryScreen(tank: _tank)));
                }),
                const SizedBox(width: 8),
                _NavIconButton(child: const _TuneSearchIcon(), tooltip: 'Attributes', color: const Color(0xFF607D8B), onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _TankAttributesScreen(tank: _tank)));
                  await _load();
                }),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Add',
                  onSelected: (value) {
                    if (value == 'add_task') _showAddTaskDialog();
                    if (value == 'add_measurement') _showAddMeasurementDialog();
                    if (value == 'add_note') _showAddNoteDialog();
                    if (value == 'add_photo') pickPhotoFlow(context, tankId: _tank.id);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add_task', child: Text('Add Task')),
                    PopupMenuItem(value: 'add_measurement', child: Text('Add Measurement')),
                    PopupMenuItem(value: 'add_note', child: Text('Add Note')),
                    PopupMenuItem(value: 'add_photo', child: Text('Add Photo')),
                  ],
                  icon: const Icon(Icons.add, size: 22, color: _cDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Open tasks card
          Builder(builder: (context) {
            final openTasks = _tasks.where((t) => !t.isDismissed && !t.isComplete).toList();
            if (openTasks.isEmpty) return const SizedBox.shrink();
            // Sort: past/today first, then future; within each group by due date
            openTasks.sort((a, b) {
              final aDue = a.dueDate != null ? DateTime.tryParse(a.dueDate!) : null;
              final bDue = b.dueDate != null ? DateTime.tryParse(b.dueDate!) : null;
              if (aDue == null && bDue == null) return 0;
              if (aDue == null) return 1;
              if (bDue == null) return -1;
              return aDue.compareTo(bDue);
            });
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Card(
                elevation: 0,
                color: const Color(0xFFFFF8F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFFFCC80), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.task_alt, size: 16, color: Color(0xFFE65100)),
                          const SizedBox(width: 6),
                          Text(
                            'Open Tasks  ${openTasks.length}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE65100), letterSpacing: 0.5),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _showAddTaskDialog(),
                            child: const Icon(Icons.add, size: 18, color: Color(0xFFE65100)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFFFCC80)),
                    ...openTasks.map((task) {
                      final desc = task.description;
                      final label = desc.isEmpty ? '' : desc[0].toUpperCase() + desc.substring(1);
                      final rawDue = task.dueDate;
                      final dueLabel = (rawDue != null && rawDue.isNotEmpty) ? _fmtNotifDue(rawDue) : null;
                      final isRecurring = task.repeatDays != null && task.repeatDays! > 0;
                      final isFuture = rawDue != null && rawDue.isNotEmpty && (() {
                        final due = DateTime.tryParse(rawDue);
                        if (due == null) return false;
                        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                        return due.isAfter(today);
                      })();
                      return InkWell(
                        onTap: () async {
                          await _showEditTaskSheet(_tank, task);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (isRecurring)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4, top: 1),
                                  child: Icon(Icons.repeat, size: 13, color: Color(0xFF8D6E63)),
                                ),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                    children: [
                                      TextSpan(text: label),
                                      if (dueLabel != null)
                                        TextSpan(
                                          text: ' — $dueLabel',
                                          style: TextStyle(
                                            color: isFuture ? const Color(0xFF6D8B74) : const Color(0xFF8D6E63),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            IconButton(
                              onPressed: () {
                                final isRecurring = task.repeatDays != null && task.repeatDays! > 0;
                                showDialog<String>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(task.description),
                                    content: const Text('What would you like to do?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, 'cancel'),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, 'dismiss'),
                                        child: const Text('Dismiss'),
                                      ),
                                      if (isRecurring)
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, 'stop'),
                                          child: const Text('Stop Recurring'),
                                        ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(ctx, 'complete'),
                                        child: const Text('Complete'),
                                      ),
                                    ],
                                  ),
                                ).then((action) async {
                                  if (action == 'complete') {
                                    await TankStore.instance.completeTaskById(task.id);
                                  } else if (action == 'dismiss') {
                                    if (isRecurring) {
                                      await TankStore.instance.completeTaskById(task.id);
                                    } else {
                                      await TankStore.instance.dismissTaskById(task.id);
                                    }
                                  } else if (action == 'stop') {
                                    await TankStore.instance.completeAndStopRecurring(task.id);
                                  } else {
                                    return;
                                  }
                                  final fresh = await TankStore.instance.tasksForTank(_tank.id);
                                  if (!mounted) return;
                                  setState(() => _tasks = fresh);
                                });
                              },
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFF8D6E63)),
                              iconSize: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              splashRadius: 16,
                              tooltip: 'Dismiss',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          // summary card
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: _cLight, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 15, color: Colors.black87),
                        SizedBox(width: 4),
                        Text('AI SUMMARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: Colors.black, letterSpacing: 0.8)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_summaryLoading)
                      const Row(
                        children: [
                          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Summarising…', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      )
                    else if (_summary != null) ...[
                      Text(
                        _summary!,
                        maxLines: _summaryExpanded ? null : 3,
                        overflow: _summaryExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.5),
                      ),
                      if (!_summaryExpanded)
                        GestureDetector(
                          onTap: () => setState(() => _summaryExpanded = true),
                          child: const Text('…more', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _cMid)),
                        ),
                      if (_summaryExpanded)
                        GestureDetector(
                          onTap: () => setState(() => _summaryExpanded = false),
                          child: const Text('…Less', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _cMid)),
                        ),
                    ] else
                      _AiSummaryEmptyHint(inhabitants: _inhabitants, logs: _logs),
                    const SizedBox(height: 6),
                    const Text(
                      'AI-generated content may be inaccurate. Always consult a professional.',
                      style: TextStyle(fontSize: 10, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // AI Suggestions card
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: _cLight, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 15, color: Colors.black87),
                        SizedBox(width: 4),
                        Text('AI SUGGESTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: Colors.black, letterSpacing: 0.8)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_suggestionsLoading)
                      const Row(
                        children: [
                          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Thinking…', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      )
                    else if (_suggestions.isNotEmpty)
                      ..._suggestions.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  ', style: TextStyle(fontSize: 13, color: _cMid, fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(s, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
                            ),
                            GestureDetector(
                              onTap: _reminderSuggestions.contains(s) ? null : () async {
                                final tomorrow = DateTime.now().add(const Duration(days: 1));
                                final dueDate = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
                                await TankStore.instance.addTask(
                                  tankId: _tank.id,
                                  description: s,
                                  dueDate: dueDate,
                                  priority: 'normal',
                                  source: 'ai',
                                );
                                final tasks = await TankStore.instance.tasksForTank(_tank.id);
                                if (mounted) {
                                  setState(() {
                                    _tasks = tasks;
                                    _reminderSuggestions.add(s);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Reminder set for tomorrow'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  _reminderSuggestions.contains(s) ? Icons.notifications_active : Icons.notification_add_outlined,
                                  size: 16,
                                  color: _reminderSuggestions.contains(s) ? const Color(0xFFE65100) : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                    else
                      const Text('No suggestions right now.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    const Text(
                      'AI-generated content may be inaccurate. Always consult a professional.',
                      style: TextStyle(fontSize: 10, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Latest water parameters card
          Builder(builder: (context) {
            final params = _latestMeasurements();
            return GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyLogsScreen(tank: _tank, logs: _logs)));
                await _load();
              },
              child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _cLight, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.science_outlined, size: 15, color: Colors.black87),
                          const SizedBox(width: 4),
                          const Text('WATER PARAMETERS — LAST 2 WEEKS',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                  color: Colors.black, letterSpacing: 0.8)),
                          const Spacer(),
                          GestureDetector(
                            onTap: _showAddMeasurementDialog,
                            child: const Icon(Icons.add, size: 18, color: _cDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (params.isEmpty)
                        const Text(
                          'Log recent test results so Ariel can help you in the future. At a minimum it\'s important to test nitrate, nitrite, and ammonia to ensure your aquarium friends stay safe.',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        )
                      else ...() {
                        // Separate measured vs deduced params
                        final measured = Map.fromEntries(params.entries.where((e) => !e.value.deduced));
                        final deduced = Map.fromEntries(params.entries.where((e) => e.value.deduced));
                        // Group measured params by date (preserving preferred order)
                        final byDate = <DateTime, List<MapEntry<String, ({String value, DateTime date, bool deduced})>>>{};
                        for (final e in measured.entries) {
                          byDate.putIfAbsent(e.value.date, () => []).add(e);
                        }
                        // Sort date groups newest first
                        final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
                        final sections = <Widget>[];
                        for (final date in sortedDates) {
                          sections.add(Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 4),
                            child: Text(
                              _formatParamDate(date),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: Color(0xFF757575), letterSpacing: 0.3),
                            ),
                          ));
                          sections.add(Wrap(
                            spacing: 6,
                            runSpacing: 8,
                            children: byDate[date]!.map((e) {
                              final bgColor = _paramColors[e.key] ?? _cMint;
                              final label = _paramShortLabel(e.key);
                              final textColor = bgColor.computeLuminance() < 0.35 ? Colors.white : Colors.black;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$label ',
                                        style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.85),
                                            fontWeight: FontWeight.w600),
                                      ),
                                      TextSpan(
                                        text: e.value.value,
                                        style: TextStyle(fontSize: 12, color: textColor,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ));
                        }
                        // Deduced values section
                        if (deduced.isNotEmpty) {
                          sections.add(const Padding(
                            padding: EdgeInsets.only(top: 12, bottom: 4),
                            child: Text(
                              'CALCULATED',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                  color: Color(0xFF9E9E9E), letterSpacing: 0.8, fontStyle: FontStyle.italic),
                            ),
                          ));
                          sections.add(Wrap(
                            spacing: 6,
                            runSpacing: 8,
                            children: deduced.entries.map((e) {
                              final bgColor = (_paramColors[e.key] ?? _cMint).withOpacity(0.15);
                              final borderColor = _paramColors[e.key] ?? _cMint;
                              final label = _paramShortLabel(e.key);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: borderColor.withOpacity(0.5), width: 1),
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$label ',
                                        style: TextStyle(fontSize: 11, color: borderColor,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      TextSpan(
                                        text: e.value.value,
                                        style: TextStyle(fontSize: 12, color: borderColor,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ));
                        }
                        return sections;
                      }(),
                    ],
                  ),
                ),
              ),
            ),
            );
          }),
          // Actions last two weeks card
          StatefulBuilder(builder: (context, setLocalState) {
            final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
            final twoWeeksKey = '${twoWeeksAgo.year}-${twoWeeksAgo.month.toString().padLeft(2,'0')}-${twoWeeksAgo.day.toString().padLeft(2,'0')}';
            final recentActions = <({String action, DateTime date})>[];
            for (final entry in _journal) {
              if (entry.category != 'actions') continue;
              if (entry.date.compareTo(twoWeeksKey) < 0) continue;
              try {
                final actions = (jsonDecode(entry.data) as List).cast<String>();
                final parts = entry.date.split('-');
                final entryDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                for (final a in actions) {
                  final text = a.trim();
                  if (text.isNotEmpty) {
                    recentActions.add((action: text, date: entryDate));
                  }
                }
              } catch (_) {}
            }
            if (recentActions.isEmpty) return const SizedBox.shrink();
            const int _kCollapsedCount = 3;
            final bool canExpand = recentActions.length > _kCollapsedCount;
            final displayed = _actionsExpanded ? recentActions : recentActions.take(_kCollapsedCount).toList();
            return GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyLogsScreen(tank: _tank, logs: _logs)));
                await _load();
              },
              child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _cLight, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.checklist, size: 15, color: Colors.black87),
                          const SizedBox(width: 4),
                          const Text('ACTIONS — LAST 2 WEEKS',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                  color: Colors.black, letterSpacing: 0.8)),
                          const Spacer(),
                          GestureDetector(
                            onTap: _showAddTaskDialog,
                            child: const Icon(Icons.add, size: 18, color: _cDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...displayed.map((item) {
                        final label = item.action[0].toUpperCase() + item.action.substring(1);
                        final dateStr = _formatParamDate(DateTime(
                          item.date.toLocal().year,
                          item.date.toLocal().month,
                          item.date.toLocal().day,
                        ));
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(label,
                                    style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              ),
                              Text(dateStr,
                                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
                            ],
                          ),
                        );
                      }),
                      if (canExpand)
                        GestureDetector(
                          onTap: () => setLocalState(() => _actionsExpanded = !_actionsExpanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _actionsExpanded ? 'Less' : 'More...',
                              style: const TextStyle(fontSize: 12, color: _cMid, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            );
          }),
          const SizedBox(height: 100),
        ],
        ),
        ),
        ),
    );
  }
}

// ─────────────────────────────────────────────
// Chat sheet (modal overlay)
// ─────────────────────────────────────────────
class _ChatSheet extends StatefulWidget {
  final TankModel? initialTank;
  final List<TankModel> allTanks;
  final VoidCallback onLogsChanged;
  final List<String> suggestions;

  const _ChatSheet({
    this.initialTank,
    required this.allTanks,
    required this.onLogsChanged,
    this.suggestions = const [],
  });

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  static const _baseUrl = _kBaseUrl;

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<_ChatMessage> _chatMessages = [];
  bool _sending = false;
  bool _aiResponding = false;
  bool _cancelled = false;
  DateTime _logDate = DateTime.now();
  final Set<String> _firedAlerts = {};

  TankModel? _selectedTank;
  late List<TankModel> _allTanks;
  /// Cache key stays fixed for the lifetime of this sheet so that
  /// messages saved mid-conversation (after tank auto-detection changes
  /// _selectedTank) can still be loaded when the sheet reopens.
  late String? _cacheKey;
  List<db.Inhabitant> _inhabitants = [];
  List<db.Plant> _plants = [];
  List<String> _recentLogs = [];
  List<db.Log> _allLogs = [];
  List<db.JournalEntry> _allJournal = [];
  String? _tapWaterJson;
  String? _equipmentJson;
  bool _hasCsvImports = false;
  List<Map<String, dynamic>> _pendingTasks = [];
  List<String> _sessionSummaries = [];
  String _experience = 'beginner';

  @override
  void initState() {
    super.initState();
    _loadExperienceLevel().then((v) { if (mounted) setState(() => _experience = v); });
    _allTanks = List.of(widget.allTanks);
    // Only pre-select a tank when opened from a specific tank screen.
    // From the home page (no initialTank) with multiple tanks, let Ariel ask.
    _selectedTank = widget.initialTank ??
        (_allTanks.length == 1 ? _allTanks.first : null);
    _cacheKey = _selectedTank?.id;
    final cached = _ChatCache.load(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      _chatMessages = cached;
      _scrollToBottom();
    } else {
      _chatMessages = [
        _ChatMessage(role: 'assistant', content: 'Hey! I\'m Ariel — ask me anything about your tanks or log an entry.'),
      ];
    }
    if (_selectedTank != null) _loadTankData(_selectedTank!);
  }

  Future<void> _loadTankData(TankModel tank) async {
    final inhabitants = await TankStore.instance.inhabitantsFor(tank.id);
    final plants = await TankStore.instance.plantsFor(tank.id);
    final logs = await TankStore.instance.logsFor(tank.id);
    final journal = await TankStore.instance.journalFor(tank.id);
    final tapWaterJson = await TankStore.instance.tapWaterJsonFor(tank.id);
    final equipmentJson = await TankStore.instance.equipmentJsonFor(tank.id);
    final sessions = await TankStore.instance.recentSessions(tank.id);
    if (mounted) {
      setState(() {
        _inhabitants = inhabitants;
        _plants = plants;
        _allLogs = logs;
        _allJournal = journal;

        // Build recent_logs from journal entries
        // Measurements: last 2 weeks only. Actions/notes: all time.
        final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
        final twoWeeksKey = '${twoWeeksAgo.year}-${twoWeeksAgo.month.toString().padLeft(2,'0')}-${twoWeeksAgo.day.toString().padLeft(2,'0')}';
        // Group by date, filtering out old measurements but keeping all actions/notes
        final byDate = <String, List<db.JournalEntry>>{};
        for (final j in journal) {
          if (j.category == 'measurements' && j.date.compareTo(twoWeeksKey) < 0) continue;
          byDate.putIfAbsent(j.date, () => []).add(j);
        }
        _recentLogs = [];
        for (final date in (byDate.keys.toList()..sort((a, b) => b.compareTo(a))).take(10)) {
          final entries = byDate[date]!;
          final parts = <String>[];
          for (final e in entries) {
            try {
              if (e.category == 'measurements') {
                final m = (jsonDecode(e.data) as Map).cast<String, dynamic>();
                parts.add(m.entries.map((kv) => '${kv.key}: ${kv.value}').join(', '));
              } else if (e.category == 'actions') {
                final a = (jsonDecode(e.data) as List).cast<String>();
                if (a.isNotEmpty) parts.add('Actions: ${a.join(", ")}');
              } else if (e.category == 'notes') {
                final n = (jsonDecode(e.data) as List).cast<String>();
                if (n.isNotEmpty) parts.add('Notes: ${n.join(", ")}');
              }
            } catch (_) {}
          }
          if (parts.isNotEmpty) _recentLogs.add('$date: ${parts.join(" | ")}');
        }

        _tapWaterJson = tapWaterJson;
        _equipmentJson = equipmentJson;
        _hasCsvImports = logs.any((l) => l.rawText == 'CSV import');
        _sessionSummaries = sessions.map((s) => s.summary).toList();
      });
    }
  }

  void _addMessage(_ChatMessage msg) {
    setState(() => _chatMessages.add(msg));
    _ChatCache.save(_cacheKey, _chatMessages);
  }

  @override
  void dispose() {
    _summarizeAndSaveSession();
    _flushPendingTasks();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _flushPendingTasks() {
    if (_pendingTasks.isEmpty) return;
    final tank = _selectedTank ?? (widget.allTanks.length == 1 ? widget.allTanks.first : null);
    if (tank == null) return;
    for (final task in _pendingTasks) {
      final rd = task['repeat_days'];
      TankStore.instance.addTask(
        tankId: tank.id,
        description: (task['description'] ?? '').toString(),
        dueDate: (task['due_date'] ?? task['due'])?.toString(),
        priority: (task['priority'] ?? 'normal').toString(),
        source: rd != null ? 'recurring' : 'ai',
        repeatDays: rd is int ? rd : (rd is num ? rd.toInt() : null),
      );
    }
    _pendingTasks = [];
    widget.onLogsChanged();
  }

  void _summarizeAndSaveSession() {
    // Only summarize if there were meaningful user messages (4+ messages total)
    final userMsgCount = _chatMessages.where((m) => m.role == 'user').length;
    if (userMsgCount < 2) return;
    final tankId = _selectedTank?.id;
    final tankName = _selectedTank?.name;
    final messages = _chatMessages
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
    final msgCount = _chatMessages.length;
    // Fire and forget — don't block dispose
    http.post(
      Uri.parse('$_baseUrl/chat/summarize'),
      headers: _apiHeaders(),
      body: jsonEncode({
        'messages': messages,
        'tank_name': tankName,
      }),
    ).then((resp) {
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final summary = data['summary']?.toString() ?? '';
        if (summary.isNotEmpty) {
          TankStore.instance.saveChatSession(
            tankId: tankId,
            summary: summary,
            messageCount: msgCount,
          );
        }
      }
    }).catchError((_) {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelResponse() {
    if (!_aiResponding) return;
    setState(() {
      _cancelled = true;
      _aiResponding = false;
    });
  }

  /// Parse a log's parsedJson into a Map, returning null on failure.
  Map<String, dynamic>? _parseParsedJson(db.Log log) {
    if (log.parsedJson == null) return null;
    try {
      final decoded = jsonDecode(log.parsedJson!);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _buildHealthProfile() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final thirtyDaysKey = '${thirtyDaysAgo.year}-${thirtyDaysAgo.month.toString().padLeft(2,'0')}-${thirtyDaysAgo.day.toString().padLeft(2,'0')}';

    // Journal entries sorted newest-first by date
    final measEntries = _allJournal.where((j) => j.category == 'measurements').toList();
    final actionEntries = _allJournal.where((j) => j.category == 'actions').toList();

    final allParamValues30d = <String, List<double>>{};
    final lastTwoReadings = <String, List<double>>{};
    int waterChanges30d = 0;
    final testedParams = <String>{};
    final testDates = <String>[]; // YYYY-MM-DD strings of days with measurements

    for (final entry in measEntries) {
      try {
        final m = (jsonDecode(entry.data) as Map).cast<String, dynamic>();
        if (m.isEmpty) continue;
        testDates.add(entry.date);
        testedParams.addAll(m.keys);

        // 30-day window
        if (entry.date.compareTo(thirtyDaysKey) >= 0) {
          m.forEach((key, value) {
            final v = (value is num) ? value.toDouble() : double.tryParse('$value');
            if (v != null) {
              allParamValues30d.putIfAbsent(key, () => []).add(v);
            }
          });
        }

        // Last 2 readings per param (entries are sorted newest-first)
        m.forEach((key, value) {
          final v = (value is num) ? value.toDouble() : double.tryParse('$value');
          if (v != null) {
            final list = lastTwoReadings.putIfAbsent(key, () => []);
            if (list.length < 2) list.add(v);
          }
        });
      } catch (_) {}
    }

    // Count water changes in last 30 days from action entries
    for (final entry in actionEntries) {
      if (entry.date.compareTo(thirtyDaysKey) < 0) continue;
      try {
        final actions = (jsonDecode(entry.data) as List).cast<String>();
        for (final a in actions) {
          if (a.toLowerCase().contains('water change')) waterChanges30d++;
        }
      } catch (_) {}
    }

    // Days since last test
    final daysSinceLastTest = testDates.isNotEmpty
        ? now.difference(DateTime.parse(testDates.first)).inDays
        : null;

    // Average days between tests
    double? avgDaysBetweenTests;
    if (testDates.length >= 2) {
      double totalGap = 0;
      for (int i = 0; i < testDates.length - 1; i++) {
        totalGap += DateTime.parse(testDates[i])
            .difference(DateTime.parse(testDates[i + 1]))
            .inDays
            .abs();
      }
      avgDaysBetweenTests = totalGap / (testDates.length - 1);
    }

    // Parameter averages (30 days)
    final parameterAverages = <String, double>{};
    allParamValues30d.forEach((key, values) {
      parameterAverages[key] =
          double.parse((values.reduce((a, b) => a + b) / values.length).toStringAsFixed(2));
    });

    // Parameter trends
    final parameterTrends = <String, String>{};
    lastTwoReadings.forEach((key, values) {
      if (values.length == 2) {
        final diff = values[0] - values[1];
        if (diff.abs() < 0.01) {
          parameterTrends[key] = 'stable';
        } else if (diff > 0) {
          parameterTrends[key] = 'rising';
        } else {
          parameterTrends[key] = 'falling';
        }
      }
    });

    return {
      'days_since_last_test': daysSinceLastTest,
      'avg_days_between_tests': avgDaysBetweenTests != null
          ? double.parse(avgDaysBetweenTests.toStringAsFixed(1))
          : null,
      'water_changes_last_30d': waterChanges30d,
      'parameter_averages': parameterAverages,
      'parameter_trends': parameterTrends,
      'parameters_tested': testedParams.toList(),
    };
  }

  Future<Map<String, dynamic>> _buildBehaviorProfile() async {
    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    final ninetyDaysKey = '${ninetyDaysAgo.year}-${ninetyDaysAgo.month.toString().padLeft(2,'0')}-${ninetyDaysAgo.day.toString().padLeft(2,'0')}';

    // Normal ranges for common parameters (freshwater defaults)
    const normalRanges = <String, List<double>>{
      'pH': [6.5, 7.5],
      'ammonia': [0, 0.25],
      'nitrite': [0, 0.25],
      'nitrate': [0, 40],
      'GH': [4, 12],
      'KH': [3, 8],
    };

    // Journal measurement entries within 90 days
    final testDates = <DateTime>[];
    final paramFrequency = <String, int>{};
    final paramExceedCount = <String, int>{};

    final measEntries = _allJournal.where((j) =>
        j.category == 'measurements' && j.date.compareTo(ninetyDaysKey) >= 0).toList();

    for (final entry in measEntries) {
      try {
        final measurements = (jsonDecode(entry.data) as Map).cast<String, dynamic>();
        if (measurements.isEmpty) continue;

        testDates.add(DateTime.parse(entry.date));
        measurements.forEach((key, value) {
          paramFrequency[key] = (paramFrequency[key] ?? 0) + 1;
          final v = (value is num) ? value.toDouble() : double.tryParse('$value');
          if (v != null && normalRanges.containsKey(key)) {
            final range = normalRanges[key]!;
            if (v < range[0] || v > range[1]) {
              paramExceedCount[key] = (paramExceedCount[key] ?? 0) + 1;
            }
          }
        });
      } catch (_) {}
    }

    // Tests per month (over 90 days = 3 months)
    final testsPerMonth = testDates.isEmpty
        ? 0.0
        : double.parse((testDates.length / 3.0).toStringAsFixed(1));

    // Most tested (top 3)
    final sortedParams = paramFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mostTested = sortedParams.take(3).map((e) => e.key).toList();

    // Least tested (fewer than 3 times in 90 days)
    final leastTested = paramFrequency.entries
        .where((e) => e.value < 3)
        .map((e) => e.key)
        .toList();

    // Recurring issues (params exceeding range in >= 30% of tests)
    final recurringIssues = <String>[];
    paramExceedCount.forEach((key, count) {
      final total = paramFrequency[key] ?? 1;
      if (count / total >= 0.3) recurringIssues.add(key);
    });

    // Task completion rate
    double? taskCompletionRate;
    if (_selectedTank != null) {
      try {
        // Get all tasks (both active and dismissed) via raw query
        final allTasks = await TankStore.instance.tasksForTank(_selectedTank!.id);
        // tasksForTank only returns non-dismissed; we approximate with what we have
        // For a proper ratio we note that dismissed = completed
        final activeTasks = allTasks.length;
        // We can't easily get dismissed count from TankStore, so we report active count
        // A simple heuristic: if there are pending tasks, rate < 1.0
        taskCompletionRate = activeTasks == 0 ? 1.0 : null;
      } catch (_) {}
    }

    // Testing regularity based on std dev of intervals
    String testingRegularity = 'unknown';
    if (testDates.length >= 3) {
      testDates.sort((a, b) => a.compareTo(b));
      final intervals = <double>[];
      for (int i = 1; i < testDates.length; i++) {
        intervals.add(testDates[i].difference(testDates[i - 1]).inDays.toDouble());
      }
      final mean = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance =
          intervals.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
              intervals.length;
      final stdDev = math.sqrt(variance);
      testingRegularity = stdDev <= mean * 0.5 ? 'regular' : 'irregular';
    }

    return {
      'tests_per_month': testsPerMonth,
      'most_tested': mostTested,
      'least_tested': leastTested,
      'recurring_issues': recurringIssues,
      if (taskCompletionRate != null) 'task_completion_rate': taskCompletionRate,
      'testing_regularity': testingRegularity,
    };
  }

  Future<void> _submit() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    _addMessage(_ChatMessage(role: 'user', content: text));
    setState(() {
      _sending = true;
      _aiResponding = true;
      _cancelled = false;
    });
    _scrollToBottom();

    // Fire log-parse and chat simultaneously; don't block chat on log parsing
    final tankSnapshot = _selectedTank;
    final logDateSnapshot = _logDate;

    Future<void> parseAndSaveLog() async {
      if (tankSnapshot == null) return;
      try {
        debugPrint('[ParseLog] Sending parse request for: "$text"');
        // Build recent conversation context so the parser can resolve
        // ambiguous references (e.g. "added to canister filter" → aragonite)
        final recentContext = _chatMessages
            .take(6)
            .map((m) => '${m.role}: ${m.content}')
            .join('\n');
        final resp = await http
            .post(Uri.parse('$_baseUrl/parse/tank-log'),
                headers: _apiHeaders(),
                body: jsonEncode({
                  'text': text,
                  if (recentContext.isNotEmpty) 'context': recentContext,
                  'client_date': '${logDateSnapshot.year}-${logDateSnapshot.month.toString().padLeft(2, '0')}-${logDateSnapshot.day.toString().padLeft(2, '0')}',
                }))
            .timeout(const Duration(seconds: 20));
        debugPrint('[ParseLog] Response status=${resp.statusCode}, body=${resp.body}');
        if (resp.statusCode == 200) {
          final parsed = jsonDecode(resp.body);
          final logEntries = (parsed is Map && parsed['logs'] is List)
              ? (parsed['logs'] as List).cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
          // Detect tap water mentions before saving
          final isTapWater = RegExp(
            r'\btap\s+water\b|\bfrom\s+the\s+tap\b|\bsource\s+water\b|\bfaucet\b|\bmunicipal\s+water\b',
            caseSensitive: false,
          ).hasMatch(text);

          // Tag entries as tap water before persisting
          if (isTapWater) {
            for (final entry in logEntries) {
              entry['source'] = 'tap_water';
            }
          }

          for (int i = 0; i < logEntries.length; i++) {
            final entry = logEntries[i];
            // Skip entries with no measurements, actions, or notes.
            // Tasks/reminders are handled separately by the chat task extraction path.
            final hasMeasurements = (entry['measurements'] as Map?)?.isNotEmpty == true;
            final hasActions = (entry['actions'] as List?)?.isNotEmpty == true;
            final hasNotes = (entry['notes'] as List?)?.isNotEmpty == true;
            debugPrint('[ParseLog] Entry $i: meas=$hasMeasurements, actions=$hasActions, notes=$hasNotes');
            if (!hasMeasurements && !hasActions && !hasNotes) continue;
            // Remove tasks from parse entries — chat path handles task saving
            entry.remove('tasks');
            final dateStr = entry['date'] as String?;
            final logDate = (dateStr != null ? DateTime.tryParse(dateStr) : null) ?? logDateSnapshot;
            final journalDate = '${logDate.year}-${logDate.month.toString().padLeft(2,'0')}-${logDate.day.toString().padLeft(2,'0')}';
            debugPrint('[ParseLog] Saving log entry $i for tank ${tankSnapshot.id}');
            // Save to audit log
            await TankStore.instance.addLog(
              tankId: tankSnapshot.id,
              rawText: logEntries.length == 1 ? text : '',
              parsedJson: jsonEncode(entry),
              date: logDate,
            );
            // Save to journal (user-facing curated view)
            if (hasMeasurements) {
              final existing = await TankStore.instance.journalForDate(tankSnapshot.id, journalDate);
              final measEntry = existing.where((e) => e.category == 'measurements').toList();
              Map<String, dynamic> measurements = {};
              if (measEntry.isNotEmpty) {
                try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
              }
              measurements.addAll((entry['measurements'] as Map).cast<String, dynamic>());
              await TankStore.instance.upsertJournal(
                tankId: tankSnapshot.id, date: journalDate, category: 'measurements', data: jsonEncode(measurements),
              );
            }
            if (hasActions) {
              final existing = await TankStore.instance.journalForDate(tankSnapshot.id, journalDate);
              final actEntry = existing.where((e) => e.category == 'actions').toList();
              List<String> actions = [];
              if (actEntry.isNotEmpty) {
                try { actions = (jsonDecode(actEntry.first.data) as List).cast<String>(); } catch (_) {}
              }
              for (final a in (entry['actions'] as List).cast<String>()) {
                if (!actions.contains(a)) actions.add(a);
              }
              await TankStore.instance.upsertJournal(
                tankId: tankSnapshot.id, date: journalDate, category: 'actions', data: jsonEncode(actions),
              );
            }
            if (hasNotes) {
              final existing = await TankStore.instance.journalForDate(tankSnapshot.id, journalDate);
              final noteEntry = existing.where((e) => e.category == 'notes').toList();
              List<String> notes = [];
              if (noteEntry.isNotEmpty) {
                try { notes = (jsonDecode(noteEntry.first.data) as List).cast<String>(); } catch (_) {}
              }
              for (final n in (entry['notes'] as List).cast<String>()) {
                if (!notes.contains(n)) notes.add(n);
              }
              await TankStore.instance.upsertJournal(
                tankId: tankSnapshot.id, date: journalDate, category: 'notes', data: jsonEncode(notes),
              );
            }
            debugPrint('[ParseLog] Log entry $i saved successfully');
            // Auto-complete matching tasks when actions are logged
            if (hasActions) {
              final actions = (entry['actions'] as List).cast<String>();
              for (final action in actions) {
                await TankStore.instance.completeMatchingTask(
                  tankId: tankSnapshot.id,
                  actionDescription: action,
                );
              }
            }
            if (i == logEntries.length - 1 && mounted) setState(() => _logDate = logDate);
          }
          if (mounted) widget.onLogsChanged();
          // Refresh chat's own journal data so calculated params
          // (magnesium_calc, ca_mg_ratio) are available in context
          if (mounted) await _loadTankData(tankSnapshot);

          // If tap water, also update the tap water profile
          if (isTapWater) {
            const logToTapKey = {
              'pH': 'ph',
              'GH': 'gh',
              'KH': 'kh',
              'ammonia': 'ammonia',
              'nitrite': 'nitrite',
              'nitrate': 'nitrate',
              'potassium': 'potassium',
              'Potassium': 'potassium',
              'K': 'potassium',
              'calcium': 'calcium',
              'Calcium': 'calcium',
              'Ca': 'calcium',
              'magnesium': 'magnesium',
              'Magnesium': 'magnesium',
              'Mg': 'magnesium',
              'TDS': 'tds',
              'tds': 'tds',
            };
            final tapData = <String, dynamic>{};
            for (final entry in logEntries) {
              final measurements = entry['measurements'];
              if (measurements is Map) {
                for (final kv in measurements.entries) {
                  final tapKey = logToTapKey[kv.key];
                  if (tapKey != null && kv.value != null) {
                    tapData[tapKey] = kv.value;
                  }
                }
              }
            }
            if (tapData.isNotEmpty) {
              final existing = _tapWaterJson != null
                  ? Map<String, dynamic>.from(jsonDecode(_tapWaterJson!) as Map)
                  : <String, dynamic>{};
              existing.addAll(tapData);
              final jsonStr = jsonEncode(existing);
              await TankStore.instance.saveTapWater(tankSnapshot.id, jsonStr);
              if (mounted) setState(() => _tapWaterJson = jsonStr);
            }
          }

          // Observation alerts are handled by the AI task extraction path —
          // no need to duplicate them here.
        }
      } catch (e) {
        debugPrint('[ParseLog] ERROR: $e');
      }
      if (mounted) setState(() => _sending = false);
    }

    // Only parse for log data if the message looks like it contains aquarium info
    // (measurements, observations, actions) — skip pure conversational messages.
    final _logWordsRe = RegExp(
      r'\b(ph|ammonia|nh3|nitrite|no2|nitrate|no3|kh|gh|temp|temperature|salinity|calcium|ca|'
      r'magnesium|mg|phosphate|po4|alkalinity|alk|potassium|iron|fe|tds|ppm|dkh|sg|'
      r'water\s*change|dose[d]?|dosing|fed|feed|clean|trim|prune|'
      r'test|tested|measure|reading|parameters|levels|results|'
      r'added|removed|replaced|installed|treated|'
      r'cloudy|clear|brown|yellow|green|murky|hazy|milky|foamy|smelly|odor|algae|bloom|sick|dead|died|spawn|'
      r'curly|curling|spots|spotted|melting|wilting|drooping|stunted|twisted|holes|pinholes|pale|'
      r'yellowing|browning|rotting|shedding|losing\s+leaves|plant|plants|'
      r'lethargic|gasping|hiding|aggressive|bloated|swollen|scratching|flashing|fin\s*rot|ich|ick|fungus|'
      r'ill|injured|infected|disease|parasite|worm|wormy|listless|clamped|erratic|darting|'
      r'terrible|awful|bad|worse|weird|strange|odd|unusual|abnormal|struggling|suffering|distressed|stressed|'
      r'not\s+eating|won.t\s+eat|stopped\s+eating|lost\s+color|losing\s+color|faded|discolored|'
      r'filter|heater|light|pump|skimmer)\b'
      r'|\b[kK]\s*[:=]?\s*\d',  // K followed by a number = potassium measurement
      caseSensitive: false,
    );
    if (_logWordsRe.hasMatch(text)) {
      parseAndSaveLog();
    }

    // Get AI chat response
    try {
      final history = _chatMessages
          .take(_chatMessages.length - 1)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      debugPrint('[Chat] sending message: "$text"');
      debugPrint('[Chat] history (${history.length} msgs): ${history.map((h) => "${h['role']}: ${(h['content'] as String).substring(0, (h['content'] as String).length.clamp(0, 50))}").toList()}');
      final healthProfile = _buildHealthProfile();
      final behaviorProfile = await _buildBehaviorProfile();
      final resp = await http
          .post(Uri.parse('$_baseUrl/chat/tank'),
              headers: _apiHeaders(),
              body: jsonEncode({
                'tank': _selectedTank != null ? {
                  'name': _selectedTank!.name,
                  'gallons': _selectedTank!.gallons,
                  'water_type': _selectedTank!.waterType.label,
                  'inhabitants': _inhabitants.map((i) => '${i.count != null ? "${i.count}x " : ""}${i.name}').toList(),
                  'plants': _plants.map((p) => p.name).toList(),
                  if (_tapWaterJson != null) 'tap_water': jsonDecode(_tapWaterJson!),
                  if (_equipmentJson != null) 'equipment': jsonDecode(_equipmentJson!),
                  if (_hasCsvImports) 'has_csv_imports': true,
                } : null,
                'available_tanks': _allTanks.map((t) => t.name).toList(),
                'available_tanks_detail': _allTanks.map((t) => <String, dynamic>{
                  'name': t.name,
                  'gallons': t.gallons,
                  'water_type': t.waterType.label,
                  'created_at': t.createdAt.toIso8601String(),
                }).toList(),
                'message': text,
                'history': history,
                'recent_logs': _recentLogs,
                'health_profile': healthProfile,
                'behavior_profile': behaviorProfile,
                'experience_level': _experience,
                if (_sessionSummaries.isNotEmpty) 'session_summaries': _sessionSummaries,
                if (widget.suggestions.isNotEmpty) 'system_context':
                    'CURRENT AI SUGGESTIONS for this tank (these were generated from the user\'s recent data): '
                    '${widget.suggestions.map((s) => "• $s").join("\n")}\n'
                    'If the user asks you to remind them about the suggestions, or to set up reminders for them, '
                    'create a task/reminder for each suggestion. '
                    'If the user asks what they should do or what the suggestions are, reference these.',
              }))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 && mounted && !_cancelled) {
        final data = jsonDecode(resp.body);
        debugPrint('[Chat] FULL RESPONSE KEYS: ${data is Map ? (data as Map).keys.toList() : "not a map"}');
        debugPrint('[Chat] new_inhabitant: ${data is Map ? data['new_inhabitant'] : "N/A"}');
        debugPrint('[Chat] new_plants: ${data is Map ? data['new_plants'] : "N/A"}');
        debugPrint('[Chat] remove_plants: ${data is Map ? data['remove_plants'] : "N/A"}');
        debugPrint('[Chat] remove_inhabitants: ${data is Map ? data['remove_inhabitants'] : "N/A"}');
        debugPrint('[Chat] _selectedTank: ${_selectedTank?.name ?? "NULL"}');
        final reply = (data is Map ? data['response'] ?? data['message'] ?? data.toString() : resp.body) as String;
        _addMessage(_ChatMessage(role: 'assistant', content: reply));
        _scrollToBottom();

        // Detect which tank Ariel identified from the reply or user message.
        // Always check the user's message for a tank name (they may have typed
        // the tank name to answer "which tank?"). Only check the reply when it
        // is NOT purely a question — this prevents premature selection from
        // "which tank?" replies while still detecting from confirming replies
        // like "Added Amazon Sword to New Tank! Anything else?"
        if (_allTanks.length > 1) {
          final replyLower = reply.toLowerCase();
          final msgLower = text.toLowerCase();
          // A reply is "purely a question" only if it ends with ? AND does not
          // contain action-confirming words (e.g. "added", "removed", "done").
          final endsWithQ = reply.trimRight().endsWith('?');
          final hasConfirm = RegExp(r'\b(added|removed|deleted|done|all set|created|updated|logged|taken care)\b')
              .hasMatch(replyLower);
          final checkReply = !endsWithQ || hasConfirm;

          TankModel? detected;

          // Check if the user replied with just a number (selecting from numbered list)
          final numberMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(text);
          if (numberMatch != null) {
            final idx = int.parse(numberMatch.group(1)!) - 1; // 1-based to 0-based
            if (idx >= 0 && idx < _allTanks.length) {
              detected = _allTanks[idx];
              debugPrint('[Chat] Tank selected by number: ${idx + 1} → ${detected.name}');
            }
          }

          // Fall back to name matching
          if (detected == null) {
            // Sort by name length descending so "New Tank" matches before "Tank"
            final sorted = List<TankModel>.from(_allTanks)
              ..sort((a, b) => b.name.length.compareTo(a.name.length));
            for (final t in sorted) {
              final nameL = t.name.toLowerCase();
              // Use word-boundary-aware matching to avoid substring false positives
              final pattern = RegExp('\\b${RegExp.escape(nameL)}\\b');
              if ((checkReply && pattern.hasMatch(replyLower)) || pattern.hasMatch(msgLower)) {
                detected = t;
                break;
              }
            }
          }

          if (detected != null && _selectedTank?.id != detected.id) {
            debugPrint('[Chat] Tank detected: ${_selectedTank?.name} → ${detected.name}');
            setState(() => _selectedTank = detected);
            await _loadTankData(detected!);
          }
        } else if (_selectedTank == null && _allTanks.length == 1) {
          setState(() => _selectedTank = _allTanks.first);
        }
        debugPrint('[Chat] After tank detection: _selectedTank=${_selectedTank?.name ?? "NULL"}');

        // Create new tank if AI collected all details
        if (data is Map && data['new_tank'] != null) {
          try {
            final newTankData = Map<String, dynamic>.from(data['new_tank'] as Map);
            await TankStore.instance.addFromParse(parseData: newTankData);
            widget.onLogsChanged();
            // Auto-select the newly created tank
            if (mounted) {
              final updated = TankStore.instance.tanks;
              if (updated.isNotEmpty) {
                final created = updated.lastWhere(
                  (t) => t.name == ((newTankData['tank'] as Map?)?['name'] ?? ''),
                  orElse: () => updated.last,
                );
                setState(() {
                  if (!_allTanks.any((t) => t.id == created.id)) {
                    _allTanks = [..._allTanks, created];
                  }
                  _selectedTank = created;
                });
                _addMessage(_ChatMessage(
                  role: 'assistant',
                  content: '${created.name} has been created and added to your tanks.',
                  newTank: created,
                ));
                await _loadTankData(created);
                _scrollToBottom();
              }
            }
          } catch (_) {}
        }

        // Auto-select tank if still null but only one tank exists
        if (_selectedTank == null && _allTanks.length == 1) {
          setState(() => _selectedTank = _allTanks.first);
          await _loadTankData(_allTanks.first);
        }

        // Add new inhabitants if AI offered and user affirmed
        if (data is Map && data['new_inhabitant'] != null && _selectedTank != null) {
          debugPrint('[Chat/InhabAdd] new_inhabitant payload: ${data['new_inhabitant']}');
          try {
            final inhData = data['new_inhabitant'] as Map<String, dynamic>;
            final inhList = (inhData['inhabitants'] as List?) ?? [];
            final existingInhabs = (await TankStore.instance.inhabitantsFor(_selectedTank!.id))
                .map((i) => i.name.toLowerCase())
                .toSet();
            int added = 0;
            for (final inh in inhList) {
              if (inh is Map && inh['name'] != null) {
                final name = inh['name'].toString();
                final type = inh['type']?.toString() ?? 'fish';
                // Route plants to addPlant instead of addInhabitant
                if (type == 'plant') {
                  await TankStore.instance.addPlant(tankId: _selectedTank!.id, name: name);
                  added++;
                } else if (!existingInhabs.contains(name.toLowerCase())) {
                  await TankStore.instance.addInhabitant(
                    tankId: _selectedTank!.id,
                    name: name,
                    type: type,
                    count: (inh['count'] as num?)?.toInt() ?? 1,
                  );
                  existingInhabs.add(name.toLowerCase());
                  added++;
                } else {
                  debugPrint('[Chat/InhabAdd] skipped duplicate: $name');
                }
              }
            }
            if (added > 0) {
              TankStore.instance.invalidateSummary(_selectedTank!.id);
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
            }
          } catch (e) {
            debugPrint('[Chat/InhabAdd] ERROR: $e');
          }
        }

        // Add new plants if AI offered and user affirmed
        if (data is Map && data['new_plants'] != null && _selectedTank != null) {
          debugPrint('[Chat/PlantAdd] new_plants payload: ${data['new_plants']}');
          try {
            final plantData = data['new_plants'] as Map<String, dynamic>;
            final plantList = (plantData['plants'] as List?) ?? [];
            debugPrint('[Chat/PlantAdd] plantList (${plantList.length}): $plantList');
            final existingPlants = (await TankStore.instance.plantsFor(_selectedTank!.id))
                .map((p) => p.name.toLowerCase())
                .toSet();
            int added = 0;
            for (final plant in plantList) {
              if (plant is String && plant.isNotEmpty && !existingPlants.contains(plant.toLowerCase())) {
                await TankStore.instance.addPlant(
                  tankId: _selectedTank!.id,
                  name: plant,
                );
                existingPlants.add(plant.toLowerCase());
                added++;
              } else {
                debugPrint('[Chat/PlantAdd] skipped (duplicate or invalid): $plant');
              }
            }
            debugPrint('[Chat/PlantAdd] saved $added plants to tank ${_selectedTank!.name}');
            if (added > 0) {
              TankStore.instance.invalidateSummary(_selectedTank!.id);
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
            }
          } catch (e) {
            debugPrint('[Chat/PlantAdd] ERROR: $e');
          }
        } else if (data is Map && data['new_plants'] != null && _selectedTank == null) {
          debugPrint('[Chat/PlantAdd] SKIPPED — new_plants present but _selectedTank is null');
        }

        // Rename a plant if AI confirmed a correction
        if (data is Map && data['rename_plant'] != null && _selectedTank != null) {
          try {
            final renameData = data['rename_plant'] as Map<String, dynamic>;
            final oldName = renameData['old_name']?.toString() ?? '';
            final newName = renameData['new_name']?.toString() ?? '';
            if (oldName.isNotEmpty && newName.isNotEmpty) {
              await TankStore.instance.renamePlant(
                tankId: _selectedTank!.id,
                oldName: oldName,
                newName: newName,
              );
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
            }
          } catch (_) {}
        }

        // Remove inhabitants if AI confirmed removal
        if (data is Map && data['remove_inhabitants'] != null && _selectedTank != null) {
          try {
            final remData = data['remove_inhabitants'] as Map<String, dynamic>;
            final remList = (remData['inhabitants'] as List?) ?? [];
            int removed = 0;
            for (final inh in remList) {
              final name = (inh is Map ? inh['name']?.toString() : inh?.toString()) ?? '';
              if (name.isNotEmpty) {
                await TankStore.instance.removeInhabitant(
                  tankId: _selectedTank!.id,
                  name: name,
                );
                removed++;
              }
            }
            if (removed > 0) {
              TankStore.instance.invalidateSummary(_selectedTank!.id);
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
              debugPrint('[Chat/InhabitantRemove] removed $removed inhabitants');
            }
          } catch (e) {
            debugPrint('[Chat/InhabitantRemove] ERROR: $e');
          }
        }

        // Remove plants if AI confirmed removal
        if (data is Map && data['remove_plants'] != null && _selectedTank != null) {
          try {
            final remData = data['remove_plants'] as Map<String, dynamic>;
            final remList = (remData['plants'] as List?) ?? [];
            int removed = 0;
            for (final plant in remList) {
              if (plant is String && plant.isNotEmpty) {
                await TankStore.instance.removePlant(
                  tankId: _selectedTank!.id,
                  name: plant,
                );
                removed++;
              }
            }
            if (removed > 0) {
              TankStore.instance.invalidateSummary(_selectedTank!.id);
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
              debugPrint('[Chat/PlantRemove] removed $removed plants');
            }
          } catch (e) {
            debugPrint('[Chat/PlantRemove] ERROR: $e');
          }
        }

        // Apply measurement correction if AI confirmed one
        if (data is Map && data['measurement_correction'] != null && _selectedTank != null) {
          try {
            final corr = data['measurement_correction'] as Map<String, dynamic>;
            final corrDate = corr['date']?.toString() ?? '';
            final remove = (corr['remove'] as Map?)?.cast<String, dynamic>() ?? {};
            final add = (corr['add'] as Map?)?.cast<String, dynamic>() ?? {};
            if (corrDate.isNotEmpty && (remove.isNotEmpty || add.isNotEmpty)) {
              debugPrint('[Chat/MeasCorrection] date=$corrDate remove=$remove add=$add');
              // Load existing measurements for this date
              final existing = await TankStore.instance.journalFor(_selectedTank!.id);
              final measEntry = existing.where((e) => e.category == 'measurements' && e.date == corrDate).toList();
              Map<String, dynamic> measurements = {};
              if (measEntry.isNotEmpty) {
                try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
              }
              // Remove specified keys
              for (final key in remove.keys) {
                measurements.remove(key);
              }
              // Add/update specified keys
              for (final entry in add.entries) {
                measurements[entry.key] = entry.value;
              }
              // Save back
              if (measurements.isNotEmpty) {
                await TankStore.instance.upsertJournal(
                  tankId: _selectedTank!.id,
                  date: corrDate,
                  category: 'measurements',
                  data: jsonEncode(measurements),
                );
              } else {
                await TankStore.instance.deleteJournalByKey(_selectedTank!.id, corrDate, 'measurements');
              }
              TankStore.instance.invalidateSummary(_selectedTank!.id);
              await _loadTankData(_selectedTank!);
              if (mounted) widget.onLogsChanged();
              debugPrint('[Chat/MeasCorrection] applied successfully');
            }
          } catch (e) {
            debugPrint('[Chat/MeasCorrection] ERROR: $e');
          }
        }

        // Apply tap water profile updates
        if (data is Map && data['tap_water_update'] != null && _selectedTank != null) {
          try {
            final tapUpdate = data['tap_water_update'] as Map<String, dynamic>;
            if (tapUpdate.isNotEmpty) {
              // Merge with existing tap water profile
              Map<String, dynamic> existing = {};
              if (_tapWaterJson != null) {
                try { existing = Map<String, dynamic>.from(jsonDecode(_tapWaterJson!) as Map); } catch (_) {}
              }
              existing.addAll(tapUpdate);
              final jsonStr = jsonEncode(existing);
              await TankStore.instance.saveTapWater(_selectedTank!.id, jsonStr);
              if (mounted) setState(() => _tapWaterJson = jsonStr);
              debugPrint('[Chat/TapWater] updated: $existing');
            }
          } catch (e) {
            debugPrint('[Chat/TapWater] ERROR: $e');
          }
        }

        // Save any tasks the AI confirmed scheduling
        debugPrint('[Chat] full response: $data');
        final rawTasks = data is Map ? (data['tasks'] as List?)?.cast<Map<String, dynamic>>() : null;
        debugPrint('[Chat] rawTasks: $rawTasks');
        final chatTasks = rawTasks != null ? await _moderateTasks(rawTasks) : null;
        debugPrint('[Chat] chatTasks after moderation: $chatTasks');
        final taskTank = _selectedTank ?? (_allTanks.length == 1 ? _allTanks.first : null);
        debugPrint('[Chat] taskTank: ${taskTank?.name ?? "null"}');
        if (chatTasks != null && chatTasks.isNotEmpty && taskTank == null) {
          // No tank selected yet — buffer tasks until tank is identified
          _pendingTasks.addAll(chatTasks);
          debugPrint('[Chat] Buffered ${chatTasks.length} task(s) — waiting for tank selection');
        }
        if (taskTank != null) {
          // Merge any buffered tasks with current ones
          final allTasks = [..._pendingTasks, ...?chatTasks];
          _pendingTasks = [];
          if (allTasks.isNotEmpty) {
            try {
              for (final task in allTasks) {
                final rd = task['repeat_days'];
                await TankStore.instance.addTask(
                  tankId: taskTank.id,
                  description: (task['description'] ?? '').toString(),
                  dueDate: (task['due_date'] ?? task['due'])?.toString(),
                  priority: (task['priority'] ?? 'normal').toString(),
                  source: rd != null ? 'recurring' : 'ai',
                  repeatDays: rd is int ? rd : (rd is num ? rd.toInt() : null),
                );
              }
            } catch (e) {
              debugPrint('[Chat] addTask error: $e');
            }
            widget.onLogsChanged();
          }
        }
      }
    } catch (e, st) {
      debugPrint('[Chat] error: $e\n$st');
      if (mounted) {
        _addMessage(_ChatMessage(role: 'assistant', content: "Sorry, something went wrong. Please try again."));
      }
    }

    if (mounted) setState(() { _aiResponding = false; _sending = false; });
  }

  Future<List<Map<String, dynamic>>> _moderateTasks(List<Map<String, dynamic>> tasks) async {
    if (tasks.isEmpty) return [];
    try {
      final descriptions = tasks.map((t) => (t['description'] ?? '').toString()).toList();
      final resp = await http.post(
        Uri.parse('$_baseUrl/moderate/tasks'),
        headers: _apiHeaders(),
        body: jsonEncode({'tasks': descriptions}),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final results = (data['results'] as List?)?.cast<bool>() ?? List.filled(tasks.length, true);
        return [
          for (int i = 0; i < tasks.length; i++)
            if (i < results.length && results[i]) tasks[i],
        ];
      }
    } catch (_) {}
    return tasks; // fail open on error
  }

  static List<String> _observationAlerts(String text) {
    final t = text.toLowerCase();
    final alerts = <String>[];
    if (RegExp(r'\balga[e]?\b').hasMatch(t)) {
      alerts.add('Algae observed — consider water change or adjusting light duration');
    }
    if (RegExp(r'(leaves?|plant).{0,20}(dying|dead|yellow|brown|rot)|(dying|dead|yellow|brown|rot).{0,20}(leaves?|plant)').hasMatch(t)) {
      alerts.add('Plant health issue — leaves dying or discolored, check nutrients and lighting');
    }
    if (RegExp(r'(fish|shrimp|snail|coral|inhabitant).{0,20}(sick|ill|dying|dead|lethargic|stress)|(sick|ill|dying|dead|lethargic|stress).{0,20}(fish|shrimp|snail|coral|inhabitant)').hasMatch(t)) {
      alerts.add('Inhabitant health concern — monitor closely and check water parameters');
    }
    if (RegExp(r'\b(cloudy|murky|brown|yellow|green|hazy|milky|foamy)\b').hasMatch(t) &&
        !RegExp(r'(leaves?|plant|fish|shrimp|coral).{0,15}(brown|yellow|green)').hasMatch(t)) {
      alerts.add('Water clarity issue — water appears discolored or cloudy');
    }
    if (RegExp(r'\b(white\s*spot|ich|ick|velvet|fungus|disease)\b').hasMatch(t)) {
      alerts.add('Possible disease detected — consider treatment and quarantine');
    }
    if (RegExp(r'\b(smell|odor|smells|stink|stinking)\b').hasMatch(t)) {
      alerts.add('Water odor detected — check filtration and substrate');
    }
    if (RegExp(r'\b(fin\s*rot|torn\s*fin|damaged\s*fin)\b').hasMatch(t)) {
      alerts.add('Fin damage observed — check for aggression or infection');
    }
    return alerts;
  }

  Widget _bubble(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: 4, bottom: 4, left: isUser ? 56 : 0, right: isUser ? 0 : 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? _cDark : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 12),
          ),
          border: isUser ? null : Border.all(color: Colors.grey.shade300, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser)
              Text(msg.content,
                  style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4))
            else
              MarkdownBody(
                data: msg.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
                  strong: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold, height: 1.4),
                  em: const TextStyle(fontSize: 15, color: Colors.black87, fontStyle: FontStyle.italic, height: 1.4),
                  listBullet: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
                  blockSpacing: 8,
                ),
              ),
            if (msg.newTank != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TankJournalScreen(tank: msg.newTank!)),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text('View ${msg.newTank!.name}'),
                style: TextButton.styleFrom(
                  foregroundColor: _cDark,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: _cMid, width: 1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // System navigation bar height (back/home buttons on Android).
    // viewPadding gives the persistent inset regardless of keyboard state.
    final navBarHeight = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      // Lifts the entire sheet above the keyboard when it opens.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 8) Navigator.of(context).pop();
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Column(
          children: [
            // drag handle + title
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 18, color: _cMid),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('AI Assistant',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (_chatMessages.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _ChatCache.clear(_cacheKey);
                            setState(() {
                              _chatMessages = [
                                _ChatMessage(role: 'assistant', content: 'Hey! I\'m Ariel — ask me anything about your tanks or log an entry.'),
                              ];
                              // Reset tank selection so the next conversation starts fresh
                              // (only for home-page chat where no tank was pre-selected)
                              if (widget.initialTank == null) {
                                _selectedTank = null;
                                _cacheKey = null;
                              }
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Text('Clear', style: TextStyle(fontSize: 13, color: Color(0xFF757575))),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.keyboard_arrow_down, size: 24, color: Color(0xFF757575)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // messages
            Expanded(
              child: _chatMessages.isEmpty && !_aiResponding
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 36, color: _cMid.withOpacity(0.35)),
                            const SizedBox(height: 16),
                            Text(
                              'Ask me a question,\nlog activity,\ntell me what you see.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: Colors.black.withOpacity(0.35),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _chatMessages.length + (_aiResponding ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i < _chatMessages.length) return _bubble(_chatMessages[i]);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 4, right: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300, width: 0.5),
                      ),
                      child: const SizedBox(
                          width: 32, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                },
              ),
            ),
            // input bar
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
                            if (!_sending) _submit();
                          },
                        },
                        child: TextField(
                          controller: _inputController,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          autofocus: false,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            hintText: 'Log, ask, or schedule a task…',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(24)),
                              borderSide: BorderSide(color: _cMid, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(24)),
                              borderSide: BorderSide(color: _cMid, width: 2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(24)),
                              borderSide: BorderSide(color: _cDark, width: 2.5),
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton.filled(
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: _aiResponding ? Colors.red.shade600 : _cDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _aiResponding ? _cancelResponse : (_sending ? null : _submit),
                        icon: _aiResponding
                            ? const Icon(Icons.stop_rounded, size: 20)
                            : _sending
                                ? const SizedBox(
                                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'AI-generated content may be inaccurate. Always consult a professional.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Colors.black38),
                  ),
                ),
                ColoredBox(
                  color: const Color(0xFF26A7BA),
                  child: SizedBox(height: navBarHeight, width: double.infinity),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ── Add Measurement Sheet ────────────────────────────────────────────────────

class _AddMeasurementSheet extends StatefulWidget {
  final String tankName;
  const _AddMeasurementSheet({required this.tankName});
  @override
  State<_AddMeasurementSheet> createState() => _AddMeasurementSheetState();
}

class _AddMeasurementSheetState extends State<_AddMeasurementSheet> {
  List<(String key, TextEditingController ctrl)> _measurements = [
    ('ph', TextEditingController()),
  ];
  bool _saving = false;
  late DateTime _selectedDate = DateTime.now();

  static const _knownParamKeys = [
    'ph', 'kh', 'gh', 'calcium', 'magnesium', 'ammonia', 'nitrite', 'nitrate',
    'potassium', 'salinity', 'temp', 'phosphate', 'co2', 'iron', 'copper', 'tds',
  ];

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  void dispose() {
    for (final e in _measurements) e.$2.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final measurements = <String, dynamic>{};
    for (final (key, ctrl) in _measurements) {
      final k = key.trim();
      final v = ctrl.text.trim();
      if (k.isEmpty || v.isEmpty) continue;
      measurements[k] = double.tryParse(v) ?? v;
    }
    Navigator.pop(context, (measurements: measurements, date: _dateKey(_selectedDate)));
  }

  Widget _sectionHeader(String title, IconData icon) => Row(children: [
    Icon(icon, size: 14, color: Colors.black87),
    const SizedBox(width: 4),
    Text(title.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87, letterSpacing: 0.8)),
  ]);

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).viewPadding.top;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - topPad - 16),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).viewPadding.top + 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Add Measurement — ${widget.tankName}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: _cMid),
                  child: const Text('Save'),
                ),
              ]),
              const Divider(height: 24),

            GestureDetector(
              onTap: _pickDate,
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDate.month.toString().padLeft(2,'0')}/${_selectedDate.day.toString().padLeft(2,'0')}/${_selectedDate.year}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black54),
                if (_dateKey(_selectedDate) == _dateKey(DateTime.now()))
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('Today', style: TextStyle(fontSize: 12, color: Colors.black45)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),

            _sectionHeader('Measurements', Icons.straighten),
            const SizedBox(height: 8),
            ..._measurements.asMap().entries.map((entry) {
              final idx = entry.key;
              final (key, ctrl) = entry.value;
              final dropdownKey = _knownParamKeys.contains(key.toLowerCase()) ? key.toLowerCase() : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: dropdownKey,
                      hint: Text(_paramShortLabel(key), style: const TextStyle(fontSize: 12)),
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _knownParamKeys.map((p) =>
                          DropdownMenuItem(value: p, child: Text(_paramDisplayNames[p] ?? p, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _measurements[idx] = (v, ctrl));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Value',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.grey,
                    onPressed: () => setState(() { entry.value.$2.dispose(); _measurements.removeAt(idx); }),
                  ),
                ]),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _measurements.add(('ph', TextEditingController()))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add measurement', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Structured log editor ───────────────────────────────────────────────────

class _LogEditSheet extends StatefulWidget {
  final Map<String, dynamic> parsed;
  final String rawText;
  final Future<void> Function(String rawText, String parsedJson) onSave;

  const _LogEditSheet({required this.parsed, required this.rawText, required this.onSave});

  @override
  State<_LogEditSheet> createState() => _LogEditSheetState();
}

class _LogEditSheetState extends State<_LogEditSheet> {
  late List<(String key, TextEditingController ctrl)> _measurements;
  late List<TextEditingController> _actions;
  late List<TextEditingController> _notes;
  bool _saving = false;

  static const _knownParamKeys = [
    'ph', 'kh', 'gh', 'calcium', 'magnesium', 'ammonia', 'nitrite', 'nitrate', 'potassium', 'salinity', 'temp', 'phosphate', 'co2',
  ];

  @override
  void initState() {
    super.initState();
    final m = (widget.parsed['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
    _measurements = m.entries.map((e) => (e.key, TextEditingController(text: e.value.toString()))).toList();
    final acts = (widget.parsed['actions'] as List?)?.cast<String>() ?? [];
    _actions = acts.map((a) => TextEditingController(text: a)).toList();
    final nts = (widget.parsed['notes'] as List?)?.cast<String>() ?? [];
    _notes = nts.map((n) => TextEditingController(text: n)).toList();
  }

  @override
  void dispose() {
    for (final e in _measurements) e.$2.dispose();
    for (final c in _actions) c.dispose();
    for (final c in _notes) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 50));
    setState(() => _saving = true);
    try {
      final measurements = <String, dynamic>{};
      for (final (key, ctrl) in _measurements) {
        final k = key.trim();
        final v = ctrl.text.trim();
        if (k.isEmpty || v.isEmpty) continue;
        measurements[k] = double.tryParse(v) ?? v;
      }
      final acts = _actions.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      final nts = _notes.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      final newParsed = Map<String, dynamic>.from(widget.parsed)
        ..['measurements'] = measurements
        ..['actions'] = acts
        ..['notes'] = nts;
      await widget.onSave(widget.rawText, jsonEncode(newParsed));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _sectionHeader(String title, IconData icon) => Row(children: [
    Icon(icon, size: 14, color: Colors.black87),
    const SizedBox(width: 4),
    Text(title.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87, letterSpacing: 0.8)),
  ]);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.only(top: 26),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('Edit Journal Entry', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: _cMid),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ]),
            const Divider(height: 24),

            // Measurements
            _sectionHeader('Measurements', Icons.straighten),
            const SizedBox(height: 8),
            ..._measurements.asMap().entries.map((entry) {
              final idx = entry.key;
              final (key, ctrl) = entry.value;
              final dropdownKey = _knownParamKeys.contains(key.toLowerCase()) ? key.toLowerCase() : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: dropdownKey,
                      hint: Text(_paramShortLabel(key), style: const TextStyle(fontSize: 12)),
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _knownParamKeys.map((p) =>
                          DropdownMenuItem(value: p, child: Text(_paramDisplayNames[p] ?? p, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _measurements[idx] = (v, ctrl));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Value',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.grey,
                    onPressed: () => setState(() { entry.value.$2.dispose(); _measurements.removeAt(idx); }),
                  ),
                ]),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _measurements.add(('ph', TextEditingController()))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add measurement', style: TextStyle(fontSize: 13)),
            ),

            const Divider(height: 24),

            // Actions
            _sectionHeader('Actions', Icons.check_circle_outline),
            const SizedBox(height: 8),
            ..._actions.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: entry.value,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.grey,
                  onPressed: () => setState(() { entry.value.dispose(); _actions.removeAt(entry.key); }),
                ),
              ]),
            )),
            TextButton.icon(
              onPressed: () => setState(() => _actions.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add action', style: TextStyle(fontSize: 13)),
            ),

            const Divider(height: 24),

            // Notes
            _sectionHeader('Notes', Icons.notes),
            const SizedBox(height: 8),
            ..._notes.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: entry.value,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.grey,
                  onPressed: () => setState(() { entry.value.dispose(); _notes.removeAt(entry.key); }),
                ),
              ]),
            )),
            TextButton.icon(
              onPressed: () => setState(() => _notes.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add note', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Log entry card ───────────────────────────────────────────────────────────

class _LogEntryCard extends StatefulWidget {
  final db.Log log;
  final Map<String, dynamic>? parsed;
  final VoidCallback onDelete;
  final Future<void> Function(String rawText, String parsedJson) onEdit;

  const _LogEntryCard({required this.log, required this.parsed, required this.onDelete, required this.onEdit});

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _showRaw = false;

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsed;
    final log = widget.log;
    final params = (parsed?['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
    final actions = ((parsed?['actions'] as List?) ?? []).map((e) => e.toString()).toList();
    final notes = ((parsed?['notes'] as List?) ?? []).map((e) => e.toString()).toList();
    final tasks = ((parsed?['tasks'] as List?) ?? []).cast<Map<String, dynamic>>();
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _cLight, width: 1),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 36, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Raw text
            if (_showRaw) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _cBeige,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  log.rawText,
                  style: const TextStyle(fontSize: 12, color: _cDark, height: 1.5),
                ),
              ),
            ],
            // Measurements
            if (params.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    parsed?['source'] == 'tap_water' ? Icons.water_drop_outlined : Icons.straighten,
                    size: 15, color: Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    parsed?['source'] == 'tap_water' ? 'TAP WATER' : 'MEASUREMENTS',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Colors.black, letterSpacing: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: params.entries.map((e) {
                  final canonical = _paramAliases[e.key.toLowerCase()];
                  final bgColor = (canonical != null ? _paramColors[canonical] : null) ?? _cMint;
                  final textColor = bgColor.computeLuminance() < 0.35 ? Colors.white : Colors.black;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${e.key} ',
                            style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.85), fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: '${e.value}',
                            style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            // Actions
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 15, color: Colors.black87),
                  SizedBox(width: 4),
                  Text('ACTIONS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: Colors.black, letterSpacing: 0.8)),
                ],
              ),
              const SizedBox(height: 6),
              ...actions.map((a) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: _Dot(color: _cMid),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(a, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
            ],
            // Notes
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.notes, size: 15, color: Colors.black87),
                  SizedBox(width: 4),
                  Text('NOTES',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: Colors.black, letterSpacing: 0.8)),
                ],
              ),
              const SizedBox(height: 6),
              ...notes.map((n) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: _Dot(color: _cLight),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(n, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
            ],
            // Tasks
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.task_alt, size: 15, color: Colors.black87),
                  SizedBox(width: 4),
                  Text('TASKS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: Colors.black, letterSpacing: 0.8)),
                ],
              ),
              const SizedBox(height: 6),
              ...tasks.map((t) {
                final desc = (t['description'] ?? '').toString();
                final due = (t['due_date'] ?? t['due'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: _Dot(color: Colors.orange),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        due.isNotEmpty ? '$desc (due $due)' : desc,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      )),
                    ],
                  ),
                );
              }),
            ],
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              iconSize: 18,
              padding: EdgeInsets.zero,
              iconColor: _cMid,
              onSelected: (value) async {
                if (value == 'original') setState(() => _showRaw = !_showRaw);
                if (value == 'delete') widget.onDelete();
                if (value == 'edit') {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _LogEditSheet(
                      parsed: widget.parsed ?? {},
                      rawText: widget.log.rawText,
                      onSave: widget.onEdit,
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'original',
                  child: Text(_showRaw ? 'Hide original' : 'Original text'),
                ),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Merged day card — consolidates all logs from one day ─────────────────────

class _JournalDayCard extends StatelessWidget {
  final String tankId;
  final String date;
  final List<db.JournalEntry> entries;
  final Future<void> Function() onChanged;

  const _JournalDayCard({
    required this.tankId,
    required this.date,
    required this.entries,
    required this.onChanged,
  });

  Map<String, dynamic> _measurements() {
    final e = entries.where((e) => e.category == 'measurements').toList();
    if (e.isEmpty) return {};
    try { return Map<String, dynamic>.from(jsonDecode(e.first.data) as Map); } catch (_) { return {}; }
  }

  List<String> _actions() {
    final e = entries.where((e) => e.category == 'actions').toList();
    if (e.isEmpty) return [];
    try { return (jsonDecode(e.first.data) as List).cast<String>(); } catch (_) { return []; }
  }

  List<String> _notes() {
    final e = entries.where((e) => e.category == 'notes').toList();
    if (e.isEmpty) return [];
    try { return (jsonDecode(e.first.data) as List).cast<String>(); } catch (_) { return []; }
  }

  /// Save edits back to journal entries.
  Future<void> _saveEdits(String rawText, String parsedJson) async {
    try {
      final parsed = jsonDecode(parsedJson) as Map<String, dynamic>;
      final measurements = (parsed['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
      final actions = ((parsed['actions'] as List?) ?? []).cast<String>();
      final notes = ((parsed['notes'] as List?) ?? []).cast<String>();

      if (measurements.isNotEmpty) {
        await TankStore.instance.upsertJournal(
          tankId: tankId, date: date, category: 'measurements', data: jsonEncode(measurements),
        );
      } else {
        await TankStore.instance.deleteJournalByKey(tankId, date, 'measurements');
      }
      if (actions.isNotEmpty) {
        await TankStore.instance.upsertJournal(
          tankId: tankId, date: date, category: 'actions', data: jsonEncode(actions),
        );
      } else {
        await TankStore.instance.deleteJournalByKey(tankId, date, 'actions');
      }
      if (notes.isNotEmpty) {
        await TankStore.instance.upsertJournal(
          tankId: tankId, date: date, category: 'notes', data: jsonEncode(notes),
        );
      } else {
        await TankStore.instance.deleteJournalByKey(tankId, date, 'notes');
      }
    } catch (_) {}
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final params = _measurements();
    final acts = _actions();
    final nts = _notes();

    final hasContent = params.isNotEmpty || acts.isNotEmpty || nts.isNotEmpty;
    if (!hasContent) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _cLight, width: 1),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 36, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Measurements
                if (params.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.straighten, size: 15, color: Colors.black87),
                      SizedBox(width: 4),
                      Text('MEASUREMENTS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: Colors.black, letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: params.entries.map((e) {
                      final canonical = _paramAliases[e.key.toLowerCase()];
                      final bgColor = (canonical != null ? _paramColors[canonical] : null) ?? _cMint;
                      final textColor = bgColor.computeLuminance() < 0.35 ? Colors.white : Colors.black;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${e.key} ',
                                style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.85), fontWeight: FontWeight.w600),
                              ),
                              TextSpan(
                                text: '${e.value}',
                                style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // Actions
                if (acts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 15, color: Colors.black87),
                      SizedBox(width: 4),
                      Text('ACTIONS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                              color: Colors.black, letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...acts.map((a) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: _Dot(color: _cMid),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a, style: const TextStyle(fontSize: 13, height: 1.4))),
                      ],
                    ),
                  )),
                ],
                // Notes
                if (nts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.notes, size: 15, color: Colors.black87),
                      SizedBox(width: 4),
                      Text('NOTES',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                              color: Colors.black, letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...nts.map((n) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: _Dot(color: _cLight),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(n, style: const TextStyle(fontSize: 13, height: 1.4))),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              iconSize: 18,
              padding: EdgeInsets.zero,
              iconColor: _cMid,
              onSelected: (value) async {
                if (value == 'edit') {
                  final editParsed = <String, dynamic>{
                    'measurements': params,
                    'actions': acts,
                    'notes': nts,
                  };
                  final saved = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _LogEditSheet(
                      parsed: editParsed,
                      rawText: '',
                      onSave: _saveEdits,
                    ),
                  );
                  if (saved == true && context.mounted) {
                    _showTopSnack(context, 'Journal updated');
                  }
                }
                if (value == 'delete') {
                  for (final entry in entries) {
                    await TankStore.instance.deleteJournalEntry(entry.id);
                  }
                  await onChanged();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _cDark),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 11, color: _cDark, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 5, height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class TankDetailScreen extends StatefulWidget {
  final TankModel tank;

  const TankDetailScreen({super.key, required this.tank});

  @override
  State<TankDetailScreen> createState() => _TankDetailScreenState();
}

class _TankDetailScreenState extends State<TankDetailScreen> {
  List<db.Inhabitant> _inhabitants = [];
  List<db.Plant> _plants = [];
  String? _tapWaterJson;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inhabitants = await TankStore.instance.inhabitantsFor(widget.tank.id);
    final plants = await TankStore.instance.plantsFor(widget.tank.id);
    final tapWaterJson = await TankStore.instance.tapWaterJsonFor(widget.tank.id);
    if (!mounted) return;
    setState(() {
      _inhabitants = inhabitants;
      _plants = plants;
      _tapWaterJson = tapWaterJson;
      _loading = false;
    });
  }

  Future<void> _editTapWater() async {
    final existing = _tapWaterJson != null
        ? Map<String, dynamic>.from(jsonDecode(_tapWaterJson!) as Map)
        : <String, dynamic>{};

    final keys   = ['ph', 'gh', 'kh', 'ammonia', 'nitrite', 'nitrate', 'potassium', 'calcium', 'tds'];
    final fields = keys.map((k) => _paramDisplayNames[k] ?? k).toList();
    final controllers = List.generate(
      fields.length,
      (i) => TextEditingController(
        text: existing[keys[i]] != null ? '${existing[keys[i]]}' : '',
      ),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tap Water Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your tap water test results. Ariel will use these when advising on adjustments.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...List.generate(fields.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[i],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: fields[i],
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('__clear__'),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final data = <String, dynamic>{};
              for (int i = 0; i < fields.length; i++) {
                final v = controllers[i].text.trim();
                if (v.isNotEmpty) {
                  final n = num.tryParse(v);
                  if (n != null) data[keys[i]] = n;
                }
              }
              final jsonStr = data.isNotEmpty ? jsonEncode(data) : null;
              Navigator.of(ctx).pop(jsonStr ?? '__clear__');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final c in controllers) c.dispose();

    if (result != null && mounted) {
      final newJson = result == '__clear__' ? null : result;
      await TankStore.instance.saveTapWater(widget.tank.id, newJson);
      if (mounted) setState(() => _tapWaterJson = newJson);
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditTankFlowScreen(tank: widget.tank)),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  static const _typeOrder = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeLabels = {
    'fish': 'Fish',
    'invertebrate': 'Invertebrates',
    'coral': 'Coral',
    'polyp': 'Polyps',
    'anemone': 'Anemones',
  };
  static const _typeEmoji = {
    'fish': '🐟',
    'invertebrate': '🦐',
    'coral': '🪸',
    'polyp': '🪼',
    'anemone': '🌺',
    'plant': '🌿',
  };

  Widget _sectionHeader(String label, String emoji) => Row(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
    ],
  );

  Widget _inhabitantTile(String name, int? count, String emoji) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        const SizedBox(width: 4),
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
        if (count != null)
          Text('×$count', style: const TextStyle(fontSize: 12, color: _cDark, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  List<Widget> _buildInhabitantGroups() {
    if (_inhabitants.isEmpty) return [];
    final byType = <String, List<db.Inhabitant>>{};
    for (final i in _inhabitants) {
      final t = i.type ?? 'fish';
      byType.putIfAbsent(t, () => []).add(i);
    }
    final widgets = <Widget>[];
    bool first = true;
    for (final type in _typeOrder) {
      final group = byType[type];
      if (group == null || group.isEmpty) continue;
      final emoji = _typeEmoji[type] ?? '🐠';
      if (!first) widgets.add(const SizedBox(height: 16));
      first = false;
      widgets.add(_sectionHeader(_typeLabels[type] ?? type, emoji));
      widgets.add(const SizedBox(height: 6));
      for (final i in group) {
        widgets.add(_inhabitantTile(i.name, i.count, emoji));
      }
    }
    // Anything with an unknown/null type that didn't match order
    final unknown = _inhabitants.where((i) => !_typeOrder.contains(i.type ?? 'fish')).toList();
    if (unknown.isNotEmpty) {
      if (!first) widgets.add(const SizedBox(height: 16));
      widgets.add(_sectionHeader('Other', '🐠'));
      widgets.add(const SizedBox(height: 6));
      for (final i in unknown) {
        widgets.add(_inhabitantTile(i.name, i.count, '🐠'));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, '', actions: [
          IconButton(
            tooltip: 'Photos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TankGalleryScreen(tank: widget.tank)),
            ),
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: _openEdit,
            icon: const Icon(Icons.edit),
          ),
        ]),
      bottomNavigationBar: _AquariaFooter(
        onAiTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChatSheet(
            initialTank: widget.tank,
            allTanks: TankStore.instance.tanks,
            onLogsChanged: _load,
          ),
        ).then((_) => _load()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              widget.tank.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            ),
          ),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tank.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text('${widget.tank.gallons} gallons'),
                        Text('Water type: ${widget.tank.waterType.label}'),
                        const SizedBox(height: 4),
                        Text(
                          'Created: ${widget.tank.createdAt.toLocal().toString().split('.').first}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _TapWaterCard(
                  tapWaterJson: _tapWaterJson,
                  onEdit: _editTapWater,
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tap Water Profile Card
// ─────────────────────────────────────────────
class _TapWaterCard extends StatelessWidget {
  final String? tapWaterJson;
  final VoidCallback onEdit;
  const _TapWaterCard({required this.tapWaterJson, required this.onEdit});

  static String _fieldLabel(String key) => _paramDisplayNames[key.toLowerCase()] ?? key;

  @override
  Widget build(BuildContext context) {
    final data = tapWaterJson != null
        ? Map<String, dynamic>.from(jsonDecode(tapWaterJson!) as Map)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop_outlined, size: 18, color: _cDark),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Tap Water Profile',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: data == null ? 'Add tap water results' : 'Edit tap water results',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (data == null || data.isEmpty)
              const Text(
                'Add your tap water test results so Ariel can account for them when advising on water adjustments.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final entry in data.entries)
                    _TapWaterChip(
                      label: _fieldLabel(entry.key),
                      value: entry.value,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TapWaterChip extends StatelessWidget {
  final String label;
  final dynamic value;
  const _TapWaterChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _cMint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(text: '$label  ', style: const TextStyle(color: Colors.black54)),
            TextSpan(text: '$value', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tap Water Profile Screen
// ─────────────────────────────────────────────
class TapWaterProfileScreen extends StatefulWidget {
  final TankModel tank;
  const TapWaterProfileScreen({super.key, required this.tank});
  @override
  State<TapWaterProfileScreen> createState() => _TapWaterProfileScreenState();
}

class _TapWaterProfileScreenState extends State<TapWaterProfileScreen> {
  static const _keys = ['ph', 'gh', 'kh', 'ammonia', 'nitrite', 'nitrate', 'potassium', 'calcium', 'tds'];
  static List<String> get _fields => _keys.map((k) => _paramDisplayNames[k] ?? k).toList();

  String? _tapWaterJson;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    TankStore.instance.tapWaterJsonFor(widget.tank.id).then((v) {
      if (mounted) setState(() { _tapWaterJson = v; _loading = false; });
    });
  }

  Map<String, dynamic> get _data => _tapWaterJson != null
      ? Map<String, dynamic>.from(jsonDecode(_tapWaterJson!) as Map)
      : {};

  Future<void> _edit() async {
    final existing = _data;
    final controllers = List.generate(
      _fields.length,
      (i) => TextEditingController(text: existing[_keys[i]] != null ? '${existing[_keys[i]]}' : ''),
    );
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tap Water Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your tap water test results. Ariel will use these when advising on adjustments.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...List.generate(_fields.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[i],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _fields[i],
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('__clear__'),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final data = <String, dynamic>{};
              for (int i = 0; i < _fields.length; i++) {
                final v = controllers[i].text.trim();
                if (v.isNotEmpty) {
                  final n = num.tryParse(v);
                  if (n != null) data[_keys[i]] = n;
                }
              }
              final jsonStr = data.isNotEmpty ? jsonEncode(data) : null;
              Navigator.of(ctx).pop(jsonStr ?? '__clear__');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final c in controllers) c.dispose();
    if (result != null && mounted) {
      final newJson = result == '__clear__' ? null : result;
      await TankStore.instance.saveTapWater(widget.tank.id, newJson);
      if (mounted) setState(() => _tapWaterJson = newJson);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, '', actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: _loading ? null : _edit,
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Tap Water Profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your tap water chemistry — Ariel uses this when advising on water adjustments.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: List.generate(_fields.length, (i) {
                      final key = _keys[i];
                      final val = data[key];
                      return ListTile(
                        title: Text(_fields[i], style: const TextStyle(fontWeight: FontWeight.w500)),
                        trailing: val != null
                            ? Text(
                                '$val',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _cDark),
                              )
                            : const Text('—', style: TextStyle(color: Colors.grey)),
                        dense: true,
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Inhabitants Screen
// ─────────────────────────────────────────────
class InhabitantsScreen extends StatefulWidget {
  final TankModel tank;
  const InhabitantsScreen({super.key, required this.tank});
  @override
  State<InhabitantsScreen> createState() => _InhabitantsScreenState();
}

class _InhabitantsScreenState extends State<InhabitantsScreen> {
  List<db.Inhabitant> _inhabitants = [];
  List<db.Plant> _plants = [];
  bool _loading = true;

  static const _typeOrder = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeLabels = {'fish': 'Fish', 'invertebrate': 'Invertebrates', 'coral': 'Coral', 'polyp': 'Polyps', 'anemone': 'Anemones'};
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺', 'plant': '🌿'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inhabitants = await TankStore.instance.inhabitantsFor(widget.tank.id);
    final plants = await TankStore.instance.plantsFor(widget.tank.id);
    if (!mounted) return;
    setState(() { _inhabitants = inhabitants; _plants = plants; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, ''),
      bottomNavigationBar: _AquariaFooter(
        onAiTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChatSheet(
            initialTank: widget.tank,
            allTanks: TankStore.instance.tanks,
            onLogsChanged: _load,
          ),
        ).then((_) => _load()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.tank.name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20, color: _cMid),
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EditInhabitantsScreen(
                              tank: widget.tank,
                              onSaved: _load,
                            ),
                          ));
                        },
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Inhabitants', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: (_inhabitants.isEmpty && _plants.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No inhabitants logged yet.', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit Inhabitants'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _cDark,
                            side: const BorderSide(color: _cMid),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                          ),
                          onPressed: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => EditInhabitantsScreen(
                                tank: widget.tank,
                                onSaved: _load,
                              ),
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    ..._buildGroups(),
                    if (_plants.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Row(children: [Text('🌿', style: TextStyle(fontSize: 15)), SizedBox(width: 6), Text('Plants', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))]),
                      const SizedBox(height: 6),
                      ..._plants.map((p) => _tile(_titleCase(p.name), null, '🌿')),
                    ],
                    ..._buildWarnings(),
                  ],
                ),
                ),
                ),
              ],
            ),
    );
  }

  List<Widget> _buildWarnings() {
    if (_inhabitants.isEmpty) return [];
    final mapped = _inhabitants.map((i) => (
      name: i.name,
      type: i.type ?? 'fish',
      count: i.count,
    )).toList();
    final warnings = _compatibilityWarnings(mapped, widget.tank.waterType, plants: _plants.map((p) => p.name).toList());
    if (warnings.isEmpty) return [];
    return [
      const SizedBox(height: 16),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Compatibility Notes',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54, letterSpacing: 0.3)),
      ),
      ...warnings.map((w) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: w.icon == '🚨' ? const Color(0xFFFFEBEE) : const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: w.icon == '🚨' ? Colors.red.shade200 : Colors.orange.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(w.message,
                style: TextStyle(fontSize: 13, color: w.icon == '🚨' ? Colors.red.shade800 : Colors.orange.shade900, height: 1.4))),
          ],
        ),
      )),
    ];
  }

  List<Widget> _buildGroups() {
    final byType = <String, List<db.Inhabitant>>{};
    for (final i in _inhabitants) { byType.putIfAbsent(i.type ?? 'fish', () => []).add(i); }
    final widgets = <Widget>[];
    bool first = true;
    for (final type in _typeOrder) {
      final group = byType[type];
      if (group == null || group.isEmpty) continue;
      final emoji = _typeEmoji[type] ?? '🐠';
      if (!first) widgets.add(const SizedBox(height: 16));
      first = false;
      widgets.add(Row(children: [Text(emoji, style: const TextStyle(fontSize: 15)), const SizedBox(width: 6), Text(_typeLabels[type] ?? type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))]));
      widgets.add(const SizedBox(height: 6));
      for (final i in group) { widgets.add(_tile(_titleCase(i.name), i.count, emoji)); }
    }
    return widgets;
  }

  Widget _tile(String name, int? count, String emoji) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      const SizedBox(width: 4),
      Text(emoji, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
      if (count != null) Text('×$count', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _cDark)),
    ]),
  );
}

// ─────────────────────────────────────────────
// Edit Inhabitants Sheet
// ─────────────────────────────────────────────
class _InhEdit {
  final TextEditingController name;
  String type;
  int count;
  _InhEdit({required String nameText, required this.type, required this.count})
      : name = TextEditingController(text: nameText);
  void dispose() => name.dispose();
}

class _PlantEdit {
  final TextEditingController name;
  _PlantEdit({required String nameText}) : name = TextEditingController(text: nameText);
  void dispose() => name.dispose();
}

// ── Species catalogue ────────────────────────────────────────────────────────

class _Species {
  final String name;
  final String type; // matches _types keys
  const _Species(this.name, this.type);
}

const _kInhabitantCatalogue = <String, List<_Species>>{
  'Freshwater Fish': [
    _Species('Betta', 'fish'), _Species('Neon Tetra', 'fish'), _Species('Cardinal Tetra', 'fish'),
    _Species('Guppy', 'fish'), _Species('Molly', 'fish'), _Species('Platy', 'fish'),
    _Species('Swordtail', 'fish'), _Species('Angelfish', 'fish'), _Species('Discus', 'fish'),
    _Species('Oscar', 'fish'), _Species('Corydoras', 'fish'), _Species('Panda Corydoras', 'fish'),
    _Species('Plecostomus', 'fish'), _Species('Bristlenose Pleco', 'fish'), _Species('Otocinclus', 'fish'),
    _Species('Clown Loach', 'fish'), _Species('Kuhli Loach', 'fish'), _Species('Dojo Loach', 'fish'),
    _Species('Zebra Danio', 'fish'), _Species('Pearl Danio', 'fish'), _Species('Harlequin Rasbora', 'fish'),
    _Species('Chili Rasbora', 'fish'), _Species('White Cloud Minnow', 'fish'), _Species('Goldfish', 'fish'),
    _Species('Koi', 'fish'), _Species('Boesemani Rainbowfish', 'fish'), _Species('Killifish', 'fish'),
    _Species('Dwarf Gourami', 'fish'), _Species('Pearl Gourami', 'fish'), _Species('Honey Gourami', 'fish'),
    _Species('Rummy Nose Tetra', 'fish'), _Species('Black Skirt Tetra', 'fish'), _Species('Ember Tetra', 'fish'),
    _Species('Cherry Barb', 'fish'), _Species('Tiger Barb', 'fish'), _Species('African Cichlid', 'fish'),
    _Species('Ram Cichlid', 'fish'), _Species('Apistogramma', 'fish'), _Species('Flowerhorn', 'fish'),
    _Species('Electric Yellow Cichlid', 'fish'), _Species('Endler\'s Livebearer', 'fish'),
    _Species('Peacock Gudgeon', 'fish'), _Species('Scarlet Badis', 'fish'),
    _Species('GloFish Tetra', 'fish'), _Species('GloFish Danio', 'fish'),
    _Species('GloFish Barb', 'fish'), _Species('GloFish Shark', 'fish'),
    _Species('GloFish Betta', 'fish'),
  ],
  'Saltwater Fish': [
    _Species('Ocellaris Clownfish', 'fish'), _Species('Percula Clownfish', 'fish'),
    _Species('Blue Tang', 'fish'), _Species('Yellow Tang', 'fish'), _Species('Hippo Tang', 'fish'),
    _Species('Green Chromis', 'fish'), _Species('Blue Damselfish', 'fish'), _Species('Royal Gramma', 'fish'),
    _Species('Firefish Goby', 'fish'), _Species('Mandarin Dragonet', 'fish'), _Species('Tailspot Blenny', 'fish'),
    _Species('Lawnmower Blenny', 'fish'), _Species('Watchman Goby', 'fish'), _Species('Hawkfish', 'fish'),
    _Species('Anthias', 'fish'), _Species('Sixline Wrasse', 'fish'), _Species('Cleaner Wrasse', 'fish'),
    _Species('Flame Angelfish', 'fish'), _Species('Coral Beauty', 'fish'), _Species('Foxface Rabbitfish', 'fish'),
    _Species('Neon Dottyback', 'fish'), _Species('Lemonpeel Angelfish', 'fish'),
  ],
  'Shrimp & Invertebrates': [
    _Species('Cherry Shrimp', 'invertebrate'), _Species('Amano Shrimp', 'invertebrate'),
    _Species('Ghost Shrimp', 'invertebrate'), _Species('Blue Velvet Shrimp', 'invertebrate'),
    _Species('Crystal Red Shrimp', 'invertebrate'), _Species('Blue Dream Shrimp', 'invertebrate'),
    _Species('Tiger Shrimp', 'invertebrate'), _Species('Bamboo Shrimp', 'invertebrate'),
    _Species('Vampire Shrimp', 'invertebrate'), _Species('Cleaner Shrimp', 'invertebrate'),
    _Species('Fire Shrimp', 'invertebrate'), _Species('Pistol Shrimp', 'invertebrate'),
    _Species('Peppermint Shrimp', 'invertebrate'), _Species('Harlequin Shrimp', 'invertebrate'),
    _Species('Nerite Snail', 'invertebrate'), _Species('Mystery Snail', 'invertebrate'),
    _Species('Assassin Snail', 'invertebrate'), _Species('Ramshorn Snail', 'invertebrate'),
    _Species('Malaysian Trumpet Snail', 'invertebrate'), _Species('Rabbit Snail', 'invertebrate'),
    _Species('Turbo Snail', 'invertebrate'), _Species('Cerith Snail', 'invertebrate'),
    _Species('Nassarius Snail', 'invertebrate'), _Species('Astrea Snail', 'invertebrate'),
    _Species('Blue Leg Hermit', 'invertebrate'), _Species('Red Leg Hermit', 'invertebrate'),
    _Species('Emerald Crab', 'invertebrate'), _Species('Fiddler Crab', 'invertebrate'),
    _Species('Vampire Crab', 'invertebrate'), _Species('Porcelain Crab', 'invertebrate'),
    _Species('Crayfish', 'invertebrate'), _Species('Sea Urchin', 'invertebrate'),
    _Species('Starfish', 'invertebrate'), _Species('Feather Duster', 'invertebrate'),
  ],
  'Corals & Polyps': [
    _Species('Zoanthids', 'coral'), _Species('Mushroom Coral', 'coral'), _Species('Hammer Coral', 'coral'),
    _Species('Torch Coral', 'coral'), _Species('Frogspawn', 'coral'), _Species('Brain Coral', 'coral'),
    _Species('Bubble Coral', 'coral'), _Species('Elegance Coral', 'coral'), _Species('Acropora', 'coral'),
    _Species('Montipora', 'coral'), _Species('Chalice Coral', 'coral'), _Species('Duncan Coral', 'coral'),
    _Species('Candycane Coral', 'coral'), _Species('Xenia', 'polyp'), _Species('Star Polyps', 'polyp'),
    _Species('Leather Coral', 'coral'), _Species('Trumpet Coral', 'coral'),
    _Species('Anemone', 'anemone'), _Species('Bubble Tip Anemone', 'anemone'),
    _Species('Carpet Anemone', 'anemone'), _Species('Long Tentacle Anemone', 'anemone'),
  ],
};

const _kPlantCatalogue = <String, List<String>>{
  'Stem Plants': [
    'Ludwigia', 'Rotala', 'Cabomba', 'Hornwort', 'Water Wisteria',
    'Hygrophila', 'Bacopa', 'Myriophyllum', 'Limnophila', 'Alternanthera',
  ],
  'Rosette Plants': [
    'Amazon Sword', 'Cryptocoryne', 'Dwarf Sagittaria', 'Vallisneria',
    'Echinodorus', 'Aponogeton', 'Tiger Lotus',
  ],
  'Rhizome Plants': [
    'Java Fern', 'Anubias', 'Bolbitis', 'Microsorum', 'Bucephalandra',
    'Needle Leaf Java Fern', 'Trident Java Fern',
  ],
  'Mosses': [
    'Java Moss', 'Christmas Moss', 'Flame Moss', 'Willow Moss',
    'Fissidens', 'Taiwan Moss', 'Weeping Moss', 'Peacock Moss',
  ],
  'Floating Plants': [
    'Duckweed', 'Frogbit', 'Water Sprite', 'Salvinia', 'Azolla',
    'Water Hyacinth', 'Red Root Floater',
  ],
  'Carpet Plants': [
    'Dwarf Baby Tears', 'Monte Carlo', 'Hairgrass', 'Glossostigma',
    'Marsilea', 'Staurogyne Repens', 'Micranthemum',
  ],
};

/// Fuzzy-match a user-typed name against the known catalogues.
/// Returns the canonical catalogue name if a close match is found, otherwise null.
/// For inhabitants, also returns the matched type.
({String name, String type})? _matchInhabitantCatalogue(String input) {
  final q = input.trim().toLowerCase().replaceAll(RegExp(r'e?s$'), '');
  for (final entry in _kInhabitantCatalogue.entries) {
    for (final s in entry.value) {
      final canon = s.name.toLowerCase();
      final canonStripped = canon.replaceAll(RegExp(r'e?s$'), '');
      if (canon == input.trim().toLowerCase() || canonStripped == q) return (name: s.name, type: s.type);
      // input words all appear in catalogue name or vice versa
      final qWords = q.split(RegExp(r'\s+'));
      final cWords = canonStripped.split(RegExp(r'\s+'));
      if (qWords.length >= 1 && cWords.length >= 1) {
        if (qWords.every((w) => cWords.any((c) => c.contains(w) || w.contains(c))) ||
            cWords.every((c) => qWords.any((w) => w.contains(c) || c.contains(w)))) {
          // Require at least 3 chars overlap to avoid spurious matches
          if (q.length >= 3) return (name: s.name, type: s.type);
        }
      }
    }
  }
  return null;
}

String? _matchPlantCatalogue(String input) {
  final q = input.trim().toLowerCase().replaceAll(RegExp(r'e?s$'), '');
  for (final entry in _kPlantCatalogue.entries) {
    for (final p in entry.value) {
      final canon = p.toLowerCase();
      final canonStripped = canon.replaceAll(RegExp(r'e?s$'), '');
      if (canon == input.trim().toLowerCase() || canonStripped == q) return p;
      final qWords = q.split(RegExp(r'\s+'));
      final cWords = canonStripped.split(RegExp(r'\s+'));
      if (qWords.length >= 1 && cWords.length >= 1) {
        if (qWords.every((w) => cWords.any((c) => c.contains(w) || w.contains(c))) ||
            cWords.every((c) => qWords.any((w) => w.contains(c) || c.contains(w)))) {
          if (q.length >= 3) return p;
        }
      }
    }
  }
  return null;
}

// ── CSV Column Mapping screen (used during onboarding) ───────────────────────

class _CsvMappingScreen extends StatefulWidget {
  final List<String> headers;
  final List<List<dynamic>> rows;
  final Map<int, String?> initialMapping;
  final int? dateColIndex;

  const _CsvMappingScreen({
    required this.headers,
    required this.rows,
    required this.initialMapping,
    this.dateColIndex,
  });

  @override
  State<_CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends State<_CsvMappingScreen> {
  late Map<int, String?> _mapping;
  late int? _dateColIndex;

  @override
  void initState() {
    super.initState();
    _mapping = Map.of(widget.initialMapping);
    _dateColIndex = widget.dateColIndex;
  }

  @override
  Widget build(BuildContext context) {
    final previewRows = widget.rows.take(3).toList();
    final mappedCount = _mapping.values.where((v) => v != null).length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Map Columns', style: TextStyle(color: _cDark, fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: _cDark),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.rows.length} rows found. Map your columns to parameters:',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('CSV COLUMN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8))),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: Text('MAP TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _MappingRow(
                  header: _dateColIndex != null ? widget.headers[_dateColIndex!] : '(no date column)',
                  assignedValue: _dateColIndex != null ? 'Date' : null,
                  isDate: true,
                  onChanged: null,
                ),
                const Divider(height: 1),
                ...List.generate(widget.headers.length, (i) {
                  if (i == _dateColIndex) return const SizedBox.shrink();
                  return Column(
                    children: [
                      _MappingRow(
                        header: widget.headers[i],
                        assignedValue: _mapping[i],
                        isDate: false,
                        preview: previewRows.map((r) => i < r.length ? r[i].toString() : '').join(', '),
                        onChanged: (val) => setState(() => _mapping[i] = val),
                      ),
                      const Divider(height: 1),
                    ],
                  );
                }),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: mappedCount == 0 ? null : () {
                  Navigator.of(context).pop({
                    'mapping': _mapping,
                    'dateCol': _dateColIndex,
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _cDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(mappedCount == 0
                    ? 'Map at least one column'
                    : 'Confirm ${widget.rows.length} Rows'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── CSV Import screen ────────────────────────────────────────────────────────

class _CsvImportScreen extends StatefulWidget {
  final TankModel tank;
  const _CsvImportScreen({required this.tank});

  @override
  State<_CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<_CsvImportScreen> {
  List<List<dynamic>>? _rows;
  List<String> _headers = [];
  // column index → parameter name (null = skip)
  Map<int, String?> _mapping = {};
  int? _dateColIndex;
  bool _importing = false;
  int _importedCount = 0;
  String? _error;

  static const _knownParams = [
    'ph', 'ammonia', 'nitrite', 'nitrate', 'gh', 'kh',
    'temp', 'salinity', 'phosphate', 'calcium', 'magnesium',
    'potassium', 'tds', 'alkalinity', 'copper', 'iron',
  ];

  /// Scan rows to find the actual header row. Returns the index of the first
  /// row where at least 2 cells match known parameter names or "date".
  /// Falls back to 0 if no row scores high enough.
  static int _findHeaderRow(List<List<dynamic>> rows) {
    const dateWords = {'date', 'timestamp', 'time', 'day', 'logged'};
    // Strict aliases — only unambiguous names that won't false-positive on data
    const strictAliases = {
      'ph', 'p.h.', 'ph level',
      'nh3', 'nh4', 'ammonia', 'nh3/nh4', 'amm',
      'no2', 'nitrite', 'nite',
      'no3', 'nitrate', 'nate',
      'gh', 'general hardness',
      'kh', 'carbonate hardness',
      'temp', 'temperature', 'water temp',
      'sal', 'salinity',
      'po4', 'phosphate', 'phos',
      'calcium', 'ca',
      'magnesium', 'mg',
      'potassium',
      'tds',
      'alk', 'alkalinity',
      'copper', 'cu',
      'iron', 'fe',
    };
    int bestRow = 0;
    int bestScore = 0;
    for (int r = 0; r < rows.length && r < 30; r++) {
      final row = rows[r];
      // Skip rows where most cells are numbers (data rows, not headers)
      int numericCells = 0;
      for (final cell in row) {
        if (num.tryParse(cell.toString().trim().replaceAll(RegExp(r'[,\s]'), '')) != null) {
          numericCells++;
        }
      }
      if (row.length > 2 && numericCells > row.length * 0.6) continue;

      int dateMatches = 0;
      int paramMatches = 0;
      for (final cell in row) {
        final h = cell.toString().replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim().toLowerCase();
        if (h.isEmpty) continue;
        if (dateWords.contains(h) || h.contains('date')) {
          dateMatches++;
        } else if (strictAliases.contains(h)) {
          paramMatches++;
        }
      }
      final score = dateMatches + paramMatches;
      // Need a date column + at least 1 param, or 3+ params
      if ((dateMatches >= 1 && paramMatches >= 1 && score > bestScore) ||
          (paramMatches >= 3 && score > bestScore)) {
        bestRow = r;
        bestScore = score;
      }
    }
    return bestRow;
  }

  static const _headerAliases = {
    'ph': 'ph', 'p.h.': 'ph', 'ph level': 'ph',
    'nh3': 'ammonia', 'nh4': 'ammonia', 'ammonia': 'ammonia', 'nh3/nh4': 'ammonia', 'amm': 'ammonia',
    'no2': 'nitrite', 'nitrite': 'nitrite', 'nite': 'nitrite',
    'no3': 'nitrate', 'nitrate': 'nitrate', 'nate': 'nitrate',
    'gh': 'gh', 'general hardness': 'gh',
    'kh': 'kh', 'carbonate hardness': 'kh',
    'temp': 'temp', 'temperature': 'temp', 'water temp': 'temp',
    'sal': 'salinity', 'salinity': 'salinity',
    'po4': 'phosphate', 'phosphate': 'phosphate', 'phos': 'phosphate',
    'ca': 'calcium', 'calcium': 'calcium',
    'mg': 'magnesium', 'magnesium': 'magnesium',
    'k': 'potassium', 'potassium': 'potassium',
    'tds': 'tds',
    'alk': 'alkalinity', 'alkalinity': 'alkalinity',
    'cu': 'copper', 'copper': 'copper',
    'fe': 'iron', 'iron': 'iron',
  };

  /// Fuzzy-match a CSV header to a known parameter.
  static String? _matchHeader(String raw) {
    // Strip units like "(ppm)", "(°F)", trailing whitespace
    final h = raw.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim().toLowerCase();
    // Exact match first
    if (_headerAliases.containsKey(h)) return _headerAliases[h];
    // Check if any alias is contained in the header or vice versa
    for (final entry in _headerAliases.entries) {
      if (h.contains(entry.key) || entry.key.contains(h)) {
        // Avoid false positives from very short keys like 'k'
        if (entry.key.length < 2 && h.length > 3) continue;
        return entry.value;
      }
    }
    // Check if header starts with a known param name
    for (final p in _knownParams) {
      if (h.startsWith(p.toLowerCase())) return p;
    }
    return null;
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
        readSequential: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      debugPrint('[CSV] picked: name=${picked.name} path=${picked.path} bytes=${picked.bytes?.length}');
      final String content;
      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        content = utf8.decode(picked.bytes!, allowMalformed: true);
      } else if (picked.path != null) {
        final file = File(picked.path!);
        if (await file.exists()) {
          content = await file.readAsString();
        } else {
          throw Exception('File not found at ${picked.path}');
        }
      } else {
        throw Exception('No file data available');
      }
      debugPrint('[CSV] content length: ${content.length}');
      final allRows = const CsvToListConverter(eol: '\n').convert(content);
      if (allRows.length < 2) {
        setState(() => _error = 'CSV must have a header row and at least one data row.');
        return;
      }
      final headerIdx = _findHeaderRow(allRows);
      final rows = allRows.sublist(headerIdx);
      if (rows.length < 2) {
        setState(() => _error = 'Could not find enough data rows after the header.');
        return;
      }
      debugPrint('[CSV] detected header at row $headerIdx');
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final mapping = <int, String?>{};
      int? dateCol;
      for (int i = 0; i < headers.length; i++) {
        final h = headers[i].toLowerCase().replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
        if (h == 'date' || h == 'timestamp' || h == 'time' ||
            h.contains('date') || h == 'day' || h == 'logged') {
          dateCol ??= i;
        } else {
          mapping[i] = _matchHeader(h);
        }
      }
      setState(() {
        _headers = headers;
        _rows = rows.sublist(1);
        _mapping = mapping;
        _dateColIndex = dateCol;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to read file: $e');
    }
  }

  Future<void> _downloadTemplate() async {
    const template =
        'Date,pH,Ammonia,Nitrite,Nitrate,GH,KH,Temp\n'
        '3/1/2026,7.2,0,0,10,8,4,78\n';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/aquaria_template.csv');
      await file.writeAsString(template);
      if (!mounted) return;
      // Use the platform share sheet so user can save/send it
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Template',
        fileName: 'aquaria_template.csv',
        bytes: Uint8List.fromList(utf8.encode(template)),
      );
    } catch (_) {
      // Fallback: just confirm it's in the app documents
      if (mounted) {
        _showTopSnack(context, 'Template saved to app documents.', backgroundColor: _cDark);
      }
    }
  }

  Future<void> _import() async {
    if (_rows == null) return;
    final paramCols = _mapping.entries
        .where((e) => e.value != null)
        .toList();
    if (paramCols.isEmpty) {
      setState(() => _error = 'Map at least one column to a parameter.');
      return;
    }
    setState(() { _importing = true; _error = null; _importedCount = 0; });
    int count = 0;
    for (final row in _rows!) {
      if (row.length <= 1 && row.first.toString().trim().isEmpty) continue;
      // Parse date
      DateTime? logDate;
      if (_dateColIndex != null && _dateColIndex! < row.length) {
        final raw = row[_dateColIndex!].toString().trim();
        logDate = _parseFlexDate(raw);
      }
      logDate ??= DateTime.now();

      // Build measurements
      final measurements = <String, dynamic>{};
      for (final entry in paramCols) {
        if (entry.key >= row.length) continue;
        final raw = row[entry.key].toString().trim();
        if (raw.isEmpty) continue;
        final num? val = num.tryParse(raw.replaceAll(RegExp(r'[^\d.\-]'), ''));
        if (val != null) {
          measurements[entry.value!] = val;
        } else {
          measurements[entry.value!] = raw;
        }
      }
      if (measurements.isEmpty) continue;

      final parsedJson = jsonEncode({
        'schemaVersion': 1,
        'measurements': measurements,
        'actions': <String>[],
        'notes': <String>[],
        'tasks': <Map>[],
        'date': logDate.toIso8601String().substring(0, 10),
      });
      await TankStore.instance.addLog(
        tankId: widget.tank.id,
        rawText: 'CSV import',
        parsedJson: parsedJson,
        date: logDate,
      );
      // Also write to journal for the curated view
      final journalDate = '${logDate.year}-${logDate.month.toString().padLeft(2,'0')}-${logDate.day.toString().padLeft(2,'0')}';
      // Merge with existing measurements for that date
      final existing = await TankStore.instance.journalForDate(widget.tank.id, journalDate);
      final measEntry = existing.where((e) => e.category == 'measurements').toList();
      Map<String, dynamic> merged = {};
      if (measEntry.isNotEmpty) {
        try { merged = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
      }
      merged.addAll(measurements);
      await TankStore.instance.upsertJournal(
        tankId: widget.tank.id,
        date: journalDate,
        category: 'measurements',
        data: jsonEncode(merged),
      );
      count++;
    }
    if (count > 0) {
      TankStore.instance.invalidateSummary(widget.tank.id);
    }
    setState(() { _importing = false; _importedCount = count; });
    if (count > 0 && mounted) {
      _showTopSnack(context, 'Imported $count entries!', backgroundColor: _cDark);
      Navigator.of(context).pop(true);
    }
  }

  static const _monthNames = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6,
    'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };

  static DateTime? _parseFlexDate(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return null;

    // Try ISO first (2026-03-01, 2026-03-01T00:00:00)
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    // Try numeric formats: M/D/YY, M/D/YYYY, M-D-YYYY, M.D.YYYY, M-D-YY
    final numParts = trimmed.split(RegExp(r'[/\-.]'));
    if (numParts.length >= 2) {
      final m = int.tryParse(numParts[0]);
      final d = int.tryParse(numParts[1]);
      if (m != null && d != null) {
        var y = numParts.length >= 3 ? int.tryParse(numParts[2]) : DateTime.now().year;
        if (y != null) {
          if (y < 100) y += 2000;
          try { return DateTime(y, m, d); } catch (_) {}
        }
      }
    }

    // Try named month formats: "Mar 1", "March 1", "Mar 1 2026", "March 1, 2026"
    final cleaned = trimmed.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ');
    final words = cleaned.split(' ');
    if (words.length >= 2) {
      final monthNum = _monthNames[words[0].toLowerCase()];
      if (monthNum != null) {
        final d = int.tryParse(words[1]);
        if (d != null) {
          var y = words.length >= 3 ? int.tryParse(words[2]) : DateTime.now().year;
          if (y != null) {
            if (y < 100) y += 2000;
            try { return DateTime(y, monthNum, d); } catch (_) {}
          }
        }
      }
      // Try "1 Mar 2026" / "1 March"
      final d = int.tryParse(words[0]);
      if (d != null) {
        final monthNum2 = _monthNames[words[1].toLowerCase()];
        if (monthNum2 != null) {
          var y = words.length >= 3 ? int.tryParse(words[2]) : DateTime.now().year;
          if (y != null) {
            if (y < 100) y += 2000;
            try { return DateTime(y, monthNum2, d); } catch (_) {}
          }
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, ''),
      body: _rows == null ? _buildPickerView() : _buildMappingView(),
    );
  }

  Widget _buildPickerView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Import CSV',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            ),
            const SizedBox(height: 16),
            const Icon(Icons.upload_file, size: 56, color: _cMid),
            const SizedBox(height: 16),
            const Text(
              'Import water parameters from a CSV file',
              style: TextStyle(fontSize: 15, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The file should have a header row with column names like Date, pH, Ammonia, Nitrate, etc.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Choose CSV File'),
              style: FilledButton.styleFrom(
                backgroundColor: _cDark,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download Template'),
              style: TextButton.styleFrom(foregroundColor: _cMid),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMappingView() {
    final previewRows = _rows!.take(3).toList();
    return Column(
      children: [
        // Column mapping
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Import CSV',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
              ),
              const SizedBox(height: 12),
              Text(
                '${_rows!.length} rows found. Map your columns to parameters:',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              // Column labels
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('CSV COLUMN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8))),
                    const SizedBox(width: 24), // arrow space
                    Expanded(flex: 2, child: Text('MAP TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8))),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Date column
              _MappingRow(
                header: _dateColIndex != null ? _headers[_dateColIndex!] : '(no date column)',
                assignedValue: _dateColIndex != null ? 'Date' : null,
                isDate: true,
                onChanged: null,
              ),
              const Divider(height: 1),
              // Parameter columns
              ...List.generate(_headers.length, (i) {
                if (i == _dateColIndex) return const SizedBox.shrink();
                return Column(
                  children: [
                    _MappingRow(
                      header: _headers[i],
                      assignedValue: _mapping[i],
                      isDate: false,
                      preview: previewRows.map((r) => i < r.length ? r[i].toString() : '').join(', '),
                      onChanged: (val) => setState(() => _mapping[i] = val),
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),
            ],
          ),
        ),
        // Bottom bar
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              if (_importedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Imported $_importedCount entries!',
                      style: const TextStyle(color: _cDark, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _importing ? null : _import,
                  style: FilledButton.styleFrom(
                    backgroundColor: _cDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _importing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Import ${_rows!.length} Rows'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MappingRow extends StatelessWidget {
  final String header;
  final String? assignedValue;
  final bool isDate;
  final String? preview;
  final ValueChanged<String?>? onChanged;

  const _MappingRow({
    required this.header,
    required this.assignedValue,
    required this.isDate,
    this.preview,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool matched = assignedValue != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(header, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: matched ? Colors.black87 : Colors.grey.shade600)),
                if (preview != null)
                  Text(preview!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.arrow_forward, size: 16, color: matched ? _cDark : Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: isDate
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _cMint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(assignedValue ?? 'Not detected',
                        style: TextStyle(fontSize: 13, color: assignedValue != null ? _cDark : Colors.grey)),
                  )
                : DropdownButtonFormField<String?>(
                    value: assignedValue,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Skip', style: TextStyle(color: Colors.grey))),
                      ..._CsvImportScreenState._knownParams.map((p) =>
                          DropdownMenuItem(value: p, child: Text(_paramDisplayNames[p] ?? p, style: const TextStyle(fontSize: 12)))),
                    ],
                    onChanged: onChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Species picker sheet ──────────────────────────────────────────────────────

class _SpeciesPickerSheet extends StatefulWidget {
  final bool isPlant;
  final WaterType? waterType;
  const _SpeciesPickerSheet({required this.isPlant, this.waterType});
  @override
  State<_SpeciesPickerSheet> createState() => _SpeciesPickerSheetState();
}

class _SpeciesPickerSheetState extends State<_SpeciesPickerSheet> {
  static const _types = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  final _searchCtrl = TextEditingController();
  final _customCtrl = TextEditingController();
  String _query = '';
  bool _showCustom = false;
  String _customType = 'fish';

  // Inline count selection state (non-plant only)
  _Species? _pending;
  int _pendingCount = 1;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Set<String> _allowedCategories() {
    final wt = widget.waterType;
    if (wt == null) return _kInhabitantCatalogue.keys.toSet();
    switch (wt) {
      case WaterType.freshwater:
      case WaterType.planted:
      case WaterType.pond:
        return {'Freshwater Fish', 'Shrimp & Invertebrates'};
      case WaterType.saltwater:
        return {'Saltwater Fish', 'Shrimp & Invertebrates'};
      case WaterType.reef:
        return {'Saltwater Fish', 'Shrimp & Invertebrates', 'Corals & Polyps'};
    }
  }

  List<MapEntry<String, List<_Species>>> _filteredInhabitants() {
    final q = _query.toLowerCase();
    final allowed = _allowedCategories();
    return _kInhabitantCatalogue.entries
        .where((e) => allowed.contains(e.key))
        .map((e) => MapEntry(e.key,
            q.isEmpty ? e.value : e.value.where((s) => s.name.toLowerCase().contains(q)).toList()))
        .where((e) => e.value.isNotEmpty)
        .toList();
  }

  List<MapEntry<String, List<String>>> _filteredPlants() {
    final q = _query.toLowerCase();
    return _kPlantCatalogue.entries
        .map((e) => MapEntry(e.key,
            q.isEmpty ? e.value : e.value.where((s) => s.toLowerCase().contains(q)).toList()))
        .where((e) => e.value.isNotEmpty)
        .toList();
  }

  void _selectSpecies(_Species s) {
    setState(() {
      if (_pending?.name == s.name && _pending?.type == s.type) {
        _pending = null; // tap same again to deselect
      } else {
        _pending = s;
        _pendingCount = 1;
      }
    });
  }

  void _confirmAdd() {
    if (_pending == null) return;
    Navigator.pop(context, (name: _pending!.name, type: _pending!.type, count: _pendingCount));
  }

  @override
  Widget build(BuildContext context) {
    final navPad = MediaQuery.of(context).viewPadding.bottom;
    final keyboardPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardPad),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    widget.isPlant ? 'Add Plant' : 'Add Inhabitant',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 22, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // List
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: navPad + 16),
                children: [
                  if (!widget.isPlant)
                    ..._filteredInhabitants().expand((e) => [
                      _sectionHeader(e.key),
                      ...e.value.map((s) => _tile(
                        s.name, _typeEmoji[s.type] ?? '🐠',
                        selected: _pending?.name == s.name && _pending?.type == s.type,
                        onTap: () => _selectSpecies(s),
                      )),
                    ]),
                  if (widget.isPlant)
                    ..._filteredPlants().expand((e) => [
                      _sectionHeader(e.key),
                      ...e.value.map((p) => _tile(
                        p, '🌿',
                        onTap: () => Navigator.pop(context, (name: p, type: 'plant', count: 1)),
                      )),
                    ]),
                  const Divider(height: 1),
                  if (!_showCustom)
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline, color: _cMid),
                      title: const Text('Other — add custom'),
                      onTap: () => setState(() => _showCustom = true),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: Row(
                        children: [
                          if (!widget.isPlant) ...[
                            DropdownButton<String>(
                              value: _customType,
                              underline: const SizedBox(),
                              isDense: true,
                              items: _types.map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(_typeEmoji[t] ?? '🐠', style: const TextStyle(fontSize: 20)),
                              )).toList(),
                              onChanged: (v) => setState(() => _customType = v!),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: TextField(
                              controller: _customCtrl,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: widget.isPlant ? 'Plant name' : 'Inhabitant name',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final name = _customCtrl.text.trim();
                              if (name.isEmpty) return;
                              if (widget.isPlant) {
                                final match = _matchPlantCatalogue(name);
                                Navigator.pop(context, (name: match ?? _titleCase(name), type: 'plant', count: 1));
                              } else {
                                final match = _matchInhabitantCatalogue(name);
                                Navigator.pop(context, (name: match?.name ?? _titleCase(name), type: match?.type ?? _customType, count: 1));
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Inline count bar — slides in when a species is selected (non-plant only)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _pending == null
                  ? const SizedBox.shrink()
                  : Container(
                      decoration: BoxDecoration(
                        color: _cMint,
                        border: Border(top: BorderSide(color: _cLight.withOpacity(0.7))),
                      ),
                      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + navPad),
                      child: Row(
                        children: [
                          Text(
                            _typeEmoji[_pending!.type] ?? '🐠',
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pending!.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _cDark),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Stepper
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                            color: _pendingCount > 1 ? _cDark : Colors.grey.shade400,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: _pendingCount > 1 ? () => setState(() => _pendingCount--) : null,
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '$_pendingCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _cDark),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            color: _pendingCount < 99 ? _cDark : Colors.grey.shade400,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: _pendingCount < 99 ? () => setState(() => _pendingCount++) : null,
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _cDark,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _confirmAdd,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
  );

  Widget _tile(String name, String emoji, {required VoidCallback onTap, bool selected = false}) => ListTile(
    dense: true,
    tileColor: selected ? _cMint : null,
    leading: Text(emoji, style: const TextStyle(fontSize: 22)),
    title: Text(name, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
    trailing: selected ? const Icon(Icons.check_circle, color: _cDark, size: 18) : null,
    onTap: onTap,
  );
}

// ─────────────────────────────────────────────
// Daily Logs Screen
// ─────────────────────────────────────────────
class DailyLogsScreen extends StatefulWidget {
  final TankModel tank;
  final List<db.Log> logs; // kept for backward compat; screen loads journal internally
  const DailyLogsScreen({super.key, required this.tank, required this.logs});
  @override
  State<DailyLogsScreen> createState() => _DailyLogsScreenState();
}

class _DailyLogsScreenState extends State<DailyLogsScreen> {
  List<db.JournalEntry> _journal = [];
  late Set<String> _collapsedDays;

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  @override
  void initState() {
    super.initState();
    _collapsedDays = {};
    _reload();
  }

  Future<void> _reload() async {
    final fresh = await TankStore.instance.journalFor(widget.tank.id);
    if (mounted) setState(() => _journal = fresh);
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  Future<void> _showAddNoteDialog() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final noteResult = await showModalBottomSheet<({String text, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddNoteSheet(tankName: widget.tank.name),
    );
    if (noteResult != null && noteResult.text.isNotEmpty && mounted) {
      final noteText = noteResult.text;
      final date = noteResult.date;
      // Merge with existing notes for the selected date
      final existing = await TankStore.instance.journalForDate(widget.tank.id, date);
      final noteEntry = existing.where((e) => e.category == 'notes').toList();
      List<String> notes = [];
      if (noteEntry.isNotEmpty) {
        try { notes = (jsonDecode(noteEntry.first.data) as List).cast<String>(); } catch (_) {}
      }
      if (!notes.contains(noteText)) notes.add(noteText);
      await TankStore.instance.upsertJournal(
        tankId: widget.tank.id,
        date: date,
        category: 'notes',
        data: jsonEncode(notes),
      );
      // Also save to logs (audit trail)
      await TankStore.instance.addLog(
        tankId: widget.tank.id,
        rawText: noteText,
        parsedJson: jsonEncode({'source': 'manual_note', 'notes': [noteText]}),
        date: DateTime.tryParse(date),
      );
      await _reload();
      if (mounted) _showTopSnack(context, 'Note saved');
    }
  }

  Future<void> _showAddMeasurementDialog() async {
    final result = await showModalBottomSheet<({Map<String, dynamic> measurements, String date})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddMeasurementSheet(tankName: widget.tank.name),
    );
    if (result != null && result.measurements.isNotEmpty && mounted) {
      final date = result.date;
      // Merge with existing measurements for the selected date
      final existing = await TankStore.instance.journalForDate(widget.tank.id, date);
      final measEntry = existing.where((e) => e.category == 'measurements').toList();
      Map<String, dynamic> measurements = {};
      if (measEntry.isNotEmpty) {
        try { measurements = Map<String, dynamic>.from(jsonDecode(measEntry.first.data) as Map); } catch (_) {}
      }
      measurements.addAll(result.measurements);
      await TankStore.instance.upsertJournal(
        tankId: widget.tank.id,
        date: date,
        category: 'measurements',
        data: jsonEncode(measurements),
      );
      // Also save to logs (audit trail)
      final parts = result.measurements.entries.map((e) => '${_paramShortLabel(e.key)}: ${e.value}').join(', ');
      await TankStore.instance.addLog(
        tankId: widget.tank.id,
        rawText: parts,
        parsedJson: jsonEncode({
          'measurements': result.measurements,
          'actions': <String>[],
          'notes': <String>[],
          'tasks': <dynamic>[],
        }),
        date: DateTime.tryParse(date),
      );
      await _reload();
      if (mounted) _showTopSnack(context, 'Measurement saved');
    }
  }

  Future<void> _showAddTaskDialog() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showModalBottomSheet<({String desc, String? dueDate, int? repeatDays, bool markComplete, bool completeAndStopRecurring, bool dismiss, bool dismissAndStopRecurring})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddTaskSheet(tankName: widget.tank.name),
    );
    if (result != null && result.desc.isNotEmpty && mounted) {
      if (result.markComplete) {
        await TankStore.instance.addTask(
          tankId: widget.tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
        final tasks = await TankStore.instance.tasksForTank(widget.tank.id);
        final match = tasks.where((t) => t.description == result.desc && !t.isComplete).toList();
        if (match.isNotEmpty) {
          await TankStore.instance.completeTaskById(match.last.id);
        }
      } else {
        await TankStore.instance.addTask(
          tankId: widget.tank.id,
          description: result.desc,
          dueDate: result.dueDate,
          source: 'manual',
          repeatDays: result.repeatDays,
        );
      }
      // Save action to journal
      final date = result.dueDate ?? _todayKey();
      final existing = await TankStore.instance.journalForDate(widget.tank.id, date);
      final actEntry = existing.where((e) => e.category == 'actions').toList();
      List<String> actions = [];
      if (actEntry.isNotEmpty) {
        try { actions = (jsonDecode(actEntry.first.data) as List).cast<String>(); } catch (_) {}
      }
      if (!actions.contains(result.desc)) actions.add(result.desc);
      await TankStore.instance.upsertJournal(
        tankId: widget.tank.id,
        date: date,
        category: 'actions',
        data: jsonEncode(actions),
      );
      await _reload();
      if (mounted) _showTopSnack(context, result.markComplete ? 'Task completed & logged' : 'Task added');
    }
  }

  String _dayLabel(DateTime dt) {
    final d = DateTime(dt.year, dt.month, dt.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Group journal entries by date
    final groups = <String, List<db.JournalEntry>>{};
    for (final entry in _journal) {
      groups.putIfAbsent(entry.date, () => []).add(entry);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    // items: String = day header, List<db.JournalEntry> = entries for that day
    final items = <Object>[];
    for (final key in sortedKeys) {
      items.add(key);
      if (!_collapsedDays.contains(key)) items.add(groups[key]!);
    }

    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, ''),
      bottomNavigationBar: _AquariaFooter(
        onAiTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChatSheet(
            initialTank: widget.tank,
            allTanks: TankStore.instance.tanks,
            onLogsChanged: _reload,
          ),
        ).then((_) => _reload()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.tank.name} — Journal',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 22),
                  tooltip: 'More options',
                  onSelected: (value) {
                    if (value == 'add_measurement') _showAddMeasurementDialog();
                    if (value == 'add_task') _showAddTaskDialog();
                    if (value == 'add_note') _showAddNoteDialog();
                    if (value == 'import_csv') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _CsvImportScreen(tank: widget.tank),
                      )).then((_) => _reload());
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add_measurement', child: Text('Add Measurement')),
                    PopupMenuItem(value: 'add_task', child: Text('Add Task')),
                    PopupMenuItem(value: 'add_note', child: Text('Add Note')),
                    PopupMenuItem(value: 'import_csv', child: Text('Import CSV')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _journal.isEmpty
          ? const Center(child: Text('No journal entries yet.', style: TextStyle(color: Colors.grey)))
          : RefreshIndicator(
              onRefresh: () async {
                if (SupabaseService.isLoggedIn) await TankStore.instance.pullFromCloud();
                await _reload();
              },
              child: ListView.builder(
              padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).padding.bottom + 80),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                if (item is String) {
                  final key = item;
                  final isCollapsed = _collapsedDays.contains(key);
                  final entryCount = groups[key]?.length ?? 0;
                  if (entryCount == 0) return const SizedBox.shrink();
                  final parts = key.split('-');
                  final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                  return InkWell(
                    onTap: () => setState(() {
                      if (isCollapsed) _collapsedDays.remove(key); else _collapsedDays.add(key);
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Row(children: [
                        Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, size: 18, color: _cDark),
                        const SizedBox(width: 4),
                        Text(_dayLabel(dt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _cDark)),
                      ]),
                    ),
                  );
                }
                if (item is List<db.JournalEntry>) {
                  return _JournalDayCard(
                    tankId: widget.tank.id,
                    date: item.first.date,
                    entries: item,
                    onChanged: _reload,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tank Gallery Screen
// ─────────────────────────────────────────────

class TankGalleryScreen extends StatefulWidget {
  final TankModel tank;
  const TankGalleryScreen({super.key, required this.tank});

  @override
  State<TankGalleryScreen> createState() => _TankGalleryScreenState();
}

class _TankGalleryScreenState extends State<TankGalleryScreen> {
  List<db.TankPhoto> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await TankStore.instance.photosFor(widget.tank.id);
    if (mounted) setState(() { _photos = photos; _loading = false; });
  }

  Future<void> _addPhoto() async {
    await pickPhotoFlow(context, tankId: widget.tank.id);
    if (mounted) await _load();
  }

  void _viewPhoto(db.TankPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoDetailScreen(photo: photo, onDelete: () async {
          try { await File(photo.filePath).delete(); } catch (_) {}
          await TankStore.instance.deletePhoto(photo.id);
          if (mounted) {
            Navigator.of(context).pop();
            _load();
          }
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, '', actions: [
        IconButton(
          icon: const Icon(Icons.add_a_photo_outlined),
          tooltip: 'Add Photo',
          onPressed: _addPhoto,
        ),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${widget.tank.name} — Photos',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            ),
          ),
          Expanded(
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 56, color: _cMid),
                        const SizedBox(height: 16),
                        const Text(
                          'No photos yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Snap a photo to track your tank\'s progress over time.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _addPhoto,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Add Photo'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _cDark,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (_, i) {
                      final photo = _photos[i];
                      return GestureDetector(
                        onTap: () => _viewPhoto(photo),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(photo.filePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

// ── Tank Attributes Screen ───────────────────────────────────────────────

class _TankAttributesScreen extends StatefulWidget {
  final TankModel tank;
  const _TankAttributesScreen({required this.tank});
  @override
  State<_TankAttributesScreen> createState() => _TankAttributesScreenState();
}

class _TankAttributesScreenState extends State<_TankAttributesScreen> {
  Map<String, dynamic> _equipment = {};
  List<db.Inhabitant> _inhabitants = [];
  List<db.Plant> _plants = [];
  bool _loading = true;
  late TankModel _tank;

  @override
  void initState() {
    super.initState();
    _tank = widget.tank;
    _load();
  }

  Future<void> _load() async {
    final json = await TankStore.instance.equipmentJsonFor(_tank.id);
    final inhabitants = await TankStore.instance.inhabitantsFor(_tank.id);
    final plants = await TankStore.instance.plantsFor(_tank.id);
    final updated = TankStore.instance.tanks.cast<TankModel?>().firstWhere((t) => t!.id == _tank.id, orElse: () => null);
    if (json != null) {
      try { _equipment = Map<String, dynamic>.from(jsonDecode(json) as Map); } catch (_) {}
    }
    if (mounted) setState(() {
      if (updated != null) _tank = updated;
      _inhabitants = inhabitants;
      _plants = plants;
      _loading = false;
    });
  }

  Widget _attrRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _cDark, letterSpacing: 0.3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator()));
    }

    final isSaltwater = [WaterType.saltwater, WaterType.reef].contains(_tank.waterType);

    // Build equipment items
    final eqItems = <Widget>[];

    // Substrate
    final substrate = _equipment['substrate'];
    if (substrate != null) {
      List<String> names;
      if (substrate is List) {
        names = substrate.where((s) => s != 'other').map<String>((s) => (s as String).replaceAll('_', ' ')).toList();
        final other = _equipment['substrate_other'] as String?;
        if (other != null && other.trim().isNotEmpty) names.add(other.trim());
      } else {
        names = [(substrate as String).replaceAll('_', ' ')];
      }
      if (names.isNotEmpty) eqItems.add(_attrRow('Substrate', names.map((n) => n[0].toUpperCase() + n.substring(1)).join(', ')));
    }

    // Filter type
    final filterType = _equipment['filter_type'] as String?;
    if (filterType != null) eqItems.add(_attrRow('Filter Type', filterType.replaceAll('_', ' ').split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')));

    // Filter media
    final media = _equipment['filter_media'];
    if (media is List && media.isNotEmpty) {
      eqItems.add(_attrRow('Filter Media', media.map<String>((m) => (m as String).replaceAll('_', ' ').split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')).join(', ')));
    }

    // Lighting
    final lighting = _equipment['lighting_type'] as String?;
    if (lighting != null) eqItems.add(_attrRow('Lighting', lighting.replaceAll('_', ' ').split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')));

    // Bool toggles
    final boolItems = <String, String>{
      'has_heater': 'Heater',
      'has_air_pump': 'Air Pump',
      'has_co2': 'CO2 Injection',
      'has_protein_skimmer': 'Protein Skimmer',
      'has_calcium_reactor': 'Calcium Reactor',
      'has_ato': 'Auto Top-Off',
      'has_dosing_pump': 'Dosing Pump',
      'has_live_rock': 'Live Rock',
    };
    final activeEquip = <String>[];
    for (final e in boolItems.entries) {
      if (_equipment[e.key] == true) activeEquip.add(e.value);
    }
    if (activeEquip.isNotEmpty) eqItems.add(_attrRow('Equipment', activeEquip.join(', ')));

    // Notes
    final notes = _equipment['notes'] as String?;
    if (notes != null && notes.trim().isNotEmpty) eqItems.add(_attrRow('Additional Details', notes.trim()));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _cDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_tank.name, style: const TextStyle(color: _cDark, fontWeight: FontWeight.w600, fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Tank info
          _sectionTitle('Tank'),
          _attrRow('Size', '${_tank.gallons} gal'),
          _attrRow('Water Type', switch (_tank.waterType) {
            WaterType.planted => 'Freshwater - Planted',
            WaterType.reef => 'Saltwater - Reef',
            _ => _tank.waterType.label,
          }),

          // Equipment
          if (eqItems.isNotEmpty) ...[
            _sectionTitle('Equipment'),
            ...eqItems,
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _cDark,
                side: const BorderSide(color: Color(0xFF1FA2A8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EditTankFlowScreen(tank: _tank)),
                );
                _load();
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Tank', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Equipment Screen ─────────────────────────────────────────────────────

class _EquipmentScreen extends StatefulWidget {
  final TankModel tank;
  final WaterType? waterTypeOverride;
  const _EquipmentScreen({required this.tank, this.waterTypeOverride});
  @override
  State<_EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<_EquipmentScreen> {
  Map<String, dynamic> _equipment = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final json = await TankStore.instance.equipmentJsonFor(widget.tank.id);
    if (json != null) {
      try { _equipment = Map<String, dynamic>.from(jsonDecode(json) as Map); } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await TankStore.instance.saveEquipment(widget.tank.id, jsonEncode(_equipment));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _ObEquipmentPage(
          waterType: widget.waterTypeOverride ?? widget.tank.waterType,
          equipment: _equipment,
          showSkip: false,
          onChanged: (updated) {
            setState(() => _equipment = updated);
            _save();
          },
          onNext: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class _FullScreenNetworkImage extends StatefulWidget {
  final String url;
  final String? photoStoragePath; // non-null = user's own photo, show share
  const _FullScreenNetworkImage({required this.url, this.photoStoragePath});

  @override
  State<_FullScreenNetworkImage> createState() => _FullScreenNetworkImageState();
}

class _FullScreenNetworkImageState extends State<_FullScreenNetworkImage> {
  bool _saving = false;
  bool _sharing = false;

  Future<void> _saveToGallery() async {
    setState(() => _saving = true);
    try {
      final resp = await http.get(Uri.parse(widget.url));
      if (resp.statusCode != 200) throw Exception('Download failed');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aquaria_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(resp.bodyBytes);
      await Gal.putImage(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved to gallery'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save photo: $e'), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.photoStoragePath != null)
            IconButton(
              icon: _sharing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.share),
              onPressed: _sharing ? null : () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.discord, color: Color(0xFF5865F2)),
                          title: const Text('Share to Discord'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showDiscordShareFlow(context, widget.photoStoragePath!);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              tooltip: 'Share',
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            onPressed: _saving ? null : _saveToGallery,
            tooltip: 'Save to gallery',
          ),
        ],
      ),
      body: InteractiveViewer(
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 64),
          ),
        ),
      ),
    );
  }
}

class _PhotoDetailScreen extends StatefulWidget {
  final db.TankPhoto photo;
  final VoidCallback onDelete;
  const _PhotoDetailScreen({required this.photo, required this.onDelete});

  @override
  State<_PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<_PhotoDetailScreen> {
  bool _sharing = false;

  Future<void> _shareToCommunity() async {
    final channel = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Share to Community', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.public, color: Color(0xFF1FA2A8)),
              title: const Text('General'),
              onTap: () => Navigator.pop(ctx, 'general'),
            ),
            ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.blue),
              title: const Text('Freshwater'),
              onTap: () => Navigator.pop(ctx, 'freshwater'),
            ),
            ListTile(
              leading: const Icon(Icons.waves, color: Colors.indigo),
              title: const Text('Saltwater'),
              onTap: () => Navigator.pop(ctx, 'saltwater'),
            ),
          ],
        ),
      ),
    );
    if (channel == null || !mounted) return;

    // Optional caption
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add a caption'),
          content: TextField(
            controller: ctrl,
            maxLength: 150,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Say something about this photo...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _cDark),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
    if (caption == null || !mounted) return;

    setState(() => _sharing = true);
    try {
      final storagePath = await SupabaseService.uploadCommunityPhoto(widget.photo.filePath);
      await SupabaseService.createPost(photoUrl: storagePath, caption: caption, channel: channel);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _CommunityScreen(initialChannel: channel)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sharing = false);
        _showTopSnack(context, 'Failed to share: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final d = photo.createdAt.toLocal();
    final dateStr = '${months[d.month - 1]} ${d.day}, ${d.year}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(dateStr, style: const TextStyle(fontSize: 15)),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('Share Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.groups_outlined, color: Color(0xFF1FA2A8)),
                          title: const Text('Aquaria Community'),
                          subtitle: const Text('Share to the in-app community feed'),
                          onTap: () { Navigator.pop(ctx); _shareToCommunity(); },
                        ),
                        ListTile(
                          leading: const Icon(Icons.discord, color: Color(0xFF5865F2)),
                          title: const Text('Discord'),
                          subtitle: const Text('Share to a Discord server'),
                          onTap: () async {
                            Navigator.pop(ctx);
                            // Upload to Supabase storage first, then share to Discord
                            setState(() => _sharing = true);
                            try {
                              final storagePath = await SupabaseService.uploadCommunityPhoto(widget.photo.filePath);
                              if (mounted) {
                                setState(() => _sharing = false);
                                _showDiscordShareFlow(context, storagePath);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() => _sharing = false);
                                _showTopSnack(context, 'Failed to upload: $e');
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () {
              showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete photo?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () { Navigator.of(ctx).pop(true); },
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ).then((confirmed) {
                if (confirmed == true) widget.onDelete();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: Image.file(
                  File(photo.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 64),
                ),
              ),
            ),
          ),
          if (photo.note != null && photo.note!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              color: Colors.black,
              child: Text(
                photo.note!,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Charts Screen
// ─────────────────────────────────────────────

// Canonical parameter names (lowercased aliases → canonical)
const _paramAliases = <String, String>{
  'nh3': 'ammonia', 'ammonia': 'ammonia',
  'no2': 'nitrite', 'nitrite': 'nitrite',
  'no3': 'nitrate', 'nitrate': 'nitrate',
  'ph': 'ph',
  'kh': 'kh', 'alkalinity': 'kh', 'alk': 'kh',
  'gh': 'gh',
  'k': 'potassium', 'potassium': 'potassium',
  'ca': 'calcium', 'calcium': 'calcium',
  'mg': 'magnesium', 'magnesium': 'magnesium', 'magnesium_calc': 'magnesium',
  'ca_mg_ratio': 'ca_mg_ratio',
  'phosphate': 'phosphate', 'po4': 'phosphate',
  'tds': 'tds',
  'iron': 'iron', 'fe': 'iron',
  'copper': 'copper', 'cu': 'copper',
  'temp': 'temp', 'temperature': 'temp',
  'salinity': 'salinity',
  'co2': 'co2', 'carbon dioxide': 'co2',
};

// Predefined chart groups: [params that share one chart]
const _chartGroups = [
  ['nitrate', 'nitrite', 'ammonia'],
  ['gh', 'kh'],
  ['potassium', 'calcium'],
  ['phosphate'],
  ['ph'],
];

const _paramColors = <String, Color>{
  'ammonia':   Color(0xFFF9A825), // amber yellow
  'nitrate':   Color(0xFF800080),
  'nitrite':   Color(0xFFD3D3FF),
  'gh':        Color(0xFF00BCD4), // vivid cyan
  'kh':        Color(0xFF5C6BC0), // indigo
  'calcium':   Color(0xFFD4A84B), // golden ivory
  'phosphate': Color(0xFF039BE5), // sky blue
  'potassium': Color(0xFF43A047),
  'ph':        Color(0xFF00ACC1),
  'magnesium': Color(0xFF00897B),
  'temp':      Color(0xFFFF7043),
  'salinity':  Color(0xFF1565C0),
  'iron':      Color(0xFFFF8F00),
  'co2':       Color(0xFF66BB6A), // green
  'ca_mg_ratio': Color(0xFF78909C),
};

// ── All Charts Screen ────────────────────────────────────────────────────────
class AllChartsScreen extends StatefulWidget {
  final List<TankModel> tanks;
  const AllChartsScreen({super.key, required this.tanks});

  @override
  State<AllChartsScreen> createState() => _AllChartsScreenState();
}

class _AllChartsScreenState extends State<AllChartsScreen> {
  // tankId → logs
  final Map<String, List<db.Log>> _logsByTank = {};
  Map<String, List<db.Task>> _tasksByTank = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final taskMap = <String, List<db.Task>>{};
    for (final tank in widget.tanks) {
      final logs = await TankStore.instance.logsFor(tank.id);
      _logsByTank[tank.id] = logs;
      final tasks = await TankStore.instance.tasksForTank(tank.id);
      if (tasks.isNotEmpty) taskMap[tank.id] = tasks;
    }
    if (mounted) setState(() { _loading = false; _tasksByTank = taskMap; });
  }

  int get _totalNotifCount {
    int count = 0;
    for (final tasks in _tasksByTank.values) count += tasks.length;
    return count;
  }

  Widget _buildNotificationBell() {
    final count = _totalNotifCount;
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 10)),
        backgroundColor: const Color(0xFFE65100),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () => _showNotificationsSheet(),
    );
  }

  void _showNotificationsSheet() {
    final items = <({TankModel tank, db.Task task})>[];
    for (final tank in widget.tanks) {
      for (final t in (_tasksByTank[tank.id] ?? [])) {
        items.add((tank: tank, task: t));
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          final liveItems = <({TankModel tank, db.Task task})>[];
          for (final tank in widget.tanks) {
            for (final t in (_tasksByTank[tank.id] ?? [])) {
              liveItems.add((tank: tank, task: t));
            }
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(children: [
                      const Icon(Icons.notifications, size: 18, color: Color(0xFFE65100)),
                      const SizedBox(width: 8),
                      Text('Notifications (${liveItems.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                    ]),
                  ),
                  const Divider(height: 1),
                  if (liveItems.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Text('No notifications', style: TextStyle(color: Colors.grey)))
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: liveItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 14),
                        itemBuilder: (_, i) {
                          final item = liveItems[i];
                          final desc = item.task.description;
                          final label = desc.isEmpty ? '' : desc[0].toUpperCase() + desc.substring(1);
                          final rawDue = item.task.dueDate;
                          final dueLabel = (rawDue != null && rawDue.isNotEmpty) ? _fmtNotifDue(rawDue) : null;
                          final isRecurring = item.task.repeatDays != null && item.task.repeatDays! > 0;
                          return ListTile(
                            dense: true,
                            leading: Icon(isRecurring ? Icons.repeat : Icons.task_alt, size: 18, color: const Color(0xFFE65100)),
                            title: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                children: [
                                  TextSpan(text: '${item.tank.name}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  TextSpan(text: label),
                                  if (dueLabel != null) TextSpan(text: ' — $dueLabel', style: const TextStyle(color: Color(0xFF8D6E63))),
                                ],
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Color(0xFF8D6E63)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () { TankStore.instance.dismissTaskById(item.task.id); _load(); setS(() {}); },
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.repeat, size: 18),
                        label: const Text('Recurring Tasks'),
                        style: OutlinedButton.styleFrom(foregroundColor: _cDark, side: const BorderSide(color: _cLight)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ManageRecurringTasksScreen())).then((_) => _load());
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  static String _fmtNotifDue(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${ms[dt.month - 1]} ${dt.day}';
  }

  Map<String, Map<DateTime, double>> _extractSeries(List<db.Log> logs) {
    final series = <String, Map<DateTime, double>>{};
    for (final log in logs) {
      if (log.parsedJson == null) continue;
      try {
        final raw = jsonDecode(log.parsedJson!);
        if (raw is! Map) continue;
        if (raw['source'] == 'tap_water') continue;
        final m = (raw['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
        final date = DateTime(log.createdAt.toLocal().year, log.createdAt.toLocal().month, log.createdAt.toLocal().day);
        for (final e in m.entries) {
          final canonical = _paramAliases[e.key.toLowerCase()];
          if (canonical == null) continue;
          final val = double.tryParse(e.value.toString().replaceAll(RegExp(r'[^\d.]'), ''));
          if (val == null) continue;
          series.putIfAbsent(canonical, () => {})[date] = val;
        }
      } catch (_) {}
    }
    return series;
  }

  List<Widget> _chartsForTank(TankModel tank) {
    final logs = _logsByTank[tank.id] ?? [];
    final series = _extractSeries(logs);
    final usedParams = <String>{};
    final charts = <Widget>[];

    for (final group in _chartGroups) {
      final groupSeries = {for (final p in group) if (series.containsKey(p) && series[p]!.keys.toSet().length >= 3) p: series[p]!};
      if (groupSeries.isEmpty) continue;
      for (final p in groupSeries.keys) usedParams.add(p);
      charts.add(_ChartCard(title: group.map(_paramShortLabel).join(' / '), seriesData: groupSeries, waterType: tank.waterType));
    }
    for (final entry in series.entries) {
      if (usedParams.contains(entry.key)) continue;
      if (entry.value.keys.toSet().length < 3) continue;
      charts.add(_ChartCard(title: ChartsScreen._paramLabel(entry.key), seriesData: {entry.key: entry.value}, waterType: tank.waterType));
    }
    return charts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, '', actions: [
        _buildNotificationBell(),
        IconButton(
          tooltip: 'Add photo',
          icon: const Icon(Icons.add_a_photo_outlined),
          onPressed: () => pickPhotoFlow(context),
        ),
      ]),
      bottomNavigationBar: const _AquariaFooter(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _loading = true);
                await _load();
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('All Charts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark)),
                  ),
                  for (final tank in widget.tanks) ...() {
                    final charts = _chartsForTank(tank);
                    if (charts.isEmpty) return <Widget>[];
                    return [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          tank.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${tank.gallons} gal • ${tank.waterType.label}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...charts.map((c) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: c,
                      )),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ];
                  }(),
                ],
              ),
            ),
    );
  }
}

// ── Per-tank Charts Screen ────────────────────────────────────────────────────
class ChartsScreen extends StatefulWidget {
  final TankModel tank;

  const ChartsScreen({super.key, required this.tank});

  static String _paramLabel(String p) => _paramDisplayNames[p.toLowerCase()] ?? p;

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  List<db.Log> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await TankStore.instance.logsFor(widget.tank.id);
    if (mounted) setState(() => _logs = logs);
  }

  /// Extract {canonical param → {date → value}} from all logs.
  Map<String, Map<DateTime, double>> _extractSeries() {
    final series = <String, Map<DateTime, double>>{};
    for (final log in _logs) {
      if (log.parsedJson == null) continue;
      try {
        final raw = jsonDecode(log.parsedJson!);
        if (raw is! Map) continue;
        if (raw['source'] == 'tap_water') continue;
        final m = (raw['measurements'] as Map?)?.cast<String, dynamic>() ?? {};
        final date = DateTime(log.createdAt.toLocal().year, log.createdAt.toLocal().month, log.createdAt.toLocal().day);
        for (final e in m.entries) {
          final canonical = _paramAliases[e.key.toLowerCase()];
          if (canonical == null) continue;
          final val = double.tryParse(e.value.toString().replaceAll(RegExp(r'[^\d.]'), ''));
          if (val == null) continue;
          series.putIfAbsent(canonical, () => {})[date] = val;
        }
      } catch (_) {}
    }
    return series;
  }

  /// A series qualifies if it has data on at least 3 different dates.
  bool _qualifies(Map<DateTime, double> data) => data.keys.toSet().length >= 3;

  @override
  Widget build(BuildContext context) {
    final series = _extractSeries();
    final usedParams = <String>{};
    final charts = <Widget>[];

    // Build predefined group charts first
    for (final group in _chartGroups) {
      final groupSeries = {for (final p in group) if (series.containsKey(p) && _qualifies(series[p]!)) p: series[p]!};
      if (groupSeries.isEmpty) continue;
      for (final p in groupSeries.keys) usedParams.add(p);
      charts.add(_ChartCard(title: group.map(_paramShortLabel).join(' / '), seriesData: groupSeries, waterType: widget.tank.waterType));
    }

    // Remaining params with enough data each get their own chart
    for (final entry in series.entries) {
      if (usedParams.contains(entry.key)) continue;
      if (!_qualifies(entry.value)) continue;
      charts.add(_ChartCard(title: ChartsScreen._paramLabel(entry.key), seriesData: {entry.key: entry.value}, waterType: widget.tank.waterType));
    }

    return Scaffold(
      appBar: _buildAppBar(context, ''),
      bottomNavigationBar: Builder(
        builder: (ctx) => _AquariaFooter(
          onAiTap: () => showModalBottomSheet(
            context: ctx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _ChatSheet(
              initialTank: widget.tank,
              allTanks: TankStore.instance.tanks,
              onLogsChanged: _load,
            ),
          ).then((_) => _load()),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${widget.tank.name} — Charts',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark),
            ),
          ),
          Expanded(
            child: charts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Not enough data yet.\nLog measurements on at least 3 different dates to see charts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: charts,
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Map<String, Map<DateTime, double>> seriesData;
  final WaterType waterType;

  const _ChartCard({required this.title, required this.seriesData, required this.waterType});

  static Map<String, (double, double)> _ranges(WaterType wt) {
    if (wt == WaterType.saltwater || wt == WaterType.reef) {
      return {
        'ammonia':   (0, 0),
        'nitrite':   (0, 0),
        'nitrate':   (0, 20),
        'ph':        (8.1, 8.3),
        'kh':        (8, 12),
        'calcium':   (380, 450),
        'magnesium': (1250, 1350),
        'phosphate': (0.03, 0.5),
        'potassium': (380, 420),
        'temp':      (76, 80),
        'salinity':  (1.024, 1.026),
      };
    }
    if (wt == WaterType.planted) {
      return {
        'ammonia':   (0, 0),
        'nitrite':   (0, 0),
        'nitrate':   (0, 20),
        'ph':        (6.5, 7.5),
        'kh':        (4, 8),
        'gh':        (4, 12),
        'phosphate': (0, 0.5),
        'potassium': (5, 20),
        'iron':      (0.05, 0.1),
        'temp':      (74, 80),
      };
    }
    return {
      'ammonia':   (0, 0),
      'nitrite':   (0, 0),
      'nitrate':   (0, 20),
      'ph':        (6.5, 7.5),
      'kh':        (4, 8),
      'gh':        (4, 12),
      'phosphate': (0, 0.5),
      'potassium': (5, 20),
      'temp':      (74, 80),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Collect all dates across all series and sort them
    final allDates = seriesData.values.expand((m) => m.keys).toSet().toList()..sort();
    final dateIndex = {for (var i = 0; i < allDates.length; i++) allDates[i]: i.toDouble()};

    // Build one LineChartBarData per param
    final bars = seriesData.entries.map((entry) {
      final color = _paramColors[entry.key] ?? Colors.blueGrey;
      final spots = entry.value.entries
          .map((e) => FlSpot(dateIndex[e.key]!, e.value))
          .toList()..sort((a, b) => a.x.compareTo(b.x));
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: color,
        barWidth: 2,
        dotData: FlDotData(show: spots.length <= 20),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    // Ideal range bands
    final idealRanges = _ranges(waterType);

    // Y-axis range: include both data values and ideal range bounds so shading is always visible
    final allVals = seriesData.values.expand((m) => m.values).toList();
    final rangeVals = seriesData.keys
        .where((p) => idealRanges.containsKey(p))
        .expand((p) => [idealRanges[p]!.$1, idealRanges[p]!.$2])
        .toList();
    final allForAxis = [...allVals, ...rangeVals];
    final minY = allForAxis.reduce((a, b) => a < b ? a : b);
    final maxY = allForAxis.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.15;
    final yMin = (minY - pad).clamp(0, double.infinity).toDouble();
    final yMax = maxY + pad;
    const rangeColors = <String, Color>{
      'nitrate':   Color(0x22800080),
      'kh':        Color(0x225C6BC0),
      'gh':        Color(0x2200BCD4),
      'nitrite':   Color(0x224CAF50),
      'ammonia':   Color(0x224CAF50),
      'ph':        Color(0x2200ACC1),
      'calcium':   Color(0x22D4A84B),
      'magnesium': Color(0x224CAF50),
      'phosphate': Color(0x22039BE5),
      'potassium': Color(0x2243A047),
      'iron':      Color(0x22FF8F00),
      'temp':      Color(0x22EF5350),
      'salinity':  Color(0x221565C0),
    };
    const legendColors = <String, Color>{
      'nitrate':   Color(0x66800080),
      'kh':        Color(0x665C6BC0),
      'gh':        Color(0x6600BCD4),
      'potassium': Color(0x6643A047),
      'calcium':   Color(0x66D4A84B),
      'magnesium': Color(0x664CAF50),
      'ph':        Color(0x6600ACC1),
      'phosphate': Color(0x66039BE5),
      'iron':      Color(0x66FF8F00),
      'temp':      Color(0x66EF5350),
      'salinity':  Color(0x661565C0),
    };
    const legendBorders = <String, Color>{
      'nitrate':   Color(0xFF800080),
      'kh':        Color(0xFF5C6BC0),
      'ph':        Color(0xFF00ACC1),
      'gh':        Color(0xFF00BCD4),
      'potassium': Color(0xFF43A047),
      'calcium':   Color(0xFFD4A84B),
      'magnesium': Color(0xFF4CAF50),
      'phosphate': Color(0xFF039BE5),
      'iron':      Color(0xFFFF8F00),
      'temp':      Color(0xFFEF5350),
      'salinity':  Color(0xFF1565C0),
    };
    const legendUnits = <String, String>{
      'salinity': 'SG',
      'gh': 'dGH',
      'kh': 'dKH',
      'iron': 'ppm',
      'temp': '°F',
    };
    final rangeAnnotations = <HorizontalRangeAnnotation>[];
    final zeroParams = <String>[];
    final rangeNotes = <({String label, Color color, Color border, double lo, double hi, String unit})>[];
    for (final param in seriesData.keys) {
      if (param == 'ammonia' || param == 'nitrite') {
        zeroParams.add(_paramShortLabel(param));
        continue;
      }
      final r = idealRanges[param];
      if (r != null) {
        final color = rangeColors[param] ?? const Color(0x224CAF50);
        rangeAnnotations.add(HorizontalRangeAnnotation(y1: r.$1, y2: r.$2, color: color));
        if (legendColors.containsKey(param)) {
          rangeNotes.add((
            label: 'Ideal ${_paramShortLabel(param)}',
            color: legendColors[param]!,
            border: legendBorders[param]!,
            lo: r.$1,
            hi: r.$2,
            unit: legendUnits[param] ?? 'ppm',
          ));
        }
      }
    }

    // Legend
    final legend = seriesData.keys.map((p) {
      final color = _paramColors[p] ?? Colors.blueGrey;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Text(_paramShortLabel(p), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]);
    }).toList();

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _cLight)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _cDark)),
            const SizedBox(height: 6),
            Wrap(spacing: 14, children: legend),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: yMin,
                  maxY: yMax,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (val, meta) => Text(
                          val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF757575)),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: allDates.length <= 6 ? 1 : (allDates.length / 5).ceilToDouble(),
                        getTitlesWidget: (val, meta) {
                          final idx = val.round();
                          if (idx < 0 || idx >= allDates.length) return const SizedBox.shrink();
                          final d = allDates[idx];
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${months[d.month - 1]} ${d.day}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF757575))),
                          );
                        },
                      ),
                    ),
                  ),
                  rangeAnnotations: RangeAnnotations(
                    horizontalRangeAnnotations: rangeAnnotations,
                  ),
                  lineBarsData: bars,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final param = seriesData.keys.elementAt(s.barIndex);
                        final d = allDates[s.x.round()];
                        return LineTooltipItem(
                          '${_paramShortLabel(param)}: ${s.y % 1 == 0 ? s.y.toInt() : s.y.toStringAsFixed(2)}\n${months[d.month - 1]} ${d.day}',
                          TextStyle(color: _paramColors[param] ?? Colors.white, fontSize: 11),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            if (rangeNotes.isNotEmpty || zeroParams.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final note in rangeNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 12,
                        decoration: BoxDecoration(
                          color: note.color,
                          border: Border.all(color: note.border, width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${note.label}: ${note.lo % 1 == 0 ? note.lo.toInt() : note.lo} – ${note.hi % 1 == 0 ? note.hi.toInt() : note.hi} ${note.unit}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF757575), height: 1.4),
                      ),
                    ],
                  ),
                ),
              if (zeroParams.isNotEmpty)
                Text(
                  'Ideal ${zeroParams.join(' & ')}: 0 ppm',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF757575), height: 1.4),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class EditTankFlowScreen extends StatelessWidget {
  final TankModel tank;
  const EditTankFlowScreen({super.key, required this.tank});
  @override
  Widget build(BuildContext context) => EditTankScreen(tank: tank);
}

class EditTankScreen extends StatefulWidget {
  final TankModel tank;
  const EditTankScreen({super.key, required this.tank});

  @override
  State<EditTankScreen> createState() => _EditTankScreenState();
}

class _EditTankScreenState extends State<EditTankScreen> {
  static const _lPerGal = 3.78541;
  static const _types = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  late final TextEditingController _nameCtrl;
  late final TextEditingController _sizeCtrl;
  String _unit = 'gal';
  late double _gallons;
  late WaterType _waterType;
  String? _waterBase;
  bool _hasPlants = false;
  final Set<String> _saltFeatures = {};
  List<_InhEdit> _inhs = [];
  List<_PlantEdit> _plts = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.tank.name);
    _gallons = widget.tank.gallons.toDouble();
    _sizeCtrl = TextEditingController(text: widget.tank.gallons.toString());
    _sizeCtrl.addListener(_onSizeChanged);
    _waterType = widget.tank.waterType;
    switch (widget.tank.waterType) {
      case WaterType.saltwater: _waterBase = 'saltwater';
      case WaterType.reef:      _waterBase = 'saltwater'; _saltFeatures.add('reef');
      case WaterType.planted:   _waterBase = 'freshwater'; _hasPlants = true;
      case WaterType.pond:      _waterBase = 'pond';
      case WaterType.freshwater: _waterBase = null;
    }
    _load();
  }

  void _onSizeChanged() {
    final val = double.tryParse(_sizeCtrl.text);
    if (val == null || val <= 0) return;
    _gallons = _unit == 'L' ? val / _lPerGal : val;
  }

  void _switchUnit(String unit) {
    if (unit == _unit) return;
    final current = double.tryParse(_sizeCtrl.text) ?? 0;
    setState(() => _unit = unit);
    if (current > 0) {
      final converted = unit == 'L' ? current * _lPerGal : current / _lPerGal;
      _sizeCtrl.text = converted.toStringAsFixed(1);
      _sizeCtrl.selection = TextSelection.collapsed(offset: _sizeCtrl.text.length);
    }
  }

  void _pushWaterType() {
    final WaterType wt;
    if (_waterBase == 'saltwater') {
      wt = _saltFeatures.isNotEmpty ? WaterType.reef : WaterType.saltwater;
    } else if (_waterBase == 'pond') {
      wt = WaterType.pond;
    } else {
      wt = _hasPlants ? WaterType.planted : WaterType.freshwater;
    }
    setState(() => _waterType = wt);
  }

  void _selectBase(String base) {
    setState(() { _waterBase = base; _hasPlants = false; _saltFeatures.clear(); });
    _pushWaterType();
  }

  Future<void> _load() async {
    final rawInhabitants = await TankStore.instance.inhabitantsFor(widget.tank.id);
    final rawPlants = await TankStore.instance.plantsFor(widget.tank.id);
    if (!mounted) return;
    setState(() {
      _inhs = rawInhabitants.map((i) => _InhEdit(nameText: i.name, type: i.type ?? 'fish', count: i.count)).toList();
      _plts = rawPlants.map((p) => _PlantEdit(nameText: p.name)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim().isEmpty ? widget.tank.name : _nameCtrl.text.trim();
      final tank = TankModel(id: widget.tank.id, name: name, gallons: _gallons.round(), waterType: _waterType, createdAt: widget.tank.createdAt);
      await TankStore.instance.saveTank(tank: tank);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showTopSnack(context, 'Error: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sizeCtrl.removeListener(_onSizeChanged);
    _sizeCtrl.dispose();
    for (final i in _inhs) i.dispose();
    for (final p in _plts) p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _cDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit Tank', style: TextStyle(color: _cDark, fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tank name
            const Text('Tank name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Living Room Tank',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            // Tank size
            const Text('Tank size', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sizeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      _UnitBtn(label: 'gal', selected: _unit == 'gal', onTap: () => _switchUnit('gal')),
                      Container(width: 1, height: 44, color: Colors.grey.shade300),
                      _UnitBtn(label: 'L', selected: _unit == 'L', onTap: () => _switchUnit('L')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Water type
            const Text('Water type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _WaterBaseCard(emoji: '💧', label: 'Freshwater', selected: _waterBase == 'freshwater', onTap: () => _selectBase('freshwater'))),
                const SizedBox(width: 10),
                Expanded(child: _WaterBaseCard(emoji: '🌊', label: 'Saltwater', selected: _waterBase == 'saltwater', onTap: () => _selectBase('saltwater'))),
                const SizedBox(width: 10),
                Expanded(child: _WaterBaseCard(emoji: '🪷', label: 'Pond', selected: _waterBase == 'pond', onTap: () => _selectBase('pond'))),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: (_waterBase == null || _waterBase == 'pond')
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _waterBase == 'freshwater'
                          ? _FreshwaterFollowUp(hasPlants: _hasPlants, onChanged: (v) { setState(() => _hasPlants = v); _pushWaterType(); })
                          : _SaltwaterFollowUp(selected: _saltFeatures, onToggle: (f) { setState(() { _saltFeatures.contains(f) ? _saltFeatures.remove(f) : _saltFeatures.add(f); }); _pushWaterType(); }),
                    ),
            ),
            const SizedBox(height: 24),
            // Equipment
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cDark,
                  side: const BorderSide(color: Color(0xFF1FA2A8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => _EquipmentScreen(tank: widget.tank, waterTypeOverride: _waterType)),
                  );
                },
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Equipment', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditInhabitantsScreen extends StatefulWidget {
  final TankModel tank;
  final VoidCallback onSaved;
  const EditInhabitantsScreen({super.key, required this.tank, required this.onSaved});

  @override
  State<EditInhabitantsScreen> createState() => _EditInhabitantsScreenState();
}

class _EditInhabitantsScreenState extends State<EditInhabitantsScreen> {
  static const _types = ['fish', 'invertebrate', 'coral', 'polyp', 'anemone'];
  static const _typeEmoji = {'fish': '🐟', 'invertebrate': '🦐', 'coral': '🪸', 'polyp': '🪼', 'anemone': '🌺'};

  List<_InhEdit> _inhs = [];
  List<_PlantEdit> _plts = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rawInhabitants = await TankStore.instance.inhabitantsFor(widget.tank.id);
    final rawPlants = await TankStore.instance.plantsFor(widget.tank.id);
    if (!mounted) return;
    setState(() {
      _inhs = rawInhabitants.map((i) => _InhEdit(nameText: i.name, type: i.type ?? 'fish', count: i.count)).toList();
      _plts = rawPlants.map((p) => _PlantEdit(nameText: p.name)).toList();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await TankStore.instance.saveParsedDetails(
        tank: widget.tank,
        inhabitants: _inhs.where((i) => i.name.text.trim().isNotEmpty).map((i) => {'name': i.name.text.trim(), 'type': i.type, 'count': i.count}).toList(),
        plants: _plts.map((p) => p.name.text.trim()).where((n) => n.isNotEmpty).toList(),
      );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showTopSnack(context, 'Error: $e');
    }
  }

  @override
  void dispose() {
    for (final i in _inhs) i.dispose();
    for (final p in _plts) p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _cDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit Inhabitants & Plants', style: TextStyle(color: _cDark, fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Inhabitants
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('INHABITANTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                TextButton.icon(
                  onPressed: () async {
                    final result = await showModalBottomSheet<({String name, String type, int count})>(
                      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                      builder: (_) => _SpeciesPickerSheet(isPlant: false, waterType: widget.tank.waterType),
                    );
                    if (result != null && mounted) setState(() => _inhs.add(_InhEdit(nameText: result.name, type: result.type, count: result.count)));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_inhs.length, (idx) {
              final inh = _inhs[idx];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: inh.type,
                      underline: const SizedBox(),
                      isDense: true,
                      items: _types.map((t) => DropdownMenuItem(value: t, child: Text(_typeEmoji[t] ?? '🐠', style: const TextStyle(fontSize: 20)))).toList(),
                      onChanged: (v) => setState(() => inh.type = v!),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final result = await showModalBottomSheet<({String name, String type, int count})>(
                            context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                            builder: (_) => _SpeciesPickerSheet(isPlant: false, waterType: widget.tank.waterType),
                          );
                          if (result != null && mounted) setState(() { inh.name.text = result.name; inh.type = result.type; });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                          child: Row(children: [
                            Expanded(child: Text(inh.name.text.isEmpty ? 'Tap to choose…' : inh.name.text, style: TextStyle(fontSize: 14, color: inh.name.text.isEmpty ? Colors.grey : Colors.black87))),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(icon: const Icon(Icons.remove, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: inh.count > 1 ? () => setState(() => inh.count--) : null),
                    SizedBox(width: 24, child: Text('${inh.count}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                    IconButton(icon: const Icon(Icons.add, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => setState(() => inh.count++)),
                    IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => setState(() { _inhs[idx].dispose(); _inhs.removeAt(idx); })),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
            // Plants
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PLANTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
                TextButton.icon(
                  onPressed: () async {
                    final result = await showModalBottomSheet<({String name, String type, int count})>(
                      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                      builder: (_) => const _SpeciesPickerSheet(isPlant: true),
                    );
                    if (result != null && mounted) setState(() => _plts.add(_PlantEdit(nameText: result.name)));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_plts.length, (idx) {
              final plt = _plts[idx];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text('🌿', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final result = await showModalBottomSheet<({String name, String type, int count})>(
                            context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                            builder: (_) => const _SpeciesPickerSheet(isPlant: true),
                          );
                          if (result != null && mounted) setState(() => plt.name.text = result.name);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                          child: Row(children: [
                            Expanded(child: Text(plt.name.text.isEmpty ? 'Tap to choose…' : plt.name.text, style: TextStyle(fontSize: 14, color: plt.name.text.isEmpty ? Colors.grey : Colors.black87))),
                            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                          ]),
                        ),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => setState(() { _plts[idx].dispose(); _plts.removeAt(idx); })),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

String _frequencyLabel(int days) {
  if (days == 1) return 'Daily';
  if (days == 7) return 'Weekly';
  if (days == 14) return 'Every 2 weeks';
  if (days == 30) return 'Monthly';
  if (days == 90) return 'Every 3 months';
  if (days == 3) return 'Every 3 days';
  return 'Every $days days';
}

class _ManageRecurringTasksScreen extends StatefulWidget {
  final String? tankId; // if non-null, pre-filter to this tank
  const _ManageRecurringTasksScreen({this.tankId});

  @override
  State<_ManageRecurringTasksScreen> createState() => _ManageRecurringTasksScreenState();
}

class _ManageRecurringTasksScreenState extends State<_ManageRecurringTasksScreen> {
  bool _loading = true;
  List<db.Task> _tasks = [];
  Map<String, String> _tankNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await TankStore.instance.getRecurringTasks(tankId: widget.tankId);
    final names = <String, String>{};
    for (final t in TankStore.instance.tanks) {
      names[t.id] = t.name;
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _tankNames = names;
      _loading = false;
    });
  }

  Future<void> _editFrequency(db.Task task) async {
    final frequencies = [
      (label: 'Daily', days: 1),
      (label: 'Every 3 days', days: 3),
      (label: 'Weekly', days: 7),
      (label: 'Every 2 weeks', days: 14),
      (label: 'Monthly', days: 30),
      (label: 'Every 3 months', days: 90),
    ];
    int selected = frequencies.indexWhere((f) => f.days == task.repeatDays);
    if (selected < 0) selected = 2;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int sel = selected;
        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            title: const Text('Change Frequency', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: frequencies.asMap().entries.map((e) {
                return RadioListTile<int>(
                  title: Text(e.value.label),
                  value: e.key,
                  groupValue: sel,
                  onChanged: (v) => setS(() => sel = v!),
                  dense: true,
                );
              }).toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, frequencies[sel].days), child: const Text('Save')),
            ],
          );
        });
      },
    );
    if (result != null && result != task.repeatDays) {
      await TankStore.instance.updateTaskFrequency(task.id, result);
      await _load();
    }
  }

  Future<void> _confirmDelete(db.Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('Delete "${task.description}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await TankStore.instance.deleteTask(task.id);
      await _load();
    }
  }

  Future<void> _createTask() async {
    final tanks = TankStore.instance.tanks;
    if (tanks.isEmpty) return;

    TankModel target;
    if (widget.tankId != null) {
      target = tanks.firstWhere((t) => t.id == widget.tankId, orElse: () => tanks.first);
    } else if (tanks.length == 1) {
      target = tanks.first;
    } else {
      // Let user pick a tank first
      final picked = await showDialog<TankModel>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Tank', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          children: tanks.map((t) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, t),
            child: Text(t.name),
          )).toList(),
        ),
      );
      if (picked == null) return;
      target = picked;
    }

    if (!mounted) return;
    final result = await showDialog<({String task, int days, DateTime startDate})>(
      context: context,
      builder: (ctx) => _RecurringTaskPicker(tankName: target.name, waterType: target.waterType),
    );
    if (result != null && mounted) {
      final due = result.startDate;
      final dueStr = '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
      await TankStore.instance.addTask(
        tankId: target.id,
        description: result.task,
        dueDate: dueStr,
        source: 'recurring',
        repeatDays: result.days,
      );
      await _load();
      if (mounted) {
        _showTopSnack(context, 'Recurring task added');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group tasks by tank
    final grouped = <String, List<db.Task>>{};
    for (final t in _tasks) {
      grouped.putIfAbsent(t.tankId, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Tasks')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTask,
        backgroundColor: _cDark,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.repeat, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('No recurring tasks yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        Text('Tap + to create one',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: grouped.entries.map((entry) {
                    final tankName = _tankNames[entry.key] ?? 'Unknown Tank';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(tankName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _cDark)),
                        ),
                        ...entry.value.map((task) => _buildTaskTile(task)),
                        const Divider(height: 1),
                      ],
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildTaskTile(db.Task task) {
    final freq = task.repeatDays != null ? _frequencyLabel(task.repeatDays!) : '—';
    final paused = task.isPaused;
    final dueDateStr = task.dueDate ?? '';

    return ListTile(
      leading: Icon(
        paused ? Icons.pause_circle_filled : Icons.repeat,
        color: paused ? Colors.orange : _cDark,
        size: 22,
      ),
      title: Text(
        task.description,
        style: TextStyle(
          fontSize: 14,
          color: paused ? Colors.grey : Colors.black87,
          decoration: paused ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '$freq${dueDateStr.isNotEmpty ? ' · Next: $dueDateStr' : ''}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (value) async {
          if (value == 'pause') {
            await TankStore.instance.toggleTaskPaused(task.id, !task.isPaused);
            await _load();
          } else if (value == 'frequency') {
            await _editFrequency(task);
          } else if (value == 'delete') {
            await _confirmDelete(task);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pause',
            child: Text(paused ? 'Resume' : 'Pause'),
          ),
          const PopupMenuItem(value: 'frequency', child: Text('Change Frequency')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE SCREEN
// ═══════════════════════════════════════════════════════════════════════════
// COMMUNITY SCREEN
// ═══════════════════════════════════════════════════════════════════════════

/// Positive-only emoji palette for reactions.
const _kReactionEmojis = ['👍', '❤️', '🔥', '😍', '🐠', '🌊', '💯', '👏'];

class _CommunityScreen extends StatefulWidget {
  final String initialChannel;
  const _CommunityScreen({this.initialChannel = 'general'});
  @override
  State<_CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<_CommunityScreen> {
  List<String> get _channels => [
    'general', 'freshwater', 'saltwater', 'mine',
    if (SupabaseService.isAdmin) 'flagged',
  ];
  static const _channelLabels = {'general': 'General', 'freshwater': 'Freshwater', 'saltwater': 'Saltwater', 'mine': 'My Shares', 'flagged': 'Flagged'};
  late String _channel = widget.initialChannel;
  List<Map<String, dynamic>> _posts = [];
  Map<int, List<Map<String, dynamic>>> _reactions = {};
  Set<String> _blockedUserIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedThenPosts();
  }

  Future<void> _loadBlockedThenPosts() async {
    try {
      _blockedUserIds = await SupabaseService.fetchBlockedUserIds();
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    try {
      var posts = _channel == 'flagged'
          ? await SupabaseService.fetchFlaggedPosts()
          : _channel == 'mine'
          ? await SupabaseService.fetchMyPosts()
          : await SupabaseService.fetchPosts(channel: _channel);
      // Filter out posts from blocked users (keep own posts and admin view)
      if (_blockedUserIds.isNotEmpty && _channel != 'mine' && _channel != 'flagged') {
        posts = posts.where((p) => !_blockedUserIds.contains(p['user_id'] as String)).toList();
      }
      // Batch-sign all photo URLs in one call
      final paths = posts.map((p) => p['photo_url'] as String).toList();
      final signedUrls = await SupabaseService.getCommunityPhotoUrls(paths);
      for (final post in posts) {
        post['_signed_url'] = signedUrls[post['photo_url']] ?? '';
      }
      final postIds = posts.map((p) => p['id'] as int).toList();
      final reactions = await SupabaseService.fetchReactions(postIds);
      if (mounted) setState(() { _posts = posts; _reactions = reactions; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showTopSnack(context, 'Error loading posts: $e');
      }
    }
  }

  Future<void> _createPost() async {
    // Pick image source — camera, gallery, or from tank photos
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_album_outlined),
              title: const Text('From Tank Photos'),
              onTap: () => Navigator.of(ctx).pop('tank'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    String? pickedPath;

    if (choice == 'tank') {
      // Pick from tank photos — choose tank first if multiple
      final tanks = TankStore.instance.tanks;
      if (tanks.isEmpty) {
        _showTopSnack(context, 'No tanks found');
        return;
      }
      TankModel tank;
      if (tanks.length == 1) {
        tank = tanks.first;
      } else {
        final selected = await showModalBottomSheet<TankModel>(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Pick a tank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ...tanks.map((t) => ListTile(
                  leading: const Icon(Icons.water_drop_outlined, color: _cDark),
                  title: Text(t.name),
                  subtitle: Text('${t.gallons}g ${t.waterType.label}'),
                  onTap: () => Navigator.pop(ctx, t),
                )),
              ],
            ),
          ),
        );
        if (selected == null || !mounted) return;
        tank = selected;
      }
      // Load photos for the selected tank
      final photos = await TankStore.instance.photosFor(tank.id);
      if (photos.isEmpty) {
        if (mounted) _showTopSnack(context, 'No photos in ${tank.name}');
        return;
      }
      if (!mounted) return;
      // Show photo grid picker
      final photo = await showModalBottomSheet<db.TankPhoto>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('${tank.name} — Photos', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (_, i) {
                    final p = photos[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, p),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(File(p.filePath), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (photo == null || !mounted) return;
      pickedPath = photo.filePath;
    } else {
      final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
      if (picked == null || !mounted) return;
      pickedPath = picked.path;
    }

    if (pickedPath == null || !mounted) return;
    final picked = XFile(pickedPath);

    // Show caption dialog
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Share to Community'),
          content: SizedBox(
            width: 300,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(picked.path), height: 180, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLength: 150,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Add a caption...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _cDark),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
    if (caption == null || !mounted) return;

    // Upload and create post
    _showPostingOverlay();
    try {
      final photoUrl = await SupabaseService.uploadCommunityPhoto(picked.path);
      await SupabaseService.createPost(photoUrl: photoUrl, caption: caption, channel: _channel);
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        _load();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss overlay
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload failed'),
            content: Text('$e'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  void _showPostingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Sharing...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(int postId, String emoji) async {
    try {
      await SupabaseService.toggleReaction(postId, emoji);
      // Refresh reactions for this post
      final updated = await SupabaseService.fetchReactions([postId]);
      if (mounted) setState(() => _reactions[postId] = updated[postId] ?? []);
    } catch (e) {
      if (mounted) _showTopSnack(context, '$e');
    }
  }

  void _showEmojiPicker(int postId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _kReactionEmojis.map((emoji) => GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _toggleReaction(postId, emoji);
              },
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            )).toList(),
          ),
        ),
      ),
    );
  }

  String _authorName(Map<String, dynamic> post) {
    final profile = post['profiles'] as Map<String, dynamic>?;
    if (profile == null) return 'Aquarist';
    final display = profile['display_name'] as String?;
    final username = profile['username'] as String?;
    if (display != null && display.isNotEmpty && !display.contains('@')) return display;
    if (username != null && username.isNotEmpty) return '@$username';
    return 'Aquarist';
  }

  String _timeAgo(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  Widget _buildReactionBar(int postId) {
    final reactions = _reactions[postId] ?? [];
    final uid = SupabaseService.userId;
    // Group by emoji
    final counts = <String, int>{};
    final userReacted = <String, bool>{};
    for (final r in reactions) {
      final emoji = r['emoji'] as String;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (r['user_id'] == uid) userReacted[emoji] = true;
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...counts.entries.map((e) => GestureDetector(
          onTap: () => _toggleReaction(postId, e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: userReacted[e.key] == true ? const Color(0xFFE0F2F1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: userReacted[e.key] == true ? const Color(0xFF1FA2A8) : Colors.grey.shade300,
              ),
            ),
            child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 13)),
          ),
        )),
        GestureDetector(
          onTap: () => _showEmojiPicker(postId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Icon(Icons.add_reaction_outlined, size: 16, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  void _openFullScreenImage(String url, {String? photoStoragePath}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullScreenNetworkImage(url: url, photoStoragePath: photoStoragePath),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, '', showCommunity: false, actions: [
        const _NotificationBellIcon(),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1FA2A8),
        onPressed: _createPost,
        child: const Icon(Icons.add_a_photo, color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Community', style: TextStyle(color: _cDark, fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1FA2A8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: _channels.map((ch) {
                final selected = ch == _channel;
                return Expanded(
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(_channelLabels[ch]!, textAlign: TextAlign.center),
                    ),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: const Color(0xFF1FA2A8),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    labelPadding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    onSelected: (_) {
                      if (ch != _channel) {
                        setState(() { _channel = ch; _loading = true; });
                        _load();
                      }
                    },
                  ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('No posts yet', style: TextStyle(color: Colors.black54, fontSize: 16)),
                            const SizedBox(height: 4),
                            const Text('Be the first to share!', style: TextStyle(color: Colors.black38, fontSize: 13)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: _posts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (_, i) {
                      final post = _posts[i];
                      final postId = post['id'] as int;
                      final isAuthor = post['user_id'] == SupabaseService.userId;
                      final isHidden = post['is_hidden'] == true;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Admin moderation banner
                            if (SupabaseService.isAdmin) ...[
                              if (post['admin_action'] == 'deleted')
                                Container(
                                  width: double.infinity,
                                  color: Colors.grey.shade200,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_forever, size: 16, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(
                                        'Deleted by admin${post['admin_action_at'] != null ? ' — ${_timeAgo(post['admin_action_at'] as String)}' : ''}',
                                        style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                                      )),
                                    ],
                                  ),
                                )
                              else if (post['admin_action'] == 'restored')
                                Container(
                                  width: double.infinity,
                                  color: Colors.green.shade50,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(
                                        'Restored by admin${post['admin_action_at'] != null ? ' — ${_timeAgo(post['admin_action_at'] as String)}' : ''}',
                                        style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                                      )),
                                    ],
                                  ),
                                )
                              else if (isHidden)
                                Container(
                                  width: double.infinity,
                                  color: Colors.red.shade50,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber, size: 16, color: Colors.red),
                                      const SizedBox(width: 8),
                                      const Expanded(child: Text('Flagged — hidden from users', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600))),
                                      TextButton(
                                        onPressed: () async {
                                          await SupabaseService.unhidePost(postId);
                                          _load();
                                        },
                                        child: const Text('Restore', style: TextStyle(fontSize: 12)),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Confirm removal'),
                                              content: const Text('This will hide the post permanently and notify the user of a violation.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                  child: const Text('Remove'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            await SupabaseService.adminDeletePost(postId);
                                            if (mounted) {
                                              _showTopSnack(context, 'Post removed and user notified.');
                                            }
                                            _load();
                                          }
                                        },
                                        child: const Text('Remove', style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            // Photo
                            GestureDetector(
                              onTap: () => _openFullScreenImage(
                                post['_signed_url'] as String,
                                photoStoragePath: isAuthor ? (post['photo_url'] as String?) : null,
                              ),
                              child: Image.network(
                                post['_signed_url'] as String,
                                width: double.infinity,
                                height: 260,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 260,
                                  color: Colors.grey.shade200,
                                  child: const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.grey)),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Author + time + delete
                                  Row(
                                    children: [
                                      const Icon(Icons.account_circle, size: 20, color: Color(0xFF1FA2A8)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _authorName(post),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        _timeAgo(post['created_at'] as String),
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                      if (isAuthor)
                                        IconButton(
                                          icon: const Icon(Icons.send, size: 16),
                                          color: const Color(0xFF5865F2),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'Share to Discord',
                                          onPressed: () {
                                            final photoPath = post['photo_url'] as String? ?? '';
                                            if (photoPath.isNotEmpty) {
                                              _showDiscordShareFlow(context, photoPath);
                                            }
                                          },
                                        ),
                                      if (isAuthor)
                                        const SizedBox(width: 8),
                                      if (isAuthor)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          color: Colors.grey,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Delete post?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              await SupabaseService.deletePost(postId);
                                              _load();
                                            }
                                          },
                                        ),
                                      if (!isAuthor)
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onSelected: (value) async {
                                            if (value == 'report') {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Report this post?'),
                                                  content: const Text('Flag this post as inappropriate. Posts flagged by multiple users will be hidden and reviewed.'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                      child: const Text('Report'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                final flagged = await SupabaseService.flagPost(postId);
                                                if (mounted) {
                                                  _showTopSnack(context, flagged ? 'Post reported. Thank you.' : 'You have already reported this post.');
                                                  _load();
                                                }
                                              }
                                            } else if (value == 'block') {
                                              final authorName = _authorName(post);
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Block this user?'),
                                                  content: Text('You will no longer see posts from $authorName. You can unblock them from your profile.'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                      child: const Text('Block'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                final blocked = await SupabaseService.blockUser(post['user_id'] as String);
                                                if (mounted) {
                                                  if (blocked) {
                                                    _blockedUserIds.add(post['user_id'] as String);
                                                    _showTopSnack(context, '$authorName blocked.');
                                                  } else {
                                                    _showTopSnack(context, 'User already blocked.');
                                                  }
                                                  _load();
                                                }
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'report', child: Row(children: [
                                              Icon(Icons.flag_outlined, size: 18), SizedBox(width: 8), Text('Report'),
                                            ])),
                                            PopupMenuItem(value: 'block', child: Row(children: [
                                              Icon(Icons.block, size: 18), SizedBox(width: 8), Text('Block User'),
                                            ])),
                                          ],
                                        ),
                                    ],
                                  ),
                                  // Caption
                                  if ((post['caption'] as String?)?.isNotEmpty == true) ...[
                                    const SizedBox(height: 8),
                                    Text(post['caption'] as String, style: const TextStyle(fontSize: 14)),
                                  ],
                                  // Reactions
                                  const SizedBox(height: 10),
                                  _buildReactionBar(postId),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen();

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _usernameError;
  String? _originalUsername;
  DateTime? _createdAt;
  List<Map<String, dynamic>> _blockedUsers = [];

  static final _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SupabaseService.fetchProfile(),
      _loadBlockedUsers(),
    ]);
    final profile = results[0] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      _displayNameCtrl.text = (profile?['display_name'] as String?) ?? '';
      _usernameCtrl.text = (profile?['username'] as String?) ?? '';
      _originalUsername = profile?['username'] as String?;
      final raw = profile?['created_at'] as String?;
      _createdAt = raw != null ? DateTime.tryParse(raw) : null;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadBlockedUsers() async {
    try {
      final uid = SupabaseService.userId;
      if (uid == null) return [];
      final data = await SupabaseService.client
          .from('blocked_users')
          .select('blocked_user_id, created_at, profiles:blocked_user_id(display_name, username)')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(data);
      if (mounted) setState(() => _blockedUsers = list);
      return list;
    } catch (e) {
      debugPrint('[Profile] Failed to load blocked users: $e');
      return [];
    }
  }

  String? _validateUsername(String value) {
    if (value.isEmpty) return null; // optional
    if (value.length < 3) return 'At least 3 characters';
    if (value.length > 20) return '20 characters max';
    if (!_usernameRe.hasMatch(value)) return 'Lowercase letters, numbers, and underscores only';
    return null;
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim().toLowerCase();
    final displayName = _displayNameCtrl.text.trim();

    // Validate username
    final valError = _validateUsername(username);
    if (valError != null) {
      setState(() => _usernameError = valError);
      return;
    }

    setState(() { _saving = true; _usernameError = null; });

    // Check availability if username changed
    if (username.isNotEmpty && username != _originalUsername) {
      final available = await SupabaseService.isUsernameAvailable(username);
      if (!available) {
        if (mounted) setState(() { _saving = false; _usernameError = 'Username already taken'; });
        return;
      }
    }

    try {
      await SupabaseService.updateProfile(
        displayName: displayName.isNotEmpty ? displayName : null,
        username: username.isNotEmpty ? username : null,
      );
      if (mounted) {
        setState(() { _saving = false; _originalUsername = username.isNotEmpty ? username : null; });
        _showTopSnack(context, 'Profile saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        final msg = e.toString();
        if (msg.contains('duplicate') || msg.contains('unique')) {
          setState(() => _usernameError = 'Username already taken');
        } else {
          _showTopSnack(context, 'Error: $msg');
        }
      }
    }
  }

  Future<void> _confirmCloseAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Account'),
        content: const Text(
          'This will close your account and sign you out. Your data will be retained for up to 12 months per our privacy policy, then permanently deleted.\n\nYou will not be able to access your tanks, logs, or any other data after closing.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Close Account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Second confirmation
    final reallyConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Type CLOSE to confirm.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          _CloseConfirmButton(onConfirmed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (reallyConfirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await SupabaseService.closeAccount();
      await TankStore.instance.clearLocal();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const _AppEntry()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        _showTopSnack(context, 'Failed to close account: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, ''),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _cDark)),
                  const SizedBox(height: 20),
                  // Email (read-only)
                  Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(SupabaseService.userEmail ?? '', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 20),
                  // Display name
                  Text('Display Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _displayNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Your name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Username
                  Text('Username', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _usernameCtrl,
                    decoration: InputDecoration(
                      hintText: 'unique_username',
                      prefixText: '@',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      errorText: _usernameError,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    onChanged: (_) { if (_usernameError != null) setState(() => _usernameError = null); },
                  ),
                  const SizedBox(height: 4),
                  Text('3–20 characters. Letters, numbers, underscores.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 24),
                  // Member since
                  if (_createdAt != null) ...[
                    Text('Member Since', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Text(
                      '${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_createdAt!.month - 1]} ${_createdAt!.day}, ${_createdAt!.year}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Tanks count
                  Text('Tanks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text('${TankStore.instance.tanks.length}', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 24),
                  // Blocked users
                  if (_blockedUsers.isNotEmpty) ...[
                    Text('Blocked Users', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    ..._blockedUsers.map((b) {
                      final profile = b['profiles'] as Map<String, dynamic>?;
                      final display = profile?['display_name'] as String?;
                      final username = profile?['username'] as String?;
                      final name = (display != null && display.isNotEmpty && !display.contains('@'))
                          ? display
                          : (username != null && username.isNotEmpty)
                              ? '@$username'
                              : 'Unknown user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.block, size: 16, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
                            TextButton(
                              onPressed: () async {
                                await SupabaseService.unblockUser(b['blocked_user_id'] as String);
                                if (mounted) {
                                  _showTopSnack(context, '$name unblocked.');
                                  _loadBlockedUsers();
                                }
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Unblock', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _cDark),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text('Danger Zone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red)),
                  const SizedBox(height: 8),
                  const Text(
                    'Close your account and sign out. Your account will be marked for permanent deletion.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: _deleting ? null : _confirmCloseAccount,
                      child: _deleting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                          : const Text('Close Account'),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

/// TextField-based confirm button that only enables when user types "CLOSE".
class _CloseConfirmButton extends StatefulWidget {
  final VoidCallback onConfirmed;
  const _CloseConfirmButton({required this.onConfirmed});

  @override
  State<_CloseConfirmButton> createState() => _CloseConfirmButtonState();
}

class _CloseConfirmButtonState extends State<_CloseConfirmButton> {
  final _ctrl = TextEditingController();
  bool _match = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type CLOSE', isDense: true),
            onChanged: (v) => setState(() => _match = v.trim().toUpperCase() == 'CLOSE'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _match ? widget.onConfirmed : null,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Close Account'),
        ),
      ],
    );
  }
}

class ArchivedTanksScreen extends StatefulWidget {
  const ArchivedTanksScreen({super.key});

  @override
  State<ArchivedTanksScreen> createState() => _ArchivedTanksScreenState();
}

class _ArchivedTanksScreenState extends State<ArchivedTanksScreen> {
  bool _loading = true;
  List<TankModel> _archived = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _archived = await TankStore.instance.getArchived();
    } catch (e) {
      _error = e.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _restore(String id) async {
    try {
      await TankStore.instance.restore(id);
      await _load();
      if (!mounted) return;
      _showTopSnack(context, 'Restored tank');
    } catch (e) {
      if (!mounted) return;
      _showTopSnack(context, 'Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context, 'Archived Tanks'),
      bottomNavigationBar: _AquariaFooter(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error:\n\n$_error'),
                  ),
                )
              : (_archived.isEmpty)
                  ? const Center(child: Text('No archived tanks.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: _archived.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = _archived[i];
                        return ListTile(
                          title: Text(t.name),
                          subtitle: Text('${t.gallons} gal • ${t.waterType.label}'),
                          trailing: TextButton(
                            onPressed: () => _restore(t.id),
                            child: const Text('Restore'),
                          ),
                        );
                      },
                    ),
                    ),
    );
  }
}