/// PaperSync pen protocol v1.
///
/// The numbers here are the contract the firmware will adopt. They are also
/// written out in `docs/protocol-v1.md`.
library;

/// Fresh v4 ids, chosen once for the GATT service and the stroke stream.
const String serviceUuid = '6f0c2d14-8a3e-4b7c-9d51-2e8f0a6b4c93';
const String strokeCharacteristicUuid = 'c4a91e70-15d2-4f6b-8a03-9b7e2d5c1f48';

/// Standard Battery Service. The pen reports charge here, not in the stroke
/// characteristic.
const int batteryServiceUuid = 0x180F;
const int batteryLevelCharacteristicUuid = 0x2A19;
const String batteryServiceUuid128 = '0000180f-0000-1000-8000-00805f9b34fb';
const String batteryLevelCharacteristicUuid128 =
    '00002a19-0000-1000-8000-00805f9b34fb';

const int protocolVersion = 1;
const int headerBytes = 12;
const int recordBytes = 8;

/// X and Y on the wire are counts of 1/200 mm.
const int unitsPerMm = 200;

const int maxPressure = 16383;

/// A notification longer than this is rejected.
const int maxNotificationBytes = 512;

/// Header bit 0: the samples were replayed from the pen's buffer.
const int flagReplayed = 0x01;

/// Record bit 0.
const int flagTouching = 0x01;

/// Record bit 1.
const int flagHover = 0x02;

/// Record bit 2. The pen synthesizes this when the page button is pressed.
const int flagPageMarker = 0x04;

/// Protocol v3, the relay format: the ESP32 forwards the tablet's own HID
/// reports unchanged. See `docs/protocol-v3.md`.
const int relayProtocolVersion = 3;

/// Bytes before each forwarded report: `dt_ms` and the report length.
const int relayRecordHeaderBytes = 2;

/// A forwarded report is never longer than one full speed packet.
const int maxRelayReportBytes = 64;

/// v3 header bit 1: a new page starts before the first record. With no
/// records, it starts before the next pen record.
const int flagPageButton = 0x02;

/// v3 header bit 2: the records are not pen samples (the tablet's buttons).
/// They carry no sequence numbers and are never replayed.
const int flagControl = 0x04;

/// v3 header bit 3: one report follows the header with no `dt_ms` or length
/// byte. The relay uses it when the link is too small for a record: the
/// default 23 byte MTU leaves 20 bytes, a header and one 8 byte report. Web
/// Bluetooth cannot ask for a larger MTU.
const int flagBare = 0x08;

/// Read and notify. The HID report descriptors of the forwarded interfaces,
/// back to back, so the app can lay out the reports itself.
const String reportDescriptorCharacteristicUuid =
    '5b2e8d61-3c7a-4f19-b0d4-8e6a1f2c7d35';
