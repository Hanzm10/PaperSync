// PaperSync relay: tablet (USB HID) -> ESP32-S3 (USB host) -> phone (BLE).
//
// The ESP32 forwards the tablet's own HID reports unchanged, in protocol v3
// (docs/protocol-v3.md). The app decodes them with the same code it uses for
// the USB cable, so report layouts, the portrait turn, corner calibration and
// the button map all live in the app, not here.
//
// Board settings (see firmware/README.md): esp32 core 3.0.7 exactly, ESP32S3
// Dev Module, USB CDC On Boot Disabled, PSRAM OPI. Logs go to UART0 at 115200.

#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <esp_random.h>

#include "usb/usb_host.h"

// ---------------------------------------------------------------------------
// Settings

// Report ids that are pen samples. Everything else (the buttons' keyboard
// report, mouse, vendor) is sent as a control notification: never buffered,
// never replayed.
static const uint8_t PEN_REPORT_IDS[] = {0x05, 0x09};

// The onboard BOOT button is the page button until the tablet housing gets
// its own. It starts a new page before the next pen record.
static const int PAGE_BUTTON_PIN = 0;

static const char *DEVICE_NAME = "PaperSync Pen";

// The same ids as app/lib/protocol/constants.dart.
static const char *SERVICE_UUID = "6f0c2d14-8a3e-4b7c-9d51-2e8f0a6b4c93";
static const char *STROKE_UUID = "c4a91e70-15d2-4f6b-8a03-9b7e2d5c1f48";
static const char *DESCRIPTOR_UUID = "5b2e8d61-3c7a-4f19-b0d4-8e6a1f2c7d35";

// Protocol v3.
static const uint8_t VERSION = 3;
static const uint8_t FLAG_REPLAYED = 0x01;
static const uint8_t FLAG_PAGE = 0x02;
static const uint8_t FLAG_CONTROL = 0x04;
// One report right after the header, with no dt_ms or length byte. Used when
// the link is too small for a record: at the default 23 byte MTU a
// notification carries 20 bytes, exactly a header and one 8 byte report.
// Web Bluetooth cannot ask for a larger MTU, so a browser can be stuck there.
static const uint8_t FLAG_BARE = 0x08;
static const int HEADER_BYTES = 12;
static const int MAX_NOTIFICATION = 512;
static const int MAX_REPORT = 64;

// A live notification goes out when it has waited this long, or is full.
// 15 ms keeps pen to screen delay low.
static const uint32_t SEND_EVERY_MS = 15;

// Notifications are at least this far apart, so a buffer replay after a
// reconnect does not overrun the Bluetooth stack's queue.
static const uint32_t MIN_GAP_MS = 7;

// With one report per notification the gap is shorter, to keep up with the
// tablet's report rate.
static const uint32_t MIN_GAP_BARE_MS = 3;

// Pen records kept while the phone is away. In PSRAM this is about 9 minutes
// of writing at 130 reports a second.
static const size_t BUFFER_RECORDS_PSRAM = 70000;
static const size_t BUFFER_RECORDS_RAM = 2000;

// HID report descriptors of every forwarded interface, back to back.
static const size_t MAX_DESCRIPTORS = 512;

// ---------------------------------------------------------------------------
// Reports from the USB side to the sender

struct Report {
  uint32_t tMs;
  uint8_t len;
  uint8_t data[MAX_REPORT];
};

static QueueHandle_t reportQueue;

// A pen record waiting to be sent.
struct PenRecord {
  uint32_t seq;
  uint32_t tMs;
  uint8_t len;
  bool page;
  bool offline;  // Read while no phone was listening: sent as replayed.
  uint8_t data[10];
};

static PenRecord *ring = nullptr;
static size_t ringCapacity = 0;
static size_t ringHead = 0;  // Oldest.
static size_t ringCount = 0;
static uint32_t nextSeq = 0;
static uint32_t droppedRecords = 0;
static uint16_t bootId = 0;

// ---------------------------------------------------------------------------
// BLE

