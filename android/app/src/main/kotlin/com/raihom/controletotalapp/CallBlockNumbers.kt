package com.wisdomapp.app

/**
 * Comparação de telefones do «Bloquear chamadas de desconhecidos».
 *
 * Kotlin puro (sem Android) — a MESMA regra está em Dart em
 * `lib/services/call_block_numbers.dart`, coberta por `test/call_block_numbers_test.dart`.
 * Mudou aqui? Mude lá também.
 *
 * Regra (Brasil):
 * - tira tudo que não é dígito; `+55`/`0055`, o `0` de longa distância e o código
 *   da operadora (`0 41 62 …`) saem;
 * - sobra DDD (2 dígitos, opcional) + assinante; do assinante valem os ÚLTIMOS 8
 *   dígitos (o 9º dígito do celular não atrapalha: «9999-9999» = «99999-9999»);
 * - dois números são o mesmo quando os 8 finais batem E o DDD bate (ou um deles
 *   foi salvo sem DDD);
 * - números curtos (190, 192, 1052…) só com igualdade exata;
 * - estrangeiros (+1, +351…) comparam os dígitos completos.
 */
object CallBlockNumbers {

    /** Serviços de emergência / utilidade pública do Brasil + 112/911. Nunca bloqueados. */
    val EMERGENCIA: Set<String> = setOf(
        "100", "112", "128", "136", "153", "180", "181", "185", "188", "190", "191", "192",
        "193", "194", "197", "198", "199", "911",
    )

    data class Canon(
        /** DDD (2 dígitos) ou null quando o número veio sem DDD. */
        val ddd: String?,
        /** Últimos 8 dígitos do assinante (sem o 9º dígito), ou null para curto/estrangeiro. */
        val sub8: String?,
        /** Assinante completo (8 ou 9 dígitos), ou null. */
        val sub: String?,
        /** Dígitos usados na comparação exata (curto/estrangeiro). */
        val digits: String,
        val foreign: Boolean,
    )

    fun digitsOf(s: String): String = s.filter { it in '0'..'9' }

    fun canon(raw: String?): Canon? {
        val t = raw?.trim().orEmpty()
        var d = digitsOf(t)
        if (d.isEmpty()) return null
        var intl = t.startsWith("+")
        if (!intl && d.startsWith("00") && d.length > 4) {
            intl = true
            d = d.drop(2)
        }
        if (intl) {
            if (!d.startsWith("55")) return Canon(null, null, null, d, foreign = true)
            d = d.drop(2)
        } else if (d.startsWith("0") && d.length >= 10) {
            d = d.drop(1)
            // 0 + operadora (2) + DDD + número
            if (d.length == 12 || d.length == 13) d = d.drop(2)
        } else if (d.startsWith("55") && (d.length == 12 || d.length == 13)) {
            d = d.drop(2)
        }
        return when (d.length) {
            10, 11 -> {
                val sub = d.drop(2)
                Canon(d.take(2), sub.takeLast(8), sub, d, foreign = false)
            }
            8, 9 -> Canon(null, d.takeLast(8), d, d, foreign = false)
            else -> Canon(null, null, null, d, foreign = d.length > 11)
        }
    }

    /** Mesmo telefone? Ver a regra no topo do arquivo. */
    fun same(a: String?, b: String?): Boolean {
        val ca = canon(a) ?: return false
        val cb = canon(b) ?: return false
        if (ca.sub8 != null && cb.sub8 != null) {
            if (ca.sub8 != cb.sub8) return false
            return ca.ddd == null || cb.ddd == null || ca.ddd == cb.ddd
        }
        if (ca.digits == cb.digits) return true
        // Estrangeiro salvo sem «+» (ou com 0 a mais): um termina com o outro, mínimo 8 dígitos.
        if (ca.foreign || cb.foreign) {
            val (curto, longo) = if (ca.digits.length <= cb.digits.length) ca.digits to cb.digits else cb.digits to ca.digits
            return curto.length >= 8 && longo.endsWith(curto)
        }
        return false
    }

    /** Número de emergência/utilidade pública (nunca bloquear). */
    fun isEmergencyShort(raw: String?): Boolean {
        val d = digitsOf(raw.orEmpty())
        return d.isNotEmpty() && d.length <= 3 && d in EMERGENCIA
    }

    /**
     * Formas de escrever o número para o `PhoneLookup` (o contato pode estar salvo
     * com/sem +55, com/sem DDD, com/sem o 9º dígito). A primeira é a original.
     */
    fun lookupVariants(raw: String): List<String> {
        val out = LinkedHashSet<String>()
        val t = raw.trim()
        if (t.isNotEmpty()) out.add(t)
        val c = canon(t) ?: return out.toList()
        if (c.foreign || c.sub == null) return out.toList()
        val subs = LinkedHashSet<String>()
        subs.add(c.sub)
        if (c.sub.length == 9 && c.sub.startsWith("9")) subs.add(c.sub.drop(1))
        if (c.sub.length == 8 && c.sub[0] in '6'..'9') subs.add("9" + c.sub)
        for (s in subs) {
            if (c.ddd != null) {
                out.add("+55${c.ddd}$s")
                out.add("${c.ddd}$s")
                out.add("0${c.ddd}$s")
            }
            out.add(s)
        }
        return out.toList()
    }
}
