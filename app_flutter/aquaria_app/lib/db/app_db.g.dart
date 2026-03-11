// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $TanksTable extends Tanks with TableInfo<$TanksTable, Tank> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TanksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gallonsMeta = const VerificationMeta(
    'gallons',
  );
  @override
  late final GeneratedColumn<int> gallons = GeneratedColumn<int>(
    'gallons',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _waterTypeMeta = const VerificationMeta(
    'waterType',
  );
  @override
  late final GeneratedColumn<String> waterType = GeneratedColumn<String>(
    'water_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tapWaterJsonMeta = const VerificationMeta(
    'tapWaterJson',
  );
  @override
  late final GeneratedColumn<String> tapWaterJson = GeneratedColumn<String>(
    'tap_water_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    gallons,
    waterType,
    createdAt,
    isArchived,
    archivedAt,
    tapWaterJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tanks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tank> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('gallons')) {
      context.handle(
        _gallonsMeta,
        gallons.isAcceptableOrUnknown(data['gallons']!, _gallonsMeta),
      );
    } else if (isInserting) {
      context.missing(_gallonsMeta);
    }
    if (data.containsKey('water_type')) {
      context.handle(
        _waterTypeMeta,
        waterType.isAcceptableOrUnknown(data['water_type']!, _waterTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_waterTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('tap_water_json')) {
      context.handle(
        _tapWaterJsonMeta,
        tapWaterJson.isAcceptableOrUnknown(
          data['tap_water_json']!,
          _tapWaterJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tank map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tank(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      gallons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gallons'],
      )!,
      waterType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}water_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      tapWaterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tap_water_json'],
      ),
    );
  }

  @override
  $TanksTable createAlias(String alias) {
    return $TanksTable(attachedDatabase, alias);
  }
}

class Tank extends DataClass implements Insertable<Tank> {
  final String id;
  final String name;
  final int gallons;
  final String waterType;
  final DateTime createdAt;
  final bool isArchived;
  final DateTime? archivedAt;
  final String? tapWaterJson;
  const Tank({
    required this.id,
    required this.name,
    required this.gallons,
    required this.waterType,
    required this.createdAt,
    required this.isArchived,
    this.archivedAt,
    this.tapWaterJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['gallons'] = Variable<int>(gallons);
    map['water_type'] = Variable<String>(waterType);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_archived'] = Variable<bool>(isArchived);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    if (!nullToAbsent || tapWaterJson != null) {
      map['tap_water_json'] = Variable<String>(tapWaterJson);
    }
    return map;
  }

  TanksCompanion toCompanion(bool nullToAbsent) {
    return TanksCompanion(
      id: Value(id),
      name: Value(name),
      gallons: Value(gallons),
      waterType: Value(waterType),
      createdAt: Value(createdAt),
      isArchived: Value(isArchived),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      tapWaterJson: tapWaterJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tapWaterJson),
    );
  }

  factory Tank.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tank(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      gallons: serializer.fromJson<int>(json['gallons']),
      waterType: serializer.fromJson<String>(json['waterType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      tapWaterJson: serializer.fromJson<String?>(json['tapWaterJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'gallons': serializer.toJson<int>(gallons),
      'waterType': serializer.toJson<String>(waterType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isArchived': serializer.toJson<bool>(isArchived),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'tapWaterJson': serializer.toJson<String?>(tapWaterJson),
    };
  }

  Tank copyWith({
    String? id,
    String? name,
    int? gallons,
    String? waterType,
    DateTime? createdAt,
    bool? isArchived,
    Value<DateTime?> archivedAt = const Value.absent(),
    Value<String?> tapWaterJson = const Value.absent(),
  }) => Tank(
    id: id ?? this.id,
    name: name ?? this.name,
    gallons: gallons ?? this.gallons,
    waterType: waterType ?? this.waterType,
    createdAt: createdAt ?? this.createdAt,
    isArchived: isArchived ?? this.isArchived,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    tapWaterJson: tapWaterJson.present ? tapWaterJson.value : this.tapWaterJson,
  );
  Tank copyWithCompanion(TanksCompanion data) {
    return Tank(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      gallons: data.gallons.present ? data.gallons.value : this.gallons,
      waterType: data.waterType.present ? data.waterType.value : this.waterType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      tapWaterJson: data.tapWaterJson.present
          ? data.tapWaterJson.value
          : this.tapWaterJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tank(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('gallons: $gallons, ')
          ..write('waterType: $waterType, ')
          ..write('createdAt: $createdAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('tapWaterJson: $tapWaterJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    gallons,
    waterType,
    createdAt,
    isArchived,
    archivedAt,
    tapWaterJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tank &&
          other.id == this.id &&
          other.name == this.name &&
          other.gallons == this.gallons &&
          other.waterType == this.waterType &&
          other.createdAt == this.createdAt &&
          other.isArchived == this.isArchived &&
          other.archivedAt == this.archivedAt &&
          other.tapWaterJson == this.tapWaterJson);
}

class TanksCompanion extends UpdateCompanion<Tank> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> gallons;
  final Value<String> waterType;
  final Value<DateTime> createdAt;
  final Value<bool> isArchived;
  final Value<DateTime?> archivedAt;
  final Value<String?> tapWaterJson;
  final Value<int> rowid;
  const TanksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.gallons = const Value.absent(),
    this.waterType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.tapWaterJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TanksCompanion.insert({
    required String id,
    required String name,
    required int gallons,
    required String waterType,
    required DateTime createdAt,
    this.isArchived = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.tapWaterJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       gallons = Value(gallons),
       waterType = Value(waterType),
       createdAt = Value(createdAt);
  static Insertable<Tank> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? gallons,
    Expression<String>? waterType,
    Expression<DateTime>? createdAt,
    Expression<bool>? isArchived,
    Expression<DateTime>? archivedAt,
    Expression<String>? tapWaterJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (gallons != null) 'gallons': gallons,
      if (waterType != null) 'water_type': waterType,
      if (createdAt != null) 'created_at': createdAt,
      if (isArchived != null) 'is_archived': isArchived,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (tapWaterJson != null) 'tap_water_json': tapWaterJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TanksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? gallons,
    Value<String>? waterType,
    Value<DateTime>? createdAt,
    Value<bool>? isArchived,
    Value<DateTime?>? archivedAt,
    Value<String?>? tapWaterJson,
    Value<int>? rowid,
  }) {
    return TanksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      gallons: gallons ?? this.gallons,
      waterType: waterType ?? this.waterType,
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      tapWaterJson: tapWaterJson ?? this.tapWaterJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (gallons.present) {
      map['gallons'] = Variable<int>(gallons.value);
    }
    if (waterType.present) {
      map['water_type'] = Variable<String>(waterType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (tapWaterJson.present) {
      map['tap_water_json'] = Variable<String>(tapWaterJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TanksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('gallons: $gallons, ')
          ..write('waterType: $waterType, ')
          ..write('createdAt: $createdAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('tapWaterJson: $tapWaterJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InhabitantsTable extends Inhabitants
    with TableInfo<$InhabitantsTable, Inhabitant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InhabitantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tankId,
    name,
    count,
    type,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inhabitants';
  @override
  VerificationContext validateIntegrity(
    Insertable<Inhabitant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Inhabitant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Inhabitant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $InhabitantsTable createAlias(String alias) {
    return $InhabitantsTable(attachedDatabase, alias);
  }
}

class Inhabitant extends DataClass implements Insertable<Inhabitant> {
  final int id;
  final String tankId;
  final String name;
  final int count;
  final String? type;
  final DateTime createdAt;
  const Inhabitant({
    required this.id,
    required this.tankId,
    required this.name,
    required this.count,
    this.type,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tank_id'] = Variable<String>(tankId);
    map['name'] = Variable<String>(name);
    map['count'] = Variable<int>(count);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  InhabitantsCompanion toCompanion(bool nullToAbsent) {
    return InhabitantsCompanion(
      id: Value(id),
      tankId: Value(tankId),
      name: Value(name),
      count: Value(count),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      createdAt: Value(createdAt),
    );
  }

  factory Inhabitant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Inhabitant(
      id: serializer.fromJson<int>(json['id']),
      tankId: serializer.fromJson<String>(json['tankId']),
      name: serializer.fromJson<String>(json['name']),
      count: serializer.fromJson<int>(json['count']),
      type: serializer.fromJson<String?>(json['type']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tankId': serializer.toJson<String>(tankId),
      'name': serializer.toJson<String>(name),
      'count': serializer.toJson<int>(count),
      'type': serializer.toJson<String?>(type),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Inhabitant copyWith({
    int? id,
    String? tankId,
    String? name,
    int? count,
    Value<String?> type = const Value.absent(),
    DateTime? createdAt,
  }) => Inhabitant(
    id: id ?? this.id,
    tankId: tankId ?? this.tankId,
    name: name ?? this.name,
    count: count ?? this.count,
    type: type.present ? type.value : this.type,
    createdAt: createdAt ?? this.createdAt,
  );
  Inhabitant copyWithCompanion(InhabitantsCompanion data) {
    return Inhabitant(
      id: data.id.present ? data.id.value : this.id,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      name: data.name.present ? data.name.value : this.name,
      count: data.count.present ? data.count.value : this.count,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Inhabitant(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('name: $name, ')
          ..write('count: $count, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tankId, name, count, type, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Inhabitant &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.name == this.name &&
          other.count == this.count &&
          other.type == this.type &&
          other.createdAt == this.createdAt);
}

class InhabitantsCompanion extends UpdateCompanion<Inhabitant> {
  final Value<int> id;
  final Value<String> tankId;
  final Value<String> name;
  final Value<int> count;
  final Value<String?> type;
  final Value<DateTime> createdAt;
  const InhabitantsCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.name = const Value.absent(),
    this.count = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  InhabitantsCompanion.insert({
    this.id = const Value.absent(),
    required String tankId,
    required String name,
    this.count = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       name = Value(name);
  static Insertable<Inhabitant> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? name,
    Expression<int>? count,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (name != null) 'name': name,
      if (count != null) 'count': count,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  InhabitantsCompanion copyWith({
    Value<int>? id,
    Value<String>? tankId,
    Value<String>? name,
    Value<int>? count,
    Value<String?>? type,
    Value<DateTime>? createdAt,
  }) {
    return InhabitantsCompanion(
      id: id ?? this.id,
      tankId: tankId ?? this.tankId,
      name: name ?? this.name,
      count: count ?? this.count,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InhabitantsCompanion(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('name: $name, ')
          ..write('count: $count, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PlantsTable extends Plants with TableInfo<$PlantsTable, Plant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [id, tankId, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plants';
  @override
  VerificationContext validateIntegrity(
    Insertable<Plant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Plant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Plant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlantsTable createAlias(String alias) {
    return $PlantsTable(attachedDatabase, alias);
  }
}

class Plant extends DataClass implements Insertable<Plant> {
  final int id;
  final String tankId;
  final String name;
  final DateTime createdAt;
  const Plant({
    required this.id,
    required this.tankId,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tank_id'] = Variable<String>(tankId);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PlantsCompanion toCompanion(bool nullToAbsent) {
    return PlantsCompanion(
      id: Value(id),
      tankId: Value(tankId),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Plant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Plant(
      id: serializer.fromJson<int>(json['id']),
      tankId: serializer.fromJson<String>(json['tankId']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tankId': serializer.toJson<String>(tankId),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Plant copyWith({
    int? id,
    String? tankId,
    String? name,
    DateTime? createdAt,
  }) => Plant(
    id: id ?? this.id,
    tankId: tankId ?? this.tankId,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Plant copyWithCompanion(PlantsCompanion data) {
    return Plant(
      id: data.id.present ? data.id.value : this.id,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Plant(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tankId, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Plant &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class PlantsCompanion extends UpdateCompanion<Plant> {
  final Value<int> id;
  final Value<String> tankId;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const PlantsCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PlantsCompanion.insert({
    this.id = const Value.absent(),
    required String tankId,
    required String name,
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       name = Value(name);
  static Insertable<Plant> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PlantsCompanion copyWith({
    Value<int>? id,
    Value<String>? tankId,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return PlantsCompanion(
      id: id ?? this.id,
      tankId: tankId ?? this.tankId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlantsCompanion(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LogsTable extends Logs with TableInfo<$LogsTable, Log> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cloudIdMeta = const VerificationMeta(
    'cloudId',
  );
  @override
  late final GeneratedColumn<int> cloudId = GeneratedColumn<int>(
    'cloud_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parsedJsonMeta = const VerificationMeta(
    'parsedJson',
  );
  @override
  late final GeneratedColumn<String> parsedJson = GeneratedColumn<String>(
    'parsed_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cloudId,
    tankId,
    rawText,
    parsedJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Log> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cloud_id')) {
      context.handle(
        _cloudIdMeta,
        cloudId.isAcceptableOrUnknown(data['cloud_id']!, _cloudIdMeta),
      );
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('parsed_json')) {
      context.handle(
        _parsedJsonMeta,
        parsedJson.isAcceptableOrUnknown(data['parsed_json']!, _parsedJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Log map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Log(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cloudId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_id'],
      ),
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      parsedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parsed_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LogsTable createAlias(String alias) {
    return $LogsTable(attachedDatabase, alias);
  }
}

class Log extends DataClass implements Insertable<Log> {
  final int id;
  final int? cloudId;
  final String tankId;
  final String rawText;
  final String? parsedJson;
  final DateTime createdAt;
  const Log({
    required this.id,
    this.cloudId,
    required this.tankId,
    required this.rawText,
    this.parsedJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cloudId != null) {
      map['cloud_id'] = Variable<int>(cloudId);
    }
    map['tank_id'] = Variable<String>(tankId);
    map['raw_text'] = Variable<String>(rawText);
    if (!nullToAbsent || parsedJson != null) {
      map['parsed_json'] = Variable<String>(parsedJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LogsCompanion toCompanion(bool nullToAbsent) {
    return LogsCompanion(
      id: Value(id),
      cloudId: cloudId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudId),
      tankId: Value(tankId),
      rawText: Value(rawText),
      parsedJson: parsedJson == null && nullToAbsent
          ? const Value.absent()
          : Value(parsedJson),
      createdAt: Value(createdAt),
    );
  }

  factory Log.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Log(
      id: serializer.fromJson<int>(json['id']),
      cloudId: serializer.fromJson<int?>(json['cloudId']),
      tankId: serializer.fromJson<String>(json['tankId']),
      rawText: serializer.fromJson<String>(json['rawText']),
      parsedJson: serializer.fromJson<String?>(json['parsedJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cloudId': serializer.toJson<int?>(cloudId),
      'tankId': serializer.toJson<String>(tankId),
      'rawText': serializer.toJson<String>(rawText),
      'parsedJson': serializer.toJson<String?>(parsedJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Log copyWith({
    int? id,
    Value<int?> cloudId = const Value.absent(),
    String? tankId,
    String? rawText,
    Value<String?> parsedJson = const Value.absent(),
    DateTime? createdAt,
  }) => Log(
    id: id ?? this.id,
    cloudId: cloudId.present ? cloudId.value : this.cloudId,
    tankId: tankId ?? this.tankId,
    rawText: rawText ?? this.rawText,
    parsedJson: parsedJson.present ? parsedJson.value : this.parsedJson,
    createdAt: createdAt ?? this.createdAt,
  );
  Log copyWithCompanion(LogsCompanion data) {
    return Log(
      id: data.id.present ? data.id.value : this.id,
      cloudId: data.cloudId.present ? data.cloudId.value : this.cloudId,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      parsedJson: data.parsedJson.present
          ? data.parsedJson.value
          : this.parsedJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Log(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('tankId: $tankId, ')
          ..write('rawText: $rawText, ')
          ..write('parsedJson: $parsedJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, cloudId, tankId, rawText, parsedJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Log &&
          other.id == this.id &&
          other.cloudId == this.cloudId &&
          other.tankId == this.tankId &&
          other.rawText == this.rawText &&
          other.parsedJson == this.parsedJson &&
          other.createdAt == this.createdAt);
}

class LogsCompanion extends UpdateCompanion<Log> {
  final Value<int> id;
  final Value<int?> cloudId;
  final Value<String> tankId;
  final Value<String> rawText;
  final Value<String?> parsedJson;
  final Value<DateTime> createdAt;
  const LogsCompanion({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    this.tankId = const Value.absent(),
    this.rawText = const Value.absent(),
    this.parsedJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  LogsCompanion.insert({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    required String tankId,
    required String rawText,
    this.parsedJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       rawText = Value(rawText);
  static Insertable<Log> custom({
    Expression<int>? id,
    Expression<int>? cloudId,
    Expression<String>? tankId,
    Expression<String>? rawText,
    Expression<String>? parsedJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cloudId != null) 'cloud_id': cloudId,
      if (tankId != null) 'tank_id': tankId,
      if (rawText != null) 'raw_text': rawText,
      if (parsedJson != null) 'parsed_json': parsedJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  LogsCompanion copyWith({
    Value<int>? id,
    Value<int?>? cloudId,
    Value<String>? tankId,
    Value<String>? rawText,
    Value<String?>? parsedJson,
    Value<DateTime>? createdAt,
  }) {
    return LogsCompanion(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      tankId: tankId ?? this.tankId,
      rawText: rawText ?? this.rawText,
      parsedJson: parsedJson ?? this.parsedJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cloudId.present) {
      map['cloud_id'] = Variable<int>(cloudId.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (parsedJson.present) {
      map['parsed_json'] = Variable<String>(parsedJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LogsCompanion(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('tankId: $tankId, ')
          ..write('rawText: $rawText, ')
          ..write('parsedJson: $parsedJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TankPhotosTable extends TankPhotos
    with TableInfo<$TankPhotosTable, TankPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TankPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [id, tankId, filePath, note, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tank_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<TankPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TankPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TankPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TankPhotosTable createAlias(String alias) {
    return $TankPhotosTable(attachedDatabase, alias);
  }
}

class TankPhoto extends DataClass implements Insertable<TankPhoto> {
  final int id;
  final String tankId;
  final String filePath;
  final String? note;
  final DateTime createdAt;
  const TankPhoto({
    required this.id,
    required this.tankId,
    required this.filePath,
    this.note,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tank_id'] = Variable<String>(tankId);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TankPhotosCompanion toCompanion(bool nullToAbsent) {
    return TankPhotosCompanion(
      id: Value(id),
      tankId: Value(tankId),
      filePath: Value(filePath),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory TankPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TankPhoto(
      id: serializer.fromJson<int>(json['id']),
      tankId: serializer.fromJson<String>(json['tankId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tankId': serializer.toJson<String>(tankId),
      'filePath': serializer.toJson<String>(filePath),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TankPhoto copyWith({
    int? id,
    String? tankId,
    String? filePath,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
  }) => TankPhoto(
    id: id ?? this.id,
    tankId: tankId ?? this.tankId,
    filePath: filePath ?? this.filePath,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
  );
  TankPhoto copyWithCompanion(TankPhotosCompanion data) {
    return TankPhoto(
      id: data.id.present ? data.id.value : this.id,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TankPhoto(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('filePath: $filePath, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tankId, filePath, note, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TankPhoto &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.filePath == this.filePath &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class TankPhotosCompanion extends UpdateCompanion<TankPhoto> {
  final Value<int> id;
  final Value<String> tankId;
  final Value<String> filePath;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  const TankPhotosCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TankPhotosCompanion.insert({
    this.id = const Value.absent(),
    required String tankId,
    required String filePath,
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       filePath = Value(filePath);
  static Insertable<TankPhoto> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? filePath,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (filePath != null) 'file_path': filePath,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TankPhotosCompanion copyWith({
    Value<int>? id,
    Value<String>? tankId,
    Value<String>? filePath,
    Value<String?>? note,
    Value<DateTime>? createdAt,
  }) {
    return TankPhotosCompanion(
      id: id ?? this.id,
      tankId: tankId ?? this.tankId,
      filePath: filePath ?? this.filePath,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TankPhotosCompanion(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('filePath: $filePath, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('normal'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ai'),
  );
  static const VerificationMeta _isDismissedMeta = const VerificationMeta(
    'isDismissed',
  );
  @override
  late final GeneratedColumn<bool> isDismissed = GeneratedColumn<bool>(
    'is_dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dismissed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dismissedAtMeta = const VerificationMeta(
    'dismissedAt',
  );
  @override
  late final GeneratedColumn<DateTime> dismissedAt = GeneratedColumn<DateTime>(
    'dismissed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCompleteMeta = const VerificationMeta(
    'isComplete',
  );
  @override
  late final GeneratedColumn<bool> isComplete = GeneratedColumn<bool>(
    'is_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatDaysMeta = const VerificationMeta(
    'repeatDays',
  );
  @override
  late final GeneratedColumn<int> repeatDays = GeneratedColumn<int>(
    'repeat_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPausedMeta = const VerificationMeta(
    'isPaused',
  );
  @override
  late final GeneratedColumn<bool> isPaused = GeneratedColumn<bool>(
    'is_paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tankId,
    description,
    dueDate,
    priority,
    source,
    isDismissed,
    dismissedAt,
    isComplete,
    completedAt,
    repeatDays,
    isPaused,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('is_dismissed')) {
      context.handle(
        _isDismissedMeta,
        isDismissed.isAcceptableOrUnknown(
          data['is_dismissed']!,
          _isDismissedMeta,
        ),
      );
    }
    if (data.containsKey('dismissed_at')) {
      context.handle(
        _dismissedAtMeta,
        dismissedAt.isAcceptableOrUnknown(
          data['dismissed_at']!,
          _dismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_complete')) {
      context.handle(
        _isCompleteMeta,
        isComplete.isAcceptableOrUnknown(data['is_complete']!, _isCompleteMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('repeat_days')) {
      context.handle(
        _repeatDaysMeta,
        repeatDays.isAcceptableOrUnknown(data['repeat_days']!, _repeatDaysMeta),
      );
    }
    if (data.containsKey('is_paused')) {
      context.handle(
        _isPausedMeta,
        isPaused.isAcceptableOrUnknown(data['is_paused']!, _isPausedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      isDismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dismissed'],
      )!,
      dismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dismissed_at'],
      ),
      isComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_complete'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      repeatDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_days'],
      ),
      isPaused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_paused'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final int id;
  final String tankId;
  final String description;
  final String? dueDate;
  final String priority;
  final String source;
  final bool isDismissed;
  final DateTime? dismissedAt;
  final bool isComplete;
  final DateTime? completedAt;
  final int? repeatDays;
  final bool isPaused;
  final DateTime createdAt;
  const Task({
    required this.id,
    required this.tankId,
    required this.description,
    this.dueDate,
    required this.priority,
    required this.source,
    required this.isDismissed,
    this.dismissedAt,
    required this.isComplete,
    this.completedAt,
    this.repeatDays,
    required this.isPaused,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tank_id'] = Variable<String>(tankId);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    map['priority'] = Variable<String>(priority);
    map['source'] = Variable<String>(source);
    map['is_dismissed'] = Variable<bool>(isDismissed);
    if (!nullToAbsent || dismissedAt != null) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt);
    }
    map['is_complete'] = Variable<bool>(isComplete);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || repeatDays != null) {
      map['repeat_days'] = Variable<int>(repeatDays);
    }
    map['is_paused'] = Variable<bool>(isPaused);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      tankId: Value(tankId),
      description: Value(description),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      priority: Value(priority),
      source: Value(source),
      isDismissed: Value(isDismissed),
      dismissedAt: dismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissedAt),
      isComplete: Value(isComplete),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      repeatDays: repeatDays == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatDays),
      isPaused: Value(isPaused),
      createdAt: Value(createdAt),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<int>(json['id']),
      tankId: serializer.fromJson<String>(json['tankId']),
      description: serializer.fromJson<String>(json['description']),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      priority: serializer.fromJson<String>(json['priority']),
      source: serializer.fromJson<String>(json['source']),
      isDismissed: serializer.fromJson<bool>(json['isDismissed']),
      dismissedAt: serializer.fromJson<DateTime?>(json['dismissedAt']),
      isComplete: serializer.fromJson<bool>(json['isComplete']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      repeatDays: serializer.fromJson<int?>(json['repeatDays']),
      isPaused: serializer.fromJson<bool>(json['isPaused']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tankId': serializer.toJson<String>(tankId),
      'description': serializer.toJson<String>(description),
      'dueDate': serializer.toJson<String?>(dueDate),
      'priority': serializer.toJson<String>(priority),
      'source': serializer.toJson<String>(source),
      'isDismissed': serializer.toJson<bool>(isDismissed),
      'dismissedAt': serializer.toJson<DateTime?>(dismissedAt),
      'isComplete': serializer.toJson<bool>(isComplete),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'repeatDays': serializer.toJson<int?>(repeatDays),
      'isPaused': serializer.toJson<bool>(isPaused),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Task copyWith({
    int? id,
    String? tankId,
    String? description,
    Value<String?> dueDate = const Value.absent(),
    String? priority,
    String? source,
    bool? isDismissed,
    Value<DateTime?> dismissedAt = const Value.absent(),
    bool? isComplete,
    Value<DateTime?> completedAt = const Value.absent(),
    Value<int?> repeatDays = const Value.absent(),
    bool? isPaused,
    DateTime? createdAt,
  }) => Task(
    id: id ?? this.id,
    tankId: tankId ?? this.tankId,
    description: description ?? this.description,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    priority: priority ?? this.priority,
    source: source ?? this.source,
    isDismissed: isDismissed ?? this.isDismissed,
    dismissedAt: dismissedAt.present ? dismissedAt.value : this.dismissedAt,
    isComplete: isComplete ?? this.isComplete,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    repeatDays: repeatDays.present ? repeatDays.value : this.repeatDays,
    isPaused: isPaused ?? this.isPaused,
    createdAt: createdAt ?? this.createdAt,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      description: data.description.present
          ? data.description.value
          : this.description,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      priority: data.priority.present ? data.priority.value : this.priority,
      source: data.source.present ? data.source.value : this.source,
      isDismissed: data.isDismissed.present
          ? data.isDismissed.value
          : this.isDismissed,
      dismissedAt: data.dismissedAt.present
          ? data.dismissedAt.value
          : this.dismissedAt,
      isComplete: data.isComplete.present
          ? data.isComplete.value
          : this.isComplete,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      repeatDays: data.repeatDays.present
          ? data.repeatDays.value
          : this.repeatDays,
      isPaused: data.isPaused.present ? data.isPaused.value : this.isPaused,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('description: $description, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('source: $source, ')
          ..write('isDismissed: $isDismissed, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('isComplete: $isComplete, ')
          ..write('completedAt: $completedAt, ')
          ..write('repeatDays: $repeatDays, ')
          ..write('isPaused: $isPaused, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tankId,
    description,
    dueDate,
    priority,
    source,
    isDismissed,
    dismissedAt,
    isComplete,
    completedAt,
    repeatDays,
    isPaused,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.description == this.description &&
          other.dueDate == this.dueDate &&
          other.priority == this.priority &&
          other.source == this.source &&
          other.isDismissed == this.isDismissed &&
          other.dismissedAt == this.dismissedAt &&
          other.isComplete == this.isComplete &&
          other.completedAt == this.completedAt &&
          other.repeatDays == this.repeatDays &&
          other.isPaused == this.isPaused &&
          other.createdAt == this.createdAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<int> id;
  final Value<String> tankId;
  final Value<String> description;
  final Value<String?> dueDate;
  final Value<String> priority;
  final Value<String> source;
  final Value<bool> isDismissed;
  final Value<DateTime?> dismissedAt;
  final Value<bool> isComplete;
  final Value<DateTime?> completedAt;
  final Value<int?> repeatDays;
  final Value<bool> isPaused;
  final Value<DateTime> createdAt;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.description = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.source = const Value.absent(),
    this.isDismissed = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.isComplete = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.repeatDays = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    required String tankId,
    required String description,
    this.dueDate = const Value.absent(),
    this.priority = const Value.absent(),
    this.source = const Value.absent(),
    this.isDismissed = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.isComplete = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.repeatDays = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       description = Value(description);
  static Insertable<Task> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? description,
    Expression<String>? dueDate,
    Expression<String>? priority,
    Expression<String>? source,
    Expression<bool>? isDismissed,
    Expression<DateTime>? dismissedAt,
    Expression<bool>? isComplete,
    Expression<DateTime>? completedAt,
    Expression<int>? repeatDays,
    Expression<bool>? isPaused,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': dueDate,
      if (priority != null) 'priority': priority,
      if (source != null) 'source': source,
      if (isDismissed != null) 'is_dismissed': isDismissed,
      if (dismissedAt != null) 'dismissed_at': dismissedAt,
      if (isComplete != null) 'is_complete': isComplete,
      if (completedAt != null) 'completed_at': completedAt,
      if (repeatDays != null) 'repeat_days': repeatDays,
      if (isPaused != null) 'is_paused': isPaused,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TasksCompanion copyWith({
    Value<int>? id,
    Value<String>? tankId,
    Value<String>? description,
    Value<String?>? dueDate,
    Value<String>? priority,
    Value<String>? source,
    Value<bool>? isDismissed,
    Value<DateTime?>? dismissedAt,
    Value<bool>? isComplete,
    Value<DateTime?>? completedAt,
    Value<int?>? repeatDays,
    Value<bool>? isPaused,
    Value<DateTime>? createdAt,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      tankId: tankId ?? this.tankId,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      source: source ?? this.source,
      isDismissed: isDismissed ?? this.isDismissed,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      isComplete: isComplete ?? this.isComplete,
      completedAt: completedAt ?? this.completedAt,
      repeatDays: repeatDays ?? this.repeatDays,
      isPaused: isPaused ?? this.isPaused,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isDismissed.present) {
      map['is_dismissed'] = Variable<bool>(isDismissed.value);
    }
    if (dismissedAt.present) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt.value);
    }
    if (isComplete.present) {
      map['is_complete'] = Variable<bool>(isComplete.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (repeatDays.present) {
      map['repeat_days'] = Variable<int>(repeatDays.value);
    }
    if (isPaused.present) {
      map['is_paused'] = Variable<bool>(isPaused.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('description: $description, ')
          ..write('dueDate: $dueDate, ')
          ..write('priority: $priority, ')
          ..write('source: $source, ')
          ..write('isDismissed: $isDismissed, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('isComplete: $isComplete, ')
          ..write('completedAt: $completedAt, ')
          ..write('repeatDays: $repeatDays, ')
          ..write('isPaused: $isPaused, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTable extends JournalEntries
    with TableInfo<$JournalEntriesTable, JournalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cloudIdMeta = const VerificationMeta(
    'cloudId',
  );
  @override
  late final GeneratedColumn<int> cloudId = GeneratedColumn<int>(
    'cloud_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cloudId,
    tankId,
    date,
    category,
    data,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cloud_id')) {
      context.handle(
        _cloudIdMeta,
        cloudId.isAcceptableOrUnknown(data['cloud_id']!, _cloudIdMeta),
      );
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tankIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JournalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cloudId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_id'],
      ),
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $JournalEntriesTable createAlias(String alias) {
    return $JournalEntriesTable(attachedDatabase, alias);
  }
}

class JournalEntry extends DataClass implements Insertable<JournalEntry> {
  final int id;
  final int? cloudId;
  final String tankId;
  final String date;
  final String category;
  final String data;
  final DateTime updatedAt;
  const JournalEntry({
    required this.id,
    this.cloudId,
    required this.tankId,
    required this.date,
    required this.category,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cloudId != null) {
      map['cloud_id'] = Variable<int>(cloudId);
    }
    map['tank_id'] = Variable<String>(tankId);
    map['date'] = Variable<String>(date);
    map['category'] = Variable<String>(category);
    map['data'] = Variable<String>(data);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  JournalEntriesCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesCompanion(
      id: Value(id),
      cloudId: cloudId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudId),
      tankId: Value(tankId),
      date: Value(date),
      category: Value(category),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory JournalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntry(
      id: serializer.fromJson<int>(json['id']),
      cloudId: serializer.fromJson<int?>(json['cloudId']),
      tankId: serializer.fromJson<String>(json['tankId']),
      date: serializer.fromJson<String>(json['date']),
      category: serializer.fromJson<String>(json['category']),
      data: serializer.fromJson<String>(json['data']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cloudId': serializer.toJson<int?>(cloudId),
      'tankId': serializer.toJson<String>(tankId),
      'date': serializer.toJson<String>(date),
      'category': serializer.toJson<String>(category),
      'data': serializer.toJson<String>(data),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  JournalEntry copyWith({
    int? id,
    Value<int?> cloudId = const Value.absent(),
    String? tankId,
    String? date,
    String? category,
    String? data,
    DateTime? updatedAt,
  }) => JournalEntry(
    id: id ?? this.id,
    cloudId: cloudId.present ? cloudId.value : this.cloudId,
    tankId: tankId ?? this.tankId,
    date: date ?? this.date,
    category: category ?? this.category,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  JournalEntry copyWithCompanion(JournalEntriesCompanion data) {
    return JournalEntry(
      id: data.id.present ? data.id.value : this.id,
      cloudId: data.cloudId.present ? data.cloudId.value : this.cloudId,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      date: data.date.present ? data.date.value : this.date,
      category: data.category.present ? data.category.value : this.category,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntry(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('tankId: $tankId, ')
          ..write('date: $date, ')
          ..write('category: $category, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, cloudId, tankId, date, category, data, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntry &&
          other.id == this.id &&
          other.cloudId == this.cloudId &&
          other.tankId == this.tankId &&
          other.date == this.date &&
          other.category == this.category &&
          other.data == this.data &&
          other.updatedAt == this.updatedAt);
}

class JournalEntriesCompanion extends UpdateCompanion<JournalEntry> {
  final Value<int> id;
  final Value<int?> cloudId;
  final Value<String> tankId;
  final Value<String> date;
  final Value<String> category;
  final Value<String> data;
  final Value<DateTime> updatedAt;
  const JournalEntriesCompanion({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    this.tankId = const Value.absent(),
    this.date = const Value.absent(),
    this.category = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  JournalEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    required String tankId,
    required String date,
    required String category,
    required String data,
    required DateTime updatedAt,
  }) : tankId = Value(tankId),
       date = Value(date),
       category = Value(category),
       data = Value(data),
       updatedAt = Value(updatedAt);
  static Insertable<JournalEntry> custom({
    Expression<int>? id,
    Expression<int>? cloudId,
    Expression<String>? tankId,
    Expression<String>? date,
    Expression<String>? category,
    Expression<String>? data,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cloudId != null) 'cloud_id': cloudId,
      if (tankId != null) 'tank_id': tankId,
      if (date != null) 'date': date,
      if (category != null) 'category': category,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  JournalEntriesCompanion copyWith({
    Value<int>? id,
    Value<int?>? cloudId,
    Value<String>? tankId,
    Value<String>? date,
    Value<String>? category,
    Value<String>? data,
    Value<DateTime>? updatedAt,
  }) {
    return JournalEntriesCompanion(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      tankId: tankId ?? this.tankId,
      date: date ?? this.date,
      category: category ?? this.category,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cloudId.present) {
      map['cloud_id'] = Variable<int>(cloudId.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesCompanion(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('tankId: $tankId, ')
          ..write('date: $date, ')
          ..write('category: $category, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tankIdMeta = const VerificationMeta('tankId');
  @override
  late final GeneratedColumn<String> tankId = GeneratedColumn<String>(
    'tank_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  @override
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: Constant(DateTime.now()),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tankId,
    summary,
    messageCount,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tank_id')) {
      context.handle(
        _tankIdMeta,
        tankId.isAcceptableOrUnknown(data['tank_id']!, _tankIdMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tank_id'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSession extends DataClass implements Insertable<ChatSession> {
  final int id;
  final String? tankId;
  final String summary;
  final int messageCount;
  final DateTime createdAt;
  const ChatSession({
    required this.id,
    this.tankId,
    required this.summary,
    required this.messageCount,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || tankId != null) {
      map['tank_id'] = Variable<String>(tankId);
    }
    map['summary'] = Variable<String>(summary);
    map['message_count'] = Variable<int>(messageCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      id: Value(id),
      tankId: tankId == null && nullToAbsent
          ? const Value.absent()
          : Value(tankId),
      summary: Value(summary),
      messageCount: Value(messageCount),
      createdAt: Value(createdAt),
    );
  }

  factory ChatSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSession(
      id: serializer.fromJson<int>(json['id']),
      tankId: serializer.fromJson<String?>(json['tankId']),
      summary: serializer.fromJson<String>(json['summary']),
      messageCount: serializer.fromJson<int>(json['messageCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tankId': serializer.toJson<String?>(tankId),
      'summary': serializer.toJson<String>(summary),
      'messageCount': serializer.toJson<int>(messageCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatSession copyWith({
    int? id,
    Value<String?> tankId = const Value.absent(),
    String? summary,
    int? messageCount,
    DateTime? createdAt,
  }) => ChatSession(
    id: id ?? this.id,
    tankId: tankId.present ? tankId.value : this.tankId,
    summary: summary ?? this.summary,
    messageCount: messageCount ?? this.messageCount,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatSession copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSession(
      id: data.id.present ? data.id.value : this.id,
      tankId: data.tankId.present ? data.tankId.value : this.tankId,
      summary: data.summary.present ? data.summary.value : this.summary,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSession(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('summary: $summary, ')
          ..write('messageCount: $messageCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tankId, summary, messageCount, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSession &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.summary == this.summary &&
          other.messageCount == this.messageCount &&
          other.createdAt == this.createdAt);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSession> {
  final Value<int> id;
  final Value<String?> tankId;
  final Value<String> summary;
  final Value<int> messageCount;
  final Value<DateTime> createdAt;
  const ChatSessionsCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.summary = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    required String summary,
    this.messageCount = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : summary = Value(summary);
  static Insertable<ChatSession> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? summary,
    Expression<int>? messageCount,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (summary != null) 'summary': summary,
      if (messageCount != null) 'message_count': messageCount,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ChatSessionsCompanion copyWith({
    Value<int>? id,
    Value<String?>? tankId,
    Value<String>? summary,
    Value<int>? messageCount,
    Value<DateTime>? createdAt,
  }) {
    return ChatSessionsCompanion(
      id: id ?? this.id,
      tankId: tankId ?? this.tankId,
      summary: summary ?? this.summary,
      messageCount: messageCount ?? this.messageCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tankId.present) {
      map['tank_id'] = Variable<String>(tankId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('id: $id, ')
          ..write('tankId: $tankId, ')
          ..write('summary: $summary, ')
          ..write('messageCount: $messageCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $TanksTable tanks = $TanksTable(this);
  late final $InhabitantsTable inhabitants = $InhabitantsTable(this);
  late final $PlantsTable plants = $PlantsTable(this);
  late final $LogsTable logs = $LogsTable(this);
  late final $TankPhotosTable tankPhotos = $TankPhotosTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $JournalEntriesTable journalEntries = $JournalEntriesTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tanks,
    inhabitants,
    plants,
    logs,
    tankPhotos,
    tasks,
    journalEntries,
    chatSessions,
  ];
}

typedef $$TanksTableCreateCompanionBuilder =
    TanksCompanion Function({
      required String id,
      required String name,
      required int gallons,
      required String waterType,
      required DateTime createdAt,
      Value<bool> isArchived,
      Value<DateTime?> archivedAt,
      Value<String?> tapWaterJson,
      Value<int> rowid,
    });
typedef $$TanksTableUpdateCompanionBuilder =
    TanksCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> gallons,
      Value<String> waterType,
      Value<DateTime> createdAt,
      Value<bool> isArchived,
      Value<DateTime?> archivedAt,
      Value<String?> tapWaterJson,
      Value<int> rowid,
    });

class $$TanksTableFilterComposer extends Composer<_$AppDb, $TanksTable> {
  $$TanksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gallons => $composableBuilder(
    column: $table.gallons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waterType => $composableBuilder(
    column: $table.waterType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tapWaterJson => $composableBuilder(
    column: $table.tapWaterJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TanksTableOrderingComposer extends Composer<_$AppDb, $TanksTable> {
  $$TanksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gallons => $composableBuilder(
    column: $table.gallons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waterType => $composableBuilder(
    column: $table.waterType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tapWaterJson => $composableBuilder(
    column: $table.tapWaterJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TanksTableAnnotationComposer extends Composer<_$AppDb, $TanksTable> {
  $$TanksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get gallons =>
      $composableBuilder(column: $table.gallons, builder: (column) => column);

  GeneratedColumn<String> get waterType =>
      $composableBuilder(column: $table.waterType, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tapWaterJson => $composableBuilder(
    column: $table.tapWaterJson,
    builder: (column) => column,
  );
}

class $$TanksTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TanksTable,
          Tank,
          $$TanksTableFilterComposer,
          $$TanksTableOrderingComposer,
          $$TanksTableAnnotationComposer,
          $$TanksTableCreateCompanionBuilder,
          $$TanksTableUpdateCompanionBuilder,
          (Tank, BaseReferences<_$AppDb, $TanksTable, Tank>),
          Tank,
          PrefetchHooks Function()
        > {
  $$TanksTableTableManager(_$AppDb db, $TanksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TanksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TanksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TanksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> gallons = const Value.absent(),
                Value<String> waterType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String?> tapWaterJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TanksCompanion(
                id: id,
                name: name,
                gallons: gallons,
                waterType: waterType,
                createdAt: createdAt,
                isArchived: isArchived,
                archivedAt: archivedAt,
                tapWaterJson: tapWaterJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int gallons,
                required String waterType,
                required DateTime createdAt,
                Value<bool> isArchived = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String?> tapWaterJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TanksCompanion.insert(
                id: id,
                name: name,
                gallons: gallons,
                waterType: waterType,
                createdAt: createdAt,
                isArchived: isArchived,
                archivedAt: archivedAt,
                tapWaterJson: tapWaterJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TanksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TanksTable,
      Tank,
      $$TanksTableFilterComposer,
      $$TanksTableOrderingComposer,
      $$TanksTableAnnotationComposer,
      $$TanksTableCreateCompanionBuilder,
      $$TanksTableUpdateCompanionBuilder,
      (Tank, BaseReferences<_$AppDb, $TanksTable, Tank>),
      Tank,
      PrefetchHooks Function()
    >;
typedef $$InhabitantsTableCreateCompanionBuilder =
    InhabitantsCompanion Function({
      Value<int> id,
      required String tankId,
      required String name,
      Value<int> count,
      Value<String?> type,
      Value<DateTime> createdAt,
    });
typedef $$InhabitantsTableUpdateCompanionBuilder =
    InhabitantsCompanion Function({
      Value<int> id,
      Value<String> tankId,
      Value<String> name,
      Value<int> count,
      Value<String?> type,
      Value<DateTime> createdAt,
    });

class $$InhabitantsTableFilterComposer
    extends Composer<_$AppDb, $InhabitantsTable> {
  $$InhabitantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InhabitantsTableOrderingComposer
    extends Composer<_$AppDb, $InhabitantsTable> {
  $$InhabitantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InhabitantsTableAnnotationComposer
    extends Composer<_$AppDb, $InhabitantsTable> {
  $$InhabitantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$InhabitantsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $InhabitantsTable,
          Inhabitant,
          $$InhabitantsTableFilterComposer,
          $$InhabitantsTableOrderingComposer,
          $$InhabitantsTableAnnotationComposer,
          $$InhabitantsTableCreateCompanionBuilder,
          $$InhabitantsTableUpdateCompanionBuilder,
          (Inhabitant, BaseReferences<_$AppDb, $InhabitantsTable, Inhabitant>),
          Inhabitant,
          PrefetchHooks Function()
        > {
  $$InhabitantsTableTableManager(_$AppDb db, $InhabitantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InhabitantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InhabitantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InhabitantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => InhabitantsCompanion(
                id: id,
                tankId: tankId,
                name: name,
                count: count,
                type: type,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tankId,
                required String name,
                Value<int> count = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => InhabitantsCompanion.insert(
                id: id,
                tankId: tankId,
                name: name,
                count: count,
                type: type,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InhabitantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $InhabitantsTable,
      Inhabitant,
      $$InhabitantsTableFilterComposer,
      $$InhabitantsTableOrderingComposer,
      $$InhabitantsTableAnnotationComposer,
      $$InhabitantsTableCreateCompanionBuilder,
      $$InhabitantsTableUpdateCompanionBuilder,
      (Inhabitant, BaseReferences<_$AppDb, $InhabitantsTable, Inhabitant>),
      Inhabitant,
      PrefetchHooks Function()
    >;
typedef $$PlantsTableCreateCompanionBuilder =
    PlantsCompanion Function({
      Value<int> id,
      required String tankId,
      required String name,
      Value<DateTime> createdAt,
    });
typedef $$PlantsTableUpdateCompanionBuilder =
    PlantsCompanion Function({
      Value<int> id,
      Value<String> tankId,
      Value<String> name,
      Value<DateTime> createdAt,
    });

class $$PlantsTableFilterComposer extends Composer<_$AppDb, $PlantsTable> {
  $$PlantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlantsTableOrderingComposer extends Composer<_$AppDb, $PlantsTable> {
  $$PlantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlantsTableAnnotationComposer extends Composer<_$AppDb, $PlantsTable> {
  $$PlantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PlantsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $PlantsTable,
          Plant,
          $$PlantsTableFilterComposer,
          $$PlantsTableOrderingComposer,
          $$PlantsTableAnnotationComposer,
          $$PlantsTableCreateCompanionBuilder,
          $$PlantsTableUpdateCompanionBuilder,
          (Plant, BaseReferences<_$AppDb, $PlantsTable, Plant>),
          Plant,
          PrefetchHooks Function()
        > {
  $$PlantsTableTableManager(_$AppDb db, $PlantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PlantsCompanion(
                id: id,
                tankId: tankId,
                name: name,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tankId,
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
              }) => PlantsCompanion.insert(
                id: id,
                tankId: tankId,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $PlantsTable,
      Plant,
      $$PlantsTableFilterComposer,
      $$PlantsTableOrderingComposer,
      $$PlantsTableAnnotationComposer,
      $$PlantsTableCreateCompanionBuilder,
      $$PlantsTableUpdateCompanionBuilder,
      (Plant, BaseReferences<_$AppDb, $PlantsTable, Plant>),
      Plant,
      PrefetchHooks Function()
    >;
typedef $$LogsTableCreateCompanionBuilder =
    LogsCompanion Function({
      Value<int> id,
      Value<int?> cloudId,
      required String tankId,
      required String rawText,
      Value<String?> parsedJson,
      Value<DateTime> createdAt,
    });
typedef $$LogsTableUpdateCompanionBuilder =
    LogsCompanion Function({
      Value<int> id,
      Value<int?> cloudId,
      Value<String> tankId,
      Value<String> rawText,
      Value<String?> parsedJson,
      Value<DateTime> createdAt,
    });

class $$LogsTableFilterComposer extends Composer<_$AppDb, $LogsTable> {
  $$LogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parsedJson => $composableBuilder(
    column: $table.parsedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LogsTableOrderingComposer extends Composer<_$AppDb, $LogsTable> {
  $$LogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parsedJson => $composableBuilder(
    column: $table.parsedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LogsTableAnnotationComposer extends Composer<_$AppDb, $LogsTable> {
  $$LogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cloudId =>
      $composableBuilder(column: $table.cloudId, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get parsedJson => $composableBuilder(
    column: $table.parsedJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LogsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LogsTable,
          Log,
          $$LogsTableFilterComposer,
          $$LogsTableOrderingComposer,
          $$LogsTableAnnotationComposer,
          $$LogsTableCreateCompanionBuilder,
          $$LogsTableUpdateCompanionBuilder,
          (Log, BaseReferences<_$AppDb, $LogsTable, Log>),
          Log,
          PrefetchHooks Function()
        > {
  $$LogsTableTableManager(_$AppDb db, $LogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cloudId = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String?> parsedJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => LogsCompanion(
                id: id,
                cloudId: cloudId,
                tankId: tankId,
                rawText: rawText,
                parsedJson: parsedJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cloudId = const Value.absent(),
                required String tankId,
                required String rawText,
                Value<String?> parsedJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => LogsCompanion.insert(
                id: id,
                cloudId: cloudId,
                tankId: tankId,
                rawText: rawText,
                parsedJson: parsedJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LogsTable,
      Log,
      $$LogsTableFilterComposer,
      $$LogsTableOrderingComposer,
      $$LogsTableAnnotationComposer,
      $$LogsTableCreateCompanionBuilder,
      $$LogsTableUpdateCompanionBuilder,
      (Log, BaseReferences<_$AppDb, $LogsTable, Log>),
      Log,
      PrefetchHooks Function()
    >;
typedef $$TankPhotosTableCreateCompanionBuilder =
    TankPhotosCompanion Function({
      Value<int> id,
      required String tankId,
      required String filePath,
      Value<String?> note,
      Value<DateTime> createdAt,
    });
typedef $$TankPhotosTableUpdateCompanionBuilder =
    TankPhotosCompanion Function({
      Value<int> id,
      Value<String> tankId,
      Value<String> filePath,
      Value<String?> note,
      Value<DateTime> createdAt,
    });

class $$TankPhotosTableFilterComposer
    extends Composer<_$AppDb, $TankPhotosTable> {
  $$TankPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TankPhotosTableOrderingComposer
    extends Composer<_$AppDb, $TankPhotosTable> {
  $$TankPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TankPhotosTableAnnotationComposer
    extends Composer<_$AppDb, $TankPhotosTable> {
  $$TankPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TankPhotosTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TankPhotosTable,
          TankPhoto,
          $$TankPhotosTableFilterComposer,
          $$TankPhotosTableOrderingComposer,
          $$TankPhotosTableAnnotationComposer,
          $$TankPhotosTableCreateCompanionBuilder,
          $$TankPhotosTableUpdateCompanionBuilder,
          (TankPhoto, BaseReferences<_$AppDb, $TankPhotosTable, TankPhoto>),
          TankPhoto,
          PrefetchHooks Function()
        > {
  $$TankPhotosTableTableManager(_$AppDb db, $TankPhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TankPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TankPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TankPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TankPhotosCompanion(
                id: id,
                tankId: tankId,
                filePath: filePath,
                note: note,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tankId,
                required String filePath,
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TankPhotosCompanion.insert(
                id: id,
                tankId: tankId,
                filePath: filePath,
                note: note,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TankPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TankPhotosTable,
      TankPhoto,
      $$TankPhotosTableFilterComposer,
      $$TankPhotosTableOrderingComposer,
      $$TankPhotosTableAnnotationComposer,
      $$TankPhotosTableCreateCompanionBuilder,
      $$TankPhotosTableUpdateCompanionBuilder,
      (TankPhoto, BaseReferences<_$AppDb, $TankPhotosTable, TankPhoto>),
      TankPhoto,
      PrefetchHooks Function()
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      required String tankId,
      required String description,
      Value<String?> dueDate,
      Value<String> priority,
      Value<String> source,
      Value<bool> isDismissed,
      Value<DateTime?> dismissedAt,
      Value<bool> isComplete,
      Value<DateTime?> completedAt,
      Value<int?> repeatDays,
      Value<bool> isPaused,
      Value<DateTime> createdAt,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      Value<String> tankId,
      Value<String> description,
      Value<String?> dueDate,
      Value<String> priority,
      Value<String> source,
      Value<bool> isDismissed,
      Value<DateTime?> dismissedAt,
      Value<bool> isComplete,
      Value<DateTime?> completedAt,
      Value<int?> repeatDays,
      Value<bool> isPaused,
      Value<DateTime> createdAt,
    });

class $$TasksTableFilterComposer extends Composer<_$AppDb, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDismissed => $composableBuilder(
    column: $table.isDismissed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeatDays => $composableBuilder(
    column: $table.repeatDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPaused => $composableBuilder(
    column: $table.isPaused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer extends Composer<_$AppDb, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDismissed => $composableBuilder(
    column: $table.isDismissed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatDays => $composableBuilder(
    column: $table.repeatDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPaused => $composableBuilder(
    column: $table.isPaused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer extends Composer<_$AppDb, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isDismissed => $composableBuilder(
    column: $table.isDismissed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeatDays => $composableBuilder(
    column: $table.repeatDays,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPaused =>
      $composableBuilder(column: $table.isPaused, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, BaseReferences<_$AppDb, $TasksTable, Task>),
          Task,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$AppDb db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isDismissed = const Value.absent(),
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> repeatDays = const Value.absent(),
                Value<bool> isPaused = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                tankId: tankId,
                description: description,
                dueDate: dueDate,
                priority: priority,
                source: source,
                isDismissed: isDismissed,
                dismissedAt: dismissedAt,
                isComplete: isComplete,
                completedAt: completedAt,
                repeatDays: repeatDays,
                isPaused: isPaused,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tankId,
                required String description,
                Value<String?> dueDate = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isDismissed = const Value.absent(),
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> repeatDays = const Value.absent(),
                Value<bool> isPaused = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                tankId: tankId,
                description: description,
                dueDate: dueDate,
                priority: priority,
                source: source,
                isDismissed: isDismissed,
                dismissedAt: dismissedAt,
                isComplete: isComplete,
                completedAt: completedAt,
                repeatDays: repeatDays,
                isPaused: isPaused,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, BaseReferences<_$AppDb, $TasksTable, Task>),
      Task,
      PrefetchHooks Function()
    >;
typedef $$JournalEntriesTableCreateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<int> id,
      Value<int?> cloudId,
      required String tankId,
      required String date,
      required String category,
      required String data,
      required DateTime updatedAt,
    });
typedef $$JournalEntriesTableUpdateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<int> id,
      Value<int?> cloudId,
      Value<String> tankId,
      Value<String> date,
      Value<String> category,
      Value<String> data,
      Value<DateTime> updatedAt,
    });

class $$JournalEntriesTableFilterComposer
    extends Composer<_$AppDb, $JournalEntriesTable> {
  $$JournalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalEntriesTableOrderingComposer
    extends Composer<_$AppDb, $JournalEntriesTable> {
  $$JournalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalEntriesTableAnnotationComposer
    extends Composer<_$AppDb, $JournalEntriesTable> {
  $$JournalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cloudId =>
      $composableBuilder(column: $table.cloudId, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$JournalEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $JournalEntriesTable,
          JournalEntry,
          $$JournalEntriesTableFilterComposer,
          $$JournalEntriesTableOrderingComposer,
          $$JournalEntriesTableAnnotationComposer,
          $$JournalEntriesTableCreateCompanionBuilder,
          $$JournalEntriesTableUpdateCompanionBuilder,
          (
            JournalEntry,
            BaseReferences<_$AppDb, $JournalEntriesTable, JournalEntry>,
          ),
          JournalEntry,
          PrefetchHooks Function()
        > {
  $$JournalEntriesTableTableManager(_$AppDb db, $JournalEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cloudId = const Value.absent(),
                Value<String> tankId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => JournalEntriesCompanion(
                id: id,
                cloudId: cloudId,
                tankId: tankId,
                date: date,
                category: category,
                data: data,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cloudId = const Value.absent(),
                required String tankId,
                required String date,
                required String category,
                required String data,
                required DateTime updatedAt,
              }) => JournalEntriesCompanion.insert(
                id: id,
                cloudId: cloudId,
                tankId: tankId,
                date: date,
                category: category,
                data: data,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $JournalEntriesTable,
      JournalEntry,
      $$JournalEntriesTableFilterComposer,
      $$JournalEntriesTableOrderingComposer,
      $$JournalEntriesTableAnnotationComposer,
      $$JournalEntriesTableCreateCompanionBuilder,
      $$JournalEntriesTableUpdateCompanionBuilder,
      (
        JournalEntry,
        BaseReferences<_$AppDb, $JournalEntriesTable, JournalEntry>,
      ),
      JournalEntry,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionsTableCreateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      Value<String?> tankId,
      required String summary,
      Value<int> messageCount,
      Value<DateTime> createdAt,
    });
typedef $$ChatSessionsTableUpdateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      Value<String?> tankId,
      Value<String> summary,
      Value<int> messageCount,
      Value<DateTime> createdAt,
    });

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDb, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDb, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tankId => $composableBuilder(
    column: $table.tankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDb, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tankId =>
      $composableBuilder(column: $table.tankId, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ChatSessionsTable,
          ChatSession,
          $$ChatSessionsTableFilterComposer,
          $$ChatSessionsTableOrderingComposer,
          $$ChatSessionsTableAnnotationComposer,
          $$ChatSessionsTableCreateCompanionBuilder,
          $$ChatSessionsTableUpdateCompanionBuilder,
          (
            ChatSession,
            BaseReferences<_$AppDb, $ChatSessionsTable, ChatSession>,
          ),
          ChatSession,
          PrefetchHooks Function()
        > {
  $$ChatSessionsTableTableManager(_$AppDb db, $ChatSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> tankId = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ChatSessionsCompanion(
                id: id,
                tankId: tankId,
                summary: summary,
                messageCount: messageCount,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> tankId = const Value.absent(),
                required String summary,
                Value<int> messageCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ChatSessionsCompanion.insert(
                id: id,
                tankId: tankId,
                summary: summary,
                messageCount: messageCount,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ChatSessionsTable,
      ChatSession,
      $$ChatSessionsTableFilterComposer,
      $$ChatSessionsTableOrderingComposer,
      $$ChatSessionsTableAnnotationComposer,
      $$ChatSessionsTableCreateCompanionBuilder,
      $$ChatSessionsTableUpdateCompanionBuilder,
      (ChatSession, BaseReferences<_$AppDb, $ChatSessionsTable, ChatSession>),
      ChatSession,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$TanksTableTableManager get tanks =>
      $$TanksTableTableManager(_db, _db.tanks);
  $$InhabitantsTableTableManager get inhabitants =>
      $$InhabitantsTableTableManager(_db, _db.inhabitants);
  $$PlantsTableTableManager get plants =>
      $$PlantsTableTableManager(_db, _db.plants);
  $$LogsTableTableManager get logs => $$LogsTableTableManager(_db, _db.logs);
  $$TankPhotosTableTableManager get tankPhotos =>
      $$TankPhotosTableTableManager(_db, _db.tankPhotos);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(_db, _db.journalEntries);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
}
