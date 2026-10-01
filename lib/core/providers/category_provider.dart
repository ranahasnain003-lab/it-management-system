import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/category_service.dart';

/// Holds the asset category catalogue for the signed-in account.
class CategoryProvider extends ChangeNotifier {
  CategoryProvider({CategoryService? categoryService})
    : _categoryService = categoryService ?? CategoryService();

  final CategoryService _categoryService;

  List<CategoryModel> _categories = [];

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<List<CategoryModel>>? _subscription;
  StreamSubscription<String?>? _authSubscription;

  String? _uid;

  bool _isListening = false;
  bool _disposed = false;

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  List<CategoryModel> get categories => List.unmodifiable(_categories);

  /// The catalogue names only, ready for a dropdown.
  List<String> get categoryNames {
    return List.unmodifiable(_categories.map((category) => category.name));
  }

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get error => _errorMessage;

  bool get isListening => _isListening;

  int get totalCategories => _categories.length;

  // ===========================================================================
  // MERGED CATEGORY LIST
  // ===========================================================================

  /// The options to offer for a category field: the catalogue plus every
  /// category already in use on an asset this account can see.
  ///
  /// Delegates to [CategoryService.mergeCategoryNames] so the form, the
  /// importer and the AI Assistant all answer this question the same way.
  List<String> mergedNames(Iterable<String> assetCategories) {
    // Keyed on the stored nameKey, so a renamed category and the older
    // spelling still sitting on an asset are one entry.
    return CategoryService.mergeCategories(
      catalogue: _categories,
      assetCategories: assetCategories,
    );
  }

  // ===========================================================================
  // ACCOUNT BINDING
  // ===========================================================================

  /// Follows Firebase's auth state so a sign-out throws the catalogue away
  /// before the next account can see it, by whichever route the session ends.
  void attachUserStream(Stream<String?> userIds) {
    _authSubscription?.cancel();
    _authSubscription = userIds.listen(bindUser);
  }

  void bindUser(String? uid) {
    if (_disposed) {
      return;
    }

    final next = (uid ?? '').trim().isEmpty ? null : uid!.trim();

    if (next == _uid) {
      return;
    }

    _uid = next;

    if (next == null) {
      clear();
      return;
    }

    listenToCategories(forceRestart: true);
  }

  // ===========================================================================
  // REAL-TIME LISTENER
  // ===========================================================================

  void listenToCategories({bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    if (_isListening && !forceRestart) {
      return;
    }

    _startListener();
  }

  void _startListener() {
    if (_disposed) {
      return;
    }

    _cancelListener();

    _isLoading = true;
    _errorMessage = null;
    _isListening = true;

    _notifySafely();

    _subscription = _categoryService.getCategories().listen(
      (data) {
        if (_disposed) {
          return;
        }

        _categories = List<CategoryModel>.from(data);
        _isLoading = false;
        _errorMessage = null;
        _isListening = true;

        _notifySafely();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed) {
          return;
        }

        _isLoading = false;
        _isListening = false;
        _errorMessage = _cleanErrorMessage(error);

        _notifySafely();
      },
      cancelOnError: false,
    );
  }

  Future<void> refreshCategories() async {
    if (_disposed) {
      return;
    }

    _startListener();
  }

  // ===========================================================================
  // CREATE CATEGORY
  // ===========================================================================

  /// Adds a category and returns its stored name.
  ///
  /// The returned name is the stored spelling, so the caller can select it
  /// straight away instead of waiting for the listener to deliver it.
  Future<String> createCategory({
    required String name,
    required String createdBy,
    String createdByName = '',
  }) async {
    _errorMessage = null;

    _notifySafely();

    try {
      final category = await _categoryService.create(
        name: name,
        createdBy: createdBy,
        createdByName: createdByName,
      );

      if (_disposed) {
        return category.name;
      }

      // Held locally as well: the snapshot listener normally delivers the new
      // document within a moment, but the form must be able to select the
      // category immediately.
      if (!_categories.any((existing) => existing.id == category.id)) {
        _categories = [
          ..._categories,
          category,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      _notifySafely();

      return category.name;
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  /// Corrects the spelling of [categoryId] and returns the stored name.
  ///
  /// Only the name changes; the category keeps its identity, so assets that
  /// already carry the old spelling keep working (see
  /// [CategoryService.rename]).
  Future<String> renameCategory({
    required String categoryId,
    required String name,
  }) async {
    _errorMessage = null;

    _notifySafely();

    try {
      final category = await _categoryService.rename(
        categoryId: categoryId,
        name: name,
      );

      if (_disposed) {
        return category.name;
      }

      // Applied locally too, for the same reason as a new category: the form
      // must show the corrected name before the snapshot arrives.
      _categories = [
        for (final existing in _categories)
          if (existing.id == category.id) category else existing,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _notifySafely();

      return category.name;
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  /// The catalogue category a display name belongs to, or null when the name
  /// only exists on assets and has no document of its own yet.
  CategoryModel? categoryFor(String name) {
    final key = CategoryService.matchKeyFor(name);

    for (final category in _categories) {
      if (CategoryService.matchKeyFor(category.name) == key) {
        return category;
      }
    }

    return null;
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  void clearError() {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  /// Stops the listener and clears state. Called on account change.
  void clear() {
    if (_disposed) {
      return;
    }

    _cancelListener();

    _categories = [];
    _isLoading = false;
    _errorMessage = null;

    _notifySafely();
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

  void _cancelListener() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'An unexpected error occurred.';
    }

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    return message;
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _disposed = true;

    _subscription?.cancel();
    _subscription = null;

    _authSubscription?.cancel();
    _authSubscription = null;

    super.dispose();
  }
}
