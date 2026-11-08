package cc.chenx.flclash

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.core.content.pm.ShortcutManagerCompat
import cc.chenx.flclash.common.GlobalState
import cc.chenx.flclash.common.QuickAction
import cc.chenx.flclash.common.action
import kotlinx.coroutines.launch

class QuickActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent.action) {
            QuickAction.START.action -> startOrOpenApp { ServiceState.handleStartAction() }
            QuickAction.STOP.action -> GlobalState.launch { ServiceState.handleStopAction() }
            QuickAction.TOGGLE.action -> {
                ShortcutManagerCompat.reportShortcutUsed(this, SHORTCUT_ID)
                startOrOpenApp { ServiceState.handleToggleAction() }
            }
        }
        finish()
    }

    private fun startOrOpenApp(action: suspend () -> Unit) {
        if (ServiceState.startNeedsApp()) {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
        } else {
            GlobalState.launch { action() }
        }
    }

    private companion object {
        const val SHORTCUT_ID = "toggle"
    }
}
