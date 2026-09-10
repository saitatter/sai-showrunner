# Heart Rate integration

Heart Rate is being added as a native Flutter/Dart ShowRunner integration for
Bluetooth SIG Heart Rate Service devices such as the COOSPO H808S.

## Current milestone

Phases 0-3 are implemented:

- typed Bluetooth transport boundary;
- deterministic HRS measurement parser, including 16-bit BPM, sensor contact,
  energy expended, and RR intervals;
- configurable heart-rate zones and incremental statistics;
- fake H808S transport for tests and local UI/overlay development;
- Heart Rate integration page in Flutter;
- Heart Rate state exposed through the existing plugin registry;
- Heart Rate Browser Source widget using the existing ShowRunner overlay bridge.

The native Bluetooth backend is intentionally not included yet. The next step
is a Windows packaging spike for a production BLE transport. H808S hardware
support has not been physically verified by this milestone.

## Product boundary

The feature stays inside ShowRunner. It does not add a separate service,
database, authentication system, overlay server, or Pulsoid dependency. The
desktop integration owns device access; OBS continues to use the existing
ShowRunner Browser Source runtime.
