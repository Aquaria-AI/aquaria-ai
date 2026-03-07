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
  final String tankId;
  final String rawText;
  final String? parsedJson;
  final DateTime createdAt;
  const Log({
    required this.id,
    required this.tankId,
    required this.rawText,
    this.parsedJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
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
      'tankId': serializer.toJson<String>(tankId),
      'rawText': serializer.toJson<String>(rawText),
      'parsedJson': serializer.toJson<String?>(parsedJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Log copyWith({
    int? id,
    String? tankId,
    String? rawText,
    Value<String?> parsedJson = const Value.absent(),
    DateTime? createdAt,
  }) => Log(
    id: id ?? this.id,
    tankId: tankId ?? this.tankId,
    rawText: rawText ?? this.rawText,
    parsedJson: parsedJson.present ? parsedJson.value : this.parsedJson,
    createdAt: createdAt ?? this.createdAt,
  );
  Log copyWithCompanion(LogsCompanion data) {
    return Log(
      id: data.id.present ? data.id.value : this.id,
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
          ..write('tankId: $tankId, ')
          ..write('rawText: $rawText, ')
          ..write('parsedJson: $parsedJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tankId, rawText, parsedJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Log &&
          other.id == this.id &&
          other.tankId == this.tankId &&
          other.rawText == this.rawText &&
          other.parsedJson == this.parsedJson &&
          other.createdAt == this.createdAt);
}

class LogsCompanion extends UpdateCompanion<Log> {
  final Value<int> id;
  final Value<String> tankId;
  final Value<String> rawText;
  final Value<String?> parsedJson;
  final Value<DateTime> createdAt;
  const LogsCompanion({
    this.id = const Value.absent(),
    this.tankId = const Value.absent(),
    this.rawText = const Value.absent(),
    this.parsedJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  LogsCompanion.insert({
    this.id = const Value.absent(),
    required String tankId,
    required String rawText,
    this.parsedJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : tankId = Value(tankId),
       rawText = Value(rawText);
  static Insertable<Log> custom({
    Expression<int>? id,
    Expression<String>? tankId,
    Expression<String>? rawText,
    Expression<String>? parsedJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tankId != null) 'tank_id': tankId,
      if (rawText != null) 'raw_text': rawText,
      if (parsedJson != null) 'parsed_json': parsedJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  LogsCompanion copyWith({
    Value<int>? id,
    Value<String>? tankId,
    Value<String>? rawText,
    Value<String?>? parsedJson,
    Value<DateTime>? createdAt,
  }) {
    return LogsCompanion(
      id: id ?? this.id,
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
          ..write('tankId: $tankId, ')
          ..write('rawText: $rawText, ')
          ..write('parsedJson: $parsedJson, ')
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tanks,
    inhabitants,
    plants,
    logs,
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
      required String tankId,
      required String rawText,
      Value<String?> parsedJson,
      Value<DateTime> createdAt,
    });
typedef $$LogsTableUpdateCompanionBuilder =
    LogsCompanion Function({
      Value<int> id,
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
                Value<String> tankId = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String?> parsedJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => LogsCompanion(
                id: id,
                tankId: tankId,
                rawText: rawText,
                parsedJson: parsedJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tankId,
                required String rawText,
                Value<String?> parsedJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => LogsCompanion.insert(
                id: id,
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
}
