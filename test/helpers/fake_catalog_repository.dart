import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/services/data/catalog_repository.dart';
import 'package:golden_maids/features/services/domain/catalog.dart';

/// In-memory [CatalogRepository] with a small test catalogue.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<ServiceCategory>? categories,
    List<HomeService>? services,
    List<Promotion>? promotions,
  }) : categories = categories ?? defaultCategories,
       services = services ?? defaultServices,
       promotions = promotions ?? defaultPromotions;

  static const defaultCategories = [
    ServiceCategory(
      id: 'c1',
      slug: 'general-cleaning',
      name: 'General Cleaning',
      description: 'Regular home cleaning.',
      icon: 'cleaning',
    ),
    ServiceCategory(
      id: 'c2',
      slug: 'hourly-maid',
      name: 'Hourly Maid',
      icon: 'hourly',
    ),
    ServiceCategory(id: 'c3', slug: 'maid-visa', name: '2-Year Maid Visa', icon: 'visa'),
  ];

  static const defaultServices = [
    HomeService(
      id: 's1',
      categoryId: 'c1',
      slug: 'home-cleaning',
      name: 'Home Cleaning',
      shortDescription: 'Regular cleaning for apartments and villas.',
      isPopular: true,
    ),
    HomeService(
      id: 's2',
      categoryId: 'c1',
      slug: 'move-in-cleaning',
      name: 'Move-In Cleaning',
    ),
    HomeService(
      id: 's3',
      categoryId: 'c2',
      slug: 'hourly-maid',
      name: 'Hourly Maid',
      basePrice: 45,
      priceUnit: PriceUnit.perHour,
      durationMinutes: 120,
      isPopular: true,
    ),
  ];

  static const defaultPromotions = [
    Promotion(
      id: 'p1',
      title: 'Find Your Perfect Maid',
      subtitle: 'Browse available candidates',
    ),
    Promotion(
      id: 'p2',
      title: 'Best Cleaning Service',
      discountPercent: 20,
      ctaLabel: 'Book Now',
      targetType: 'category',
      targetValue: 'general-cleaning',
    ),
  ];

  final List<ServiceCategory> categories;
  final List<HomeService> services;
  final List<Promotion> promotions;

  /// When set, every call fails with this error.
  AppFailure? failure;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<ServiceCategory>> getCategories() async {
    _check();
    return categories;
  }

  @override
  Future<ServiceCategory> getCategory(String slug) async {
    _check();
    return categories.firstWhere(
      (c) => c.slug == slug,
      orElse: () => throw const NotFoundFailure(),
    );
  }

  @override
  Future<List<HomeService>> getPopularServices() async {
    _check();
    return services.where((s) => s.isPopular).toList();
  }

  @override
  Future<List<HomeService>> getServicesInCategory(String categoryId) async {
    _check();
    return services.where((s) => s.categoryId == categoryId).toList();
  }

  @override
  Future<HomeService> getService(String slug) async {
    _check();
    return services.firstWhere(
      (s) => s.slug == slug,
      orElse: () => throw const NotFoundFailure(),
    );
  }

  @override
  Future<List<HomeService>> searchServices(String query) async {
    _check();
    final term = query.toLowerCase();
    return services
        .where(
          (s) =>
              s.name.toLowerCase().contains(term) ||
              s.shortDescription.toLowerCase().contains(term),
        )
        .toList();
  }

  @override
  Future<List<Promotion>> getPromotions() async {
    _check();
    return promotions;
  }

  @override
  String? imageUrl(String? path) => null;
}
