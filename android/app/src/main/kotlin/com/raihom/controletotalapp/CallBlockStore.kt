package com.wisdomapp.app

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * «Bloquear chamadas de desconhecidos» (SOMENTE ANDROID 10+).
 *
 * Guarda o liga/desliga e o contador de chamadas recusadas em SharedPreferences,
 * para o [CallBlockScreeningService] decidir mesmo com o Flutter fechado.
 *
 * Privacidade: nunca lê o conteúdo da ligação nem o histórico de chamadas — só
 * recebe do sistema o NÚMERO de quem liga e confere se ele está nos contatos.
 */
object CallBlockStore {
    private const val PREFS = "wisdomapp_call_block"
    private const val K_ENABLED = "enabled"
    private const val K_COUNT = "blocked_count"
    private const val K_LAST_AT = "last_blocked_at"
    private const val K_LOG = "blocked_log"
    private const val K_ALLOW_CONTACTS = "allow_contacts"
    private const val K_MODE = "mode"
    private const val K_ALLOW = "allow_list"
    private const val K_BLOCK = "block_list"

    /** Registros guardados (os mais antigos saem primeiro). */
    private const val MAX_LOG = 3000

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean(K_ENABLED, false)

    fun setEnabled(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(K_ENABLED, enabled).apply()
    }

    /** «Permitir contatos salvos» (padrão: sim). */
    fun allowContacts(ctx: Context): Boolean = prefs(ctx).getBoolean(K_ALLOW_CONTACTS, true)

    /** «O que fazer com a chamada»: "block" (recusa) ou "silence" (entra sem tocar). */
    fun mode(ctx: Context): String =
        if (prefs(ctx).getString(K_MODE, "block") == "silence") "silence" else "block"

    /** Números que SEMPRE podem ligar (digitados ou vindos do relatório). */
    fun allowList(ctx: Context): List<String> = readList(prefs(ctx), K_ALLOW)

    /** Números SEMPRE bloqueados com o filtro ligado (mesmo sendo contato). */
    fun blockList(ctx: Context): List<String> = readList(prefs(ctx), K_BLOCK)

    private fun readList(p: SharedPreferences, k: String): List<String> {
        val a = runCatching { JSONArray(p.getString(k, "[]") ?: "[]") }.getOrElse { JSONArray() }
        return (0 until a.length()).map { a.optString(it, "") }.filter { it.isNotBlank() }
    }

    private fun limpa(l: List<String>): String =
        JSONArray(l.map { it.trim() }.filter { it.isNotEmpty() }.distinct()).toString()

    /** Grava as preferências da tela «Bloqueio de chamadas» (Salvar). */
    fun saveConfig(
        ctx: Context,
        allowContacts: Boolean,
        mode: String,
        allow: List<String>,
        block: List<String>,
    ) {
        prefs(ctx).edit()
            .putBoolean(K_ALLOW_CONTACTS, allowContacts)
            .putString(K_MODE, if (mode == "silence") "silence" else "block")
            .putString(K_ALLOW, limpa(allow))
            .putString(K_BLOCK, limpa(block))
            .apply()
    }

    /** Põe [number] em «Números permitidos» (e tira dos bloqueados). */
    @Synchronized
    fun addAllowed(ctx: Context, number: String) {
        val p = prefs(ctx)
        val allow = readList(p, K_ALLOW).toMutableList()
        if (allow.none { sameNumber(it, number) }) allow.add(number.trim())
        val block = readList(p, K_BLOCK).filterNot { sameNumber(it, number) }
        p.edit().putString(K_ALLOW, limpa(allow)).putString(K_BLOCK, limpa(block)).apply()
    }

    /** Tira [number] do relatório (virou contato ou foi permitido). */
    @Synchronized
    fun removeFromLog(ctx: Context, number: String) {
        val p = prefs(ctx)
        val log = readLog(p)
        val novo = JSONArray()
        var tirados = 0
        for (i in 0 until log.length()) {
            val o = log.optJSONObject(i) ?: continue
            if (sameNumber(o.optString("n", ""), number)) tirados++ else novo.put(o)
        }
        p.edit()
            .putString(K_LOG, novo.toString())
            .putInt(K_COUNT, maxOf(0, p.getInt(K_COUNT, 0) - tirados))
            .apply()
    }

    /**
     * Mesmo número? DDD + últimos 8 dígitos (ignora +55, 0, operadora e o 9º
     * dígito; DDD diferente NÃO casa). Regra em [CallBlockNumbers].
     */
    fun sameNumber(a: String, b: String): Boolean = CallBlockNumbers.same(a, b)

    fun blockedCount(ctx: Context): Int = prefs(ctx).getInt(K_COUNT, 0)

