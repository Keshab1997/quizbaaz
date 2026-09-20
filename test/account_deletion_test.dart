import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/user_model.dart';
import 'package:quizbaaz/data/services/account_deletion_service.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/sync_service.dart';

/// R15 — account deletion must never destroy data before the user has proved
/// they own the account, and must never claim a clean deletion it cannot back
/// up.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('qb_delete_test');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.clearAll();
  });

  AccountDeletionService serviceWith({
    required Future<void> Function(String uid) reAuth,
    required Future<AccountCleanupReport> Function(String uid) cleanup,
  }) =>
      AccountDeletionService(reAuthenticate: reAuth, remoteCleanup: cleanup);

  test('cancelling re-auth leaves everything untouched', () async {
    var cleanupRuns = 0;
    var authDeletes = 0;

    final service = serviceWith(
      reAuth: (_) async => throw const AccountDeletionCanceled(),
      cleanup: (_) async {
        cleanupRuns++;
        return const AccountCleanupReport();
      },
    );

    final result = await service.deleteAccountWith(
      uid: 'uid-a',
      providerIds: const ['google.com'],
      deleteAuthUser: () async => authDeletes++,
    );

    expect(result.status, AccountDeletionStatus.canceled);
    expect(cleanupRuns, 0, reason: 'remote data must not be touched');
    expect(authDeletes, 0);
    expect(AccountDeletionService.isDeletionPending('uid-a'), isFalse);
    expect(result.accountGone, isFalse);
  });

  test('a failed re-auth leaves everything untouched too', () async {
    var cleanupRuns = 0;

    final service = serviceWith(
      reAuth: (_) async => throw Exception('network down'),
      cleanup: (_) async {
        cleanupRuns++;
        return const AccountCleanupReport();
      },
    );

    final result = await service.deleteAccountWith(
      uid: 'uid-a',
      providerIds: const ['google.com'],
      deleteAuthUser: () async {},
    );

    expect(result.status, AccountDeletionStatus.failed);
    expect(cleanupRuns, 0);
    expect(AccountDeletionService.isDeletionPending('uid-a'), isFalse);
  });

  test('the order is re-auth → cleanup → the account itself', () async {
    final order = <String>[];
    final service = serviceWith(
      reAuth: (_) async => order.add('re-auth'),
      cleanup: (_) async {
        order.add('cleanup');
        return const AccountCleanupReport(deleted: ['users/uid-a']);
      },
    );

    final result = await service.deleteAccountWith(
      uid: 'uid-a',
      providerIds: const ['google.com'],
      deleteAuthUser: () async => order.add('delete-auth'),
    );

    expect(result.status, AccountDeletionStatus.success);
    expect(result.report.isComplete, isTrue);
    expect(order, ['re-auth', 'cleanup', 'delete-auth']);
    expect(result.accountGone, isTrue);
    // The tombstone stays in place: the screen clears it after wiping the
    // local profile, so nothing can re-upload the deleted account in between.
    expect(AccountDeletionService.isDeletionPending('uid-a'), isTrue);
  });

  test('a partially cleaned account is reported as partial, never as clean',
      () async {
    final service = serviceWith(
      reAuth: (_) async {},
      cleanup: (_) async => const AccountCleanupReport(
        deleted: ['users/uid-a'],
        pending: ['battle_rooms', 'leaderboard/scores'],
      ),
    );

    final result = await service.deleteAccountWith(
      uid: 'uid-a',
      providerIds: const ['google.com'],
      deleteAuthUser: () async {},
    );

    expect(result.status, AccountDeletionStatus.partial);
    expect(result.accountGone, isTrue);
    expect(result.report.isComplete, isFalse);
    expect(result.report.pending, contains('battle_rooms'));
  });

  test('when the account delete fails the account and local data survive',
      () async {
    var cleanupRuns = 0;
    final service = serviceWith(
      reAuth: (_) async {},
      cleanup: (_) async {
        cleanupRuns++;
        return const AccountCleanupReport(deleted: ['users/uid-a']);
      },
    );

    final result = await service.deleteAccountWith(
      uid: 'uid-a',
      providerIds: const ['google.com'],
      deleteAuthUser: () async => throw Exception('auth unavailable'),
    );

    expect(result.status, AccountDeletionStatus.failed);
    expect(result.accountGone, isFalse);
    expect(cleanupRuns, 1);
    // No tombstone means sync keeps working for a profile that still exists.
    expect(AccountDeletionService.isDeletionPending('uid-a'), isFalse);
  });

  test('a profile being deleted is not pushed back to the server', () async {
    final user = UserModel(
      userId: 'uid-a',
      username: 'alpha',
      fullName: 'Alpha',
      avatarPath: 'a.png',
      isGuest: false,
    );

    await HiveService.setMeta(AccountDeletionService.deletingUidKey, 'uid-a');
    expect(AccountDeletionService.isDeletionPending('uid-a'), isTrue);

    // `pushUser` returns before it can reach Firestore. Without the tombstone
    // this call would attempt a write (and, in the field, resurrect the
    // account the user just deleted).
    await SyncService.pushUser(user);

    await HiveService.setMeta(AccountDeletionService.deletingUidKey, 'uid-b');
    expect(AccountDeletionService.isDeletionPending('uid-a'), isFalse);
    expect(AccountDeletionService.isDeletionPending('uid-b'), isTrue);

    await AccountDeletionService.clearTombstone();
    expect(AccountDeletionService.isDeletionPending('uid-b'), isFalse);
  });
}
