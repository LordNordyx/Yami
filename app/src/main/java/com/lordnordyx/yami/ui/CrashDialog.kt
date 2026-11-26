package com.lordnordyx.yami.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lordnordyx.yami.ui.theme.Mono

/** Shows a crash report with copy/share so it can be sent for debugging. */
@Composable
fun CrashDialog(report: String?, onDismiss: () -> Unit) {
    report ?: return
    val ctx = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("The game crashed") },
        text = {
            Column {
                Text("Copy or share this report so the crash can be fixed.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.heightIn(max = 380.dp).verticalScroll(rememberScrollState())) {
                    Row(Modifier.horizontalScroll(rememberScrollState())) {
                        Text(report, fontFamily = Mono, fontSize = 10.sp, lineHeight = 13.sp)
                    }
                }
            }
        },
        confirmButton = {
            TextButton({
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Yami crash report", report))
            }) { Text("Copy") }
            TextButton({
                ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, "Yami crash report")
                    putExtra(Intent.EXTRA_TEXT, report)
                }, "Share crash report").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }) { Text("Share") }
        },
        dismissButton = { TextButton(onDismiss) { Text("Close") } },
    )
}
