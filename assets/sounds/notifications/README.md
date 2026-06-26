# Banco offline de áudios de notificação

Esta pasta contém os **toques de notificação embutidos no app** (estilo WhatsApp:
o usuário escolhe entre vários sons pré-instalados, sem precisar baixar nada).

## Arquivos no repositório

Os ficheiros `*.wav` curtos são **gerados localmente** a partir do script:

```bash
cd flutter_app
dart run tool/generate_notification_wavs.dart
```

Isto recria tons simples (beeps distintos) para cada entrada do catálogo. Para
sons mais ricos, substitua os `.wav` por versões suas (CC0 / licença livre),
mantendo **o mesmo nome de ficheiro** que em `lib/services/notification_sound_catalog.dart`.

## Onde os arquivos são usados

- **Preferências → Sons das notificações** — o usuário escolhe um som padrão
  para cada categoria (Escala, Compromisso, Audiência, Conta a pagar).
- **Criação / edição de evento** — em **Escala**, **Compromisso** e
  **Audiência** o usuário pode escolher um som *só para aquele item*,
  sobrescrevendo o padrão da categoria.

## Lista de ficheiros (`.wav`)

Os nomes precisam bater **exatamente** com `assetPath` em
`lib/services/notification_sound_catalog.dart`:

| Ficheiro | Rótulo na UI |
| -------- | ------------ |
| `pop_curto.wav` | Pop curto |
| `aviso_suave.wav` | Aviso suave |
| `sino_curto.wav` | Sino curto |
| `sino_triplo.wav` | Sino triplo |
| `alerta.wav` | Alerta |
| `beep_classico.wav` | Beep clássico |
| `duo_curto.wav` | Duo curto |
| `plim.wav` | Plim |
| `whatsapp_like.wav` | Notificação clássica |
| `sino_grave.wav` | Sino grave |
| `chime.wav` | Chime |
| `urgente.wav` | Urgente |

> **Aviso jurídico:** **não** use sons proprietários (WhatsApp, iMessage,
> etc.). Use somente áudios com licença livre (CC0 / domínio público) —
> Freesound, Pixabay Audio, Mixkit, etc. — ou gravados pela equipe.

## Para adicionar um som novo

1. Copie o `.wav` (ou `.mp3` / `.m4a`, ajustando o catálogo) para esta pasta.
2. Adicione uma entrada nova em
   `lib/services/notification_sound_catalog.dart`.
3. Rode `flutter pub get` e teste em
   *Preferências → Sons das notificações*.

## Sobre tocar em background

Quando o app está **aberto**, o som escolhido toca via `AudioPlayer`.
Quando o app está **fechado** no Android, o sistema usa o tom do
**canal Android** (limitação técnica). O lembrete continua a aparecer
sempre; o tom personalizado toca quando o usuário abre o app ou já
está com ele aberto.
