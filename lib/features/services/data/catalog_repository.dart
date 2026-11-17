import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
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

final promotionsProvider = FutureProvider<List<Promotion>>(
  (ref) => ref.watch(catalogRepositoryProvider).getPromotions(),
);

/// Photos of the Home "Hire a Maid" cards (visa route → photo path).
final hireCardPhotosProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(catalogRepositoryProvider).getHireCardPhotos(),
);

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
