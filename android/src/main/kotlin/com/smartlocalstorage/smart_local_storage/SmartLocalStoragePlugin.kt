package com.smartlocalstorage.smart_local_storage

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** SmartLocalStoragePlugin — returns the app's private files directory path.
 *  This is the same directory Android gives every app for its own files;
 *  we read it directly instead of depending on a pub.dev package. */
class SmartLocalStoragePlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private var filesDirPath: String? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "smart_local_storage")
    channel.setMethodCallHandler(this)
    filesDirPath = flutterPluginBinding.applicationContext.filesDir.path
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "getDocumentsPath") {
      result.success(filesDirPath)
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
