package com.nowait.nowait_app

import com.razorpay.Checkout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // With UPI, Razorpay's checkout can capture the payment and then sit on its own
        // "order is already paid" screen without calling back. The app detects the payment
        // from the backend and closes the checkout here (razorpay_flutter opens it with
        // startActivityForResult(…, Checkout.RZP_REQUEST_CODE) from this activity).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nowait/razorpay")
            .setMethodCallHandler { call, result ->
                if (call.method == "closeCheckout") {
                    finishActivity(Checkout.RZP_REQUEST_CODE)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
