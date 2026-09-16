import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/routes/route_guard.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/services/permission_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';
import 'package:it_management_system/models/user_model.dart';

void main() {
  // ===========================================================================
  // ROUTE GUARD (direct navigation to restricted routes)
  // ===========================================================================

  group('RouteGuard', () {
    test('post-login redirect accepts only same-app paths', () {
      expect(RouteGuard.safeRedirectTarget('/inventory?x=1'), '/inventory?x=1');
      expect(RouteGuard.safeRedirectTarget('//evil.example'), '/dashboard');
      expect(RouteGuard.safeRedirectTarget('https://evil.example'), '/dashboard');
      expect(RouteGuard.safeRedirectTarget('/login'), '/dashboard');
      expect(RouteGuard.safeRedirectTarget(null), '/dashboard');
    });

    test('signed-out users can only open public routes', () {
      for (final path in ['/', '/login', '/signup']) {
        expect(
          RouteGuard.redirect(path: path, isSignedIn: false, role: null),
          isNull,
          reason: path,
        );
      }

      for (final path in [
        '/dashboard',
        '/assets',
        '/currently-at-bazaars',
        '/locations',
        '/requests',
        '/users',
        '/deployments',
        '/import-assets',
        '/notifications',
        '/profile',
      ]) {
        expect(
          RouteGuard.redirect(path: path, isSignedIn: false, role: null),
          '/login?from=${Uri.encodeComponent(path)}',
          reason: path,
        );
      }
    });

    test('normal users are redirected away from manager routes', () {
      for (final path in ['/users', '/deployments', '/import-assets']) {
        expect(
          RouteGuard.redirect(path: path, isSignedIn: true, role: 'user'),
          '/dashboard',
          reason: path,
        );
      }

      for (final path in [
        '/dashboard',
        '/assets',
        '/requests',
        '/locations',
        '/currently-at-bazaars',
      ]) {
        expect(
          RouteGuard.redirect(path: path, isSignedIn: true, role: 'user'),
          isNull,
          reason: path,
        );
      }
    });

    test('admin and super admin can open manager routes', () {
      for (final role in ['admin', 'super_admin']) {
        for (final path in ['/users', '/deployments', '/import-assets']) {
          expect(
            RouteGuard.redirect(path: path, isSignedIn: true, role: role),
            isNull,
            reason: '$role $path',
          );
        }
      }
    });

    test('a profile that failed to load keeps restricted routes closed', () {
      for (final path in ['/users', '/roles', '/deployments']) {
        expect(
          RouteGuard.redirect(
            path: path,
            isSignedIn: true,
            role: null,
            isProfileLoading: false,
          ),
          '/dashboard',
          reason: path,
        );
      }

      // Still loading: wait for the profile instead of redirecting.
      expect(
        RouteGuard.redirect(path: '/users', isSignedIn: true, role: null),
        isNull,
      );
    });

    test('trailing slash does not bypass the guard', () {
      expect(
        RouteGuard.redirect(path: '/users/', isSignedIn: true, role: 'user'),
        '/dashboard',
      );
    });
  });

  // ===========================================================================
  // RBAC / MULTIPLE ROLES
  // ===========================================================================

  group('PermissionService', () {
    test('multiple roles receive the union of permissions', () {
      final combined = PermissionService.permissionsForRoles(['user', 'admin']);

      expect(
        combined.containsAll(PermissionService.permissionsForRole('user')),
        isTrue,
      );
      expect(
        combined.containsAll(PermissionService.permissionsForRole('admin')),
        isTrue,
      );
    });

    test('removing a role removes permissions only that role granted', () {
      final withAdmin = PermissionService.permissionsForRoles(['user', 'admin']);
      final userOnly = PermissionService.permissionsForRoles(['user']);

      expect(withAdmin.contains(PermissionService.transferAsset), isTrue);
      expect(userOnly.contains(PermissionService.transferAsset), isFalse);
      expect(userOnly.contains(PermissionService.createRequest), isTrue);
    });

    test('user cannot transfer, edit directly or manage users', () {
      for (final permission in [
        PermissionService.transferAsset,
        PermissionService.editAsset,
        PermissionService.deleteAsset,
        PermissionService.manageUsers,
        PermissionService.approveRequests,
      ]) {
        expect(
          PermissionService.hasPermission(
            roles: const ['user'],
            permission: permission,
          ),
          isFalse,
          reason: permission,
        );
      }
    });

    test('unknown roles grant nothing', () {
      expect(PermissionService.permissionsForRoles(['viewer_x']), isEmpty);
    });
  });

  group('UserModel', () {
    test('ignores injected unknown roles and treats deleted as inactive', () {
      final user = UserModel.fromMap({
        'role': 'user',
        'roles': ['user', 'root'],
        'status': 'deleted',
      }, uid: 'u1');

      expect(user.effectiveRoles, ['user']);
      expect(user.isActive, isFalse);
      expect(user.isSuperAdmin, isFalse);
    });

    test('blocked and disabled accounts are inactive', () {
      for (final status in ['blocked', 'disabled', 'inactive']) {
        final user = UserModel.fromMap({
          'role': 'admin',
          'status': status,
        }, uid: 'u');

        expect(user.isActive, isFalse, reason: status);
      }
    });
  });

  // ===========================================================================
  // MODELS
  // ===========================================================================

  group('AssetModel', () {
    test('explicit stock fields are used and clamped', () {
      final asset = AssetModel.fromMap({
        'quantity': 100,
        'headOfficeQuantity': 80,
        'assignedQuantity': 0,
        'deployedQuantity': 20,
        'status': 'Assigned',
      }, 'a1');

      expect(asset.calculatedHeadOfficeQuantity, 80);
      expect(asset.calculatedDeployedQuantity, 20);
      expect(asset.calculatedAssignedQuantity, 0);
    });

    test('malformed numeric fields never throw', () {
      final asset = AssetModel.fromMap({
        'quantity': '12',
        'purchasePrice': 'abc',
        'warrantyMonths': null,
        'createdAt': 'not-a-date',
      }, 'a2');

      expect(asset.quantity, 12);
      expect(asset.purchasePrice, 0);
      expect(asset.warrantyMonths, 0);
      expect(asset.createdAt, isNull);
    });
  });

  group('DeploymentModel', () {
    test('legacy bazaarId is used only when toBazaarId is absent', () {
      final legacy = DeploymentModel.fromFirestore({
        'bazaarId': 'b1',
        'bazaarName': 'Legacy Bazaar',
        'status': 'Active',
        'quantity': 3,
      }, 'd1');

      expect(legacy.toBazaarId, 'b1');

      final returnRecord = DeploymentModel.fromFirestore({
        'toBazaarId': null,
        'bazaarId': 'source-bazaar',
        'status': 'Returned',
        'quantity': 3,
      }, 'd2');

      expect(returnRecord.toBazaarId, isNull);
    });
  });

  group('Bazaar master data', () {
    test('master dataset has 64 Bazaars with unique deterministic ids', () {
      expect(BazaarService.masterBazaarCount, 64);

      final id1 = BazaarService.masterBazaarDocumentId('Township Bazaar', 'Lahore');
      final id2 = BazaarService.masterBazaarDocumentId('  township   bazaar ', 'LAHORE');

      expect(id1, id2);
      expect(id1, isNot(contains('/')));
    });

    test('isActive understands isActive flag and legacy status field', () {
      expect(BazaarModel.fromFirestore({'name': 'A', 'isActive': false}, 'a').isActive, isFalse);
      expect(BazaarModel.fromFirestore({'name': 'A', 'status': 'Disabled'}, 'a').isActive, isFalse);
      expect(BazaarModel.fromFirestore({'name': 'A', 'status': 'Active'}, 'a').isActive, isTrue);
      expect(BazaarModel.fromFirestore({'name': 'A'}, 'a').isActive, isTrue);
    });
  });
}
