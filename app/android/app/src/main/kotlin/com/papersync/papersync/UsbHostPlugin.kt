package com.papersync.papersync

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException

/**
 * Reads the tablet's raw pen reports over USB host and hands them to Dart.
 *
 * The tablet is a composite device: mass storage, a HID interface on endpoint
 * 0x84 (vendor, mouse and the Report ID 9 pen reports) and a second HID
 * interface on 0x86. Only the 0x84 interface is claimed. Every interrupt
 * transfer is forwarded as it arrives, and Dart keeps the ones that start with
 * 0x09.
 *
 * Channels, all under "papersync/usb":
 *  - method: devices, requestPermission, open, close
 *  - events "reports": one ByteArray per interrupt transfer
 *  - events "events": {type: attached|detached, name: String?}
 *
 * Interrupt IN endpoints are read with UsbRequest, which is the method Android
 * provides for them. Plain bulkTransfer is only a fallback, because many
 * phones refuse it on an interrupt endpoint.
 *
 * Once a pen report (Report ID 9) has really arrived, the other HID
 * interfaces of the tablet are claimed too. That stops Android from also
 * turning the tablet into a mouse, which would press buttons in the app.
 */
class UsbHostPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val ACTION_PERMISSION = "com.papersync.papersync.USB_PERMISSION"
        private const val PEN_ENDPOINT_ADDRESS = 0x84
        private const val READ_TIMEOUT_MS = 100
        private const val SET_IDLE_REQUEST_TYPE = 0x21
        private const val SET_IDLE_REQUEST = 0x0A
        private const val CONTROL_TIMEOUT_MS = 1000
        private const val MIN_BUFFER = 16
        private const val PEN_REPORT_ID = 0x09
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var reportSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null

    private var pendingPermission: MethodChannel.Result? = null

    private var connection: UsbDeviceConnection? = null
    private var claimed: UsbInterface? = null
    private var reader: Thread? = null
    private var openName: String? = null

    @Volatile
    private var reading = false

    // What the reader thread has seen, for the on-screen USB check.
    @Volatile
    private var transferCount = 0L

    @Volatile
    private var emptyReads = 0L

    @Volatile
    private var lastResult = 0

    @Volatile
    private var readMode = "none"

    @Volatile
    private var penReportSeen = false

    @Volatile
    private var quietedInterfaces = 0

    private val extraClaimed = mutableListOf<UsbInterface>()

    private var claimedInterfaceId = -1
    private var claimedEndpointAddress = -1
    private var claimedMaxPacket = 0
    private var interfaceSummary: List<String> = emptyList()

    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent == null) return
            when (intent.action) {
                ACTION_PERMISSION -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val result = pendingPermission
                    pendingPermission = null
                    result?.success(granted)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val name = deviceNameOf(intent)
                    if (name != null && name == openName) closeLink()
                    sendEvent("detached", name)
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    sendEvent("attached", deviceNameOf(intent))
                }
            }
        }
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "papersync/usb").setMethodCallHandler(this)
        EventChannel(messenger, "papersync/usb/reports").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    reportSink = events
                }

                override fun onCancel(arguments: Any?) {
                    reportSink = null
                }
            }
        )
        EventChannel(messenger, "papersync/usb/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        registerReceiver()
    }

    fun detach() {
        closeLink()
        if (receiverRegistered) {
            context.unregisterReceiver(receiver)
            receiverRegistered = false
        }
        pendingPermission?.success(false)
        pendingPermission = null
        reportSink = null
        eventSink = null
    }

    /**
     * Android sends USB_DEVICE_ATTACHED only to the activity that declares it,
     * not to a registered receiver, so MainActivity passes new intents here.
     */
    fun handleIntent(intent: Intent) {
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            sendEvent("attached", deviceNameOf(intent))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> result.success(listDevices())
            "requestPermission" -> requestPermission(call.argument<String>("name"), result)
            "open" -> open(call.argument<String>("name"), result)
            "stats" -> result.success(stats())
            "close" -> {
                closeLink()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun stats(): Map<String, Any> {
        return mapOf(
            "open" to (connection != null),
            "reading" to reading,
            "interfaceId" to claimedInterfaceId,
            "endpoint" to claimedEndpointAddress,
            "maxPacket" to claimedMaxPacket,
            "transfers" to transferCount,
            "emptyReads" to emptyReads,
            "lastResult" to lastResult,
            "readMode" to readMode,
            "penReportSeen" to penReportSeen,
            "quietedInterfaces" to quietedInterfaces,
            "interfaces" to interfaceSummary,
        )
    }

    private fun describeInterfaces(device: UsbDevice): List<String> {
        val lines = mutableListOf<String>()
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            val endpoints = (0 until iface.endpointCount).joinToString(",") { j ->
                "0x" + iface.getEndpoint(j).address.toString(16)
            }
            lines.add("id " + iface.id + " class " + iface.interfaceClass + " eps " + endpoints)
        }
        return lines
    }

    private fun listDevices(): List<Map<String, Any>> {
        return usbManager.deviceList.values.map { device ->
            mapOf(
                "name" to device.deviceName,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "hasPermission" to usbManager.hasPermission(device),
            )
        }
    }

    private fun requestPermission(name: String?, result: MethodChannel.Result) {
        val device = name?.let { usbManager.deviceList[it] }
        if (device == null) {
            result.success(false)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(ACTION_PERMISSION).setPackage(context.packageName)
        usbManager.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    private fun open(name: String?, result: MethodChannel.Result) {
        closeLink()
        val device = name?.let { usbManager.deviceList[it] }
        if (device == null) {
            result.error("no_device", "The tablet is not plugged in", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            result.error("no_permission", "USB permission was not granted", null)
            return
        }
        val found = findPenInterface(device)
        if (found == null) {
            result.error("no_interface", "No pen interface on endpoint 0x84", null)
            return
        }
        val iface = found.first
        val endpoint = found.second
        interfaceSummary = describeInterfaces(device)
        claimedInterfaceId = iface.id
        claimedEndpointAddress = endpoint.address
        claimedMaxPacket = endpoint.maxPacketSize
        val conn = usbManager.openDevice(device)
        if (conn == null) {
            result.error("open_failed", "Android would not open the tablet", null)
            return
        }
        // force = true detaches Android's own HID driver from the interface.
        if (!conn.claimInterface(iface, true)) {
            conn.close()
            result.error("claim_failed", "Could not claim the pen interface", null)
            return
        }
        // Windows sends SET_IDLE before reading. A device may stall it, so the
        // result is ignored.
        conn.controlTransfer(
            SET_IDLE_REQUEST_TYPE,
            SET_IDLE_REQUEST,
            0,
            iface.id,
            null,
            0,
            CONTROL_TIMEOUT_MS,
        )
        connection = conn
        claimed = iface
        openName = device.deviceName
        startReader(conn, endpoint, device)
        result.success(null)
    }

    private fun findPenInterface(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass != UsbConstants.USB_CLASS_HID) continue
            for (j in 0 until iface.endpointCount) {
                val endpoint = iface.getEndpoint(j)
                if (endpoint.address == PEN_ENDPOINT_ADDRESS &&
                    endpoint.direction == UsbConstants.USB_DIR_IN &&
                    endpoint.type == UsbConstants.USB_ENDPOINT_XFER_INT
                ) {
                    return Pair(iface, endpoint)
                }
            }
        }
        return null
    }

    private fun startReader(conn: UsbDeviceConnection, endpoint: UsbEndpoint, device: UsbDevice) {
        transferCount = 0L
        emptyReads = 0L
        lastResult = 0
        readMode = "none"
        penReportSeen = false
        quietedInterfaces = 0
        reading = true
        val name = device.deviceName
        val size = maxOf(endpoint.maxPacketSize, MIN_BUFFER)
        val thread = Thread {
            val request = UsbRequest()
            if (request.initialize(conn, endpoint)) {
                readMode = "request"
                readWithRequests(conn, request, size, device)
                try {
                    request.cancel()
                    request.close()
                } catch (e: Exception) {
                    // Already closed with the connection.
                }
            } else {
                readMode = "bulk"
                readWithBulk(conn, endpoint, size, device)
            }
            if (reading) {
                // The device went away without being closed.
                mainHandler.post {
                    if (openName == name) {
                        closeLink()
                        sendEvent("detached", name)
                    }
                }
            }
        }
        thread.name = "papersync-usb-reader"
        thread.isDaemon = true
        reader = thread
        thread.start()
    }

    private fun readWithRequests(
        conn: UsbDeviceConnection,
        request: UsbRequest,
        size: Int,
        device: UsbDevice,
    ) {
        val name = device.deviceName
        val buffer = ByteBuffer.allocate(size)
        var pending = false
        while (reading) {
            if (!pending) {
                buffer.clear()
                val queued = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    request.queue(buffer)
                } else {
                    request.queue(buffer, size)
                }
                if (!queued) {
                    lastResult = -2
                    emptyReads += 1
                    if (!usbManager.deviceList.containsKey(name)) break
                    sleepQuietly(20)
                    continue
                }
                pending = true
            }
            val done: UsbRequest? = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    conn.requestWait(READ_TIMEOUT_MS.toLong())
                } else {
                    conn.requestWait()
                }
            } catch (e: TimeoutException) {
                null
            }
            if (done == null) {
                // No report yet, or the connection was closed. The request
                // stays queued, so wait on it again without queueing twice.
                lastResult = -1
                emptyReads += 1
                if (!usbManager.deviceList.containsKey(name)) break
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) sleepQuietly(20)
                continue
            }
            pending = false
            val count = buffer.position()
            lastResult = count
            if (count > 0) {
                handleReport(conn, device, buffer.array().copyOf(count))
            } else {
                emptyReads += 1
            }
        }
    }

    private fun readWithBulk(
        conn: UsbDeviceConnection,
        endpoint: UsbEndpoint,
        size: Int,
        device: UsbDevice,
    ) {
        val name = device.deviceName
        val buffer = ByteArray(size)
        while (reading) {
            val started = System.currentTimeMillis()
            val count = conn.bulkTransfer(endpoint, buffer, buffer.size, READ_TIMEOUT_MS)
            lastResult = count
            if (count > 0) {
                handleReport(conn, device, buffer.copyOf(count))
            } else {
                emptyReads += 1
                if (!usbManager.deviceList.containsKey(name)) break
                // An error that returns at once would otherwise spin.
                if (System.currentTimeMillis() - started < 20) sleepQuietly(20)
            }
        }
    }

    private fun handleReport(conn: UsbDeviceConnection, device: UsbDevice, bytes: ByteArray) {
        transferCount += 1
        mainHandler.post { reportSink?.success(bytes) }
        if (!penReportSeen && bytes.isNotEmpty() && bytes[0].toInt() == PEN_REPORT_ID) {
            penReportSeen = true
            quietOtherInterfaces(conn, device)
        }
    }

    /**
     * Claims the tablet's other HID interfaces so Android stops treating it as
     * a mouse or stylus. This only happens after a pen report has arrived,
     * which proves the raw route works, so the tablet is never left with
     * nothing reading it.
     */
    private fun quietOtherInterfaces(conn: UsbDeviceConnection, device: UsbDevice) {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass != UsbConstants.USB_CLASS_HID) continue
            if (iface.id == claimedInterfaceId) continue
            if (conn.claimInterface(iface, true)) {
                extraClaimed.add(iface)
                quietedInterfaces += 1
            }
        }
    }

    private fun sleepQuietly(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private fun closeLink() {
        reading = false
        val thread = reader
        reader = null
        if (thread != null && thread != Thread.currentThread()) {
            try {
                thread.join(300)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        val conn = connection
        val iface = claimed
        connection = null
        claimed = null
        openName = null
        val extras = extraClaimed.toList()
        extraClaimed.clear()
        if (conn != null) {
            try {
                for (extra in extras) conn.releaseInterface(extra)
                if (iface != null) conn.releaseInterface(iface)
            } catch (e: Exception) {
                // Already gone.
            }
            conn.close()
        }
    }

    private fun sendEvent(type: String, name: String?) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(mapOf("type" to type, "name" to name)) }
    }

    @Suppress("DEPRECATION")
    private fun deviceNameOf(intent: Intent): String? {
        val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        return device?.deviceName
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(ACTION_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }
}
