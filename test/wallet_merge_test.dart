import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/user_model.dart';
import 'package:quizbaaz/data/services/sync_service.dart';

/// Two economy bugs from PROJECT_REVIEW.md (R16, R13) that both ended with a
/// player getting something for nothing.
void main() {
  group('R16 — a brand-new player can buy something', () {
    test('newPlayer inventory is mutable', () {
      final player = UserModel.newPlayer(isGuest: false);

      // This line threw UnsupportedError while the field was `const {}`.
      player.inventory['coin_booster'] = 1;

      expect(player.inventoryCount('coin_booster'), 1);
    });

    test('guest inventory is mutable too', () {
      final guest = UserModel.guestUser();
      guest.inventory['extra_life'] = 2;
      expect(guest.inventoryCount('extra_life'), 2);
    });

    test('copyWith keeps a mutable map', () {
      final player = UserModel.newPlayer(isGuest: false)..inventory['x'] = 1;
      final copy = player.copyWith(username: 'Keshab');
      copy.inventory['y'] = 1;
      expect(copy.inventory.keys, containsAll(['x', 'y']));
    });
  });

  group('R13 — a pull must not refund what was spent', () {
    test('spent coins stay spent', () {
      // Local: bought a 500-coin item, so 100 left. Remote mirror is stale and
      // still shows 600 from before the purchase.
      final local = UserModel.newPlayer(isGuest: false)
        ..coins = 100
        ..gems = 0
        ..inventory = {'coin_booster': 1};
      final remote = UserModel.newPlayer(isGuest: false)
        ..coins = 600
        ..gems = 5;

      final wallet = SyncService.mergeWallet(local, remote);

      expect(wallet.coins, 100, reason: 'max() here refunded the purchase');
      expect(wallet.gems, 0);
      expect(wallet.inventory['coin_booster'], 1);
    });

    test('a used power-up is not restored', () {
      // The last booster was consumed: the key exists and is zero.
      final local = UserModel.newPlayer(isGuest: false)
        ..coins = 50
        ..inventory = {'coin_booster': 0, 'fifty_fifty': 0};
      final remote = UserModel.newPlayer(isGuest: false)
        ..coins = 50
        ..inventory = {'coin_booster': 4, 'fifty_fifty': 2};

      final wallet = SyncService.mergeWallet(local, remote);

      expect(wallet.inventory['coin_booster'], 0);
      expect(wallet.inventory['fifty_fifty'], 0);
    });

    test('a fresh profile adopts the remote balance (reinstall)', () {
      final local = UserModel.newPlayer(isGuest: false);      // 0 coins, no items
      final remote = UserModel.newPlayer(isGuest: false)
        ..coins = 2400
        ..gems = 12
        ..inventory = {'coin_booster': 3};

      final wallet = SyncService.mergeWallet(local, remote);

      expect(wallet.coins, 2400);
      expect(wallet.gems, 12);
      expect(wallet.inventory['coin_booster'], 3);
      expect(wallet.inventory, isNot(same(remote.inventory)),
          reason: 'the returned map must be mutable and independent');
    });
  });
}
