import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/user_model.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';

/// A reinstall must restore the remote wallet instead of treating the fresh
/// local profile as an existing one because a signup bonus was applied first.
void main() {
  group('Google link signup bonus', () {
    test('a fresh profile that adopted remote items gets no second bonus', () {
      final merged =
          UserModel.newPlayer(isGuest: false)
            ..coins = 1200
            ..gems = 7
            ..inventory = {'fifty_fifty': 3}
            ..dailyStreak = 4;

      expect(
        UserProvider.grantLinkBonus(
          wasGuest: true,
          wasFreshLocal: true,
          merged: merged,
        ),
        isFalse,
        reason: 'this is a returning player, not a new signup',
      );
    });

    test('a fresh profile with no remote wallet still gets the bonus', () {
      final merged = UserModel.newPlayer(isGuest: false);

      expect(
        UserProvider.grantLinkBonus(
          wasGuest: true,
          wasFreshLocal: true,
          merged: merged,
        ),
        isTrue,
      );
    });

    test('a guest with local progress keeps the link bonus', () {
      final merged =
          UserModel.newPlayer(isGuest: false)
            ..coins = 250
            ..inventory = {'freeze_time': 1};

      expect(
        UserProvider.grantLinkBonus(
          wasGuest: true,
          wasFreshLocal: false,
          merged: merged,
        ),
        isTrue,
      );
    });

    test('an already signed-in player never gets a signup bonus', () {
      final merged = UserModel.newPlayer(isGuest: false);

      expect(
        UserProvider.grantLinkBonus(
          wasGuest: false,
          wasFreshLocal: true,
          merged: merged,
        ),
        isFalse,
      );
    });
  });
}
