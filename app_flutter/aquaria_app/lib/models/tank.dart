enum WaterType {
  freshwater,
  saltwater,
  reef,
  planted,
  pond;

  String get label {
    switch (this) {
      case WaterType.freshwater: return 'Freshwater';
      case WaterType.saltwater:  return 'Saltwater';
      case WaterType.reef:       return 'Reef';
      case WaterType.planted:    return 'Planted';
      case WaterType.pond:       return 'Pond';
    }
  }

  static WaterType fromString(String s) {
    switch (s) {
      case 'saltwater': return WaterType.saltwater;
      case 'reef':      return WaterType.reef;
      case 'planted':   return WaterType.planted;
      case 'pond':      return WaterType.pond;
      default:          return WaterType.freshwater;
    }
  }
}

class TankModel {
  final String id;
  String name;
  int gallons;
  WaterType waterType;
  final DateTime createdAt;

  TankModel({
    String? id,
    required this.name,
    required this.gallons,
    required this.waterType,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();
}