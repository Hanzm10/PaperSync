package com.papersync.papersync

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var usbHost: UsbHostPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = UsbHostPlugin(applicationContext)
        plugin.attach(flutterEngine.dartExecutor.binaryMessenger)
        usbHost = plugin
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usbHost?.detach()
        usbHost = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // The tablet being plugged in while the app is open arrives here, because
    // the activity declares the USB_DEVICE_ATTACHED filter.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        usbHost?.handleIntent(intent)
    }
}
