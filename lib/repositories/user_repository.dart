import '../models/user_model.dart';

import '../core/services/user_service.dart';

class UserRepository {
  final UserService _userService = UserService();

  Stream<List<UserModel>> getUsers() {
    return _userService.getUsers();
  }

  Future<UserModel?> getUserById(String uid) async {
    return await _userService.getUserById(uid);
  }

  Future<void> createUserProfile(UserModel user) async {
    await _userService.createUserProfile(user);
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _userService.updateUser(uid, data);
  }

  Future<void> deleteUser(String uid) async {
    await _userService.deleteUser(uid);
  }

  Future<void> changeUserRole(String uid, String role) async {
    await _userService.changeUserRole(uid, role);
  }

  Future<void> changeUserStatus(String uid, String status) async {
    await _userService.changeUserStatus(uid, status);
  }
}
