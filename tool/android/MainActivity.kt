package com.flocker.f_locker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Native helpers for F-Locker: "All files access" so files can be moved out
// of the gallery and put back, and refreshing the gallery afterwards.
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val legacyPerms = arrayOf(
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.WRITE_EXTERNAL_STORAGE
    )

    private fun hasAccess(): Boolean = when {
        Build.VERSION.SDK_INT >= 30 -> Environment.isExternalStorageManager()
        Build.VERSION.SDK_INT >= 23 -> legacyPerms.all {
            checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
        else -> true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "f_locker/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "storageRoot" -> result.success(
                        Environment.getExternalStorageDirectory().absolutePath
                    )
                    "hasAccess" -> result.success(hasAccess())
                    "requestAccess" -> requestAccess(result)
                    "mediaScan" -> {
                        mediaScan(call.argument<List<String>>("paths") ?: emptyList())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (hasAccess()) {
            result.success("granted")
            return
        }
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
            result.success("settings")
        } else if (Build.VERSION.SDK_INT >= 23) {
            pending?.success("denied")
            pending = result
            requestPermissions(legacyPerms, 4242)
        } else {
            result.success("granted")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4242) {
            pending?.success(if (hasAccess()) "granted" else "denied")
            pending = null
        }
    }

    @Suppress("DEPRECATION")
    private fun mediaScan(paths: List<String>) {
        for (path in paths) {
            if (!File(path).exists()) {
                try {
                    contentResolver.delete(
                        MediaStore.Files.getContentUri("external"),
                        MediaStore.MediaColumns.DATA + "=?",
                        arrayOf(path)
                    )
                } catch (e: Exception) {
                }
            }
        }
        if (paths.isNotEmpty()) {
            MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
        }
    }
}
