import 'patient_session.dart';

abstract interface class PatientSessionStore {
  PatientSession? get currentSession;

  void save(PatientSession session);

  void clear();
}

class InMemoryPatientSessionStore implements PatientSessionStore {
  PatientSession? _session;

  @override
  PatientSession? get currentSession => _session;

  @override
  void save(PatientSession session) => _session = session;

  @override
  void clear() => _session = null;
}
