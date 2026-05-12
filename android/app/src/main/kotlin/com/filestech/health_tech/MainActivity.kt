package com.filestech.health_tech

import android.content.ContentUris
import android.content.ContentValues
import android.os.Bundle
import android.provider.CalendarContract
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity (rather than FlutterActivity) is required by
/// androidx.biometric.BiometricPrompt, which expects a FragmentActivity to
/// host its prompt fragment.
class MainActivity : FlutterFragmentActivity() {

    private val secureChannel  = "com.filestech.health_tech/secure_window"
    private val calendarChannel = "com.filestech.health_tech/calendar_sync"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Secure window ──────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        runOnUiThread {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE,
                            )
                        }
                        result.success(true)
                    }
                    "disable" -> {
                        // FLAG_SECURE is non-negotiable for wellness/health data.
                        result.error("forbidden", "FLAG_SECURE cannot be cleared", null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Calendar sync (direct ContentResolver — device_calendar 4.3.3   ──
        //    deserialises Calendar objects as all-null on Samsung Android 14,  ──
        //    so we bypass its retrieval/insert methods entirely)               ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, calendarChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFirstWritableCalendarId" -> getFirstWritableCalendarId(result)
                    "createOrUpdateEvent"        -> createOrUpdateEvent(call, result)
                    "deleteEvent"                -> deleteEvent(call, result)
                    else                         -> result.notImplemented()
                }
            }

        // ── Biometric bridge ────────────────────────────────────────────────
        BiometricBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    // ── Calendar helpers ───────────────────────────────────────────────────────

    private fun getFirstWritableCalendarId(result: MethodChannel.Result) {
        try {
            val projection  = arrayOf(CalendarContract.Calendars._ID)
            // ACCESS_CONTRIBUTOR (600) and above are writable; ACCESS_OWNER = 700
            val selection   = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"
            val selArgs     = arrayOf("500")
            val cursor = contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection, selection, selArgs,
                "${CalendarContract.Calendars._ID} ASC",
            )
            var calId: String? = null
            cursor?.use { if (it.moveToFirst()) calId = it.getLong(0).toString() }
            result.success(calId)
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun createOrUpdateEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args       = call.arguments as? Map<*, *> ?: throw Exception("args required")
            val calendarId = args["calendarId"] as? String ?: throw Exception("calendarId required")
            val eventId    = args["eventId"]    as? String
            val title      = args["title"]      as? String ?: "Health Tech"
            val startMs    = (args["startMs"] as? Long) ?: (args["startMs"] as? Int)?.toLong()
                             ?: throw Exception("startMs required")
            val endMs      = (args["endMs"]   as? Long) ?: (args["endMs"]   as? Int)?.toLong()
                             ?: throw Exception("endMs required")
            val timeZone   = args["timeZone"]   as? String ?: "UTC"

            val values = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID,    calendarId.toLong())
                put(CalendarContract.Events.TITLE,          title)
                put(CalendarContract.Events.DTSTART,        startMs)
                put(CalendarContract.Events.DTEND,          endMs)
                put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
            }

            if (eventId != null) {
                val uri = ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI, eventId.toLong(),
                )
                contentResolver.update(uri, values, null, null)
                result.success(eventId)
            } else {
                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                    ?: throw Exception("ContentResolver.insert returned null")
                result.success(uri.lastPathSegment)
            }
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun deleteEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args    = call.arguments as? Map<*, *> ?: throw Exception("args required")
            val eventId = args["eventId"] as? String ?: throw Exception("eventId required")
            val uri     = ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI, eventId.toLong(),
            )
            contentResolver.delete(uri, null, null)
            result.success(null)
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }
}
