package app.musilink

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.ActivityResult
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var appUpdateManager: AppUpdateManager
    private var pendingUpdateResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdateManager = AppUpdateManagerFactory.create(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startImmediateUpdate" -> startImmediateUpdate(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startImmediateUpdate(result: MethodChannel.Result) {
        if (pendingUpdateResult != null) {
            result.success("inProgress")
            return
        }
        pendingUpdateResult = result

        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { info ->
                val availability = info.updateAvailability()
                val updateCanStart =
                    availability == UpdateAvailability.UPDATE_AVAILABLE ||
                        availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS

                if (!updateCanStart || !info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                    finishUpdateRequest("unavailable")
                    return@addOnSuccessListener
                }

                val options = AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build()
                appUpdateManager.startUpdateFlow(info, this, options)
                    .addOnSuccessListener { resultCode ->
                        val status = when (resultCode) {
                            Activity.RESULT_OK -> "completed"
                            Activity.RESULT_CANCELED -> "cancelled"
                            ActivityResult.RESULT_IN_APP_UPDATE_FAILED -> "failed"
                            else -> "failed"
                        }
                        finishUpdateRequest(status)
                    }
                    .addOnFailureListener { finishUpdateRequest("failed") }
            }
            .addOnFailureListener { finishUpdateRequest("failed") }
    }

    private fun finishUpdateRequest(status: String) {
        pendingUpdateResult?.success(status)
        pendingUpdateResult = null
    }

    companion object {
        private const val UPDATE_CHANNEL = "app.musilink/play_in_app_update"
    }
}