static BLEServer *server = nullptr;
static BLECharacteristic *strokeChar = nullptr;
static BLECharacteristic *descriptorChar = nullptr;
static BLE2902 *strokeCccd = nullptr;
static BLE2902 *descriptorCccd = nullptr;
static volatile bool phoneConnected = false;
static volatile uint16_t connId = 0;

class ServerEvents : public BLEServerCallbacks {
  void onConnect(BLEServer *s, esp_ble_gatts_cb_param_t *param) override {
    connId = param->connect.conn_id;
    phoneConnected = true;
    Serial.println("[ble] phone connected");
  }

  void onDisconnect(BLEServer *s, esp_ble_gatts_cb_param_t *param) override {
    phoneConnected = false;
    Serial.printf("[ble] phone disconnected (reason 0x%02X), advertising again\n",
                  param->disconnect.reason);
    BLEDevice::startAdvertising();
  }

  void onMtuChanged(BLEServer *s, esp_ble_gatts_cb_param_t *param) override {
    Serial.printf("[ble] link MTU %u\n", param->mtu.mtu);
  }
};

static bool phoneListening() {
  return phoneConnected && strokeCccd != nullptr &&
         strokeCccd->getNotifications();
}

// Bytes one notification may carry on this link.
static size_t notifyRoom() {
  uint16_t mtu = server->getPeerMTU(connId);
  if (mtu < 23) mtu = 23;
  size_t room = mtu - 3;
  return room > MAX_NOTIFICATION ? MAX_NOTIFICATION : room;
}

