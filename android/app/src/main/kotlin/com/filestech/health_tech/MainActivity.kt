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

    private companion object {
        // Couleur ocre des événements Health Tech dans le Calendar Android.
        // Argument ARGB de `CalendarContract.Events.EVENT_COLOR`.
        const val EVENT_COLOR_OCHRE = 0xFFE07B39.toInt()
        // _SYNC_ID préfixe qui signe les events posés par Health Tech.
        // Permet de distinguer nos events des autres au moment du
        // anti-doublon (cf. findExistingEventId).
        const val SYNC_ID_PREFIX = "healthtech:"
    }

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
            val accessFilter = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"

            // Pass 1 — prefer a real Google account (syncs with Google Agenda).
            val googleSel  = "$accessFilter AND ${CalendarContract.Calendars.ACCOUNT_TYPE} = ?"
            var calId: String? = null
            contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection, googleSel, arrayOf("500", "com.google"),
                "${CalendarContract.Calendars._ID} ASC",
            )?.use { if (it.moveToFirst()) calId = it.getLong(0).toString() }

            // Pass 2 — fallback to any writable calendar (local, Exchange, etc.)
            if (calId == null) {
                contentResolver.query(
                    CalendarContract.Calendars.CONTENT_URI,
                    projection, accessFilter, arrayOf("500"),
                    "${CalendarContract.Calendars._ID} ASC",
                )?.use { if (it.moveToFirst()) calId = it.getLong(0).toString() }
            }

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
            val calendarIdLong = calendarId.toLongOrNull()
                ?: throw Exception("calendarId not a valid long")
            val eventId    = args["eventId"]    as? String
            val title      = args["title"]      as? String ?: "Health Tech"
            val startMs    = (args["startMs"] as? Long) ?: (args["startMs"] as? Int)?.toLong()
                             ?: throw Exception("startMs required")
            val endMs      = (args["endMs"]   as? Long) ?: (args["endMs"]   as? Int)?.toLong()
                             ?: throw Exception("endMs required")
            val timeZone   = args["timeZone"]   as? String ?: "UTC"
            // ownerId : identifiant logique côté Dart (sessionId ou
            // appointmentId). Sert à signer l'event via CUSTOM_APP_URI
            // pour que findEventBySyncId() reconnaisse uniquement nos
            // events (audit code H3 — anti-collision data-loss
            // inter-événement). On utilise CUSTOM_APP_PACKAGE + CUSTOM_APP_URI
            // car les colonnes SYNC_DATA1-10 sont RESERVÉES aux sync adapters
            // par Android — un app standard se prend une IllegalArgumentException
            // au insert. CUSTOM_APP_* est explicitement prévu pour les apps tierces.
            val ownerId    = args["ownerId"]    as? String
            val syncId     = ownerId?.let { SYNC_ID_PREFIX + it }

            val values = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID,    calendarIdLong)
                put(CalendarContract.Events.TITLE,          title)
                put(CalendarContract.Events.DTSTART,        startMs)
                put(CalendarContract.Events.DTEND,          endMs)
                put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
                put(CalendarContract.Events.EVENT_COLOR,    EVENT_COLOR_OCHRE)
                if (syncId != null) {
                    put(CalendarContract.Events.CUSTOM_APP_PACKAGE, packageName)
                    put(CalendarContract.Events.CUSTOM_APP_URI,     syncId)
                }
            }

            // 1) Si eventId connu, tente un update direct.
            if (eventId != null) {
                val resolvedLong = eventId.toLongOrNull()
                if (resolvedLong != null) {
                    val uri = ContentUris.withAppendedId(
                        CalendarContract.Events.CONTENT_URI, resolvedLong,
                    )
                    val rowsUpdated = contentResolver.update(uri, values, null, null)
                    if (rowsUpdated > 0) {
                        result.success(eventId)
                        return
                    }
                    // 0 row affected → event supprimé manuellement par
                    // l'utilisateur dans Google Calendar. On tombe en
                    // re-create plutôt que de laisser un id mort en DB.
                }
            }

            // 2) Pas d'eventId ou update no-op → cherche un event existant
            //    signé par notre _SYNC_ID (anti-doublon non-destructif).
            val byMarker = syncId?.let { findEventBySyncId(calendarIdLong, it) }
            if (byMarker != null) {
                val uri = ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI, byMarker,
                )
                contentResolver.update(uri, values, null, null)
                result.success(byMarker.toString())
                return
            }

            // 3) Compat v1.4.5 / v1.5.0 : un event posé avant que le
            //    marqueur CUSTOM_APP_URI existe peut être ré-attrapé par
            //    son créneau. On le re-signe au passage pour que la
            //    prochaine sync passe par le chemin (2) au-dessus.
            val legacy = findExistingEventByTime(calendarIdLong, startMs, endMs)
            if (legacy != null) {
                val uri = ContentUris.withAppendedId(
                    CalendarContract.Events.CONTENT_URI, legacy,
                )
                contentResolver.update(uri, values, null, null)
                result.success(legacy.toString())
                return
            }

            // 4) Sinon, insert.
            val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                ?: throw Exception("ContentResolver.insert returned null")
            result.success(uri.lastPathSegment)
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }

    /// Cherche un event existant signé par notre marqueur dans
    /// CUSTOM_APP_URI + CUSTOM_APP_PACKAGE. Évite la collision sur
    /// (calendar_id, dtstart, dtend) si l'utilisateur a 2 RDV strictement
    /// aux mêmes horaires (audit code H3).
    private fun findEventBySyncId(calendarIdLong: Long, syncId: String): Long? {
        val projection = arrayOf(CalendarContract.Events._ID)
        val sel = "${CalendarContract.Events.CALENDAR_ID} = ? AND " +
                  "${CalendarContract.Events.CUSTOM_APP_PACKAGE} = ? AND " +
                  "${CalendarContract.Events.CUSTOM_APP_URI} = ? AND " +
                  "${CalendarContract.Events.DELETED} = 0"
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection, sel,
            arrayOf(calendarIdLong.toString(), packageName, syncId),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        return null
    }

    /// Compat v1.4.5 : retrouve un event posé avant l'introduction du
    /// marqueur SYNC_DATA1, identifié uniquement par son créneau.
    /// N'est consulté qu'après l'échec du chemin marqueur, pour ne pas
    /// dégénérer en overwrite d'event tiers (audit code H3).
    private fun findExistingEventByTime(
        calendarIdLong: Long,
        startMs: Long,
        endMs: Long,
    ): Long? {
        val projection = arrayOf(CalendarContract.Events._ID)
        val sel = "${CalendarContract.Events.CALENDAR_ID} = ? AND " +
                  "${CalendarContract.Events.DTSTART} = ? AND " +
                  "${CalendarContract.Events.DTEND} = ? AND " +
                  "${CalendarContract.Events.DELETED} = 0"
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection, sel,
            arrayOf(calendarIdLong.toString(), startMs.toString(), endMs.toString()),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        return null
    }

    @Suppress("UNCHECKED_CAST")
    private fun deleteEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args    = call.arguments as? Map<*, *> ?: throw Exception("args required")
            val eventId = args["eventId"] as? String ?: throw Exception("eventId required")
            val eventIdLong = eventId.toLongOrNull()
                ?: throw Exception("eventId not a valid long")
            val uri     = ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI, eventIdLong,
            )
            // Remontée du nombre de lignes affectées au Dart pour
            // permettre un fallback explicite si l'event a déjà été
            // effacé manuellement par l'utilisateur (audit code H4).
            val rowsDeleted = contentResolver.delete(uri, null, null)
            result.success(rowsDeleted)
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }
}
