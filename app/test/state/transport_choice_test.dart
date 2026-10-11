import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/state/signal.dart';
import 'package:papersync/state/transport_choice.dart';

void main() {
  test('the simulator is web, tests, or a debug phone switch', () {
    expect(
      shouldUseSimulator(
        isWeb: true,
        isTest: false,
        isRelease: true,
        debugSwitch: false,
      ),
      isTrue,
    );
    expect(
      shouldUseSimulator(
        isWeb: false,
        isTest: true,
        isRelease: false,
        debugSwitch: false,
      ),
      isTrue,
    );
    expect(
      shouldUseSimulator(
        isWeb: false,
        isTest: false,
        isRelease: false,
        debugSwitch: true,
      ),
      isTrue,
    );
    expect(
      shouldUseSimulator(
        isWeb: false,
        isTest: false,
        isRelease: false,
        debugSwitch: false,
      ),
      isFalse,
    );
    expect(
      shouldUseSimulator(
        isWeb: false,
        isTest: false,
        isRelease: true,
        debugSwitch: true,
      ),
      isFalse,
    );
  });

  test('the debug overlay is absent from release builds', () {
    expect(debugOverlayEnabled(debugMode: true, releaseMode: true), isFalse);
    expect(debugOverlayEnabled(debugMode: false, releaseMode: false), isFalse);
    expect(debugOverlayEnabled(debugMode: true, releaseMode: false), isTrue);
  });

  test('RSSI buckets are strong, fair, and weak', () {
    expect(signalForRssi(-65), 'Strong');
    expect(signalForRssi(-40), 'Strong');
    expect(signalForRssi(-66), 'Fair');
    expect(signalForRssi(-80), 'Fair');
    expect(signalForRssi(-81), 'Weak');
  });
}
