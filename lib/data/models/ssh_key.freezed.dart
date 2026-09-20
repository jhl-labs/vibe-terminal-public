// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh_key.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshKey {

 String get id; String get name; String get keyType; String get publicKey; String get fingerprint; String get secretRef; SshKeySource get source; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of SshKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshKeyCopyWith<SshKey> get copyWith => _$SshKeyCopyWithImpl<SshKey>(this as SshKey, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshKey&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.keyType, keyType) || other.keyType == keyType)&&(identical(other.publicKey, publicKey) || other.publicKey == publicKey)&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.secretRef, secretRef) || other.secretRef == secretRef)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,keyType,publicKey,fingerprint,secretRef,source,createdAt,updatedAt);

@override
String toString() {
  return 'SshKey(id: $id, name: $name, keyType: $keyType, publicKey: $publicKey, fingerprint: $fingerprint, secretRef: $secretRef, source: $source, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SshKeyCopyWith<$Res>  {
  factory $SshKeyCopyWith(SshKey value, $Res Function(SshKey) _then) = _$SshKeyCopyWithImpl;
@useResult
$Res call({
 String id, String name, String keyType, String publicKey, String fingerprint, String secretRef, SshKeySource source, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$SshKeyCopyWithImpl<$Res>
    implements $SshKeyCopyWith<$Res> {
  _$SshKeyCopyWithImpl(this._self, this._then);

  final SshKey _self;
  final $Res Function(SshKey) _then;

/// Create a copy of SshKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? keyType = null,Object? publicKey = null,Object? fingerprint = null,Object? secretRef = null,Object? source = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,publicKey: null == publicKey ? _self.publicKey : publicKey // ignore: cast_nullable_to_non_nullable
as String,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,secretRef: null == secretRef ? _self.secretRef : secretRef // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SshKeySource,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SshKey].
extension SshKeyPatterns on SshKey {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshKey() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshKey value)  $default,){
final _that = this;
switch (_that) {
case _SshKey():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshKey value)?  $default,){
final _that = this;
switch (_that) {
case _SshKey() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String keyType,  String publicKey,  String fingerprint,  String secretRef,  SshKeySource source,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshKey() when $default != null:
return $default(_that.id,_that.name,_that.keyType,_that.publicKey,_that.fingerprint,_that.secretRef,_that.source,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String keyType,  String publicKey,  String fingerprint,  String secretRef,  SshKeySource source,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _SshKey():
return $default(_that.id,_that.name,_that.keyType,_that.publicKey,_that.fingerprint,_that.secretRef,_that.source,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String keyType,  String publicKey,  String fingerprint,  String secretRef,  SshKeySource source,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _SshKey() when $default != null:
return $default(_that.id,_that.name,_that.keyType,_that.publicKey,_that.fingerprint,_that.secretRef,_that.source,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _SshKey extends SshKey {
  const _SshKey({required this.id, required this.name, required this.keyType, required this.publicKey, required this.fingerprint, required this.secretRef, this.source = SshKeySource.imported, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String keyType;
@override final  String publicKey;
@override final  String fingerprint;
@override final  String secretRef;
@override@JsonKey() final  SshKeySource source;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of SshKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshKeyCopyWith<_SshKey> get copyWith => __$SshKeyCopyWithImpl<_SshKey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshKey&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.keyType, keyType) || other.keyType == keyType)&&(identical(other.publicKey, publicKey) || other.publicKey == publicKey)&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.secretRef, secretRef) || other.secretRef == secretRef)&&(identical(other.source, source) || other.source == source)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,keyType,publicKey,fingerprint,secretRef,source,createdAt,updatedAt);

@override
String toString() {
  return 'SshKey(id: $id, name: $name, keyType: $keyType, publicKey: $publicKey, fingerprint: $fingerprint, secretRef: $secretRef, source: $source, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SshKeyCopyWith<$Res> implements $SshKeyCopyWith<$Res> {
  factory _$SshKeyCopyWith(_SshKey value, $Res Function(_SshKey) _then) = __$SshKeyCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String keyType, String publicKey, String fingerprint, String secretRef, SshKeySource source, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$SshKeyCopyWithImpl<$Res>
    implements _$SshKeyCopyWith<$Res> {
  __$SshKeyCopyWithImpl(this._self, this._then);

  final _SshKey _self;
  final $Res Function(_SshKey) _then;

/// Create a copy of SshKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? keyType = null,Object? publicKey = null,Object? fingerprint = null,Object? secretRef = null,Object? source = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_SshKey(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,keyType: null == keyType ? _self.keyType : keyType // ignore: cast_nullable_to_non_nullable
as String,publicKey: null == publicKey ? _self.publicKey : publicKey // ignore: cast_nullable_to_non_nullable
as String,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,secretRef: null == secretRef ? _self.secretRef : secretRef // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SshKeySource,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
