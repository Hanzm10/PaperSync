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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong

/**
 * Reads the tablet's raw HID reports over USB host and hands them to Dart.
 *
 * Every HID interface of the tablet that has an interrupt IN endpoint is
 * claimed and read. Which one carries pen data depends on the host: on
 * Windows it is Report ID 9 on endpoint 0x84, on a phone it can be Report ID 5
 * on 0x86. Claiming them all also stops Android from treating the tablet as a
 * mouse, which would move a pointer and press buttons in the app.
 *
 * Each interface's HID report descriptor is read and returned from open, so
 * Dart can find the pen report and its layout without guessing.
 *
 * Interrupt endpoints are read with UsbRequest, the method Android provides
 * for them. bulkTransfer is only a fallback.
 *
 * Channels, all under "papersync/usb":
 *  - method: devices, requestPermission, open, close, stats
 *  - events "reports": {ep: Int, data: ByteArray} per interrupt transfer
 *  - events "events": {type: attached|detached, name: String?}
 */
class UsbHostPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val ACTION_PERMISSION = "com.papersync.papersync.USB_PERMISSION"
        private const val READ_TIMEOUT_MS = 100
        private const val SET_IDLE_REQUEST_TYPE = 0x21
        private const val SET_IDLE_REQUEST = 0x0A
        private const val GET_DESCRIPTOR_REQUEST_TYPE = 0x81
        private const val GET_DESCRIPTOR_REQUEST = 0x06
        private const val HID_REPORT_DESCRIPTOR = 0x2200
        private const val CONTROL_TIMEOUT_MS = 1000
        private const val MIN_BUFFER = 16
    }

    private class Link(val iface: UsbInterface, val endpoint: UsbEndpoint)

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var reportSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null

    private var pendingPermission: MethodChannel.Result? = null

    private var connection: UsbDeviceConnection? = null
    private val links = mutableListOf<Link>()
    private val readers = mutableListOf<Thread>()
    private var openName: String? = null

    @Volatile
    private var reading = false

    // What the readers have seen, for the on-screen USB check.
    private val transferCount = AtomicLong(0)
    private val emptyReads = AtomicLong(0)
    private val perEndpoint = ConcurrentHashMap<Int, AtomicLong>()

    @Volatile
    private var lastResult = 0

    @Volatile
    private var readMode = "none"

    @Volatile
    private var lastError = ""

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
        val endpoints = perEndpoint.entries
            .sortedBy { it.key }
            .joinToString(" ") { "0x" + it.key.toString(16) + ":" + it.value.get() }
        return mapOf(
            "open" to (connection != null),
            "reading" to reading,
            "claimed" to links.size,
            "transfers" to transferCount.get(),
            "emptyReads" to emptyReads.get(),
            "lastResult" to lastResult,
            "readMode" to readMode,
            "lastError" to lastError,
            "perEndpoint" to endpoints,
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
        interfaceSummary = describeInterfaces(device)
        val candidates = hidInterfaces(device)
        if (candidates.isEmpty()) {
            result.error("no_interface", "No HID interface with an interrupt IN endpoint", null)
            return
        }
        val conn = usbManager.openDevice(device)
        if (conn == null) {
            result.error("open_failed", "Android would not open the tablet", null)
            return
        }
        val opened = mutableListOf<Map<String, Any?>>()
        for (link in candidates) {
            // force = true detaches Android's own HID driver from the interface.
            if (!conn.claimInterface(link.iface, true)) continue
            links.add(link)
            // Windows sends SET_IDLE before reading. A device may stall it, so
            // the result is ignored.
            conn.controlTransfer(
                SET_IDLE_REQUEST_TYPE,
                SET_IDLE_REQUEST,
                0,
                link.iface.id,
                null,
                0,
                CONTROL_TIMEOUT_MS,
            )
            opened.add(
                mapOf(
                    "interface" to link.iface.id,
                    "endpoint" to link.endpoint.address,
                    "descriptor" to readReportDescriptor(conn, link.iface.id),
                )
            )
        }
        if (links.isEmpty()) {
            conn.close()
            result.error("claim_failed", "Could not claim any HID interface", null)
            return
        }
        connection = conn
        openName = device.deviceName
        startReaders(conn, device)
        result.success(opened)
    }

    private fun hidInterfaces(device: UsbDevice): List<Link> {
        val found = mutableListOf<Link>()
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass != UsbConstants.USB_CLASS_HID) continue
            for (j in 0 until iface.endpointCount) {
                val endpoint = iface.getEndpoint(j)
                if (endpoint.direction == UsbConstants.USB_DIR_IN &&
                    endpoint.type == UsbConstants.USB_ENDPOINT_XFER_INT
                ) {
                    found.add(Link(iface, endpoint))
                    break
                }
            }
        }
        return found
    }

    private fun readReportDescriptor(conn: UsbDeviceConnection, interfaceId: Int): ByteArray? {
        val buffer = ByteArray(4096)
        val count = conn.controlTransfer(
            GET_DESCRIPTOR_REQUEST_TYPE,
            GET_DESCRIPTOR_REQUEST,
            HID_REPORT_DESCRIPTOR,
            interfaceId,
            buffer,
            buffer.size,
            CONTROL_TIMEOUT_MS,
        )
        return if (count > 0) buffer.copyOf(count) else null
    }

    private fun startReaders(conn: UsbDeviceConnection, device: UsbDevice) {
        transferCount.set(0)
        emptyReads.set(0)
        perEndpoint.clear()
        lastResult = 0
        readMode = "none"
        lastError = ""
        reading = true
        val name = device.deviceName
        val claimed = links.toList()
        for (link in claimed) perEndpoint[link.endpoint.address] = AtomicLong(0)

        // requestWait returns whichever request on the connection finished, so
        // one thread services every endpoint's request.
        val requests = mutableMapOf<UsbRequest, Link>()
        for (link in claimed) {
            val request = UsbRequest()
            if (request.initialize(conn, link.endpoint)) {
                requests[request] = link
            } else {
                request.close()
            }
        }
        if (requests.size == claimed.size) {
            readMode = "request"
            startThread("all", name) { readWithRequests(conn, requests, name) }
        } else {
            for (request in requests.keys) request.close()
            readMode = "bulk"
            for (link in claimed) {
                startThread(link.endpoint.address.toString(16), name) {
                    readWithBulk(conn, link.endpoint, name)
                }
            }
        }
    }

    private fun startThread(tag: String, name: String, body: () -> Unit) {
        val thread = Thread {
            try {
                body()
            } catch (e: Throwable) {
                // An uncaught error on this thread would end the whole app.
                lastError = e.javaClass.simpleName + ": " + (e.message ?: "")
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
        thread.name = "papersync-usb-reader-" + tag
        thread.isDaemon = true
        readers.add(thread)
        thread.start()
    }

    @Suppress("DEPRECATION")
    private fun queue(request: UsbRequest, buffer: ByteBuffer): Boolean {
        buffer.clear()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request.queue(buffer)
        } else {
            request.queue(buffer, buffer.capacity())
        }
    }

    private fun readWithRequests(
        conn: UsbDeviceConnection,
        requests: Map<UsbRequest, Link>,
        name: String,
    ) {
        val buffers = requests.mapValues { (_, link) ->
            ByteBuffer.allocate(maxOf(link.endpoint.maxPacketSize, MIN_BUFFER))
        }
        val pending = mutableSetOf<UsbRequest>()
        try {
            while (reading) {
                for ((request, buffer) in buffers) {
                    if (request !in pending && queue(request, buffer)) pending.add(request)
                }
                if (pending.isEmpty()) {
                    lastResult = -2
                    emptyReads.incrementAndGet()
                    if (!usbManager.deviceList.containsKey(name)) break
                    sleepQuietly(20)
                    continue
                }
                val done: UsbRequest? = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        conn.requestWait(READ_TIMEOUT_MS.toLong())
                    } else {
                        conn.requestWait()
                    }
                } catch (e: TimeoutException) {
                    null
                } catch (e: Exception) {
                    // The connection was closed under the wait.
                    null
                }
                if (done == null) {
                    // No report yet, or the connection was closed. Queued
                    // requests stay queued.
                    lastResult = -1
                    emptyReads.incrementAndGet()
                    if (!usbManager.deviceList.containsKey(name)) break
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) sleepQuietly(20)
                    continue
                }
                pending.remove(done)
                val link = requests[done] ?: continue
                val buffer = buffers.getValue(done)
                val count = buffer.position()
                lastResult = count
                if (count > 0) {
                    handleReport(link.endpoint.address, buffer.array().copyOf(count))
                } else {
                    emptyReads.incrementAndGet()
                }
            }
        } finally {
            for (request in requests.keys) {
                try {
                    request.cancel()
                    request.close()
                } catch (e: Exception) {
                    // Already closed with the connection.
                }
            }
        }
    }

    private fun readWithBulk(conn: UsbDeviceConnection, endpoint: UsbEndpoint, name: String) {
        val buffer = ByteArray(maxOf(endpoint.maxPacketSize, MIN_BUFFER))
        while (reading) {
            val started = System.currentTimeMillis()
            val count = conn.bulkTransfer(endpoint, buffer, buffer.size, READ_TIMEOUT_MS)
            lastResult = count
            if (count > 0) {
                handleReport(endpoint.address, buffer.copyOf(count))
            } else {
                emptyReads.incrementAndGet()
                if (!usbManager.deviceList.containsKey(name)) break
                // An error that returns at once would otherwise spin.
                if (System.currentTimeMillis() - started < 20) sleepQuietly(20)
            }
        }
    }

    private fun handleReport(endpointAddress: Int, bytes: ByteArray) {
        transferCount.incrementAndGet()
        perEndpoint[endpointAddress]?.incrementAndGet()
        val event = mapOf("ep" to endpointAddress, "data" to bytes)
        mainHandler.post { reportSink?.success(event) }
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
        val threads = readers.toList()
        readers.clear()
        for (thread in threads) {
            if (thread == Thread.currentThread()) continue
            try {
                thread.join(300)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        val conn = connection
        val claimed = links.toList()
        connection = null
        links.clear()
        openName = null
        if (conn != null) {
            for (link in claimed) {
                try {
                    conn.releaseInterface(link.iface)
                } catch (e: Exception) {
                    // Already gone.
                }
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
