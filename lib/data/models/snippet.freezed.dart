// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'snippet.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Snippet {

 String get id; String get name; String get body; SnippetScope get scope; String? get hostId; SnippetRunMode get defaultRunMode; int get sortOrder; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Snippet
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnippetCopyWith<Snippet> get copyWith => _$SnippetCopyWithImpl<Snippet>(this as Snippet, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Snippet&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.body, body) || other.body == body)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.defaultRunMode, defaultRunMode) || other.defaultRunMode == defaultRunMode)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,body,scope,hostId,defaultRunMode,sortOrder,createdAt,updatedAt);

@override
String toString() {
  return 'Snippet(id: $id, name: $name, body: $body, scope: $scope, hostId: $hostId, defaultRunMode: $defaultRunMode, sortOrder: $sortOrder, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SnippetCopyWith<$Res>  {
  factory $SnippetCopyWith(Snippet value, $Res Function(Snippet) _then) = _$SnippetCopyWithImpl;
@useResult
$Res call({
 String id, String name, String body, SnippetScope scope, String? hostId, SnippetRunMode defaultRunMode, int sortOrder, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$SnippetCopyWithImpl<$Res>
    implements $SnippetCopyWith<$Res> {
  _$SnippetCopyWithImpl(this._self, this._then);

  final Snippet _self;
  final $Res Function(Snippet) _then;

/// Create a copy of Snippet
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? body = null,Object? scope = null,Object? hostId = freezed,Object? defaultRunMode = null,Object? sortOrder = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as SnippetScope,hostId: freezed == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as String?,defaultRunMode: null == defaultRunMode ? _self.defaultRunMode : defaultRunMode // ignore: cast_nullable_to_non_nullable
as SnippetRunMode,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Snippet].
extension SnippetPatterns on Snippet {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Snippet value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Snippet() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Snippet value)  $default,){
final _that = this;
switch (_that) {
case _Snippet():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Snippet value)?  $default,){
final _that = this;
switch (_that) {
case _Snippet() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String body,  SnippetScope scope,  String? hostId,  SnippetRunMode defaultRunMode,  int sortOrder,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Snippet() when $default != null:
return $default(_that.id,_that.name,_that.body,_that.scope,_that.hostId,_that.defaultRunMode,_that.sortOrder,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String body,  SnippetScope scope,  String? hostId,  SnippetRunMode defaultRunMode,  int sortOrder,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Snippet():
return $default(_that.id,_that.name,_that.body,_that.scope,_that.hostId,_that.defaultRunMode,_that.sortOrder,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String body,  SnippetScope scope,  String? hostId,  SnippetRunMode defaultRunMode,  int sortOrder,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Snippet() when $default != null:
return $default(_that.id,_that.name,_that.body,_that.scope,_that.hostId,_that.defaultRunMode,_that.sortOrder,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Snippet implements Snippet {
  const _Snippet({required this.id, required this.name, required this.body, this.scope = SnippetScope.global, this.hostId, this.defaultRunMode = SnippetRunMode.paste, this.sortOrder = 0, required this.createdAt, required this.updatedAt});
  

@override final  String id;
@override final  String name;
@override final  String body;
@override@JsonKey() final  SnippetScope scope;
@override final  String? hostId;
@override@JsonKey() final  SnippetRunMode defaultRunMode;
@override@JsonKey() final  int sortOrder;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Snippet
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SnippetCopyWith<_Snippet> get copyWith => __$SnippetCopyWithImpl<_Snippet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Snippet&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.body, body) || other.body == body)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.defaultRunMode, defaultRunMode) || other.defaultRunMode == defaultRunMode)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,body,scope,hostId,defaultRunMode,sortOrder,createdAt,updatedAt);

@override
String toString() {
  return 'Snippet(id: $id, name: $name, body: $body, scope: $scope, hostId: $hostId, defaultRunMode: $defaultRunMode, sortOrder: $sortOrder, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SnippetCopyWith<$Res> implements $SnippetCopyWith<$Res> {
  factory _$SnippetCopyWith(_Snippet value, $Res Function(_Snippet) _then) = __$SnippetCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String body, SnippetScope scope, String? hostId, SnippetRunMode defaultRunMode, int sortOrder, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$SnippetCopyWithImpl<$Res>
    implements _$SnippetCopyWith<$Res> {
  __$SnippetCopyWithImpl(this._self, this._then);

  final _Snippet _self;
  final $Res Function(_Snippet) _then;

/// Create a copy of Snippet
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? body = null,Object? scope = null,Object? hostId = freezed,Object? defaultRunMode = null,Object? sortOrder = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Snippet(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as SnippetScope,hostId: freezed == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as String?,defaultRunMode: null == defaultRunMode ? _self.defaultRunMode : defaultRunMode // ignore: cast_nullable_to_non_nullable
as SnippetRunMode,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