    fun lastBlockedAt(ctx: Context): Long = prefs(ctx).getLong(K_LAST_AT, 0L)

    /**
     * Conta a recusa e guarda o registro (número + hora) para o relatório
     * do app. Fica só no aparelho — nada sai para o servidor.
     */
    @Synchronized
    fun registerBlocked(ctx: Context, number: String = "") {
        val p = prefs(ctx)
        val agora = System.currentTimeMillis()
        val log = readLog(p)
        log.put(JSONObject().put("n", number).put("t", agora))
        val corte = log.length() - MAX_LOG
        val guardado = if (corte > 0) {
            JSONArray().also { novo -> for (i in corte until log.length()) novo.put(log.get(i)) }
        } else {
            log
        }
        p.edit()
            .putInt(K_COUNT, p.getInt(K_COUNT, 0) + 1)
            .putLong(K_LAST_AT, agora)
            .putString(K_LOG, guardado.toString())
            .apply()
    }

    private fun readLog(p: SharedPreferences): JSONArray =
        runCatching { JSONArray(p.getString(K_LOG, "[]") ?: "[]") }.getOrElse { JSONArray() }

    /** Registros das chamadas recusadas: [{number, at}]. */
    fun blockedLog(ctx: Context): List<Map<String, Any>> {
        val log = readLog(prefs(ctx))
        return (0 until log.length()).mapNotNull { i ->
            val o = log.optJSONObject(i) ?: return@mapNotNull null
            mapOf("number" to o.optString("n", ""), "at" to o.optLong("t", 0L))
        }
    }

    fun resetCount(ctx: Context) {
        prefs(ctx).edit().putInt(K_COUNT, 0).putLong(K_LAST_AT, 0L).apply()
    }

    /** «Limpar registros»: apaga o histórico e zera o contador. */
    fun clearLog(ctx: Context) {
        prefs(ctx).edit().putInt(K_COUNT, 0).putLong(K_LAST_AT, 0L).remove(K_LOG).apply()
    }

    fun hasContactsPermission(ctx: Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * True se [number] é um contato salvo no aparelho. Sem a permissão de
     * contatos devolve null (não dá para saber) — quem chama deixa a ligação
     * passar, para nunca bloquear todo mundo por falta de permissão.
     */
    fun isKnownContact(ctx: Context, number: String): Boolean? {
        if (!hasContactsPermission(ctx)) return null
        if (number.isBlank()) return false
        return runCatching {
            // 1) PhoneLookup (índice do próprio Android, todas as contas: Google,
            //    aparelho, SIM importado…) com as formas comuns do número.
            var consultou = false
            for (v in CallBlockNumbers.lookupVariants(number)) {
                val achou = phoneLookup(ctx, v) ?: continue
                consultou = true
                if (achou) return@runCatching true
            }
            // 2) Varredura dos telefones salvos com a regra DDD + 8 dígitos (pega
            //    contato salvo sem DDD, sem o 9º dígito, com operadora etc.).
            val varreu = scanPhones(ctx, number) ?: return@runCatching if (consultou) false else null
            varreu
        }.getOrNull()
    }

    /** true/false = consultou; null = o provedor de contatos não respondeu. */
    private fun phoneLookup(ctx: Context, number: String): Boolean? {
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(number),
        )
        return ctx.contentResolver.query(
            uri,
            arrayOf(ContactsContract.PhoneLookup._ID),
            null,
            null,
            null,
        )?.use { it.moveToFirst() }
    }

    /** null = consulta falhou (quem chama deixa a ligação passar). */
    private fun scanPhones(ctx: Context, number: String): Boolean? {
        val alvo = CallBlockNumbers.canon(number) ?: return false
        val fim = alvo.sub8 ?: alvo.digits.takeLast(minOf(8, alvo.digits.length))
        if (fim.length < 3) return false
        val col = ContactsContract.CommonDataKinds.Phone.NUMBER
        val norm = ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER
        return ctx.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(col, norm),
            null,
            null,
            null,
        )?.use { c ->
            val iNum = c.getColumnIndex(col)
            val iNorm = c.getColumnIndex(norm)
            while (c.moveToNext()) {
                val n = if (iNum >= 0) c.getString(iNum).orEmpty() else ""
                val z = if (iNorm >= 0) c.getString(iNorm).orEmpty() else ""
                // Filtro barato antes da regra completa.
                if (!CallBlockNumbers.digitsOf(n).endsWith(fim) &&
                    !CallBlockNumbers.digitsOf(z).endsWith(fim)
                ) continue
                if (CallBlockNumbers.same(n, number) || CallBlockNumbers.same(z, number)) return@use true
            }
            false
        }
    }
}
