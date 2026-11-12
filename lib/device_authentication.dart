import 'package:local_auth/local_auth.dart';

abstract interface class DeviceAuthenticator {
  Future<bool> authenticate();
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  const LocalDeviceAuthenticator();

  @override
  Future<bool> authenticate() {
    return LocalAuthentication().authenticate(
      localizedReason: 'Unlock Expense Tracker',
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  }
}
