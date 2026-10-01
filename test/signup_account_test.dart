// Self-registration: what a new account is created as, and how the one
// verification e-mail is addressed.
//
// Verifying the e-mail address and being approved are two separate
// requirements. Login refuses an unverified address, and refuses an account
// that nobody has approved yet; this file pins the second half, which is the
// one that changed. The Firestore side is proven against the emulator: the
// public signup rule accepts status 'pending' and refuses 'active'.

import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/services/auth_service.dart';
import 'package:it_management_system/core/services/permission_service.dart';

void main() {
  group('a self-registered account is created awaiting approval', () {
    test('signup status is pending, not active', () {
      expect(AuthProvider.selfSignupStatus, 'pending');
    });

    test('pending is not an active status, so it carries no permissions', () {
      expect(
        PermissionService.isActiveStatus(AuthProvider.selfSignupStatus),
        isFalse,
      );
      expect(
        PermissionService.isPendingStatus(AuthProvider.selfSignupStatus),
        isTrue,
      );
    });

    test('login explains the wait instead of failing silently', () {
      final message = AuthProvider.accountStatusMessage(
        AuthProvider.selfSignupStatus,
      );

      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('approval'));
    });

    test('a pending account is told the same thing in any letter case', () {
      for (final status in ['pending', 'Pending', ' PENDING ']) {
        expect(
          PermissionService.isActiveStatus(status),
          isFalse,
          reason: status,
        );
        expect(AuthProvider.accountStatusMessage(status), isNotNull);
      }
    });
  });

  group('the verification e-mail link', () {
    test('continues to this project\'s own sign-in page', () {
      final settings = AuthService.verificationLinkSettings;

      // A link on the project's own hosted domain, so the person lands back
      // in the app rather than on a bare Firebase page - and so the link in
      // the message points somewhere that belongs to this project.
      expect(settings.url, startsWith('https://'));
      expect(settings.url, contains('it-inventory-8e690.web.app'));
      expect(settings.url, contains('/login'));

      // Handled by Firebase's own action page, not inside the app: there is
      // no deep-link handler registered for it.
      expect(settings.handleCodeInApp, isFalse);
    });
  });
}
