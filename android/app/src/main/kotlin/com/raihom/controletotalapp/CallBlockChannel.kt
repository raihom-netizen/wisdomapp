package com.wisdomapp.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Canal `br.com.wisdomapp/call_block` — Configurações → «Bloquear chamadas de
 * desconhecidos» (SOMENTE ANDROID 10+). Cópia do Controle Total (MainActivity),
 * isolada aqui para a [MainActivity] só registrar e repassar os resultados.
 *
 * Quem decide a ligação é o [CallBlockScreeningService] (funciona com o app
 * fechado); este canal só liga/desliga, pede permissões e lê o relatório.
 */
class CallBlockChannel(private val activity: Activity) {

    companion object {
        const val CHANNEL = "br.com.wisdomapp/call_block"
        private const val RC_ROLE = 8801
        private const val RC_CONTACTS = 8802
        private const val RC_ADD_CONTACT = 8803
    }

    private val ctx get() = activity.applicationContext

    private var pendingRole: MethodChannel.Result? = null
    private var pendingContacts: MethodChannel.Result? = null
    private var pendingAddContact: MethodChannel.Result? = null
    private var pendingAddContactNumber: String = ""

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(status())
                "setEnabled" -> {
                    CallBlockStore.setEnabled(ctx, call.argument<Boolean>("enabled") == true)
                    result.success(status())
                }
                "requestRole" -> requestRole(result)
                "requestContactsPermission" -> requestContacts(result)
                "resetCount" -> {
                    CallBlockStore.resetCount(ctx)
                    result.success(status())
                }
                "getLog" -> result.success(CallBlockStore.blockedLog(ctx))
                "getConfig" -> result.success(config())
                "saveConfig" -> {
                    CallBlockStore.saveConfig(
                        ctx,
                        allowContacts = call.argument<Boolean>("allowContacts") != false,
                        mode = call.argument<String>("mode") ?: "block",
                        allow = call.argument<List<String>>("allow") ?: emptyList(),
                        block = call.argument<List<String>>("block") ?: emptyList(),
                    )
                    result.success(config())
                }
                "allowNumber" -> {
                    val n = call.argument<String>("number").orEmpty()
                    if (n.isNotBlank()) {
                        CallBlockStore.addAllowed(ctx, n)
                        CallBlockStore.removeFromLog(ctx, n)
                    }
                    result.success(config())
                }
                "addContact" -> addContact(call.argument<String>("number").orEmpty(), result)
                "clearLog" -> {
                    CallBlockStore.clearLog(ctx)
                    result.success(status())
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", activity.packageName, null),
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun roleManager(): android.app.role.RoleManager? =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            null
        } else {
            activity.getSystemService(android.app.role.RoleManager::class.java)
        }

    private fun roleAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val rm = roleManager() ?: return false
        return runCatching {
            rm.isRoleAvailable(android.app.role.RoleManager.ROLE_CALL_SCREENING)
        }.getOrDefault(false)
    }

    private fun roleHeld(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val rm = roleManager() ?: return false
        return runCatching {
            rm.isRoleAvailable(android.app.role.RoleManager.ROLE_CALL_SCREENING) &&
                rm.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)
        }.getOrDefault(false)
    }

    private fun config(): Map<String, Any> = mapOf(
        "allowContacts" to CallBlockStore.allowContacts(ctx),
        "mode" to CallBlockStore.mode(ctx),
        "allow" to CallBlockStore.allowList(ctx),
        "block" to CallBlockStore.blockList(ctx),
    )

    private fun status(): Map<String, Any> = mapOf(
        "sdkInt" to Build.VERSION.SDK_INT,
        "supported" to roleAvailable(),
        "roleHeld" to roleHeld(),
        "contactsGranted" to CallBlockStore.hasContactsPermission(ctx),
        "enabled" to CallBlockStore.isEnabled(ctx),
        "blockedCount" to CallBlockStore.blockedCount(ctx),
        "lastBlockedAt" to CallBlockStore.lastBlockedAt(ctx),
    )

    /** Abre «Novo contato» já com o número; na volta, se virou contato, sai do relatório. */
    private fun addContact(number: String, result: MethodChannel.Result) {
        if (number.isBlank()) {
            result.success(false)
            return
        }
        try {
            pendingAddContact?.success(false)
            pendingAddContact = result
            pendingAddContactNumber = number
            val intent = Intent(ContactsContract.Intents.Insert.ACTION).apply {
                type = ContactsContract.RawContacts.CONTENT_TYPE
                putExtra(ContactsContract.Intents.Insert.PHONE, number)
                putExtra("finishActivityOnSaveCompleted", true)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, RC_ADD_CONTACT)
        } catch (_: Exception) {
            pendingAddContact = null
            result.success(false)
        }
    }

    /** Tela do sistema para escolher o app como triagem de chamadas. */
    private fun requestRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !roleAvailable()) {
            result.success(false)
            return
        }
        if (roleHeld()) {
            result.success(true)
            return
        }
        val rm = roleManager()
        if (rm == null) {
            result.success(false)
            return
        }
        try {
            pendingRole?.success(false)
            pendingRole = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                rm.createRequestRoleIntent(android.app.role.RoleManager.ROLE_CALL_SCREENING),
                RC_ROLE,
            )
        } catch (_: Exception) {
            pendingRole = null
            result.success(false)
        }
    }

    private fun requestContacts(result: MethodChannel.Result) {
        if (CallBlockStore.hasContactsPermission(ctx)) {
            result.success(true)
            return
        }
        try {
            pendingContacts?.success(false)
            pendingContacts = result
            androidx.core.app.ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.READ_CONTACTS),
                RC_CONTACTS,
            )
        } catch (_: Exception) {
            pendingContacts = null
            result.success(false)
        }
    }

    /** Repassado pela [MainActivity.onActivityResult]. */
    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode == RC_ROLE) {
            pendingRole?.success(roleHeld())
            pendingRole = null
        }
        if (requestCode == RC_ADD_CONTACT) {
            val n = pendingAddContactNumber
            val virou = resultCode == Activity.RESULT_OK ||
                CallBlockStore.isKnownContact(ctx, n) == true
            if (virou) CallBlockStore.removeFromLog(ctx, n)
            pendingAddContact?.success(virou)
            pendingAddContact = null
            pendingAddContactNumber = ""
        }
    }

    /** Repassado pela [MainActivity.onRequestPermissionsResult]. */
    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode == RC_CONTACTS) {
            pendingContacts?.success(CallBlockStore.hasContactsPermission(ctx))
            pendingContacts = null
        }
    }
}
