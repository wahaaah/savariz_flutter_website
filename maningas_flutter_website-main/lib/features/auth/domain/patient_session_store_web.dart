import 'dart:convert';

import 'package:web/web.dart' as web;

import 'patient_session.dart';
import 'patient_session_store.dart';

class BrowserPatientSessionStore implements PatientSessionStore {
  BrowserPatientSessionStore()
    : _session =
          _readSession(web.window.sessionStorage, rememberMe: false) ??
          _readSession(web.window.localStorage, rememberMe: true);

  static const _tokenKey = 'patientAuthToken';
  static const _patientIdKey = 'patientId';
  static const _patientNameKey = 'patientName';
  static const _patientEmailKey = 'patientEmail';
  static const _patientKey = 'patient';
  static const _patientIdAliases = ['patient_id', 'patientID'];
  static const _keys = [
    _tokenKey,
    _patientIdKey,
    ..._patientIdAliases,
    _patientNameKey,
    _patientEmailKey,
    _patientKey,
  ];

  PatientSession? _session;

  @override
  PatientSession? get currentSession => _session;

  @override
  void save(PatientSession session) {
    _writeSession(web.window.sessionStorage, session);
    if (session.rememberMe) {
      _writeSession(web.window.localStorage, session);
    } else {
      _clearSession(web.window.localStorage);
    }
    _session = session;
  }

  @override
  void clear() {
    _session = null;
    _clearSession(web.window.sessionStorage);
    _clearSession(web.window.localStorage);
  }

  static PatientSession? _readSession(
    web.Storage storage, {
    required bool rememberMe,
  }) {
    final token = storage.getItem(_tokenKey);
    final patientId =
        storage.getItem(_patientIdKey) ??
        storage.getItem(_patientIdAliases.first) ??
        storage.getItem(_patientIdAliases.last);
    if (token == null ||
        token.isEmpty ||
        patientId == null ||
        patientId.isEmpty) {
      return null;
    }
    return PatientSession(
      patientId: patientId,
      name: storage.getItem(_patientNameKey) ?? '',
      email: storage.getItem(_patientEmailKey) ?? '',
      token: token,
      rememberMe: rememberMe,
      emailVerified: true,
    );
  }

  static void _writeSession(web.Storage storage, PatientSession session) {
    storage
      ..setItem(_tokenKey, session.token)
      ..setItem(_patientIdKey, session.patientId)
      ..setItem(_patientIdAliases.first, session.patientId)
      ..setItem(_patientIdAliases.last, session.patientId)
      ..setItem(_patientNameKey, session.name)
      ..setItem(_patientEmailKey, session.email)
      ..setItem(
        _patientKey,
        jsonEncode({
          'patient_id': session.patientId,
          'name': session.name,
          'email': session.email,
          'email_verified': true,
        }),
      );
  }

  static void _clearSession(web.Storage storage) {
    for (final key in _keys) {
      storage.removeItem(key);
    }
  }
}

PatientSessionStore createPatientSessionStore() =>
    BrowserPatientSessionStore();
