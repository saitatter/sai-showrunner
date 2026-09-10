# Heart Rate integration

Heart Rate is being added as a native Flutter/Dart ShowRunner integration for
Bluetooth SIG Heart Rate Service devices such as the COOSPO H808S.

## Current milestone

Phases 0-4 are implemented:

- typed Bluetooth transport boundary;
- deterministic HRS measurement parser, including 16-bit BPM, sensor contact,
  energy expended, and RR intervals;
- configurable heart-rate zones and incremental statistics;
- fake H808S transport for tests and local simulation;
- Windows BLE transport using the packaged `universal_ble` WinRT backend;
- Heart Rate integration page in Flutter;
- Heart Rate state exposed through the existing plugin registry;
- Heart Rate Browser Source widget using the existing ShowRunner overlay bridge.

The configured desktop application uses the native Bluetooth transport. The
default test registry keeps the deterministic fake transport so tests do not
depend on a Bluetooth adapter. H808S hardware support still needs physical
verification on the packaged Windows build.

The native transport is deliberately behind the same typed boundary as the
fake transport: scanning, GATT discovery, heart-rate notifications, battery
reads, disconnect handling, and adapter-state diagnostics all flow through
`BleTransport`.

The Windows release archive has been verified to include the native BLE DLL,
the Flutter executable, and the OBS overlay bundle. Physical H808S pairing and
streaming still require a Bluetooth-enabled Windows machine with the sensor.

## Product boundary

The feature stays inside ShowRunner. It does not add a separate service,
database, authentication system, overlay server, or Pulsoid dependency. The
desktop integration owns device access; OBS continues to use the existing
ShowRunner Browser Source runtime.
