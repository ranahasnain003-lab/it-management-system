// The account status model, and who may change it.
//
// There are exactly two states that mean anything:
//
//   ACTIVE  - the account may use the system
//   BLOCKED - it may not
//
// There is no self-registration and no approval step: an Admin or Super Admin
// creates an account through Add User and it works straight away. 'pending',
// 'inactive', 'disabled' and 'deleted' are only recognised so that a profile
// written by an older version, or edited by hand in the Firebase console,
// still resolves to the right side of that line.
//
// The matching Firestore rules (isActiveUser, and the ADMIN UPDATE status
// whitelist) are proven separately against the emulator.
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/services/permission_service.dart';
import 'package:it_management_system/models/user_model.dart';

UserModel _user({required String status, String role = 'user', String createdBy = ''}) {
  return UserModel(
    uid: 'u1',
    name: 'Test Person',
    email: 'test.person@psba.test',
    role: role,
    status: status,
    createdBy: createdBy,
  );
}

void main() {
  selfSignupTests();

  group('ACTIVE means the account may use the system', () {
    test('active is the value the app writes, and is accepted in any spelling', () {
      for (final status in ['active', 'Active', ' active ', 'ACTIVE']) {
        expect(PermissionService.isActiveStatus(status), isTrue, reason: '"$status"');
        expect(PermissionService.isBlockedStatus(status), isFalse, reason: '"$status"');
      }
    });

    test('approved is still honoured, so an older profile is not locked out', () {
      expect(PermissionService.isActiveStatus('approved'), isTrue);
    });
  });

  group('everything else means the account may not', () {
    test('blocked, and the legacy values, all deny access', () {
      for (final status in ['blocked', 'Blocked', 'deleted', 'inactive', 'disabled', 'pending', 'nonsense', '']) {
        expect(PermissionService.isActiveStatus(status), isFalse, reason: '"$status"');
        expect(PermissionService.isBlockedStatus(status), isTrue, reason: '"$status"');
      }
    });

    test('a missing status is blocked, never admitted by default', () {
      expect(PermissionService.isActiveStatus(null), isFalse);
      expect(PermissionService.isBlockedStatus(null), isTrue);
    });

    test('a blocked account carries no permissions at all', () {
      // Access is role AND status: the role alone grants nothing.
      expect(PermissionService.isActiveStatus('blocked'), isFalse);
      expect(PermissionService.permissionsForRole('user'), isNotEmpty);
    });
  });

  group('the model has two states on the user object', () {
    test('isActive and isBlocked are exact opposites', () {
      for (final status in ['active', 'blocked', 'pending', 'deleted', '']) {
        final user = _user(status: status);
        expect(user.isActive, !user.isBlocked, reason: '"$status"');
      }
    });

    test('a status nobody recognises leaves the account blocked', () {
      expect(_user(status: 'something-else').isBlocked, isTrue);
    });
  });
}

// ============================================================================
// SELF-REGISTRATION
// ============================================================================

void selfSignupTests() {
  group('a self-registered account', () {
    test('is created ACTIVE, so it can be used at once', () {
      expect(AuthProvider.selfSignupStatus, 'active');
      expect(PermissionService.isActiveStatus(AuthProvider.selfSignupStatus), isTrue);
      expect(PermissionService.isBlockedStatus(AuthProvider.selfSignupStatus), isFalse);
    });

    test('is always the normal User role, never an administrator', () {
      expect(AuthProvider.selfSignupRole, 'user');
      expect(PermissionService.normalizeRole(AuthProvider.selfSignupRole), 'user');
      expect(AuthProvider.selfSignupRole, isNot('admin'));
      expect(AuthProvider.selfSignupRole, isNot('super_admin'));
    });

    test('gets exactly the normal User permissions, and none of the Admin ones', () {
      final granted = PermissionService.permissionsForRole(AuthProvider.selfSignupRole);
      final adminOnly = PermissionService.permissionsForRole('admin')
          .difference(granted);

      expect(granted, isNotEmpty);
      // Whatever an Admin may do that a User may not, a self-signup must not
      // acquire by signing itself up.
      expect(adminOnly, isNotEmpty, reason: 'the two roles should not be identical');
      for (final permission in adminOnly) {
        expect(granted.contains(permission), isFalse, reason: permission);
      }
    });

    test('can be blocked afterwards, which takes its access away', () {
      // Blocking is the control that replaces approval.
      final blocked = _user(status: 'blocked', role: AuthProvider.selfSignupRole);
      expect(blocked.isActive, isFalse);
      expect(blocked.isBlocked, isTrue);
    });
  });
}
