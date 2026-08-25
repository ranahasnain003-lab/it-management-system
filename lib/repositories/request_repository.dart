import '../models/request_model.dart';
import '../core/services/request_service.dart';

class RequestRepository {
  RequestRepository({RequestService? requestService})
    : _requestService = requestService ?? RequestService();

  final RequestService _requestService;

  // ============================================================
  // GET ALL REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getRequests() {
    return _requestService.getRequests();
  }

  // ============================================================
  // GET USER REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getUserRequests(String userId) {
    return _requestService.getRequestsByUser(userId);
  }

  // ============================================================
  // CREATE REQUEST
  // ============================================================

  Future<void> createRequest(RequestModel request) async {
    await _requestService.createRequest(request);
  }

  // ============================================================
  // UPDATE REQUEST STATUS
  // ============================================================

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
  }) async {
    await _requestService.updateRequestStatus(
      requestId: requestId,
      status: status,
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // GET SINGLE REQUEST
  // ============================================================

  Future<RequestModel?> getRequestById(String id) async {
    return _requestService.getRequestById(id);
  }

  // ============================================================
  // DELETE REQUEST
  // ============================================================

  Future<void> deleteRequest(String id) async {
    await _requestService.deleteRequest(id);
  }
}
