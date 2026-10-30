package cc.chenx.flclash

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import cc.chenx.flclash.common.GlobalState
import cc.chenx.flclash.common.QuickAction
import cc.chenx.flclash.common.quickIntent
import cc.chenx.flclash.common.toPendingIntent
import kotlinx.coroutines.launch

class ToggleWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, ServiceState.runState.value)
        GlobalState.launch { ServiceState.refresh() }
    }

    companion object {
        fun observe(context: Context) {
            GlobalState.launch {
                ServiceState.runState.collect { render(context, it) }
            }
        }

        private fun render(context: Context, runState: RunState) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ToggleWidget::class.java))
            if (ids.isEmpty()) return
            val views = RemoteViews(context.packageName, R.layout.widget_toggle).apply {
                setImageViewResource(
                    R.id.widget_toggle_icon,
                    if (runState == RunState.STARTED) R.drawable.widget_toggle_on else R.drawable.widget_toggle_off,
                )
                setTextViewText(
                    R.id.widget_toggle_label,
                    context.getString(
                        when (runState) {
                            RunState.STARTED -> R.string.widget_toggle_on
                            RunState.STOPPED -> R.string.widget_toggle_off
                            RunState.STARTING, RunState.STOPPING -> R.string.widget_toggle_busy
                        },
                    ),
                )
                setOnClickPendingIntent(R.id.widget_toggle_root, QuickAction.TOGGLE.quickIntent.toPendingIntent)
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