static void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(247);
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerEvents());

  BLEService *service = server->createService(SERVICE_UUID);
  strokeChar = service->createCharacteristic(
      STROKE_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  strokeCccd = new BLE2902();
  strokeChar->addDescriptor(strokeCccd);

  descriptorChar = service->createCharacteristic(
      DESCRIPTOR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  descriptorCccd = new BLE2902();
  descriptorChar->addDescriptor(descriptorCccd);
  service->start();

  // An advertising packet holds 31 bytes. The 128 bit service id (18) and
  // the name (15) do not fit together, so the id goes in the advertisement,
  // which the app filters on, and the name in the scan response.
  BLEAdvertisementData advert;
  advert.setFlags(ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT);
  advert.setCompleteServices(BLEUUID(SERVICE_UUID));
  BLEAdvertisementData scanResponse;
  scanResponse.setName(DEVICE_NAME);
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->setAdvertisementData(advert);
  advertising->setScanResponseData(scanResponse);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.printf("[ble] advertising as \"%s\"\n", DEVICE_NAME);
}

static void putHeader(uint8_t *out, uint8_t flags, uint32_t firstSeq,
                      uint32_t baseMs) {
  out[0] = VERSION;
  out[1] = flags;
  out[2] = bootId & 0xFF;
  out[3] = bootId >> 8;
  for (int i = 0; i < 4; i++) {
    out[4 + i] = (firstSeq >> (8 * i)) & 0xFF;
    out[8 + i] = (baseMs >> (8 * i)) & 0xFF;
  }
}

// ---------------------------------------------------------------------------
// Pen record buffer

static bool isPenReport(const Report &report) {
  for (uint8_t id : PEN_REPORT_IDS) {
    if (report.len > 0 && report.data[0] == id) return true;
  }
  return false;
}

static void setupBuffer() {
  if (psramFound()) {
    ring = (PenRecord *)ps_malloc(BUFFER_RECORDS_PSRAM * sizeof(PenRecord));
    if (ring) ringCapacity = BUFFER_RECORDS_PSRAM;
  }
  if (!ring) {
    ring = (PenRecord *)malloc(BUFFER_RECORDS_RAM * sizeof(PenRecord));
    ringCapacity = ring ? BUFFER_RECORDS_RAM : 0;
  }
  Serial.printf("[buf] room for %u pen records\n", (unsigned)ringCapacity);
}

static volatile bool pagePending = false;

static void storePen(const Report &report) {
  if (ringCapacity == 0) return;
  if (ringCount == ringCapacity) {
    // Full: the oldest record goes. The app sees the gap in the sequence.
    ringHead = (ringHead + 1) % ringCapacity;
    ringCount--;
    droppedRecords++;
  }
  PenRecord &record = ring[(ringHead + ringCount) % ringCapacity];
  record.seq = nextSeq++;
  record.tMs = report.tMs;
  record.len = report.len > sizeof(record.data) ? sizeof(record.data)
                                                : report.len;
  memcpy(record.data, report.data, record.len);
  record.page = pagePending;
  pagePending = false;
  record.offline = !phoneListening();
  ringCount++;
}

// Sends one notification from the front of the buffer. Records in one
// notification share the replay flag, have consecutive sequence numbers, and
// lie within 255 ms of the first. A page record always starts a notification.
static bool sendPenNotification() {
  if (ringCount == 0) return false;
  static uint8_t out[MAX_NOTIFICATION];
  const size_t room = notifyRoom();
  const PenRecord &first = ring[ringHead];
  if (room < HEADER_BYTES + 2 + first.len) {
    // Too small for a record: send the first one bare.
    if (room < HEADER_BYTES + first.len) return false;
    uint8_t flags = FLAG_BARE;
    if (first.offline) flags |= FLAG_REPLAYED;
    if (first.page) flags |= FLAG_PAGE;
    putHeader(out, flags, first.seq, first.tMs);
    memcpy(out + HEADER_BYTES, first.data, first.len);
    strokeChar->setValue(out, HEADER_BYTES + first.len);
    strokeChar->notify();
    ringHead = (ringHead + 1) % ringCapacity;
    ringCount--;
    return true;
  }
  size_t used = HEADER_BYTES;
  size_t taken = 0;
  while (taken < ringCount) {
    const PenRecord &record = ring[(ringHead + taken) % ringCapacity];
    if (taken > 0) {
      if (record.page || record.offline != first.offline) break;
      if (record.seq != first.seq + taken) break;
      if (record.tMs - first.tMs > 255) break;
    }
    if (used + 2 + record.len > room) break;
    out[used++] = (uint8_t)(record.tMs - first.tMs);
    out[used++] = record.len;
    memcpy(out + used, record.data, record.len);
    used += record.len;
    taken++;
  }
  if (taken == 0) return false;
  uint8_t flags = 0;
  if (first.offline) flags |= FLAG_REPLAYED;
  if (first.page) flags |= FLAG_PAGE;
  putHeader(out, flags, first.seq, first.tMs);
  strokeChar->setValue(out, used);
  strokeChar->notify();
  ringHead = (ringHead + taken) % ringCapacity;
  ringCount -= taken;
  return true;
}

static void sendControl(const Report &report) {
  if (!phoneListening()) return;  // A late button press would surprise.
  uint8_t out[HEADER_BYTES + 2 + MAX_REPORT];
  const size_t room = notifyRoom();
  if (room >= HEADER_BYTES + 2 + report.len) {
    putHeader(out, FLAG_CONTROL, 0, report.tMs);
    out[HEADER_BYTES] = 0;
    out[HEADER_BYTES + 1] = report.len;
    memcpy(out + HEADER_BYTES + 2, report.data, report.len);
    strokeChar->setValue(out, HEADER_BYTES + 2 + report.len);
  } else if (room >= HEADER_BYTES + report.len) {
    putHeader(out, FLAG_CONTROL | FLAG_BARE, 0, report.tMs);
    memcpy(out + HEADER_BYTES, report.data, report.len);
    strokeChar->setValue(out, HEADER_BYTES + report.len);
  } else {
    return;
  }
  strokeChar->notify();
}

// ---------------------------------------------------------------------------
// USB host

struct HidLink {
  uint8_t interface;
  uint8_t endpoint;
  uint16_t mps;
  usb_transfer_t *transfer;
  volatile bool inFlight;
};

static const int MAX_LINKS = 4;
static usb_host_client_handle_t client = nullptr;
static usb_device_handle_t device = nullptr;
static HidLink links[MAX_LINKS];
static int linkCount = 0;
static volatile uint8_t newDeviceAddress = 0;
static volatile bool deviceGone = false;
static volatile bool deviceOpen = false;

static uint8_t descriptors[MAX_DESCRIPTORS];
static size_t descriptorLength = 0;

static void onClientEvent(const usb_host_client_event_msg_t *msg, void *arg) {
  switch (msg->event) {
    case USB_HOST_CLIENT_EVENT_NEW_DEV:
      newDeviceAddress = msg->new_dev.address;
      break;
    case USB_HOST_CLIENT_EVENT_DEV_GONE:
      deviceGone = true;
      break;
    default:
      break;
  }
}

static void onInterruptIn(usb_transfer_t *transfer) {
  HidLink *link = (HidLink *)transfer->context;
  if (transfer->status == USB_TRANSFER_STATUS_COMPLETED &&
      transfer->actual_num_bytes > 0) {
    Report report;
    report.tMs = millis();
    report.len = transfer->actual_num_bytes > MAX_REPORT
                     ? MAX_REPORT
                     : transfer->actual_num_bytes;
    memcpy(report.data, transfer->data_buffer, report.len);
    xQueueSend(reportQueue, &report, 0);
  }
  if (deviceOpen && !deviceGone &&
      transfer->status != USB_TRANSFER_STATUS_NO_DEVICE &&
      transfer->status != USB_TRANSFER_STATUS_CANCELED) {
    if (usb_host_transfer_submit(transfer) == ESP_OK) return;
  }
  link->inFlight = false;
}

// Control transfers finish inside usb_host_client_handle_events, which runs
// on this same task, so the wait keeps handling events.
static volatile bool controlDone = false;

static void onControl(usb_transfer_t *transfer) { controlDone = true; }

static int controlTransfer(uint8_t requestType, uint8_t request,
                           uint16_t value, uint16_t index, uint16_t length,
                           uint8_t *in) {
  usb_transfer_t *transfer = nullptr;
  if (usb_host_transfer_alloc(sizeof(usb_setup_packet_t) + MAX_DESCRIPTORS, 0,
                              &transfer) != ESP_OK) {
    return -1;
  }
  usb_setup_packet_t *setup = (usb_setup_packet_t *)transfer->data_buffer;
  setup->bmRequestType = requestType;
  setup->bRequest = request;
  setup->wValue = value;
  setup->wIndex = index;
  setup->wLength = length;
  transfer->num_bytes = sizeof(usb_setup_packet_t) + length;
  transfer->device_handle = device;
  transfer->bEndpointAddress = 0;
  transfer->callback = onControl;
  transfer->context = nullptr;
  controlDone = false;
  int result = -1;
  if (usb_host_transfer_submit_control(client, transfer) == ESP_OK) {
    const uint32_t start = millis();
    while (!controlDone && millis() - start < 1000) {
      usb_host_client_handle_events(client, pdMS_TO_TICKS(10));
    }
    if (controlDone && transfer->status == USB_TRANSFER_STATUS_COMPLETED) {
      result = transfer->actual_num_bytes - sizeof(usb_setup_packet_t);
      if (in && result > 0) {
        memcpy(in, transfer->data_buffer + sizeof(usb_setup_packet_t), result);
      }
    }
  }
  usb_host_transfer_free(transfer);
  return result;
}

static void publishDescriptors() {
  // The app reads the whole value again on any notification, so one byte
  // says it changed. The whole value would not fit a small link. The full
  // value is back before the app's read arrives.
  if (phoneConnected && descriptorCccd && descriptorCccd->getNotifications()) {
    uint8_t changed = 1;
    descriptorChar->setValue(&changed, 1);
    descriptorChar->notify();
  }
  descriptorChar->setValue(descriptors, descriptorLength);
}

static void openDevice(uint8_t address) {
  if (usb_host_device_open(client, address, &device) != ESP_OK) {
    Serial.println("[usb] could not open the device");
    return;
  }
  const usb_device_desc_t *deviceDesc;
  usb_host_get_device_descriptor(device, &deviceDesc);
  Serial.printf("[usb] device %04X:%04X\n", deviceDesc->idVendor,
                deviceDesc->idProduct);

  const usb_config_desc_t *config;
  usb_host_get_active_config_descriptor(device, &config);
  linkCount = 0;
  descriptorLength = 0;
  for (uint8_t number = 0; number < config->bNumInterfaces; number++) {
    int offset = 0;
    const usb_intf_desc_t *intf =
        usb_parse_interface_descriptor(config, number, 0, &offset);
    if (!intf || intf->bInterfaceClass != USB_CLASS_HID) continue;
    for (int i = 0; i < intf->bNumEndpoints && linkCount < MAX_LINKS; i++) {
      int epOffset = offset;
      const usb_ep_desc_t *ep = usb_parse_endpoint_descriptor_by_index(
          intf, i, config->wTotalLength, &epOffset);
      if (!ep || !USB_EP_DESC_GET_EP_DIR(ep) ||
          USB_EP_DESC_GET_XFERTYPE(ep) != USB_TRANSFER_TYPE_INTR) {
        continue;
      }
      if (usb_host_interface_claim(client, device, number, 0) != ESP_OK) {
        Serial.printf("[usb] could not claim interface %u\n", number);
        break;
      }
      HidLink &link = links[linkCount++];
      link.interface = number;
      link.endpoint = ep->bEndpointAddress;
      link.mps = USB_EP_DESC_GET_MPS(ep);
      link.transfer = nullptr;
      link.inFlight = false;
      break;
    }
  }

  for (int i = 0; i < linkCount; i++) {
    HidLink &link = links[i];
    // HID report descriptor: GET_DESCRIPTOR, type 0x22, to the interface.
    uint8_t buffer[MAX_DESCRIPTORS];
    int got = controlTransfer(0x81, 0x06, 0x2200, link.interface,
                              MAX_DESCRIPTORS - descriptorLength, buffer);
    if (got > 0) {
      memcpy(descriptors + descriptorLength, buffer, got);
      descriptorLength += got;
    }
    // SET_IDLE, as Windows does. A stall is fine.
    controlTransfer(0x21, 0x0A, 0, link.interface, 0, nullptr);
    Serial.printf("[usb] interface %u, endpoint %02X, packet %u, descriptor %d bytes\n",
                  link.interface, link.endpoint, link.mps, got);
  }
  publishDescriptors();

  deviceOpen = true;
  for (int i = 0; i < linkCount; i++) {
    HidLink &link = links[i];
    // One packet per transfer, so one transfer is one report.
    if (usb_host_transfer_alloc(link.mps, 0, &link.transfer) != ESP_OK) continue;
    link.transfer->device_handle = device;
    link.transfer->bEndpointAddress = link.endpoint;
    link.transfer->callback = onInterruptIn;
    link.transfer->context = &link;
    link.transfer->num_bytes = link.mps;
    link.inFlight = usb_host_transfer_submit(link.transfer) == ESP_OK;
  }
  Serial.printf("[usb] reading %d HID interfaces\n", linkCount);
}

static void closeDevice() {
  deviceOpen = false;
  const uint32_t start = millis();
  bool waiting = true;
  while (waiting && millis() - start < 500) {
    waiting = false;
    for (int i = 0; i < linkCount; i++) waiting |= links[i].inFlight;
    if (waiting) usb_host_client_handle_events(client, pdMS_TO_TICKS(10));
  }
  for (int i = 0; i < linkCount; i++) {
    if (links[i].transfer) usb_host_transfer_free(links[i].transfer);
    links[i].transfer = nullptr;
    usb_host_interface_release(client, device, links[i].interface);
  }
  linkCount = 0;
  usb_host_device_close(client, device);
  device = nullptr;
  descriptorLength = 0;
  publishDescriptors();
  Serial.println("[usb] tablet unplugged");
}

static void usbLibraryTask(void *arg) {
  usb_host_config_t config = {};
  config.skip_phy_setup = false;
  config.intr_flags = ESP_INTR_FLAG_LEVEL1;
  ESP_ERROR_CHECK(usb_host_install(&config));
  xTaskNotifyGive((TaskHandle_t)arg);
  while (true) {
    uint32_t flags;
    usb_host_lib_handle_events(portMAX_DELAY, &flags);
    if (flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS) {
      usb_host_device_free_all();
    }
  }
}

static void usbClientTask(void *arg) {
  usb_host_client_config_t config = {};
  config.is_synchronous = false;
  config.max_num_event_msg = 5;
  config.async.client_event_callback = onClientEvent;
  config.async.callback_arg = nullptr;
  ESP_ERROR_CHECK(usb_host_client_register(&config, &client));
  Serial.println("[usb] waiting for the tablet");
  while (true) {
    usb_host_client_handle_events(client, pdMS_TO_TICKS(10));
    if (newDeviceAddress && !device) {
      uint8_t address = newDeviceAddress;
      newDeviceAddress = 0;
      deviceGone = false;
      openDevice(address);
    }
    if (deviceGone && device) {
      closeDevice();
      deviceGone = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Status LED: blue waiting for the tablet, yellow tablet but no phone,
// green both.

static void showStatus() {
#ifdef RGB_BUILTIN
  static int last = -1;
  int now = !deviceOpen ? 0 : (phoneListening() ? 2 : 1);
  if (now == last) return;
  last = now;
  if (now == 0) rgbLedWrite(RGB_BUILTIN, 0, 0, 16);
  if (now == 1) rgbLedWrite(RGB_BUILTIN, 16, 12, 0);
  if (now == 2) rgbLedWrite(RGB_BUILTIN, 0, 16, 0);
#endif
}

// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nPaperSync relay, protocol v3");
  bootId = esp_random() & 0xFFFF;
  pinMode(PAGE_BUTTON_PIN, INPUT_PULLUP);

  reportQueue = xQueueCreate(256, sizeof(Report));
  setupBuffer();
  setupBle();

  TaskHandle_t self = xTaskGetCurrentTaskHandle();
  xTaskCreatePinnedToCore(usbLibraryTask, "usb_lib", 4096, self, 3, nullptr, 0);
  ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
  xTaskCreatePinnedToCore(usbClientTask, "usb_client", 8192, nullptr, 3,
                          nullptr, 0);
}

void loop() {
  // Page button, debounced: a press is a release to press edge held 30 ms.
  static bool lastLevel = HIGH;
  static uint32_t changedAt = 0;
  static bool pressed = false;
  bool level = digitalRead(PAGE_BUTTON_PIN);
  if (level != lastLevel) {
    lastLevel = level;
    changedAt = millis();
  } else if (millis() - changedAt > 30 && pressed != (level == LOW)) {
    pressed = level == LOW;
    if (pressed) {
      pagePending = true;
      Serial.println("[page] new page");
    }
  }

  Report report;
  static uint32_t printed = 0;
  while (xQueueReceive(reportQueue, &report, 0) == pdTRUE) {
    if (printed < 5) {
      // The first few reports, so the Serial Monitor shows the tablet talks.
      printed++;
      Serial.print("[usb] report:");
      for (int i = 0; i < report.len && i < 16; i++) {
        Serial.printf(" %02X", report.data[i]);
      }
      Serial.println();
    }
    if (isPenReport(report)) {
      storePen(report);
    } else {
      sendControl(report);
    }
  }

  static uint32_t lastSend = 0;
  const uint32_t gap = phoneListening() && notifyRoom() < HEADER_BYTES + 2 + 8
                           ? MIN_GAP_BARE_MS
                           : MIN_GAP_MS;
  if (phoneListening() && ringCount > 0 && millis() - lastSend >= gap) {
    const PenRecord &oldest = ring[ringHead];
    const bool due = oldest.offline || ringCount >= 17 ||
                     millis() - oldest.tMs >= SEND_EVERY_MS;
    if (due && sendPenNotification()) lastSend = millis();
  }

  static uint32_t lastLog = 0;
  if (millis() - lastLog > 5000) {
    lastLog = millis();
    Serial.printf(
        "[stat] tablet %s, phone %s, mtu %u, waiting %u, seq %u, dropped %u\n",
        deviceOpen ? "yes" : "no",
        phoneListening() ? "listening" : (phoneConnected ? "connected" : "no"),
        phoneConnected ? (unsigned)server->getPeerMTU(connId) : 0u,
        (unsigned)ringCount, (unsigned)nextSeq, (unsigned)droppedRecords);
  }

  showStatus();
  delay(2);
}
