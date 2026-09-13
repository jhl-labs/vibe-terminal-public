// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'host.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Host {

 String get id; String get alias; String get hostname; int get port; String get username; HostConnectionType get connectionType; HostAuthType get authType; LocalShellType get localShellType; String? get workingDirectory; String? get credentialRef; String? get jumpHostId; String? get kubernetesContext; String? get kubernetesNamespace; String? get kubernetesResource; int get kubernetesSshPort; String? get kubernetesUsername; HostAuthType get kubernetesAuthType; String? get kubernetesCredentialRef; String? get transportHostname; int? get transportPort; RemoteSessionPersistence get remoteSessionPersistence;/// 공개키 인증에 사용한 키를 원격 세션의 SSH agent 요청에도 제공한다.
/// 원격 프로세스에 서명 권한을 위임하는 민감 기능이므로 기본값은 꺼져 있다.
 bool get agentForwarding; bool get x11Forwarding; String? get startupScript; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Host
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HostCopyWith<Host> get copyWith => _$HostCopyWithImpl<Host>(this as Host, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Host&&(identical(other.id, id) || other.id == id)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.hostname, hostname) || other.hostname == hostname)&&(identical(other.port, port) || other.port == port)&&(identical(other.username, username) || other.username == username)&&(identical(other.connectionType, connectionType) || other.connectionType == connectionType)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.localShellType, localShellType) || other.localShellType == localShellType)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.credentialRef, credentialRef) || other.credentialRef == credentialRef)&&(identical(other.jumpHostId, jumpHostId) || other.jumpHostId == jumpHostId)&&(identical(other.kubernetesContext, kubernetesContext) || other.kubernetesContext == kubernetesContext)&&(identical(other.kubernetesNamespace, kubernetesNamespace) || other.kubernetesNamespace == kubernetesNamespace)&&(identical(other.kubernetesResource, kubernetesResource) || other.kubernetesResource == kubernetesResource)&&(identical(other.kubernetesSshPort, kubernetesSshPort) || other.kubernetesSshPort == kubernetesSshPort)&&(identical(other.kubernetesUsername, kubernetesUsername) || other.kubernetesUsername == kubernetesUsername)&&(identical(other.kubernetesAuthType, kubernetesAuthType) || other.kubernetesAuthType == kubernetesAuthType)&&(identical(other.kubernetesCredentialRef, kubernetesCredentialRef) || other.kubernetesCredentialRef == kubernetesCredentialRef)&&(identical(other.transportHostname, transportHostname) || other.transportHostname == transportHostname)&&(identical(other.transportPort, transportPort) || other.transportPort == transportPort)&&(identical(other.remoteSessionPersistence, remoteSessionPersistence) || other.remoteSessionPersistence == remoteSessionPersistence)&&(identical(other.agentForwarding, agentForwarding) || other.agentForwarding == agentForwarding)&&(identical(other.x11Forwarding, x11Forwarding) || other.x11Forwarding == x11Forwarding)&&(identical(other.startupScript, startupScript) || other.startupScript == startupScript)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,alias,hostname,port,username,connectionType,authType,localShellType,workingDirectory,credentialRef,jumpHostId,kubernetesContext,kubernetesNamespace,kubernetesResource,kubernetesSshPort,kubernetesUsername,kubernetesAuthType,kubernetesCredentialRef,transportHostname,transportPort,remoteSessionPersistence,agentForwarding,x11Forwarding,startupScript,createdAt,updatedAt]);

