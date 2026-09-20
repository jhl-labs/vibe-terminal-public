// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Identity {

 String get id; String get label; String get username; HostAuthType get authType; String? get keyId; String? get secretRef; bool get hostScoped; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Identity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdentityCopyWith<Identity> get copyWith => _$IdentityCopyWithImpl<Identity>(this as Identity, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Identity&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.username, username) || other.username == username)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.keyId, keyId) || other.keyId == keyId)&&(identical(other.secretRef, secretRef) || other.secretRef == secretRef)&&(identical(other.hostScoped, hostScoped) || other.hostScoped == hostScoped)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,label,username,authType,keyId,secretRef,hostScoped,createdAt,updatedAt);

@override
String toString() {
  return 'Identity(id: $id, label: $label, username: $username, authType: $authType, keyId: $keyId, secretRef: $secretRef, hostScoped: $hostScoped, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $IdentityCopyWith<$Res>  {
  factory $IdentityCopyWith(Identity value, $Res Function(Identity) _then) = _$IdentityCopyWithImpl;
@useResult
$Res call({
 String id, String label, String username, HostAuthType authType, String? keyId, String? secretRef, bool hostScoped, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$IdentityCopyWithImpl<$Res>
    implements $IdentityCopyWith<$Res> {
  _$IdentityCopyWithImpl(this._self, this._then);

  final Identity _self;
  final $Res Function(Identity) _then;

/// Create a copy of Identity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? username = null,Object? authType = null,Object? keyId = freezed,Object? secretRef = freezed,Object? hostScoped = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as HostAuthType,keyId: freezed == keyId ? _self.keyId : keyId // ignore: cast_nullable_to_non_nullable
as String?,secretRef: freezed == secretRef ? _self.secretRef : secretRef // ignore: cast_nullable_to_non_nullable
as String?,hostScoped: null == hostScoped ? _self.hostScoped : hostScoped // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Identity].
extension IdentityPatterns on Identity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Identity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Identity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Identity value)  $default,){
final _that = this;
switch (_that) {
case _Identity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Identity value)?  $default,){
final _that = this;
switch (_that) {
case _Identity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String username,  HostAuthType authType,  String? keyId,  String? secretRef,  bool hostScoped,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Identity() when $default != null:
return $default(_that.id,_that.label,_that.username,_that.authType,_that.keyId,_that.secretRef,_that.hostScoped,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String username,  HostAuthType authType,  String? keyId,  String? secretRef,  bool hostScoped,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Identity():
return $default(_that.id,_that.label,_that.username,_that.authType,_that.keyId,_that.secretRef,_that.hostScoped,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String username,  HostAuthType authType,  String? keyId,  String? secretRef,  bool hostScoped,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Identity() when $default != null:
return $default(_that.id,_that.label,_that.username,_that.authType,_that.keyId,_that.secretRef,_that.hostScoped,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Identity extends Identity {
  const _Identity({required this.id, required this.label, required this.username, this.authType = HostAuthType.password, this.keyId, this.secretRef, this.hostScoped = false, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String label;
@override final  String username;
@override@JsonKey() final  HostAuthType authType;
@override final  String? keyId;
@override final  String? secretRef;
@override@JsonKey() final  bool hostScoped;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Identity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IdentityCopyWith<_Identity> get copyWith => __$IdentityCopyWithImpl<_Identity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Identity&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.username, username) || other.username == username)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.keyId, keyId) || other.keyId == keyId)&&(identical(other.secretRef, secretRef) || other.secretRef == secretRef)&&(identical(other.hostScoped, hostScoped) || other.hostScoped == hostScoped)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,label,username,authType,keyId,secretRef,hostScoped,createdAt,updatedAt);

@override
String toString() {
  return 'Identity(id: $id, label: $label, username: $username, authType: $authType, keyId: $keyId, secretRef: $secretRef, hostScoped: $hostScoped, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$IdentityCopyWith<$Res> implements $IdentityCopyWith<$Res> {
  factory _$IdentityCopyWith(_Identity value, $Res Function(_Identity) _then) = __$IdentityCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String username, HostAuthType authType, String? keyId, String? secretRef, bool hostScoped, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$IdentityCopyWithImpl<$Res>
    implements _$IdentityCopyWith<$Res> {
  __$IdentityCopyWithImpl(this._self, this._then);

  final _Identity _self;
  final $Res Function(_Identity) _then;

/// Create a copy of Identity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? username = null,Object? authType = null,Object? keyId = freezed,Object? secretRef = freezed,Object? hostScoped = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Identity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as HostAuthType,keyId: freezed == keyId ? _self.keyId : keyId // ignore: cast_nullable_to_non_nullable
as String?,secretRef: freezed == secretRef ? _self.secretRef : secretRef // ignore: cast_nullable_to_non_nullable
as String?,hostScoped: null == hostScoped ? _self.hostScoped : hostScoped // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
