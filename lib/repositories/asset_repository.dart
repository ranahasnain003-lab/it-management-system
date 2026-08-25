import '../models/asset_model.dart';
import '../core/services/asset_service.dart';



class AssetRepository {

  final AssetService _assetService =
      AssetService();



  Stream<List<AssetModel>> getAssets() {

    return _assetService.getAssets();

  }



  Future<AssetModel?> getAssetById(
    String id,
  ) async {

    return await _assetService.getAssetById(
      id,
    );

  }



  Future<void> addAsset(
    AssetModel asset,
  ) async {

    await _assetService.addAsset(
      asset,
    );

  }



  Future<void> updateAsset(
    String id,
    AssetModel asset,
  ) async {

    await _assetService.updateAsset(
      id,
      asset,
    );

  }



  Future<void> deleteAsset(
    String id,
  ) async {

    await _assetService.deleteAsset(
      id,
    );

  }



  Future<bool> checkDuplicateSerial(
    String serialNumber,
  ) async {

    return await _assetService
        .checkDuplicateSerial(
          serialNumber,
        );

  }



  Future<int> getTotalQuantity() async {

    return await _assetService
        .getTotalQuantity();

  }

}