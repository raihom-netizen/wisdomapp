package com.wisdomapp.app

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telephony.TelephonyManager
import androidx.annotation.RequiresApi

/**
 * Recusa ligações RECEBIDAS de números que não estão nos contatos do aparelho
 * (Configurações → «Bloquear chamadas de desconhecidos»).
 *
 * Só funciona quando o usuário escolhe o WISDOMAPP como app de triagem de
 * chamadas (RoleManager.ROLE_CALL_SCREENING, Android 10+). Não usa
 * READ_CALL_LOG nem READ_PHONE_STATE: o sistema entrega apenas o número de
 * quem liga (Call.Details.handle). A chamada recusada continua no histórico do
 * telefone (setSkipCallLog(false)) para o usuário poder conferir.
 *
 * Regras de segurança (ordem):
 * - Filtro desligado ou chamada feita (não recebida) → deixa passar.
 * - Emergência/utilidade pública (190, 192, 193, 112…) → sempre passa.
 * - «Números permitidos» → passa; «Números bloqueados» → cai.
 * - Sem permissão de contatos ou consulta com falha → deixa passar
 *   (nunca bloqueia todo mundo).
 * - Número oculto/privado → recusa (não está nos contatos).
 * - Contato salvo (PhoneLookup + varredura DDD + 8 dígitos) → passa.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class CallBlockScreeningService : CallScreeningService() {

    override fun onScreenCall(details: Call.Details) {
        // Qualquer erro inesperado → deixa a ligação passar (nunca derruba
        // chamada por falha do app) e o sistema sempre recebe uma resposta.
        val (bloquear, number) = try {
            decide(details)
        } catch (_: Throwable) {
            false to ""
        }
        if (!bloquear) {
            respondToCall(details, allow())
            return
        }
        runCatching { CallBlockStore.registerBlocked(this, number) }
        val mode = runCatching { CallBlockStore.mode(this) }.getOrDefault("block")
        respondToCall(details, deny(mode))
    }

    /** (bloquear?, número). */
    private fun decide(details: Call.Details): Pair<Boolean, String> {
        val incoming = details.callDirection == Call.Details.DIRECTION_INCOMING
        if (!incoming || !CallBlockStore.isEnabled(this)) return false to ""
        val number = details.handle?.schemeSpecificPart?.trim().orEmpty()

        // 0) Emergência / utilidade pública (190, 192, 193, 112…) nunca cai —
        //    nem se estiver em «Números bloqueados».
        if (number.isNotEmpty() && isEmergency(number)) return false to number

        // 1) «Números permitidos» sempre passam.
        if (number.isNotEmpty() && CallBlockStore.allowList(this).any { CallBlockStore.sameNumber(it, number) }) {
            return false to number
        }
        // 2) «Números bloqueados» (digitados) caem mesmo sendo contato.
        if (number.isNotEmpty() && CallBlockStore.blockList(this).any { CallBlockStore.sameNumber(it, number) }) {
            return true to number
        }
        // 3) Contato salvo passa quando «Permitir contatos salvos» está ligado.
        //    Sem permissão de contatos (negada/revogada) ou consulta com falha →
        //    deixa passar, inclusive oculto (nunca bloqueia todo mundo por falta
        //    de permissão; o card de Configurações avisa «Precisa de permissão»).
        //    Com permissão, oculto/privado nunca é contato → bloqueia.
        val allowContacts = CallBlockStore.allowContacts(this)
        val known: Boolean? = when {
            !allowContacts -> false
            !CallBlockStore.hasContactsPermission(this) -> null
            number.isEmpty() -> false
            else -> CallBlockStore.isKnownContact(this, number)
        }
        return (known == false) to number
    }

    private fun isEmergency(number: String): Boolean {
        if (CallBlockNumbers.isEmergencyShort(number)) return true
        return runCatching {
            getSystemService(TelephonyManager::class.java)?.isEmergencyNumber(number) == true
        }.getOrDefault(false)
    }

    private fun allow(): CallResponse =
        CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()

    /**
     * «Bloquear»: recusa (como ocupado). «Silenciar»: a ligação entra sem
     * tocar e fica no histórico para retornar depois.
     */
    private fun deny(mode: String): CallResponse =
        if (mode == "silence") {
            CallResponse.Builder()
                .setSilenceCall(true)
                .setDisallowCall(false)
                .setRejectCall(false)
                .setSkipCallLog(false)
                .setSkipNotification(false)
                .build()
        } else {
            CallResponse.Builder()
                .setDisallowCall(true)
                .setRejectCall(true)
                .setSkipCallLog(false)
                .setSkipNotification(false)
                .build()
        }
}
