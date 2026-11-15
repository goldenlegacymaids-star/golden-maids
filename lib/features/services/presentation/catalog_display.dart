import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/catalog.dart';

/// Icon for a category icon key stored in the database.
IconData categoryIcon(String key) {
  return switch (key) {
    'cleaning' => Icons.cleaning_services_rounded,
    'deep_cleaning' => Icons.auto_awesome_rounded,
    'hourly' => Icons.schedule_rounded,
    'maid' => Icons.woman_rounded,
    'baby' => Icons.child_friendly_rounded,
    'elderly' => Icons.elderly_rounded,
    'caregiver' => Icons.volunteer_activism_rounded,
    'nurse' => Icons.medical_services_rounded,
    'driver' => Icons.directions_car_rounded,
    'pet' => Icons.pets_rounded,
    'visa' => Icons.badge_rounded,
    _ => Icons.home_repair_service_rounded,
  };
}

/// "AED 120 / visit", "AED 900", or "Price on request" when an
/// administrator has not set a price.
String priceLabel(HomeService service) {
  final price = service.basePrice;
  if (price == null) return 'Price on request';
  final unit = service.priceUnit?.label;
  final amount = Formatters.aed(price);
  return unit == null ? amount : '$amount / $unit';
}
