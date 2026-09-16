import '../../models/deployment_model.dart';

/// Movement kind derived from the recorded route (same rule as the Android
/// Deployment History screen): HO -> Bazaar = deployment,
/// Bazaar -> Bazaar = transfer, Bazaar -> HO = return.
String movementKind(DeploymentModel movement) {
  final action = movement.action.trim().toLowerCase();
  final to = movement.toLocation.trim().toLowerCase();

  final hasFromBazaar = (movement.fromBazaarId ?? '').trim().isNotEmpty;
  final hasToBazaar = (movement.toBazaarId ?? '').trim().isNotEmpty;

  if (action == 'return' ||
      action == 'returned' ||
      (!hasToBazaar && to == 'head office')) {
    return 'return';
  }

  if (hasFromBazaar && hasToBazaar) {
    return 'transfer';
  }

  return 'deployment';
}

String movementKindLabel(DeploymentModel movement) {
  switch (movementKind(movement)) {
    case 'return':
      return 'Bazaar → Head Office';
    case 'transfer':
      return 'Bazaar → Bazaar';
    default:
      return 'Head Office → Bazaar';
  }
}
