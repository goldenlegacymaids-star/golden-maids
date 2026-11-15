/// A home-service category (`public.service_categories`).
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.description = '',
    this.icon = 'service',
    this.imagePath,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'service',
      imagePath: json['image_path'] as String?,
    );
  }

  final String id;
  final String slug;
  final String name;
  final String description;

  /// Icon key, e.g. `cleaning` or `nurse`.
  final String icon;

  /// Path in the public `app-media` storage bucket.
  final String? imagePath;
}

/// How a service price is charged.
enum PriceUnit {
  perHour('per_hour', 'hour'),
  perVisit('per_visit', 'visit'),
  perMonth('per_month', 'month'),
  fixed('fixed', null);

  const PriceUnit(this.value, this.label);

  final String value;

  /// Shown after the price ("AED 45 / hour"); null for fixed prices.
  final String? label;

  static PriceUnit? fromValue(String? value) {
    for (final unit in values) {
      if (unit.value == value) return unit;
    }
    return null;
  }
}

/// A bookable home service (`public.services`).
class HomeService {
  const HomeService({
    required this.id,
    required this.categoryId,
    required this.slug,
    required this.name,
    this.shortDescription = '',
    this.description = '',
    this.requirements = '',
    this.imagePath,
    this.basePrice,
    this.priceUnit,
    this.durationMinutes,
    this.isPopular = false,
  });

  factory HomeService.fromJson(Map<String, dynamic> json) {
    return HomeService(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      shortDescription: json['short_description'] as String? ?? '',
      description: json['description'] as String? ?? '',
      requirements: json['requirements'] as String? ?? '',
      imagePath: json['image_path'] as String?,
      basePrice: (json['base_price'] as num?)?.toDouble(),
      priceUnit: PriceUnit.fromValue(json['price_unit'] as String?),
      durationMinutes: json['duration_minutes'] as int?,
      isPopular: json['is_popular'] as bool? ?? false,
    );
  }

  final String id;
  final String categoryId;
  final String slug;
  final String name;
  final String shortDescription;
  final String description;
  final String requirements;
  final String? imagePath;

  /// Set by administrators; null means "Price on request".
  final double? basePrice;
  final PriceUnit? priceUnit;
  final int? durationMinutes;
  final bool isPopular;
}

/// A home-screen banner or offer (`public.promotions`).
class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.ctaLabel = '',
    this.targetType = 'none',
    this.targetValue,
    this.discountPercent,
    this.imagePath,
  });

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      ctaLabel: json['cta_label'] as String? ?? '',
      targetType: json['target_type'] as String? ?? 'none',
      targetValue: json['target_value'] as String?,
      discountPercent: (json['discount_percent'] as num?)?.toDouble(),
      imagePath: json['image_path'] as String?,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String ctaLabel;

  /// `none`, `category` or `service`.
  final String targetType;

  /// Category or service slug when [targetType] is not `none`.
  final String? targetValue;

  /// Offer percentage set by administrators.
  final double? discountPercent;

  final String? imagePath;

  bool get hasAction =>
      ctaLabel.isNotEmpty && targetType != 'none' && targetValue != null;
}
