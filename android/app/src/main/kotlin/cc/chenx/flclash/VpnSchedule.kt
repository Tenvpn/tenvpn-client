package cc.chenx.flclash

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.edit
import cc.chenx.flclash.common.GlobalState
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.util.Calendar

// The windows live here, not in Flutter, so the alarm works with the app closed
// and after a reboot. Same rules as lib/tenvpn/schedule.dart, which has the tests.
object VpnSchedule {
    private const val PREFS = "tenvpn_schedule"
    private const val KEY_SLOTS = "slots"
    const val ACTION_TICK = "cc.chenx.flclash.action.SCHEDULE_TICK"

    private data class Slot(val start: Int, val end: Int, val days: Set<Int>)

    fun update(context: Context, slotsJson: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            if (slotsJson == null) remove(KEY_SLOTS) else putString(KEY_SLOTS, slotsJson)
        }
        arm(context)
    }

    suspend fun tick(context: Context) {
        val slots = load(context) ?: return
        if (isActive(slots, Calendar.getInstance())) {
            GlobalState.log("Schedule: window opened, starting VPN")
            ServiceState.handleStartAction()
        } else {
            GlobalState.log("Schedule: window closed, stopping VPN")
            ServiceState.handleStopAction()
        }
        arm(context)
    }

    fun arm(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = tickIntent(context)
        val slots = load(context)
        val next = slots?.let { nextChange(it, Calendar.getInstance()) }
        if (next == null) {
            alarms.cancel(intent)
            return
        }
        // Inexact on purpose: exact alarms need a permission Play reviews; a
        // few minutes of drift is fine for «VPN in the evening».
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, intent)
        GlobalState.log("Schedule: next change at $next")
    }

    private fun tickIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, VpnScheduleReceiver::class.java).setAction(ACTION_TICK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun load(context: Context): List<Slot>? {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SLOTS, null) ?: return null
        return try {
            val array = JSONArray(json)
            List(array.length()) { i ->
                val slot = array.getJSONObject(i)
                val days = slot.getJSONArray("days")
                Slot(
                    start = slot.getInt("start"),
                    end = slot.getInt("end"),
                    days = List(days.length()) { days.getInt(it) }.toSet(),
                )
            }
        } catch (error: Exception) {
            GlobalState.log("Schedule: unreadable slots: $error")
            null
        }
    }

    private fun windowsAround(slots: List<Slot>, at: Calendar): List<Pair<Long, Long>> =
        (-1..7).flatMap { offset ->
            val day = (at.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                add(Calendar.DAY_OF_MONTH, offset)
            }
            // Calendar counts Sunday as 1; the schedule uses ISO, Monday as 1.
            val isoDay = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            slots.filter { isoDay in it.days }.map { slot ->
                val start = (day.clone() as Calendar).apply { add(Calendar.MINUTE, slot.start) }
                val end = (day.clone() as Calendar).apply {
                    if (slot.end <= slot.start) add(Calendar.DAY_OF_MONTH, 1)
                    add(Calendar.MINUTE, slot.end)
                }
                start.timeInMillis to end.timeInMillis
            }
        }

    private fun isActive(slots: List<Slot>, at: Calendar): Boolean {
        val now = at.timeInMillis
        return windowsAround(slots, at).any { (start, end) -> now in start until end }
    }

    private fun nextChange(slots: List<Slot>, at: Calendar): Long? {
        val now = at.timeInMillis
        val active = isActive(slots, at)
        return windowsAround(slots, at)
            .flatMap { listOf(it.first, it.second) }
            .filter { it > now }
            .distinct()
            .sorted()
            .firstOrNull { edge ->
                isActive(slots, (at.clone() as Calendar).apply { timeInMillis = edge }) != active
            }
    }
}

class VpnScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        GlobalState.launch {
            try {
                if (intent.action == VpnSchedule.ACTION_TICK) {
                    VpnSchedule.tick(context)
                } else {
                    VpnSchedule.arm(context)
                }
            } catch (error: Exception) {
                GlobalState.log("Schedule: ${intent.action} failed: $error")
            } finally {
                pending.finish()
            }
        }
    }
}
