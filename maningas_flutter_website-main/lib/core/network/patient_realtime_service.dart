import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../config/api_config.dart';

typedef RealtimeListener = void Function(dynamic payload);

class PatientRealtimeService {
  PatientRealtimeService._();

  static final PatientRealtimeService instance = PatientRealtimeService._();

  final Map<String, Set<RealtimeListener>> _listeners = {};
  socket_io.Socket? _socket;
  String? _activeToken;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token) {
    if (_socket != null && _activeToken == token) return;

    disconnect();
    _activeToken = token;
    final socket = socket_io.io(ApiConfig.baseUrl, <String, dynamic>{
      'auth': {'token': token},
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'reconnection': true,
    });
    _socket = socket;

    for (final entry in _listeners.entries) {
      if (entry.key != 'realtime:connected') {
        for (final listener in entry.value) {
          socket.on(entry.key, listener);
        }
      }
    }

    socket.onConnect((_) => _notify('realtime:connected', null));
    socket.onConnectError((error) {
      developer.log(
        'Real-time connection unavailable; REST polling will continue.',
        name: 'patient_realtime',
        error: error,
      );
    });
    socket.onError((error) {
      developer.log(
        'Real-time connection error.',
        name: 'patient_realtime',
        error: error,
      );
    });
    socket.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _activeToken = null;
  }

  void Function() listen(String event, RealtimeListener listener) {
    final listeners = _listeners.putIfAbsent(event, () => <RealtimeListener>{});
    listeners.add(listener);
    if (event != 'realtime:connected') _socket?.on(event, listener);
    if (event == 'realtime:connected' && isConnected) listener(null);
    return () {
      listeners.remove(listener);
      if (event != 'realtime:connected') _socket?.off(event, listener);
      if (listeners.isEmpty) _listeners.remove(event);
    };
  }

  void Function() listenToPatientData(
    String resource,
    void Function() listener,
  ) {
    return listen('patient:data:changed', (payload) {
      if (payload is Map && payload['resource'] == resource) listener();
    });
  }

  void _notify(String event, dynamic payload) {
    for (final listener in List<RealtimeListener>.of(_listeners[event] ?? {})) {
      listener(payload);
    }
  }
}
