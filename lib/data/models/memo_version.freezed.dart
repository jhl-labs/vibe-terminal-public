// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memo_version.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MemoVersion {

 int get id; String get hostId; String get body; DateTime get createdAt; String? get label;
/// Create a copy of MemoVersion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoVersionCopyWith<MemoVersion> get copyWith => _$MemoVersionCopyWithImpl<MemoVersion>(this as MemoVersion, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoVersion&&(identical(other.id, id) || other.id == id)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.label, label) || other.label == label));
}


@override
int get hashCode => Object.hash(runtimeType,id,hostId,body,createdAt,label);

@override
String toString() {
  return 'MemoVersion(id: $id, hostId: $hostId, body: $body, createdAt: $createdAt, label: $label)';
}


}

/// @nodoc
abstract mixin class $MemoVersionCopyWith<$Res>  {
  factory $MemoVersionCopyWith(MemoVersion value, $Res Function(MemoVersion) _then) = _$MemoVersionCopyWithImpl;
@useResult
$Res call({
 int id, String hostId, String body, DateTime createdAt, String? label
});




}
/// @nodoc
class _$MemoVersionCopyWithImpl<$Res>
    implements $MemoVersionCopyWith<$Res> {
  _$MemoVersionCopyWithImpl(this._self, this._then);

  final MemoVersion _self;
  final $Res Function(MemoVersion) _then;

/// Create a copy of MemoVersion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? hostId = null,Object? body = null,Object? createdAt = null,Object? label = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MemoVersion].
extension MemoVersionPatterns on MemoVersion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoVersion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoVersion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoVersion value)  $default,){
final _that = this;
switch (_that) {
case _MemoVersion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoVersion value)?  $default,){
final _that = this;
switch (_that) {
case _MemoVersion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String hostId,  String body,  DateTime createdAt,  String? label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoVersion() when $default != null:
return $default(_that.id,_that.hostId,_that.body,_that.createdAt,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String hostId,  String body,  DateTime createdAt,  String? label)  $default,) {final _that = this;
switch (_that) {
case _MemoVersion():
return $default(_that.id,_that.hostId,_that.body,_that.createdAt,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String hostId,  String body,  DateTime createdAt,  String? label)?  $default,) {final _that = this;
switch (_that) {
case _MemoVersion() when $default != null:
return $default(_that.id,_that.hostId,_that.body,_that.createdAt,_that.label);case _:
  return null;

}
}

}

/// @nodoc


class _MemoVersion implements MemoVersion {
  const _MemoVersion({required this.id, required this.hostId, required this.body, required this.createdAt, this.label});
  

@override final  int id;
@override final  String hostId;
@override final  String body;
@override final  DateTime createdAt;
@override final  String? label;

/// Create a copy of MemoVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoVersionCopyWith<_MemoVersion> get copyWith => __$MemoVersionCopyWithImpl<_MemoVersion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoVersion&&(identical(other.id, id) || other.id == id)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.label, label) || other.label == label));
}


@override
int get hashCode => Object.hash(runtimeType,id,hostId,body,createdAt,label);

@override
String toString() {
  return 'MemoVersion(id: $id, hostId: $hostId, body: $body, createdAt: $createdAt, label: $label)';
}


}

/// @nodoc
abstract mixin class _$MemoVersionCopyWith<$Res> implements $MemoVersionCopyWith<$Res> {
  factory _$MemoVersionCopyWith(_MemoVersion value, $Res Function(_MemoVersion) _then) = __$MemoVersionCopyWithImpl;
@override @useResult
$Res call({
 int id, String hostId, String body, DateTime createdAt, String? label
});




}
/// @nodoc
class __$MemoVersionCopyWithImpl<$Res>
    implements _$MemoVersionCopyWith<$Res> {
  __$MemoVersionCopyWithImpl(this._self, this._then);

  final _MemoVersion _self;
  final $Res Function(_MemoVersion) _then;

/// Create a copy of MemoVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? hostId = null,Object? body = null,Object? createdAt = null,Object? label = freezed,}) {
  return _then(_MemoVersion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
