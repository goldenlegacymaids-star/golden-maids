import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../../core/services/supabase_providers.dart';
import '../domain/catalog.dart';

/// Read access to the public service catalogue. Row Level Security returns
/// only live content (active, within dates) to customers and guests.
abstract interface class CatalogRepository {
  Future<List<ServiceCategory>> getCategories();

  Future<ServiceCategory> getCategory(String slug);

  Future<List<HomeService>> getPopularServices();

  Future<List<HomeService>> getServicesInCategory(String categoryId);

  Future<HomeService> getService(String slug);

  Future<List<HomeService>> searchServices(String query);

  Future<List<Promotion>> getPromotions();

  /// Photo paths of the Home "Hire a Maid" cards, by visa route
  /// (`sponsor`, `company`); a route without a photo is left out.
  Future<Map<String, String>> getHireCardPhotos();

  /// Public URL of an image in the `app-media` bucket, or null.
  String? imageUrl(String? path);
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client);

  final SupabaseClient _client;

  static const _mediaBucket = 'app-media';
  static const _categoryColumns =
      'id, slug, name, description, icon, image_path';
  static const _serviceColumns =
      'id, category_id, slug, name, short_description, description, '
      'requirements, image_path, base_price, price_unit, duration_minutes, '
      'is_popular, booking_type';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<List<ServiceCategory>> getCategories() => _guard(() async {
    final rows = await _client
        .from('service_categories')
        .select(_categoryColumns)
        .order('sort_order', ascending: true);
    return rows.map(ServiceCategory.fromJson).toList();
  });

  @override
  Future<ServiceCategory> getCategory(String slug) => _guard(() async {
    final row = await _client
        .from('service_categories')
        .select(_categoryColumns)
        .eq('slug', slug)
        .single();
    return ServiceCategory.fromJson(row);
  });

  @override
  Future<List<HomeService>> getPopularServices() => _guard(() async {
    final rows = await _client
        .from('services')
        .select(_serviceColumns)
        .eq('is_popular', true)
        .order('sort_order', ascending: true)
        .limit(10);
    return rows.map(HomeService.fromJson).toList();
  });

  @override
  Future<List<HomeService>> getServicesInCategory(String categoryId) =>
      _guard(() async {
        final rows = await _client
            .from('services')
            .select(_serviceColumns)
            .eq('category_id', categoryId)
            .order('sort_order', ascending: true);
        return rows.map(HomeService.fromJson).toList();
      });

  @override
  Future<HomeService> getService(String slug) => _guard(() async {
    final row = await _client
        .from('services')
        .select(_serviceColumns)
        .eq('slug', slug)
        .single();
    return HomeService.fromJson(row);
  });

  @override
  Future<List<HomeService>> searchServices(String query) => _guard(() async {
    // Characters with a meaning in PostgREST filters are removed.
    final term = query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isEmpty) return const <HomeService>[];
    final rows = await _client
        .from('services')
        .select(_serviceColumns)
        .or('name.ilike.%$term%,short_description.ilike.%$term%')
        .order('name', ascending: true)
        .limit(30);
    return rows.map(HomeService.fromJson).toList();
  });

  @override
  Future<List<Promotion>> getPromotions() => _guard(() async {
    final rows = await _client
        .from('promotions')
        .select(
          'id, title, subtitle, cta_label, target_type, target_value, '
          'discount_percent, image_path',
        )
        .order('sort_order', ascending: true);
    return rows.map(Promotion.fromJson).toList();
  });

  @override
  Future<Map<String, String>> getHireCardPhotos() => _guard(() async {
    final rows = await _client
        .from('hire_route_cards')
        .select('visa_type, image_path');
    return {
      for (final row in rows)
        if (row['image_path'] case final String path when path.isNotEmpty)
          row['visa_type'] as String: path,
    };
  });

  @override
  String? imageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(_mediaBucket).getPublicUrl(path);
  }
}

/// Used when the app has no Supabase settings.
class UnavailableCatalogRepository implements CatalogRepository {
  const UnavailableCatalogRepository();

