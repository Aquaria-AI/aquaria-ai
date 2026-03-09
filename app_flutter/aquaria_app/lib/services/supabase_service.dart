import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://jdiwsvealnrzdxofomvz.supabase.co';
const _supabaseAnonKey = 'sb_publishable_syXNGrF-g9mAGkTWO30EXg_sBIiTTHc';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;
  static String? get userId => currentUser?.id;
  static String? get userEmail => currentUser?.email;
  static bool get isLoggedIn => currentUser != null;

  static Future<void> init() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  static Future<AuthResponse> signUpWithEmail(String email, String password) {
    return client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signInWithEmail(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() {
    return client.auth.signOut();
  }

  /// Returns true if the current user's account has been closed (soft-deleted).
  static Future<bool> isAccountClosed() async {
    final profile = await fetchProfile();
    if (profile == null) return false;
    return profile['closed_at'] != null;
  }

  /// Close the current user's account (soft-delete).
  /// Sets profiles.closed_at so RLS blocks all data access,
  /// then signs the user out. Data retained per privacy policy.
  static Future<void> closeAccount() async {
    final uid = userId;
    if (uid == null) throw Exception('Not logged in');
    await client.rpc('close_user_account');
    await client.auth.signOut();
  }

  static Future<AuthResponse> signInWithGoogle() async {
    const webClientId = '710206253790-t370vahqu6hrnh21ume0474ajqp1l7jt.apps.googleusercontent.com';
    const iosClientId = '710206253790-4qollfoaeal3bau5rhas3emqn9uhqpd2.apps.googleusercontent.com';

    final googleSignIn = GoogleSignIn(
      clientId: iosClientId,
      serverClientId: webClientId,
    );

    // Clear any cached session so the user gets a fresh prompt
    await googleSignIn.signOut();

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) throw Exception('No ID token from Google');

    return client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  static Future<AuthResponse> signInWithApple() async {
    final rawNonce = client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) throw Exception('No ID token from Apple');

    return client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  /// Clone the sample tank into the new user's account (called once after signup).
  static Future<void> cloneSampleTank() async {
    final uid = userId;
    if (uid == null) return;
    try {
      await client.rpc('clone_sample_tank', params: {'target_user_id': uid});
      debugPrint('[Supabase] cloneSampleTank succeeded');
    } catch (e) {
      debugPrint('[Supabase] cloneSampleTank failed: $e');
    }
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchProfile() async {
    final uid = userId;
    if (uid == null) return null;
    final data = await client.from('profiles').select().eq('id', uid).maybeSingle();
    return data;
  }

  static Future<void> updateProfile({String? displayName, String? username}) async {
    final uid = userId;
    if (uid == null) return;
    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (username != null) updates['username'] = username.toLowerCase();
    if (updates.isEmpty) return;
    await client.from('profiles').update(updates).eq('id', uid);
  }

  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final result = await client.rpc('is_username_available', params: {'desired_username': username.toLowerCase()});
      return result == true;
    } catch (e) {
      debugPrint('[Supabase] isUsernameAvailable error: $e');
      return false;
    }
  }

  // ── Tanks CRUD ───────────────────────────────────────────────────────────

  static Future<void> insertTank({
    required String id,
    required String name,
    required int gallons,
    required String waterType,
    String? tapWaterJson,
    bool isArchived = false,
    required DateTime createdAt,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('tanks').insert({
      'id': id,
      'user_id': uid,
      'name': name,
      'gallons': gallons,
      'water_type': waterType,
      'tap_water_json': tapWaterJson,
      'is_archived': isArchived,
      'created_at': createdAt.toUtc().toIso8601String(),
    });
  }

  static Future<void> upsertTank({
    required String id,
    required String name,
    required int gallons,
    required String waterType,
    String? tapWaterJson,
    bool isArchived = false,
    required DateTime createdAt,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('tanks').upsert(
      {
        'id': id,
        'user_id': uid,
        'name': name,
        'gallons': gallons,
        'water_type': waterType,
        'tap_water_json': tapWaterJson,
        'is_archived': isArchived,
        'created_at': createdAt.toUtc().toIso8601String(),
      },
      onConflict: 'id',
    );
  }

  static Future<List<Map<String, dynamic>>> fetchTanks() async {
    final uid = userId;
    if (uid == null) return [];
    final data = await client
        .from('tanks')
        .select()
        .eq('user_id', uid)
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> deleteTank(String id) async {
    await client.from('tanks').delete().eq('id', id);
  }

  static Future<void> updateTapWater(String tankId, String? tapWaterJson) async {
    await client.from('tanks').update({'tap_water_json': tapWaterJson}).eq('id', tankId);
  }

  // ── Inhabitants CRUD ─────────────────────────────────────────────────────

  static Future<void> replaceInhabitants(String tankId, List<Map<String, dynamic>> inhabitants) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('inhabitants').delete().eq('tank_id', tankId);
    if (inhabitants.isEmpty) return;
    final rows = inhabitants.map((i) => {
      'tank_id': tankId,
      'user_id': uid,
      'name': i['name'],
      'count': i['count'] ?? 1,
      'type': i['type'],
    }).toList();
    await client.from('inhabitants').insert(rows);
  }

  static Future<List<Map<String, dynamic>>> fetchInhabitants(String tankId) async {
    final data = await client
        .from('inhabitants')
        .select()
        .eq('tank_id', tankId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Plants CRUD ──────────────────────────────────────────────────────────

  static Future<void> replacePlants(String tankId, List<String> plants) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('plants').delete().eq('tank_id', tankId);
    if (plants.isEmpty) return;
    final rows = plants.map((p) => {
      'tank_id': tankId,
      'user_id': uid,
      'name': p,
    }).toList();
    await client.from('plants').insert(rows);
  }

  static Future<List<Map<String, dynamic>>> fetchPlants(String tankId) async {
    final data = await client
        .from('plants')
        .select()
        .eq('tank_id', tankId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Logs CRUD ────────────────────────────────────────────────────────────

  static Future<void> insertLog({
    required String tankId,
    required String rawText,
    String? parsedJson,
    required DateTime createdAt,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('logs').insert({
      'tank_id': tankId,
      'user_id': uid,
      'raw_text': rawText,
      'parsed_json': parsedJson,
      'created_at': createdAt.toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> fetchLogs(String tankId) async {
    final data = await client
        .from('logs')
        .select()
        .eq('tank_id', tankId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> updateLog(int id, String rawText, String? parsedJson) async {
    await client.from('logs').update({
      'raw_text': rawText,
      'parsed_json': parsedJson,
    }).eq('id', id);
  }

  static Future<void> updateLogByKey(String tankId, DateTime createdAt, String rawText, String? parsedJson) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('logs').update({
      'raw_text': rawText,
      'parsed_json': parsedJson,
    }).eq('user_id', uid).eq('tank_id', tankId).eq('created_at', createdAt.toUtc().toIso8601String());
  }

  static Future<void> deleteLog(int id) async {
    await client.from('logs').delete().eq('id', id);
  }

  static Future<void> deleteLogByKey(String tankId, DateTime createdAt) async {
    final uid = userId;
    if (uid == null) return;
    await client
        .from('logs')
        .delete()
        .eq('user_id', uid)
        .eq('tank_id', tankId)
        .eq('created_at', createdAt.toUtc().toIso8601String());
  }

  // ── Tasks ───────────────────────────────────────────────────────────

  static Future<void> insertTask({
    required String tankId,
    required String description,
    String? dueDate,
    String priority = 'normal',
    String source = 'ai',
    int? repeatDays,
    bool isPaused = false,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('tasks').insert({
      'tank_id': tankId,
      'user_id': uid,
      'description': description,
      'due_date': dueDate,
      'priority': priority,
      'source': source,
      'repeat_days': repeatDays,
      'is_paused': isPaused,
    });
  }

  static Future<List<Map<String, dynamic>>> fetchActiveTasks() async {
    final uid = userId;
    if (uid == null) return [];
    final data = await client
        .from('tasks')
        .select()
        .eq('user_id', uid)
        .eq('is_dismissed', false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> dismissTaskById(int id) async {
    await client.from('tasks').update({
      'is_dismissed': true,
      'dismissed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Dismiss a task by matching key fields (works across local/cloud ID mismatch).
  static Future<void> dismissTaskByKey({
    required String tankId,
    required String description,
    required DateTime createdAt,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('tasks').update({
      'is_dismissed': true,
      'dismissed_at': DateTime.now().toUtc().toIso8601String(),
    })
    .eq('user_id', uid)
    .eq('tank_id', tankId)
    .eq('description', description)
    .eq('is_dismissed', false);
  }

  // ── Legal Acceptances ────────────────────────────────────────────────

  static const currentTermsVersion = '2026-03-09';
  static const currentPrivacyVersion = '2026-03-09';

  static Future<bool> hasAcceptedCurrentTerms() async {
    final uid = userId;
    if (uid == null) return false;
    final data = await client
        .from('legal_acceptances')
        .select('id')
        .eq('user_id', uid)
        .eq('terms_version', currentTermsVersion)
        .eq('privacy_version', currentPrivacyVersion)
        .limit(1);
    return (data as List).isNotEmpty;
  }

  static Future<void> recordAcceptance({
    String? appVersion,
    String? deviceInfo,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('legal_acceptances').insert({
      'user_id': uid,
      'email': userEmail,
      'username': null, // populated later if user sets one
      'terms_version': currentTermsVersion,
      'privacy_version': currentPrivacyVersion,
      'app_version': appVersion,
      'device_info': deviceInfo,
    });
  }

  // ── Dismissed Tasks (legacy) ───────────────────────────────────────────

  static Future<void> dismissTask(String taskKey) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('dismissed_tasks').upsert({
      'user_id': uid,
      'task_key': taskKey,
    });
  }

  static Future<Set<String>> fetchDismissedTasks() async {
    final uid = userId;
    if (uid == null) return {};
    final data = await client
        .from('dismissed_tasks')
        .select('task_key')
        .eq('user_id', uid);
    return data.map<String>((r) => r['task_key'] as String).toSet();
  }

  // ── Community ──────────────────────────────────────────────────────────

  /// Upload a photo to Supabase Storage and return the storage path.
  /// The bucket is private — use [getCommunityPhotoUrl] to get a signed URL.
  static Future<String> uploadCommunityPhoto(String filePath) async {
    final uid = userId;
    if (uid == null) throw Exception('Not logged in');
    final ext = filePath.split('.').last;
    final storagePath = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await File(filePath).readAsBytes();
    await client.storage.from('community-photos').uploadBinary(
      storagePath,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    return storagePath;
  }

  /// Get signed URLs for community photos in one batch call (valid for 1 hour).
  static Future<Map<String, String>> getCommunityPhotoUrls(List<String> storagePaths) async {
    if (storagePaths.isEmpty) return {};
    final results = await client.storage
        .from('community-photos')
        .createSignedUrls(storagePaths, 3600);
    final map = <String, String>{};
    for (final r in results) {
      if (r.signedUrl.isNotEmpty) {
        map[r.path ?? ''] = r.signedUrl;
      }
    }
    return map;
  }

  /// Create a community post with a photo URL and caption.
  static Future<void> createPost({
    required String photoUrl,
    required String caption,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await client.from('community_posts').insert({
      'user_id': uid,
      'photo_url': photoUrl,
      'caption': caption,
    });
  }

  /// Fetch all posts in the general channel, newest first.
  static Future<List<Map<String, dynamic>>> fetchPosts() async {
    final data = await client
        .from('community_posts')
        .select('*, profiles!inner(display_name, username)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Fetch reactions for a list of post IDs.
  static Future<Map<int, List<Map<String, dynamic>>>> fetchReactions(List<int> postIds) async {
    if (postIds.isEmpty) return {};
    final data = await client
        .from('post_reactions')
        .select()
        .inFilter('post_id', postIds);
    final map = <int, List<Map<String, dynamic>>>{};
    for (final r in data) {
      final pid = r['post_id'] as int;
      map.putIfAbsent(pid, () => []).add(r);
    }
    return map;
  }

  /// Toggle a reaction on a post. Returns true if added, false if removed.
  static Future<bool> toggleReaction(int postId, String emoji) async {
    final uid = userId;
    if (uid == null) throw Exception('Not logged in');
    // Check if reaction already exists
    final existing = await client
        .from('post_reactions')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', uid)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing != null) {
      await client.from('post_reactions').delete().eq('id', existing['id']);
      return false;
    } else {
      await client.from('post_reactions').insert({
        'post_id': postId,
        'user_id': uid,
        'emoji': emoji,
      });
      return true;
    }
  }

  /// Delete a community post (only the author can delete via RLS).
  static Future<void> deletePost(int postId) async {
    await client.from('community_posts').delete().eq('id', postId);
  }

  // ── Full Sync (pull from cloud) ──────────────────────────────────────────

  static Future<Map<String, dynamic>> pullAll() async {
    final uid = userId;
    if (uid == null) return {};
    final tanks = await fetchTanks();
    final dismissed = await fetchDismissedTasks();
    final activeTasks = await fetchActiveTasks();
    final allInhabitants = <String, List<Map<String, dynamic>>>{};
    final allPlants = <String, List<Map<String, dynamic>>>{};
    final allLogs = <String, List<Map<String, dynamic>>>{};
    for (final tank in tanks) {
      final id = tank['id'] as String;
      allInhabitants[id] = await fetchInhabitants(id);
      allPlants[id] = await fetchPlants(id);
      allLogs[id] = await fetchLogs(id);
    }
    return {
      'tanks': tanks,
      'inhabitants': allInhabitants,
      'plants': allPlants,
      'logs': allLogs,
      'dismissed_tasks': dismissed,
      'tasks': activeTasks,
    };
  }
}