@override
String toString() {
  return 'Host(id: $id, alias: $alias, hostname: $hostname, port: $port, username: $username, connectionType: $connectionType, authType: $authType, localShellType: $localShellType, workingDirectory: $workingDirectory, credentialRef: $credentialRef, jumpHostId: $jumpHostId, kubernetesContext: $kubernetesContext, kubernetesNamespace: $kubernetesNamespace, kubernetesResource: $kubernetesResource, kubernetesSshPort: $kubernetesSshPort, kubernetesUsername: $kubernetesUsername, kubernetesAuthType: $kubernetesAuthType, kubernetesCredentialRef: $kubernetesCredentialRef, transportHostname: $transportHostname, transportPort: $transportPort, remoteSessionPersistence: $remoteSessionPersistence, agentForwarding: $agentForwarding, x11Forwarding: $x11Forwarding, startupScript: $startupScript, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $HostCopyWith<$Res>  {
  factory $HostCopyWith(Host value, $Res Function(Host) _then) = _$HostCopyWithImpl;
@useResult
$Res call({
 String id, String alias, String hostname, int port, String username, HostConnectionType connectionType, HostAuthType authType, LocalShellType localShellType, String? workingDirectory, String? credentialRef, String? jumpHostId, String? kubernetesContext, String? kubernetesNamespace, String? kubernetesResource, int kubernetesSshPort, String? kubernetesUsername, HostAuthType kubernetesAuthType, String? kubernetesCredentialRef, String? transportHostname, int? transportPort, RemoteSessionPersistence remoteSessionPersistence, bool agentForwarding, bool x11Forwarding, String? startupScript, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$HostCopyWithImpl<$Res>
    implements $HostCopyWith<$Res> {
  _$HostCopyWithImpl(this._self, this._then);

  final Host _self;
  final $Res Function(Host) _then;

/// Create a copy of Host
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? alias = null,Object? hostname = null,Object? port = null,Object? username = null,Object? connectionType = null,Object? authType = null,Object? localShellType = null,Object? workingDirectory = freezed,Object? credentialRef = freezed,Object? jumpHostId = freezed,Object? kubernetesContext = freezed,Object? kubernetesNamespace = freezed,Object? kubernetesResource = freezed,Object? kubernetesSshPort = null,Object? kubernetesUsername = freezed,Object? kubernetesAuthType = null,Object? kubernetesCredentialRef = freezed,Object? transportHostname = freezed,Object? transportPort = freezed,Object? remoteSessionPersistence = null,Object? agentForwarding = null,Object? x11Forwarding = null,Object? startupScript = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,hostname: null == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as HostConnectionType,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as HostAuthType,localShellType: null == localShellType ? _self.localShellType : localShellType // ignore: cast_nullable_to_non_nullable
as LocalShellType,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,credentialRef: freezed == credentialRef ? _self.credentialRef : credentialRef // ignore: cast_nullable_to_non_nullable
as String?,jumpHostId: freezed == jumpHostId ? _self.jumpHostId : jumpHostId // ignore: cast_nullable_to_non_nullable
as String?,kubernetesContext: freezed == kubernetesContext ? _self.kubernetesContext : kubernetesContext // ignore: cast_nullable_to_non_nullable
as String?,kubernetesNamespace: freezed == kubernetesNamespace ? _self.kubernetesNamespace : kubernetesNamespace // ignore: cast_nullable_to_non_nullable
as String?,kubernetesResource: freezed == kubernetesResource ? _self.kubernetesResource : kubernetesResource // ignore: cast_nullable_to_non_nullable
as String?,kubernetesSshPort: null == kubernetesSshPort ? _self.kubernetesSshPort : kubernetesSshPort // ignore: cast_nullable_to_non_nullable
as int,kubernetesUsername: freezed == kubernetesUsername ? _self.kubernetesUsername : kubernetesUsername // ignore: cast_nullable_to_non_nullable
as String?,kubernetesAuthType: null == kubernetesAuthType ? _self.kubernetesAuthType : kubernetesAuthType // ignore: cast_nullable_to_non_nullable
as HostAuthType,kubernetesCredentialRef: freezed == kubernetesCredentialRef ? _self.kubernetesCredentialRef : kubernetesCredentialRef // ignore: cast_nullable_to_non_nullable
as String?,transportHostname: freezed == transportHostname ? _self.transportHostname : transportHostname // ignore: cast_nullable_to_non_nullable
as String?,transportPort: freezed == transportPort ? _self.transportPort : transportPort // ignore: cast_nullable_to_non_nullable
as int?,remoteSessionPersistence: null == remoteSessionPersistence ? _self.remoteSessionPersistence : remoteSessionPersistence // ignore: cast_nullable_to_non_nullable
as RemoteSessionPersistence,agentForwarding: null == agentForwarding ? _self.agentForwarding : agentForwarding // ignore: cast_nullable_to_non_nullable
as bool,x11Forwarding: null == x11Forwarding ? _self.x11Forwarding : x11Forwarding // ignore: cast_nullable_to_non_nullable
as bool,startupScript: freezed == startupScript ? _self.startupScript : startupScript // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Host].
extension HostPatterns on Host {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Host value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Host() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Host value)  $default,){
final _that = this;
switch (_that) {
case _Host():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Host value)?  $default,){
final _that = this;
switch (_that) {
case _Host() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String alias,  String hostname,  int port,  String username,  HostConnectionType connectionType,  HostAuthType authType,  LocalShellType localShellType,  String? workingDirectory,  String? credentialRef,  String? jumpHostId,  String? kubernetesContext,  String? kubernetesNamespace,  String? kubernetesResource,  int kubernetesSshPort,  String? kubernetesUsername,  HostAuthType kubernetesAuthType,  String? kubernetesCredentialRef,  String? transportHostname,  int? transportPort,  RemoteSessionPersistence remoteSessionPersistence,  bool agentForwarding,  bool x11Forwarding,  String? startupScript,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Host() when $default != null:
return $default(_that.id,_that.alias,_that.hostname,_that.port,_that.username,_that.connectionType,_that.authType,_that.localShellType,_that.workingDirectory,_that.credentialRef,_that.jumpHostId,_that.kubernetesContext,_that.kubernetesNamespace,_that.kubernetesResource,_that.kubernetesSshPort,_that.kubernetesUsername,_that.kubernetesAuthType,_that.kubernetesCredentialRef,_that.transportHostname,_that.transportPort,_that.remoteSessionPersistence,_that.agentForwarding,_that.x11Forwarding,_that.startupScript,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String alias,  String hostname,  int port,  String username,  HostConnectionType connectionType,  HostAuthType authType,  LocalShellType localShellType,  String? workingDirectory,  String? credentialRef,  String? jumpHostId,  String? kubernetesContext,  String? kubernetesNamespace,  String? kubernetesResource,  int kubernetesSshPort,  String? kubernetesUsername,  HostAuthType kubernetesAuthType,  String? kubernetesCredentialRef,  String? transportHostname,  int? transportPort,  RemoteSessionPersistence remoteSessionPersistence,  bool agentForwarding,  bool x11Forwarding,  String? startupScript,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Host():
return $default(_that.id,_that.alias,_that.hostname,_that.port,_that.username,_that.connectionType,_that.authType,_that.localShellType,_that.workingDirectory,_that.credentialRef,_that.jumpHostId,_that.kubernetesContext,_that.kubernetesNamespace,_that.kubernetesResource,_that.kubernetesSshPort,_that.kubernetesUsername,_that.kubernetesAuthType,_that.kubernetesCredentialRef,_that.transportHostname,_that.transportPort,_that.remoteSessionPersistence,_that.agentForwarding,_that.x11Forwarding,_that.startupScript,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String alias,  String hostname,  int port,  String username,  HostConnectionType connectionType,  HostAuthType authType,  LocalShellType localShellType,  String? workingDirectory,  String? credentialRef,  String? jumpHostId,  String? kubernetesContext,  String? kubernetesNamespace,  String? kubernetesResource,  int kubernetesSshPort,  String? kubernetesUsername,  HostAuthType kubernetesAuthType,  String? kubernetesCredentialRef,  String? transportHostname,  int? transportPort,  RemoteSessionPersistence remoteSessionPersistence,  bool agentForwarding,  bool x11Forwarding,  String? startupScript,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Host() when $default != null:
return $default(_that.id,_that.alias,_that.hostname,_that.port,_that.username,_that.connectionType,_that.authType,_that.localShellType,_that.workingDirectory,_that.credentialRef,_that.jumpHostId,_that.kubernetesContext,_that.kubernetesNamespace,_that.kubernetesResource,_that.kubernetesSshPort,_that.kubernetesUsername,_that.kubernetesAuthType,_that.kubernetesCredentialRef,_that.transportHostname,_that.transportPort,_that.remoteSessionPersistence,_that.agentForwarding,_that.x11Forwarding,_that.startupScript,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Host extends Host {
  const _Host({required this.id, required this.alias, required this.hostname, this.port = 22, required this.username, this.connectionType = HostConnectionType.ssh, this.authType = HostAuthType.password, this.localShellType = LocalShellType.powershell, this.workingDirectory, this.credentialRef, this.jumpHostId, this.kubernetesContext, this.kubernetesNamespace, this.kubernetesResource, this.kubernetesSshPort = 22, this.kubernetesUsername, this.kubernetesAuthType = HostAuthType.password, this.kubernetesCredentialRef, this.transportHostname, this.transportPort, this.remoteSessionPersistence = RemoteSessionPersistence.none, this.agentForwarding = false, this.x11Forwarding = false, this.startupScript, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String alias;
@override final  String hostname;
@override@JsonKey() final  int port;
@override final  String username;
@override@JsonKey() final  HostConnectionType connectionType;
@override@JsonKey() final  HostAuthType authType;
@override@JsonKey() final  LocalShellType localShellType;
@override final  String? workingDirectory;
@override final  String? credentialRef;
@override final  String? jumpHostId;
@override final  String? kubernetesContext;
@override final  String? kubernetesNamespace;
@override final  String? kubernetesResource;
@override@JsonKey() final  int kubernetesSshPort;
@override final  String? kubernetesUsername;
@override@JsonKey() final  HostAuthType kubernetesAuthType;
@override final  String? kubernetesCredentialRef;
@override final  String? transportHostname;
@override final  int? transportPort;
@override@JsonKey() final  RemoteSessionPersistence remoteSessionPersistence;
/// 공개키 인증에 사용한 키를 원격 세션의 SSH agent 요청에도 제공한다.
/// 원격 프로세스에 서명 권한을 위임하는 민감 기능이므로 기본값은 꺼져 있다.
@override@JsonKey() final  bool agentForwarding;
@override@JsonKey() final  bool x11Forwarding;
@override final  String? startupScript;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Host
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HostCopyWith<_Host> get copyWith => __$HostCopyWithImpl<_Host>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Host&&(identical(other.id, id) || other.id == id)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.hostname, hostname) || other.hostname == hostname)&&(identical(other.port, port) || other.port == port)&&(identical(other.username, username) || other.username == username)&&(identical(other.connectionType, connectionType) || other.connectionType == connectionType)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.localShellType, localShellType) || other.localShellType == localShellType)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.credentialRef, credentialRef) || other.credentialRef == credentialRef)&&(identical(other.jumpHostId, jumpHostId) || other.jumpHostId == jumpHostId)&&(identical(other.kubernetesContext, kubernetesContext) || other.kubernetesContext == kubernetesContext)&&(identical(other.kubernetesNamespace, kubernetesNamespace) || other.kubernetesNamespace == kubernetesNamespace)&&(identical(other.kubernetesResource, kubernetesResource) || other.kubernetesResource == kubernetesResource)&&(identical(other.kubernetesSshPort, kubernetesSshPort) || other.kubernetesSshPort == kubernetesSshPort)&&(identical(other.kubernetesUsername, kubernetesUsername) || other.kubernetesUsername == kubernetesUsername)&&(identical(other.kubernetesAuthType, kubernetesAuthType) || other.kubernetesAuthType == kubernetesAuthType)&&(identical(other.kubernetesCredentialRef, kubernetesCredentialRef) || other.kubernetesCredentialRef == kubernetesCredentialRef)&&(identical(other.transportHostname, transportHostname) || other.transportHostname == transportHostname)&&(identical(other.transportPort, transportPort) || other.transportPort == transportPort)&&(identical(other.remoteSessionPersistence, remoteSessionPersistence) || other.remoteSessionPersistence == remoteSessionPersistence)&&(identical(other.agentForwarding, agentForwarding) || other.agentForwarding == agentForwarding)&&(identical(other.x11Forwarding, x11Forwarding) || other.x11Forwarding == x11Forwarding)&&(identical(other.startupScript, startupScript) || other.startupScript == startupScript)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,alias,hostname,port,username,connectionType,authType,localShellType,workingDirectory,credentialRef,jumpHostId,kubernetesContext,kubernetesNamespace,kubernetesResource,kubernetesSshPort,kubernetesUsername,kubernetesAuthType,kubernetesCredentialRef,transportHostname,transportPort,remoteSessionPersistence,agentForwarding,x11Forwarding,startupScript,createdAt,updatedAt]);

@override
String toString() {
  return 'Host(id: $id, alias: $alias, hostname: $hostname, port: $port, username: $username, connectionType: $connectionType, authType: $authType, localShellType: $localShellType, workingDirectory: $workingDirectory, credentialRef: $credentialRef, jumpHostId: $jumpHostId, kubernetesContext: $kubernetesContext, kubernetesNamespace: $kubernetesNamespace, kubernetesResource: $kubernetesResource, kubernetesSshPort: $kubernetesSshPort, kubernetesUsername: $kubernetesUsername, kubernetesAuthType: $kubernetesAuthType, kubernetesCredentialRef: $kubernetesCredentialRef, transportHostname: $transportHostname, transportPort: $transportPort, remoteSessionPersistence: $remoteSessionPersistence, agentForwarding: $agentForwarding, x11Forwarding: $x11Forwarding, startupScript: $startupScript, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$HostCopyWith<$Res> implements $HostCopyWith<$Res> {
  factory _$HostCopyWith(_Host value, $Res Function(_Host) _then) = __$HostCopyWithImpl;
@override @useResult
$Res call({
 String id, String alias, String hostname, int port, String username, HostConnectionType connectionType, HostAuthType authType, LocalShellType localShellType, String? workingDirectory, String? credentialRef, String? jumpHostId, String? kubernetesContext, String? kubernetesNamespace, String? kubernetesResource, int kubernetesSshPort, String? kubernetesUsername, HostAuthType kubernetesAuthType, String? kubernetesCredentialRef, String? transportHostname, int? transportPort, RemoteSessionPersistence remoteSessionPersistence, bool agentForwarding, bool x11Forwarding, String? startupScript, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$HostCopyWithImpl<$Res>
    implements _$HostCopyWith<$Res> {
  __$HostCopyWithImpl(this._self, this._then);

  final _Host _self;
  final $Res Function(_Host) _then;

/// Create a copy of Host
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? alias = null,Object? hostname = null,Object? port = null,Object? username = null,Object? connectionType = null,Object? authType = null,Object? localShellType = null,Object? workingDirectory = freezed,Object? credentialRef = freezed,Object? jumpHostId = freezed,Object? kubernetesContext = freezed,Object? kubernetesNamespace = freezed,Object? kubernetesResource = freezed,Object? kubernetesSshPort = null,Object? kubernetesUsername = freezed,Object? kubernetesAuthType = null,Object? kubernetesCredentialRef = freezed,Object? transportHostname = freezed,Object? transportPort = freezed,Object? remoteSessionPersistence = null,Object? agentForwarding = null,Object? x11Forwarding = null,Object? startupScript = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Host(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,hostname: null == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as HostConnectionType,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as HostAuthType,localShellType: null == localShellType ? _self.localShellType : localShellType // ignore: cast_nullable_to_non_nullable
as LocalShellType,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,credentialRef: freezed == credentialRef ? _self.credentialRef : credentialRef // ignore: cast_nullable_to_non_nullable
as String?,jumpHostId: freezed == jumpHostId ? _self.jumpHostId : jumpHostId // ignore: cast_nullable_to_non_nullable
as String?,kubernetesContext: freezed == kubernetesContext ? _self.kubernetesContext : kubernetesContext // ignore: cast_nullable_to_non_nullable
as String?,kubernetesNamespace: freezed == kubernetesNamespace ? _self.kubernetesNamespace : kubernetesNamespace // ignore: cast_nullable_to_non_nullable
as String?,kubernetesResource: freezed == kubernetesResource ? _self.kubernetesResource : kubernetesResource // ignore: cast_nullable_to_non_nullable
as String?,kubernetesSshPort: null == kubernetesSshPort ? _self.kubernetesSshPort : kubernetesSshPort // ignore: cast_nullable_to_non_nullable
as int,kubernetesUsername: freezed == kubernetesUsername ? _self.kubernetesUsername : kubernetesUsername // ignore: cast_nullable_to_non_nullable
as String?,kubernetesAuthType: null == kubernetesAuthType ? _self.kubernetesAuthType : kubernetesAuthType // ignore: cast_nullable_to_non_nullable
as HostAuthType,kubernetesCredentialRef: freezed == kubernetesCredentialRef ? _self.kubernetesCredentialRef : kubernetesCredentialRef // ignore: cast_nullable_to_non_nullable
as String?,transportHostname: freezed == transportHostname ? _self.transportHostname : transportHostname // ignore: cast_nullable_to_non_nullable
as String?,transportPort: freezed == transportPort ? _self.transportPort : transportPort // ignore: cast_nullable_to_non_nullable
as int?,remoteSessionPersistence: null == remoteSessionPersistence ? _self.remoteSessionPersistence : remoteSessionPersistence // ignore: cast_nullable_to_non_nullable
as RemoteSessionPersistence,agentForwarding: null == agentForwarding ? _self.agentForwarding : agentForwarding // ignore: cast_nullable_to_non_nullable
as bool,x11Forwarding: null == x11Forwarding ? _self.x11Forwarding : x11Forwarding // ignore: cast_nullable_to_non_nullable
as bool,startupScript: freezed == startupScript ? _self.startupScript : startupScript // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