  static const _failure = ServerFailure(
    message: 'Services cannot be loaded: the app is not connected to its '
        'server.',
  );

  @override
  Future<List<ServiceCategory>> getCategories() => Future.error(_failure);

  @override
  Future<ServiceCategory> getCategory(String slug) => Future.error(_failure);

  @override
  Future<List<HomeService>> getPopularServices() => Future.error(_failure);

  @override
  Future<List<HomeService>> getServicesInCategory(String categoryId) =>
      Future.error(_failure);

  @override
  Future<HomeService> getService(String slug) => Future.error(_failure);

  @override
  Future<List<HomeService>> searchServices(String query) =>
      Future.error(_failure);

  @override
  Future<List<Promotion>> getPromotions() => Future.error(_failure);

  @override
  Future<Map<String, String>> getHireCardPhotos() => Future.error(_failure);

  @override
  String? imageUrl(String? path) => null;
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableCatalogRepository();
  return SupabaseCatalogRepository(ref.watch(supabaseClientProvider));
});

// Catalogue data is cached for the app session (pull to refresh reloads).

final categoriesProvider = FutureProvider<List<ServiceCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).getCategories(),
);

final popularServicesProvider = FutureProvider<List<HomeService>>(
  (ref) => ref.watch(catalogRepositoryProvider).getPopularServices(),
);

/// Home banners. The last list is saved on the phone and shown at once on
/// the next launch, then replaced by the server's list when it arrives.
final promotionsProvider = StreamProvider<List<Promotion>>((ref) async* {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repository = ref.watch(catalogRepositoryProvider);
  final saved = _readSaved(prefs, _promotionsKey);
  final cached = saved is List
      ? [
          for (final item in saved)
            if (item is Map<String, dynamic>) Promotion.fromJson(item),
        ]
      : null;
  if (cached != null) yield cached;
  try {
    final fresh = await repository.getPromotions();
    await _save(prefs, _promotionsKey, [for (final p in fresh) p.toJson()]);
    yield fresh;
  } catch (_) {
    // Keep showing the saved banners when offline; without them, show
    // the error.
    if (cached == null) rethrow;
  }
});

/// Photos of the Home "Hire a Maid" cards (visa route → photo path); saved
/// on the phone like the banners.
final hireCardPhotosProvider = StreamProvider<Map<String, String>>((
  ref,
) async* {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repository = ref.watch(catalogRepositoryProvider);
  final saved = _readSaved(prefs, _hireCardsKey);
  final cached = saved is Map<String, dynamic>
      ? {
          for (final entry in saved.entries)
            if (entry.value is String) entry.key: entry.value as String,
        }
      : null;
  if (cached != null) yield cached;
  try {
    final fresh = await repository.getHireCardPhotos();
    await _save(prefs, _hireCardsKey, fresh);
    yield fresh;
  } catch (_) {
    if (cached == null) rethrow;
  }
});

const _promotionsKey = 'cache.home_promotions.v1';
const _hireCardsKey = 'cache.home_hire_cards.v1';

Object? _readSaved(SharedPreferences prefs, String key) {
  final text = prefs.getString(key);
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Future<void> _save(SharedPreferences prefs, String key, Object value) async {
  try {
    await prefs.setString(key, jsonEncode(value));
  } on Object {
    // Saving is only a speed-up; the app works without it.
  }
}

final categoryProvider = FutureProvider.family<ServiceCategory, String>(
  (ref, slug) => ref.watch(catalogRepositoryProvider).getCategory(slug),
);

final categoryServicesProvider = FutureProvider.family<List<HomeService>, String>(
  (ref, categoryId) =>
      ref.watch(catalogRepositoryProvider).getServicesInCategory(categoryId),
);

final serviceProvider = FutureProvider.family<HomeService, String>(
  (ref, slug) => ref.watch(catalogRepositoryProvider).getService(slug),
);

final serviceSearchProvider = FutureProvider.family<List<HomeService>, String>(
  (ref, query) => ref.watch(catalogRepositoryProvider).searchServices(query),
  isAutoDispose: true,
);
