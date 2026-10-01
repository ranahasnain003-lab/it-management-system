// The final permission matrix, role by role, allowed AND denied.
//
// This is the app's half of the handover contract. The other half lives in
// firestore.rules and is proven against the Firestore emulator; the two must
// agree, because a button the UI offers and the database refuses is a broken
// feature, and a button the UI hides while the database allows it is a hole.
// Each expectation below names the Firestore rule that backs it.
//
// Role and status are read the way the rules read them: trimmed, lower-cased,
// and only the three canonical values count. A profile saved by hand in the
// Firebase console as 'Admin' or 'Active' must behave exactly like 'admin'
// and 'active'; anything else is an unknown role with no access at all.

import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/services/permission_service.dart';

void main() {
  // The capability getters, as the screens call them.
  bool viewInventory(String role) => PermissionService.canViewAssets(role);
  bool addAsset(String role) => PermissionService.canAddAsset(role);
  bool editAsset(String role) => PermissionService.canEditAsset(role);
  bool deleteAsset(String role) => PermissionService.canDeleteAsset(role);
  bool transferAsset(String role) => PermissionService.canTransferAsset(role);
  bool addBazaar(String role) => PermissionService.canAddBazaar(role);
  bool manageBazaars(String role) => PermissionService.canManageBazaars(role);
  bool addCategory(String role) => PermissionService.canAddCategory(role);
  bool manageCategories(String role) =>
      PermissionService.canManageCategories(role);
  bool manageUsers(String role) => PermissionService.canManageUsers(role);
  bool approveRequests(String role) =>
      PermissionService.canApproveRequests(role);
  bool viewAuditLogs(String role) => PermissionService.canViewAuditLogs(role);

  group('Super Admin has everything', () {
    for (final role in ['super_admin', 'Super_Admin', ' SUPER_ADMIN ']) {
      test('"$role"', () {
        expect(viewInventory(role), isTrue);
        expect(addAsset(role), isTrue);
        expect(editAsset(role), isTrue);
        expect(deleteAsset(role), isTrue);
        expect(transferAsset(role), isTrue);
        expect(addBazaar(role), isTrue);
        expect(manageBazaars(role), isTrue);
        expect(addCategory(role), isTrue);
        expect(manageCategories(role), isTrue);
        expect(manageUsers(role), isTrue);
        expect(approveRequests(role), isTrue);
        expect(viewAuditLogs(role), isTrue);

        // Every permission the app knows about, with nothing withheld.
        expect(
          PermissionService.permissionsForRole(role),
          PermissionService.allPermissions,
        );
      });
    }
  });

  group('Admin manages the inventory', () {
    // 'Admin' with a capital A is how the production profile was once
    // stored, and it is why the whole inventory query used to fail.
    for (final role in ['admin', 'Admin', ' ADMIN ']) {
      test('"$role"', () {
        // Allowed - rules: assets read/create/update/delete (isManager),
        // bazaars create/update, categories create/update, requests update.
        expect(viewInventory(role), isTrue);
        expect(addAsset(role), isTrue);
        expect(editAsset(role), isTrue, reason: 'edits directly, no approval');
        expect(deleteAsset(role), isTrue);
        expect(transferAsset(role), isTrue);
        expect(addBazaar(role), isTrue);
        expect(manageBazaars(role), isTrue);
        expect(addCategory(role), isTrue);
        expect(manageCategories(role), isTrue);
        expect(manageUsers(role), isTrue);
        expect(approveRequests(role), isTrue);
        expect(viewAuditLogs(role), isTrue);

        // Withheld: appointing or removing a Super Admin stays with the
        // Super Admin (rules: the appoint/remove/handover update rules).
        expect(
          PermissionService.permissionsForRole(role),
          isNot(contains(PermissionService.manageRoles)),
        );
      });
    }
  });

  group(
    'User is read-only on the inventory, plus the three additive actions',
    () {
      for (final role in ['user', 'User', ' USER ']) {
        test('"$role"', () {
          // Allowed.
          expect(
            viewInventory(role),
            isTrue,
            reason: 'rules: assets read is isActiveUser, organisation-wide',
          );
          expect(
            addAsset(role),
            isTrue,
            reason: 'rules: assets create has a User branch',
          );
          expect(
            addBazaar(role),
            isTrue,
            reason: 'rules: bazaars create is isActiveUser',
          );
          expect(
            addCategory(role),
            isTrue,
            reason: 'rules: categories create is isActiveUser',
          );
          expect(PermissionService.canCreateRequest(role), isTrue);
          expect(
            manageCategories(role),
            isTrue,
            reason:
                'renaming only corrects a spelling; the rules let a User '
                'change the name field and nothing else',
          );

          // Refused in the app AND in the rules. These are the guarantees the
          // owner asked for: a User may add, never change or remove.
          expect(
            editAsset(role),
            isFalse,
            reason: 'rules: assets update is managers only',
          );
          expect(
            deleteAsset(role),
            isFalse,
            reason: 'rules: assets delete is isManager',
          );
          expect(
            transferAsset(role),
            isFalse,
            reason: 'rules: deployments create is isManager',
          );
          expect(
            manageBazaars(role),
            isFalse,
            reason: 'rules: bazaars update is isManager, delete is never',
          );
          expect(
            manageUsers(role),
            isFalse,
            reason: 'rules: users read/write is managers only',
          );
          expect(
            approveRequests(role),
            isFalse,
            reason: 'rules: canActOnRequest is isManager',
          );
          expect(
            viewAuditLogs(role),
            isFalse,
            reason: 'rules: logs read is isManager',
          );
          expect(PermissionService.canImportAssets(role), isFalse);
        });
      }
    },
  );

  group('Anything that is not one of the three roles has no access', () {
    for (final role in [
      '',
      'administrator',
      'manager',
      'employee',
      'Super Admin',
      'super-admin',
      'staff',
    ]) {
      test('"$role" gets nothing', () {
        expect(PermissionService.permissionsForRole(role), isEmpty);
        expect(viewInventory(role), isFalse);
        expect(addAsset(role), isFalse);
        expect(addBazaar(role), isFalse);
        expect(addCategory(role), isFalse);
        expect(editAsset(role), isFalse);
        expect(deleteAsset(role), isFalse);
        expect(manageUsers(role), isFalse);
      });
    }
  });

  group('The roles mirror array never grants anything', () {
    test('a User profile carrying roles: [super_admin] stays a User', () {
      // firestore.rules validRoles() requires the array to mirror the single
      // primary role, and a legacy document that breaks that must not be
      // able to buy privileges with it here either.
      expect(
        PermissionService.canDeleteAsset('user', roles: ['super_admin']),
        isFalse,
      );
      expect(PermissionService.canEditAsset('user', roles: ['admin']), isFalse);
      expect(
        PermissionService.canManageUsers('user', roles: ['admin', 'user']),
        isFalse,
      );
    });

    test('an Admin profile carrying roles: [user] keeps its Admin rights', () {
      expect(PermissionService.canEditAsset('admin', roles: ['user']), isTrue);
    });
  });

  group('Status is read like the rules read it', () {
    test('active and approved are active, in any letter case', () {
      for (final status in ['active', 'Active', ' ACTIVE ', 'approved']) {
        expect(
          PermissionService.isActiveStatus(status),
          isTrue,
          reason: status,
        );
      }
    });

    test('pending and every blocked spelling are not active', () {
      for (final status in [
        'pending',
        'Pending',
        'blocked',
        'disabled',
        'inactive',
        'deleted',
        'rejected',
        '',
      ]) {
        expect(
          PermissionService.isActiveStatus(status),
          isFalse,
          reason: status,
        );
      }
    });
  });
}
