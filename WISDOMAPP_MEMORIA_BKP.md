# WISDOMAPP — MEMÓRIA / BACKUP DO PROJETO

> **Ponto de partida oficial** para melhorias, correções e deploys.  
> **Data do snapshot:** 02/08/2026 · **Release:** `10.05+26` (marketing `10.05`, build `26`, iOS build base `26`)  
> **Repositório:** `c:\WISDOMAPP` · **Firebase:** `wisdomapp-b9e98`  
> **Memória:** ficheiro único na raiz — **`WISDOMAPP_MEMORIA_BKP.md`** — **não** duplicar em `D:\TEMPORARIOS`.  
> **Referência de padrão (paridade):** Controle Total em `C:\Controletotalapp_Independente\flutter_app`.

---

## 0. COMO USAR ESTE ARQUIVO (OBRIGATÓRIO)

Este documento é a **memória viva** do que já está pronto e funcionando. Antes de qualquer alteração:

1. **Consultar este arquivo** — entender o que existe e onde está.
2. **Alteração mínima** — corrigir só o pedido; não refatorar módulos inteiros sem necessidade.
3. **Não retroagir** — não remover, simplificar ou “limpar” funcionalidades que já funcionam.
4. **Preservar padrões** — versão única, OAuth calendário, player de cursos, grid admin compacta, boot web leve, etc.
5. **Testar impacto cruzado** — web + Android + iOS quando tocar auth, versão, push, calendário ou deploy.
6. **Atualizar este arquivo** — após mudanças relevantes, registrar o que mudou na seção 16 (changelog memória). **Ficheiro fica só na raiz** (`WISDOMAPP_MEMORIA_BKP.md`); não copiar para `D:\TEMPORARIOS`.
7. **Deploy só com ordem explícita** — roteiro oficial na seção **«Deploy completo (padrão Controle Total)»** (fim do arquivo): versão → commit escopado → push nas branches de build → `.\deploy.ps1 -WebOnly` (só hosting) → functions escopadas → `.\build_aab_release.ps1` → iOS no GitHub Actions (start do dono). Codemagic = legado.

**Gatilhos de cautela extra (não quebrar):**

| Área | Arquivo(s) sensível(is) | Risco se mexer errado |
|------|-------------------------|------------------------|
| Versão multi-plataforma | `lib/constants/app_version.dart`, `scripts/sync_app_version.ps1` | Desalinhamento web/Android/iOS, erro 90189 iOS |
| Force update | `app_config/version`, `force_version_online.ps1` | Usuários presos ou sem atualização |
| **Boot web Flutter** | `web/flutter_bootstrap.js`, `web/index.html`, `deploy.ps1`, `Validate-HostingPreDeploy.ps1` | **Splash eterno** se remover `_flutter.loader.load()` do bootstrap (index **não** chama `load()`) |
| Google Calendar OAuth | `google_calendar_oauth_mobile.dart`, `web/google_calendar_oauth.html`, `functions/googleCalendarOAuth.js` | `UnimplementedError`, sync quebrada |
| Apple Calendar | `apple_calendar_sync_service.dart`, `Info.plist` permissões | EventKit negado no iOS |
| Player cursos | `course_video_player_shell.dart`, embeds web/mobile | Tela preta no vídeo |
| Dicas admin grid | `admin_tip_grid_card.dart` | Cards grandes de novo |
| HomeShell lazy | `home_shell.dart` `_materializedModuleIndices` | Memória/streams duplicados |
| Financeiro instantâneo | `finance_instant_prefetch_service.dart`, `finance_month_cache.dart`, `finance_transactions_hub.dart` | Lista lenta / cache zerado |
| Firestore offline web | `main.dart` `_configureFirebaseCore` long-polling | Crash Safari / assert SDK |
| Domínio custom Hosting | DNS TXT `hosting-site=wisdomapp-b9e98` + Firebase customDomains | Apex OK (02/08); se TXT sumir → 404 / `OWNERSHIP_MISSING` |
| Sync calendário auto | `external_calendar_scheduled_sync.dart`, `external_calendar_bidirectional_sync.dart` | Sync 00:00/12:00 ou chip Sync quebrados |
| Deploy | `deploy.ps1` | Versão errada online / web quebrada |
| Codemagic iOS | `codemagic.yaml`, `scripts/codemagic_ios_*.sh` | Rejeição App Store 90189 |

---

## 1. IDENTIDADE DO PROJETO

| Campo | Valor |
|-------|-------|
| Nome comercial | WISDOMAPP / WISDOM APP |
| Package Flutter | `controle_total_premium` |
| Android `applicationId` | `com.wisdomapp.app` |
| iOS `BUNDLE_ID` | `com.wisdomapp` |
| iOS Widget Extension | `com.wisdomapp.WisdomappWidget` |
| iOS App Group | `group.com.wisdomapp.widget` |
| Domínio produção (custom) | `https://wisdomapp.com.br` (e `www`) — ver §10.4 DNS |
| Hosting Firebase (sempre) | `https://wisdomapp-b9e98.web.app` |
| Storage | `wisdomapp-b9e98.firebasestorage.app` |
| Auth authorized domains | `wisdomapp-b9e98.web.app`, `wisdomapp-b9e98.firebaseapp.com`, `wisdomapp.com.br`, `www.wisdomapp.com.br`, `localhost` |
| TestFlight | `https://testflight.apple.com/join/qWpWwhnN` |
| Play Store | `https://play.google.com/store/apps/details?id=com.wisdomapp.app` |

### Fonte única de versão

```
lib/constants/app_version.dart
  ├── current          = '10.05'     (marketing, rodapé)
  ├── buildNumber      = 34          (pubspec + web/version.json)
  ├── iosBuildNumber   = 34          (base iOS; Codemagic pode elevar contra App Store Connect)
  ├── versionCode      = 34          (Android versionCode)
  └── releaseTag       = '10.05+34'
```

**Scripts de versão:**

| Script | Função |
|--------|--------|
| `scripts/sync_app_version.ps1` | **Script único de versão.** Sem parâmetro: alinha tudo a partir do dart. `-Build N` (+ `-Marketing X`): novo release (buildNumber = versionCode = N, iosBuildNumber = máx(ios+1, N)). `-Conferir [-Antigo N]`: tabela de todos os pontos + onde sobrou build antigo (exit 1 se divergir). Pontos: dart, pubspec, build.gradle, `web/index.html` (`flutter_bootstrap.js?v=`, `swVersion`), `web/firebase-messaging-sw.js` (`BANNER_CACHE_V`), `web/version.json` |
| `scripts/bump_build.ps1` | Atalho: `sync_app_version.ps1 -Build <atual+1>` |
| `scripts/sync_app_version_from_dart.sh` | Validação bash (CI iOS) |
| `deploy.ps1` | Chama sync no início do deploy |
| `force_version_online.ps1` | Grava `app_config/version` no Firestore |

**Regra:** `deploy.ps1` **não** força atualização automaticamente. Use Admin “Subir versão e forçar atualização” ou `force_version_online.ps1`.

---

## 2. ARQUITETURA GERAL

```
Flutter 3.x (Material 3, GeminiTheme)
├── Web PWA (principal) — build/web → Firebase Hosting
├── Android (AAB) — com.wisdomapp.app
├── iOS (IPA Codemagic) — com.wisdomapp
├── Cloud Functions (Node) — functions/index.js + módulos
└── Firestore + Storage + FCM + Auth
```

### Boot do app (`lib/main.dart`)

```
AuthWrapper
  → ForceUpdateScreen? (version_check_service + app_config/version)
  → sem user → Landing/Login
  → com user → LicenseGate → BiometricGate (resume) → HomeShell(uid)
```

**Safari/iOS Web:** retries Firebase init, `ensureWebDocumentHead`, Firestore long-polling (evita crash SDK 11.x).

**Boot web leve (paridade Controle Total — 02/08/2026):**

1. `web/flutter_bootstrap.js` **deve** chamar `_flutter.loader.load({ serviceWorkerSettings: null, config: { canvasKitVariant: "full", canvasKitBaseUrl: "/canvaskit/" } })`.
2. `web/index.html` **não** chama `load()` de novo (evita double `initializeFirestore`).
3. `deploy.ps1` **não** remove o `load()` do bootstrap; `Validate-HostingPreDeploy.ps1` falha se estiver ausente.
4. GSI (`accounts.google.com/gsi/client`) e PDF.js CDN **fora** do caminho crítico do head (login Google web = popup Firebase).
5. Em `main.dart` (web): warmUps de cursos/notificações **após** `runApp` — 1º frame mais rápido.
6. Prefetch financeiro: `FinanceInstantPrefetchService` no boot do shell / ao abrir Financeiro e Agenda.

### Shell logado (`lib/screens/home_shell.dart`)

- `IndexedStack` com **10 módulos** (índices 0–9).
- **Lazy materialization:** só instancia módulo ao visitar.
- **Máx. 2 módulos retidos** em memória (atual + anterior).
- **Rodapé rápido (5 atalhos):** índices `{0, 1, 2, 3, 7}`.

| Idx | Tela | Label drawer / rodapé |
|-----|------|------------------------|
| 0 | `WisdomDashboardScreen` | Início |
| 1 | `FinanceScreen` | Financeiro |
| 2 | `MetaFinanceiraScreen` | **Objetivos Financeiros** (rodapé: "Objetivo") |
| 3 | `WisdomAgendaScreen` | Agenda |
| 4 | — | ~~Calculadora~~ REMOVIDA em 02/10/2026 (índice reservado, nunca materializa) |
| 5 | `WisdomDashboardScreen(onlyTips: true)` | Dicas Financeiras |
| 6 | `ReportsScreen` | Relatórios |
| 7 | `CursosVideosScreen` | Cursos em Vídeo (rodapé: "Cursos") |
| 8 | — | ~~Minhas Anotações~~ REMOVIDA em 02/10/2026 (índice reservado, nunca materializa) |
| 9 | `SettingsScreen` | Configurações |

### Rotas nomeadas (`main.dart`)

| Rota | Destino |
|------|---------|
| `/` | AuthWrapper |
| `/login` | LoginScreen (web) / LandingScreen (mobile) |
| `/signup` | SignUpScreen |
| `/dashboard` | HomeShell se logado |
| `/admin` | AdminRouteGate → AdminScreen |
| `/divulgacao` | TelaDivulgacaoPage |
| `/checkout`, `/escolha-plano`, `/premium-pro-paywall` | Fluxo planos |
| `/premium-pro-success` | PremiumSuccessPage |
| `/downloads` | DownloadsScreen |
| `/privacidade`, `/termos`, `/suporte` | Legal |
| `/assego_usuarios`, `/convenio_usuarios` | Cadastro convênio |
| `/bancos-suportados` | SupportedBanksScreen |
| `/licenca-expirada`, `/planos` | Licença expirada |

---

## 3. MÓDULOS DO APP (USUÁRIO) — ÍNDICE COMPLETO

### 3.1 Início / Dashboard (`wisdom_dashboard_screen.dart`)

- Dicas financeiras rotativas (Firestore `financial_tips` + `app_config/financial_tips_home`).
- Cards de atalho, versículos, insights.
- **Desde 01/10/2026:** padrão do painel do Controle Total — cabeçalho com saudação/data, «Acesso rápido» aos 9 módulos, financeiro completo (`home_finance_overview_panel.dart` + `home_pendentes_cards.dart`: saldo, contas, pendentes, fixas do mês, Evolução do Saldo, categorias em pizza 3D) e objetivos; 2 colunas em tela ≥ 1100 px. Escutas sempre guardadas no estado (nunca `.snapshots()` no build). Ver changelog §16.
- Motor: `lib/utils/insights_engine.dart`.
- Sync admin → usuários: `financial_tips_home_sync_service.dart`.

### 3.2 Financeiro (`finance_screen.dart` + satélites)

**Telas principais:**

- `finance_screen.dart` — hub financeiro (receitas, despesas, contas, cartão, pendentes).
- `finance_accounts_screen.dart` — contas bancárias/cartão.
- `finance_transactions_fullscreen_page.dart` — lista fullscreen.
- `finance_categories_fullscreen_page.dart` — categorias.
- `finance_bulk_assign_screen.dart` — atribuição em massa.
- `novo_lancamento_page.dart` — novo lançamento.
- `despesas_fixas_screen.dart` / `receitas_fixas_screen.dart` — fixas.
- `planejamento_financeiro_screen.dart` — planejamento.
- `finance_assistant_insights_page.dart` — insights IA.
- `financial_tips_fullscreen_page.dart` — dicas fullscreen.
- `smart_input_screen.dart` — OCR/voz (Cloud Functions).
- `open_finance_connections_screen.dart` — Pluggy/Open Finance.
- `bank_connection_screen.dart`, `pluggy_connect_webview_screen.dart`.
- `extra_bank_connection_paywall_screen.dart` — paywall conexão extra.
- `budget_screen.dart`, `new_budget_flow_screen.dart` — orçamento.
- `payment_status_screen.dart`, `receipts_screen.dart`.
- `anexo_viewer_screen.dart` (+ web/stub).

**Serviços-chave:** `finance_service.dart`, `finance_accounts_service.dart`, `transaction_save_service.dart`, `fixed_expense_service.dart`, `billing_service.dart`, `pluggy_service.dart`, `bank_integration_service.dart`, **`finance_month_cache.dart`**, **`finance_instant_prefetch_service.dart`**, hub `finance_transactions_hub.dart`.

**Performance financeiro (NÃO retroagir — 02/08/2026):**

| Peça | Função |
|------|--------|
| `FinanceMonthCache` | Cache mensal cache-first; seed na Agenda enquanto streams aquecem |
| `FinanceInstantPrefetchService` | Prefetch mês atual + adjacentes no boot / ao abrir módulo |
| `FinanceScreen` | Prime cache → reload com `preserveExistingDocs`; listener do hub |
| `FinanceAccountsService.listOnce` | Cache-first |
| Hub mutações | Invalida `FinanceMonthCache` no mês afetado |
| `fixed_pending_prefs_sheet.dart` | Sheet «definir meses» (chips Mês atual…12) em despesas/receitas fixas — port CT |

**Índices:** `transactions` com `type+status+date` (e demais em `firestore.indexes.json`).

**Regras:** `lib/constants/app_business_rules.dart` (biometria 525600 min, fatura cartão desde 16/06/2026, max parcelas, etc.).

**Subcoleções Firestore:** `users/{uid}/transactions`, `fixed_incomes`, `finance_month_buckets`, `bank_connections`.

### 3.3 Objetivos Financeiros (`meta_financeira_screen.dart`)

- Metas com contribuições, gráficos, projeções.
- Subcoleções: `users/{uid}/goals`, `goals/{id}/contributions`.

### 3.4 Agenda (`wisdom_agenda_screen.dart`)

- Compromissos, lembretes, integração escalas.
- `compromisso_form_page.dart`, `reminder_detail_screen.dart`.
- Campo **Contato WhatsApp** aceita digitação, colagem e seleção da agenda nativa (`flutter_native_contact_picker`), com normalização em `compromisso_contact_links.dart`.
- Ao abrir o módulo, seleciona **hoje** e mostra o resumo; dia vazio abre cadastro; dia preenchido seleciona primeiro e permite adicionar em nova ação.
- Dias com vários compromissos exibem **divisão de cores** na célula (2+ eventos; sem shrink/dots).
- Preferência de início semanal **domingo (padrão) ou segunda-feira**, salva localmente e em `users/{uid}/settings/planning` por `agenda_calendar_week_start_preferences.dart`.
- **Chips compactos (padrão Escalas CT)** no topo: **Sync** (verde) · **Hoje** · **Config** (início da semana). Removida a barra grande `ExternalCalendarSyncCollapsedButton`.
  - Sync: se Google/Apple ativo → sync bidirecional agora; senão → preview de ativação.
- **Limpeza por período:** `agenda_bulk_clear_period_dialog.dart` — datas inicial/final digitáveis (`DateFieldWithCalendarOrManual`) → contagem → `showAgendaBulkClearConfirm` (`agenda_bulk_clear_confirm_dialog.dart` / toolbar).
- **UI sem «audiência»:** labels/abas focam em compromissos particulares; tipo legado `audiencia` pode existir no backend; deep link `audiencia` → compromissos; central de notificações oculta aba audiências.
- Seed financeiro no calendário via `FinanceMonthCache` enquanto streams aquecem; warm ao abrir módulo / mudar mês.
- `agenda_notifications_queue_screen.dart` — fila push/e-mail.
- **Calendários externos:** `external_calendar_integration_panel.dart` (Settings + chip Config/Sync na Agenda).
  - Google: OAuth web/mobile, `google_calendar_sync_service.dart`, CF `googleCalendarOAuth.js`.
  - Apple: EventKit iOS via `device_calendar`, `apple_calendar_sync_service.dart`.
  - Sync agora: `external_calendar_bidirectional_sync.dart`.
  - Auto sync **00:00 e 12:00** (Timer + catch-up no boot/resume): `external_calendar_scheduled_sync.dart` — ligado em `agenda_boot_orchestrator.dart` + `home_shell.dart` resume.
- Boot: `agenda_boot_orchestrator.dart` (inclui `completeWebOAuthReturnIfNeeded` + scheduled sync).
- Subcoleções: `users/{uid}/reminders`, `agendaAlerts`, `settings/google_calendar`.

### 3.5 Escalas / Plantões (`scales_screen.dart`)

- Plantões, tarifas GO (AC4), horas extras, locais, naturezas.
- `scale_rates_edit_screen.dart`, `horas_extras_config_screen.dart`, `locations_screen.dart`.
- Notificações locais: `scale_notifications_service.dart` (+ io/web/stub).
- Auto-confirmação: `scale_auto_confirm_service.dart` + CF `scaleAutoConfirmScheduled.js`.
- Tarifas globais: coleção `config/scale_rates`.
- Subcoleção: `users/{uid}/scales`.

### 3.6 Calculadora (`calculator_screen.dart`)

- Entradas salvas em `users/{uid}/calculator_entries`.

### 3.7 Relatórios (`reports_screen.dart`)

- PDF financeiro, super extrato (cliente + CF `financePdfSuperExtrato.js`).
- `report_preview_screen.dart`.

### 3.8 Cursos em Vídeo (`cursos_videos_screen.dart`)

**Estado atual (funcionando — NÃO retroagir):**

- Lista cursos/dicas de `course_videos` (cache: `course_videos_cache_service.dart`).
- Player estilo YouTube: **`course_video_player_shell.dart`**
  - Mostra thumbnail/capa colorida + ▶ antes do play.
  - Só carrega embed após toque (inline) ou com poster enquanto carrega (autoplay).
- Embeds: `course_video_embed_mobile.dart` (WebView), `course_video_embed_web.dart` (iframe/video nativo).
- Thumbnails: `course_thumb_resolver.dart`, `course_media_url_resolver.dart`, YouTube `maxresdefault`.
- Admin CRUD: `admin_cursos_tab.dart`.
- Upload no Admin mostra progresso em tempo real; após gravar/publicar, fecha o formulário e retorna à lista.
- Após mutações, o cache força leitura do servidor para o conteúdo aparecer imediatamente aos usuários.
- Descrição completa fica aberta por padrão e selecionável no painel do curso.
- Painel inline: `course_module_media_panel.dart`.
- Tela assistir: `course_video_watch_screen.dart`.
- Feed estilo YouTube + progresso/like; analytics admin: `course_analytics_service.dart` → coleção `course_stats` (+ regras Firestore).
- CF limpeza expirados: `courseVideosExpiryCleanup.js`.
- Storage path: `wisdomapp/course_videos/...`.

### 3.9 Anotações / Produtividade

- `anotacoes_screen.dart` → `notes_service.dart` → `users/{uid}/notes`.
- `ocorrencias_screen.dart` → `users/{uid}/ocorrencias`.

### 3.10 Configurações (`settings_screen.dart`)

- Perfil, biometria, notificações, sons, backup/restore.
- Integração calendários (painel unificado).
- Links úteis, categorias, módulo inicial.
- Premium/plano, Open Finance, telemetria.

### 3.11 Premium / Planos / Pagamentos

- `escolha_plano_page.dart`, `premium_pro_paywall_screen.dart`, `premium_success_page.dart`.
- Mercado Pago **somente** projeto `wisdomapp-b9e98` (purge legado ok): callables `ctCreateMpCheckout`, `ctCreateMpPixPayment`, `ctPurgeMpPayments` + HTTP `mpWebhook`; coleções `mp_payments`, `app_config/mp_checkout_prices`, `settings/mercadopago`.
- IAP Apple: `ios_iap_products.dart`, gate `ios_payments_gate.dart`.
- Limites Premium Pro: `premium_pro_limits.dart`, `premium_pro_rollout.dart`.

### 3.12 Auth / Onboarding / Gates

- `landing_screen.dart`, `login_screen.dart`, `signup_screen.dart`, `onboarding_screen.dart`.
- `biometric_gate_screen.dart`, `force_update_screen.dart`, `license_expired_screen.dart`.
- `complete_profile_screen.dart`, `post_login_biometric_prompt.dart`.
- CPF index: `cpf_index` + `cpf_auth_service.dart`.
- Delegado: `delegate_access_service.dart`, `delegate_email_index`.

---

## 4. SITE / DIVULGAÇÃO

### 4.1 Landing Flutter

| Tela | Rota / uso | Firestore |
|------|------------|-----------|
| `landing_screen.dart` | Login inicial mobile / web entry | `landing_content/main` |
| `tela_divulgacao_page.dart` | `/divulgacao` | mesmo conteúdo |
| `editor_divulgacao_screen.dart` | Admin edita landing | `landing_content/main`, legado `settings/landing_page` |

**Conteúdo típico:** hero, features, planos, depoimentos, CTAs, versículo Proverbs 16:3 no rodapé.

### 4.2 Web estática (`web/`)

| Arquivo | Função |
|---------|--------|
| `index.html` | Entry PWA Flutter — splash WISDOMAPP; canonical/OG dinâmicos por host; **sem** GSI/PDF no head |
| `flutter_bootstrap.js` | **Boot único:** `_flutter.loader.load` + CanvasKit full local `/canvaskit/` |
| `manifest.json` | PWA |
| `version.json` | Versão force-update (sync com app_version.dart) — online `10.05+26` |
| `firebase-config.js` | Config Firebase web |
| `firebase-messaging-sw.js`, `sw.js` | Service workers push (FCM SW só desktop/Android Chrome; iOS/in-app skip) |
| `google-oauth-config.js` | OAuth Google |
| `google_calendar_oauth.html` | Callback OAuth Google Calendar |
| `admin.html` | **Admin HTML legado** (separado do Flutter `/admin`) |
| `404.html` | Fallback hosting |
| `.well-known/assetlinks.json` | Android App Links |
| `icons/` | PWA + push banners (`icons/wisdomapp_emblem.png` no splash) |

**URLs oficiais:**

| URL | Estado (02/08/2026) |
|-----|---------------------|
| `https://wisdomapp-b9e98.web.app/` | ✅ Online, boot com `load()` OK · `version.json` = `10.05+26` |
| `https://wisdomapp.com.br/` | ✅ Apex OK (TXT ownership + Hosting) · `version.json` = `10.05+26` |
| `https://www.wisdomapp.com.br/` | CNAME `ghs.googlehosted.com` (mesmo padrão CT); Auth já autoriza |

### 4.3 Páginas públicas

- `downloads_screen.dart` — `public_downloads`.
- `privacidade_screen.dart`, `termos_screen.dart`, `suporte_screen.dart`.
- `supported_banks_screen.dart` — bancos Open Finance.
- `assego_public_signup_screen.dart` — convênio Assego.

---

## 5. PAINEL ADMIN — COMPLETO

### 5.1 Entrada

```
/admin → admin_route_gate.dart
  → Firebase Auth + admin_permissions_service.canAccessAdminPanel
  → AdminScreen (lib/screens/admin_screen.dart ~12k linhas)
```

**Perfis:** admin total, gestor (`admin_gestor_config.dart`), parceiro (`admin_partner_config.dart`).

### 5.2 Menu lateral (`AdminMenuItem` em `admin_menu_lateral.dart`)

| Item enum | Título menu | Arquivo principal |
|-----------|-------------|-------------------|
| `resumo` | Resumo | Dentro de `admin_screen.dart` |
| `usuarios` | Usuários | `admin_screen.dart` |
| `usuarios360` | Inteligência 360° | `admin_usuarios_inteligencia_tab.dart` |
| `equipe` | Equipe ADM | `gestao_equipe_adm.dart` |
| `logs` | Logs | `logs_atividade_page.dart` → `activity_logs` |
| `relatorios` | Relatórios | `admin_screen.dart` |
| `sugestoes` | Sugestões | `admin_sugestoes_tab.dart` → `user_feedback` |
| `dicasFinanceiras` | Dicas financeiras | `admin_financial_tips_page.dart` |
| `downloads` | Downloads | `admin_screen.dart` → `public_downloads` |
| `landing` | Landing / Divulgação | `editor_divulgacao_screen.dart` |
| `acessosDominio` | Acessos domínio | `acessos_dominio_tab.dart` |
| `escala` | Escala / Tarifas | `admin_screen.dart` + `config/scale_rates` |
| `drive` | Google Drive | `admin_screen.dart` |
| `mercadopago` | Mercado Pago | `admin_mercado_pago_tab.dart` |
| `cursos` | Cursos em vídeo | `admin_cursos_tab.dart` → `course_videos` |
| `pluggy` | Pluggy | `admin_pluggy_tab.dart` → `app_config/pluggy` |
| `openFinanceExtras` | Open Finance extras | `admin_open_finance_extras_tab.dart` |
| `premiumProMonitor` | Premium Pro monitor | `admin_premium_pro_monitor_tab.dart` |
| `promocoes` | Promoções | `admin_promocoes_tab.dart` → `promotions` |
| `convenios` | Convênios | `admin_screen.dart` → `partnerships` |
| `lojas` | Lojas (Play/App Store) | `admin_screen.dart` |
| `migracaoEmail` | Migração e-mail | `admin_migracao_email_tab.dart` |
| `email` | E-mail / SMTP | `admin_screen.dart` → `settings/email` |
| `manutencao` | Manutenção / Versão | `admin_screen.dart` → force update, `app_config/version` |
| `voltar` | Voltar ao app | — |

### 5.3 Widgets admin reutilizáveis (`lib/widgets/admin/`)

- `admin_page_shell.dart` — layout padrão.
- `admin_tip_grid_card.dart` — **cards compactos só cabeçalho colorido** (olho = detalhes).
- `admin_financial_tip_editor_sheet.dart` — editor dica.
- `admin_financial_tips_schedule_sheet.dart` — programar dicas no Início.
- `admin_mercado_pago_tab.dart`, `admin_partner_*`, `admin_revenue_forecast_panel.dart`.
- `admin_system_health_panel.dart`, `admin_alert_center.dart`.
- `admin_bulk_actions_bar.dart`, `admin_global_search_delegate.dart`.
- `admin_user_compare_sheet.dart`, `admin_user_360_extras.dart`.
- `admin_notification_templates_tab.dart` — templates push/e-mail.

### 5.4 Dicas financeiras admin (estado atual)

**Arquivo:** `admin_financial_tips_page.dart`

- Abas: **Bíblicas** / **Gerais**.
- Grid compacto: 2 col mobile, 3 tablet, 4 desktop.
- Card = gradiente + título + ref + ações (👁 detalhes, ⭐ favorita, 🏠 início, ✏ editar, 🗑 excluir).
- Toque no card → bottom sheet detalhes completos.
- Coleção: `financial_tips`.
- Config Início: `app_config/financial_tips_home`.
- Seed: `financial_tips_seed_service.dart`, catálogos em `lib/data/`.

### 5.5 Cursos admin

**Arquivo:** `admin_cursos_tab.dart`

- CRUD `course_videos`: YouTube ID, MP4 upload Storage, thumbnails, validade, publicado.
- `thumbnailUrl` nunca vazio (prioriza imagem → YouTube thumb).
- Tipos: `curso` | `dica`.

### 5.6 Auditoria

- `admin_audit_service.dart` → `admin_audit_log`.
- `logs_service.dart` → `activity_logs`.

---

## 6. SERVIÇOS — ÍNDICE POR DOMÍNIO

> Pasta: `lib/services/` (~144 arquivos)

| Domínio | Arquivos principais |
|---------|---------------------|
| Auth/sessão | `auth_service`, `cpf_auth_service`, `biometric_auth_service`, `session_restore_service`, `login_preferences`, `account_switch_flow` |
| Firestore user | `firestore_service`, `firestore_user_doc_id` (utils) |
| Cloud Functions | `functions_service` |
| Financeiro | `finance_service`, `finance_accounts_service`, `finance_transfer_service`, `transaction_save_service`, `fixed_expense_service`, `billing_service`, `pluggy_service`, `bank_integration_service`, `finance_month_cache`, `finance_instant_prefetch_service` |
| Agenda | `agenda_boot_orchestrator`, `agenda_managed_queue_service`, `agenda_alerts_queue_service`, `compromisso_reminder_service`, `google_calendar_sync_service`, `apple_calendar_sync_service`, `google_calendar_oauth_mobile/web`, `external_calendar_bidirectional_sync`, `external_calendar_scheduled_sync` (00:00/12:00) |
| Escalas | `scale_rates_service`, `scale_notifications_service`, `scale_auto_confirm_service`, `goias_scale_rates_recalc_service` |
| Push | `push_notification_service`, `fcm_local_notification_presenter`, `notification_sound_preferences` |
| Dicas | `financial_tips_catalog_service`, `financial_tips_home_sync_service`, `financial_tips_seed_service` |
| Cursos | `course_videos_cache_service`, `course_video_file_service`, `course_videos_expiry_cleanup_service` |
| Admin | `admin_permissions_service`, `admin_audit_service`, `admin_user_plan_apply_service` |
| Backup | `user_backup_service`, `user_restore_service`, `backup_save` |
| Versão | `version_check_service` (+ web impl) |
| Widget Android | `widget_update_service` (alias `WidgetDataService`), `widget_firestore_live_sync` |
| Cursos analytics | `course_analytics_service` → `course_stats` |

### Widgets Android (home screen) — port Controle Total

**Package Kotlin:** `android/app/src/main/kotlin/com/raihom/controletotalapp/` (applicationId continua `com.wisdomapp.app`).

| Provider | Tamanho | XML |
|----------|---------|-----|
| `ControleTotalWidgetSmallProvider` | 2×2 | `home_widget_controle_total_small` |
| `ControleTotalWidgetMediumProvider` | 4×2 | `home_widget_controle_total_medium` |
| `ControleTotalWidgetProvider` | 4×3 | `home_widget_controle_total` |

- Serviço: `ControleTotalWidgetService` + `WidgetSyncAlarmReceiver` (alarme 00:00/12:00 + boot + rollover meia-noite).
- Dados: compromissos + escalas + financeiro; brand **WISDOMAPP**; logo `@mipmap/ic_launcher`.
- Dart: `widget_update_service.dart` (+ satélites); export via `widget_data_service.dart`.

---

## 7. CLOUD FUNCTIONS — ÍNDICE

**Monolito:** `functions/index.js` (~9800+ linhas) — OCR, speech, MP webhooks, push agenda, partnerships, IAP Apple, course videos, version bump, etc.

**Módulos separados:**

| Arquivo | Função / gatilho |
|---------|------------------|
| `googleCalendarOAuth.js` | OAuth GCal (tokens servidor) |
| `agenda_daily_digest.js` | Cron ~20h Brasília — resumo agenda e-mail+push |
| `agenda_message_templates.js` | Templates premium (escala, compromisso, audiência…) |
| `agenda_delivery_prefs.js` | Preferências entrega push/e-mail |
| `agendaPeriodSnapshot.js` | Callable snapshot período reminders |
| `notification_templates_config.js` | Cache `app_config/notification_templates` |
| `scaleAutoConfirmScheduled.js` | Cron auto-confirma plantões passados |
| `goiasScaleRatesRecalc.js` | Recálculo tarifas GO em massa |
| `financePdfSuperExtrato.js` | PDF Super Extrato servidor |
| `financeTransfers.js` | Transferências server-side |
| `financeMonthBuckets.js` | Agregados mensais saldo abertura |
| `financeMigrationImport.js` | Importação financeira migração legado |
| `generateFinancialTipAI.js` | Dicas via Gemini |
| `financialTipsInsightPushScheduled.js` | Cron push dicas por lançamentos |
| `courseVideosExpiryCleanup.js` | Limpeza vídeos expirados |
| `wisdomapp_firestore_bootstrap.js` | Bootstrap Firestore + Storage |
| `set_mp_split_config.js` / `set_mp_webhook_secret.js` | Config MP |

**MP (exports em `index.js`):** `ctCreateMpCheckout`, `ctCreateMpPixPayment`, `ctPurgeMpPayments`, `mpWebhook` — só Wisdomapp.

**Canais Android FCM:** `controletotal_escala`, `_compromisso`, `_audiencia`, `_folga`, `_financeiro`.

---

## 8. FIRESTORE — COLEÇÕES E ÍNDICES

### 8.1 Coleções raiz

| Coleção | Uso |
|---------|-----|
| `users` | Documento principal usuário |
| `users_uid` | Mapeamento UID alternativo |
| `landing_content` | Landing (`main`) |
| `app_config` | version, mp_checkout_prices, pluggy, pro_open_finance, notification_templates, financial_tips_home |
| `settings` | mercadopago, googledrive, email, landing_page (legado) |
| `config` | scale_rates (tarifas GO) |
| `secure_config` | mercado_pago (segredos) |
| `mp_project_config` | Config MP |
| `mp_payments` | Pagamentos MP |
| `promotions` | Promoções/cupons |
| `partnerships` | Convênios (+ sub `members`) |
| `course_videos` | Cursos em vídeo |
| `course_stats` | Analytics cursos (views/likes — admin) |
| `financial_tips` | Banco dicas financeiras |
| `cpf_index` | CPF → uid |
| `delegate_email_index` | Acesso delegado |
| `activity_logs` | Logs atividade |
| `admin_audit_log` | Auditoria admin |
| `user_feedback` | Sugestões |
| `notifications` | Broadcast |
| `public_downloads` | Downloads públicos |
| `news_rss_server_cache` | Cache RSS |

### 8.2 Subcoleções `users/{uid}/`

`transactions`, `scales`, `reminders`, `goals` (+ `contributions`), `settings`, `bank_connections`, `bank_connection_entitlements`, `entitlement_payments`, `locations`, `calculator_entries`, `ocorrencias`, `notes`, `fixed_incomes`, `budgets`, `agendaAlerts`, `insights_cache`, `notifications`, `deviceTokens`, `fcmTokens`, `prefs`, `finance_month_buckets`, `finance_account_month_buckets`.

### 8.3 Índices compostos (`firestore.indexes.json`)

Principais collection groups indexados:

- `mp_payments` (status + dateApprovedAt)
- `users` (app + licenseExpiresAt)
- `user_feedback` (uid + createdAt)
- `scales` (paid + date, autoViradaSourceId, createdByMagic, magicBatchId…)
- `transactions` (fixedExpenseId + monthKey, accountId + date, type + date…)
- `reminders` (vários combos date/type)
- `course_videos` (published + type + ordem)
- `financial_tips` (ativo + ordem, tipo + ordem)
- `activity_logs`, `admin_audit_log`, `partnerships/members`

**Regra:** novas queries compostas exigem entrada em `firestore.indexes.json` + deploy índices.

---

## 9. TEMA E CORES (NÃO ALTERAR SEM MOTIVO)

### AppColors (`lib/theme/app_colors.dart`)

| Token | Hex | Uso |
|-------|-----|-----|
| primary | `#2D5BFF` | Azul WISDOMAPP |
| secondary | `#4B3DF0` | Roxo-azul |
| accent | `#12B5A5` | Teal |
| amber | `#FFB648` | Dourado/amarelo logo |
| logoOrange | `#F97316` | Laranja |
| deepBlue / deepBlueDark | `#122B6B` / `#0B1F4B` | Headers |
| logoGradient | deepBlueDark → accent | Escudo/barra |

### GeminiTheme (`lib/theme/gemini_theme.dart`)

- Material 3, fonte Inter, border radius 20–24.

### Paleta calendário (`color_palette.dart`)

- Plantão `#2D5BFF`, Compromisso `#12B5A5`, legado Audiência `#D4AF37` (dourado — UI atual prioriza compromissos particulares).

---

## 10. DEPLOY E CI/CD

### 10.1 Deploy web + functions (`deploy.ps1`)

**Comandos padrão (Controle Total):**

| Modo | Comando | Escopo |
|------|---------|--------|
| **Web (padrão)** | `.\deploy.ps1 -WebOnly` | **SÓ hosting** (`firebase deploy --only hosting --project wisdomapp-b9e98`). Desde 01/10/2026 — antes publicava também firestore/storage/**todas as functions** + bootstrap |
| Plano sem publicar | `.\deploy.ps1 -WebOnly -DryRun` | Confere versão, token e `load()`; não builda nem publica |
| Completo legado | `.\deploy.ps1` | web + firestore/storage + TODAS as functions + bootstrap + `build_aab_release.ps1`. **Só com pedido explícito** — o roteiro padrão é `-WebOnly` + functions escopadas |
| Codemagic legado | `.\deploy.ps1 -LegacyCodemagic` | + ZIP iOS (`Export-AabIosTemporarios`) + commit automático amplo + push + trigger Codemagic (fluxo antigo; `-NoCodemagicPush` virou no-op) |
| Force version | **não** no deploy padrão | Admin ou `.\force_version_online.ps1` |
| Clean | só com `-Clean` | `flutter clean` |

**Passos internos:**

1. `scripts/sync_app_version.ps1`
2. `flutter pub get` (+ patch Gradle plugins se necessário)
3. `flutter build web --release --pwa-strategy=none --no-wasm-dry-run --no-tree-shake-icons`
4. **Garantir** `build/web/flutter_bootstrap.js` com `_flutter.loader.load(...)` (nunca stripar)
5. Sync `web/version.json` / `build/web/version.json`
6. `Validate-HostingPreDeploy.ps1` (exige `load()` no bootstrap)
7. `scripts/Invoke-FirebaseDeploy.ps1` (token `.firebase-ci-token`; `--project wisdomapp-b9e98` explícito; `-HostingOnly` no `-WebOnly`)
8. Completo: `build_aab_release.ps1` → `D:\TEMPORARIOS\WISDOMAPP_*`; git **não** é mais automático (push manual nas branches de build — ver seção «Deploy completo (padrão Controle Total)»)

**Incidente corrigido 02/08/2026:** versão antiga do `deploy.ps1` comentava/removia `load()` assumindo que `index.html` chamava — a web ficava no splash («Quase pronto…» / timeout). **Nunca reintroduzir esse strip.**

### 10.2 Codemagic iOS (`codemagic.yaml`)

- Workflow `ios-workflow`, bundle `com.wisdomapp`.
- Widget: target `WisdomappWidgetExtension`, bundle `com.wisdomapp.WisdomappWidget`, Team ID `82RC6YL7KL`, App Group `group.com.wisdomapp.widget`.
- `scripts/codemagic_ios_prepare_widget_signing.sh` registra/configura o bundle e os perfis do Widget. Se a API Apple não aceitar o App Group, remove apenas o Widget daquela execução para não bloquear o IPA principal.
- `fetch-signing-files` não usa `--strict-match-identifier`, permitindo buscar perfis do app e da extensão.
- `scripts/codemagic_ios_delete_appstore_profiles.py` remove perfis antigos dos dois bundle IDs antes da recriação.
- Scripts anti-erro **90189** (`CFBundleVersion` ≤ App Store Connect):
  - `scripts/codemagic_ios_sync_version_from_app_version_dart.sh`
  - `ios/asc_build_number_floor.txt` (= 11)
  - `codemagic_ios_pre_publish_90189_gate.sh`
- **Importante:** retry só Publishing reutiliza IPA antigo — precisa **Start new build** completo após bump de versão.

### 10.3 Atalhos Windows

- `Start-CodemagicIos.bat`, `Fix-CodemagicIos.bat`
- `IOS_BUILD_README.md`
- Scripts domínio (diagnóstico): `scripts/check-hosting-custom-domain.js`, `scripts/add-hosting-custom-domains.js`, `scripts/fix-hosting-custom-domain.js`

### 10.4 Domínio custom `wisdomapp.com.br` (Hosting + DNS)

| Item | Valor |
|------|--------|
| Site Hosting | `wisdomapp-b9e98` → `https://wisdomapp-b9e98.web.app` |
| Apex A | `199.36.158.100` (Firebase Hosting) — já correto |
| Apex TXT **obrigatório** | `hosting-site=wisdomapp-b9e98` (**ADD** — igual CT `hosting-site=controletotal-4c867`) |
| Apex TXT legado | pode coexistir `wisdomapp-b9e98.web.app` |
| www | CNAME → `ghs.googlehosted.com` (mesmo padrão CT) |
| Cert | `CERT_ACTIVE` / grouped (já provisionado) |
| Estado visto 02/08/2026 (tarde) | ✅ Apex `https://wisdomapp.com.br/version.json` = `10.05+26` (ownership OK após TXT) |
| Auth | domains já incluem `wisdomapp.com.br` e `www.wisdomapp.com.br` |

**Se apex voltar a 404:** revalidar TXT `hosting-site=wisdomapp-b9e98` no Registro.br + `node scripts/check-hosting-custom-domain.js` (ou Console Hosting → Verify).

### 10.5 Artefatos release `10.05+34` (confirmados 02/10/2026)

| Artefato | Caminho / valor |
|----------|-----------------|
| AAB Play | `D:TEMPORARIOSWISDOMAPP_10.05+34_34_release.aab` (181 909 948 bytes · SHA-256 `45454B9EEBF11606A362402FD9853C6F697B46A5A762A1C792C99BEA3890C87E`) — versionCode 34, 16 KB OK, 7 textos novos conferidos; **pede READ_CONTACTS** (bloqueio de chamadas) → declaração no Play Console |
| Web | 10.05+34 nos dois domínios; SDK JS do Firestore fixo 12.19.0 (`window.flutterfire_web_sdk_version`) + auto-detecção de long-polling (republicado 9e98301) |
| GitHub | `codemagic-ios-ready` = 1ae8c1c (release 34); `main`/`codemagic-10-05-ready` = 9e98301 (só web a mais) |
| Backend | 107 functions, rules, storage, indexes (2 índices duplicados removidos — davam 409); migração `wmigr_buckets.js --gravar` v4 em 4 usuários (0 divergência) |
| Force update | `app_config/version` = 10.05+34 |

### 10.5-b Artefatos release `10.05+29`

| Artefato | Caminho / valor |
|----------|-----------------|
| AAB Play | `D:TEMPORARIOSWISDOMAPP_10.05+29_29_release.aab` (180 691 722 bytes · SHA-256 `2E56F054EF3A5EDAED284D8219BCD829F2463C2FD77DE6B55DE5E500B57337E6`) — versionCode 29, sem READ_CONTACTS, 16 KB OK, 9 textos novos conferidos |
| Web `version.json` | `https://wisdomapp.com.br/version.json` e `https://wisdomapp-b9e98.web.app/version.json` → `10.05+29`; `flutter_bootstrap.js?v=29` com `load()` |
| GitHub | `codemagic-10-05-ready`, `codemagic-ios-ready`, `main` = `85852ca` (app_version 29 conferido via gh api); iOS: start do dono |
| Force update | `app_config/version` = `10.05+29`, `forceUpdate=true` (aviso que dá para fechar, não trava) |
| Backend | 106 functions publicadas (deploy de `functions` inteiro), `firestore:rules`, `storage`, `firestore:indexes` (+3 índices users: role+email, plan+email, email+createdAt — sem eles o Resumo do admin dava failed-precondition) |

### 10.5-a Artefatos release anterior `10.05+26`

| Artefato | Caminho |
|----------|---------|
| AAB Play | `D:\TEMPORARIOS\WISDOMAPP_10.05+26_26_release.aab` (127 939 181 bytes · SHA-256 `645754E5CCFDEDA8FD9F096E9A2638135591E3A7BA09D0E917BAAC1FDCAACD4D`) |
| Alias AAB | `D:\TEMPORARIOS\WISDOMAPP_ultimo_release.aab` |
| Pacote iOS CodeMagic | `D:\TEMPORARIOS\WISDOMAPP_ios_codemagic_10.05+26_26.zip` (1 235 566 bytes) |
| Export note | `D:\TEMPORARIOS\WISDOMAPP_EXPORT_10.05+26_26.txt` |
| Web `version.json` | `https://wisdomapp-b9e98.web.app/version.json` e `https://wisdomapp.com.br/version.json` → `10.05+26` (#26) |
| Force update Firestore | `app_config/version` = `10.05+26`, `forceUpdate=true` (deploy completo 02/08) |

---

## 11. UTILITÁRIOS E CONSTANTES — ÍNDICE RÁPIDO

### `lib/constants/`

`app_version`, `app_brand`, `app_strings`, `app_business_rules`, `color_palette`, `currency_formats`, `date_time_formats`, `premium_pro_limits`, `premium_pro_rollout`, `finance_*`, `admin_gestor_config`, `admin_partner_config`, `google_oauth_config`, `ios_iap_products`, `promo_site_urls`, ícones módulos.

### `lib/utils/` (destaques)

| Área | Arquivos |
|------|----------|
| Firestore | `firestore_user_doc_id`, `firestore_retry`, `firestore_web_guard` |
| Financeiro | `finance_transactions_realtime`, `finance_shell_navigation`, `pdf_financeiro_super_extrato` |
| Agenda | `agenda_notification_plan`, `compromisso_schedule_dates` |
| Cursos | `course_media_url_resolver`, `course_thumb_resolver`, `youtube_url_helper` |
| Admin | `admin_financial_tip_utils`, `admin_panel_launch`, `admin_responsive` |
| Web/PWA | `pwa_install_helper`, `ensure_web_document_head_web`, `gcal_web_url_clean` |
| Insights | `insights_engine` |

---

## 12. WIDGETS COURSE VIDEO (REFERÊNCIA — NÃO REGREDIR)

```
lib/widgets/course_video/
├── course_video_player_shell.dart    ← poster YouTube-style, tap ▶
├── course_video_embed.dart           ← export conditional
├── course_video_embed_mobile.dart    ← WebView + poster HTML
├── course_video_embed_web.dart       ← iframe/video nativo
├── course_module_media_panel.dart    ← painel inline módulo
├── course_video_watch_screen.dart    ← tela assistir fullscreen
├── course_media_preview.dart         ← thumbnails CourseMediaThumbnail
├── course_protected_image*.dart
└── course_media_view_policy.dart     ← bloqueio context menu
```

---

## 13. INTEGRAÇÃO CALENDÁRIOS (REFERÊNCIA — NÃO REGREDIR)

```
lib/widgets/external_calendar_integration_panel.dart  ← painel unificado
lib/services/google_calendar_sync_service.dart
lib/services/google_calendar_oauth_mobile.dart        ← SEM canAccessScopes (só web)
lib/services/google_calendar_oauth_web.dart
lib/services/apple_calendar_sync_service.dart       ← EventKit iOS
lib/services/external_calendar_bidirectional_sync.dart  ← sync agora (Google e/ou Apple)
lib/services/external_calendar_scheduled_sync.dart     ← auto 00:00 + 12:00 + catch-up
lib/widgets/agenda/agenda_bulk_clear_period_dialog.dart
lib/widgets/agenda/agenda_bulk_clear_confirm_dialog.dart
lib/widgets/agenda/agenda_bulk_clear_toolbar.dart
web/google_calendar_oauth.html
functions/googleCalendarOAuth.js
ios/Info.plist → NSCalendarsUsageDescription, NSCalendarsFullAccessUsageDescription
```

**UI Agenda:** chips Sync · Hoje · Config (não usar barra grande colapsável antiga).

**Web Apple Calendar:** explicar CalDAV/iCloud (sem API REST) — só EventKit no iOS nativo.

---

## 14. REGRAS DE NEGÓCIO FIXAS

| Regra | Valor / local |
|-------|---------------|
| Biometria timeout | 525600 min (~1 ano) — `app_business_rules.dart` |
| Usuário logado até Sair | session restore + Firestore offline-first |
| Fatura cartão data mínima | 16/06/2026 |
| Max parcelas lançamento | 120 |
| Max parcelas fixa | 360 |
| PWA prompt mínimo visitas | 2 |
| Versão única 3 plataformas | `app_version.dart` |
| Deploy não força update sozinho | Admin ou `force_version_online.ps1` |
| thumbnailUrl cursos nunca vazio | `admin_cursos_tab` finalize |
| MP4 curso: poster antes play | `CourseVideoPlayerShell` |
| Admin dicas: só cabeçalho na grid | `AdminTipGridCard` compacto |
| Label drawer idx 2 | "Objetivos Financeiros" (rodapé pode ser "Objetivo") |
| Web boot: `load()` só no bootstrap | Nunca stripar em `deploy.ps1`; index não chama `load()` |
| Domínio custom ownership | TXT `hosting-site=wisdomapp-b9e98` no apex (confirmado OK 02/08/2026) |
| Agenda chips Sync/Hoje/Config | Compactos estilo Escalas CT — sem barra grande antiga |
| Sync calendário auto | 00:00 e 12:00 via `ExternalCalendarScheduledSync` |
| Temporários | Sempre `D:\TEMPORARIOS\WISDOMAPP_*` |
| CodeMagic | Somente iOS; sem AAB/APK no CM |
| Deploy | Só com ordem explícita do usuário |
| Mercado Pago | Só Firebase `wisdomapp-b9e98` |

---

## 15. MAPA DE ARQUIVOS CRÍTICOS (ABSOLUTO)

```
c:\WISDOMAPP\lib\constants\app_version.dart          ← VERSÃO ÚNICA (10.05+26)
c:\WISDOMAPP\lib\main.dart                           ← boot, rotas, Firebase web (warmUps leves)
c:\WISDOMAPP\lib\screens\home_shell.dart             ← shell 10 módulos + prefetch financeiro + resume sync agenda
c:\WISDOMAPP\lib\screens\admin_screen.dart           ← admin principal
c:\WISDOMAPP\lib\screens\admin_financial_tips_page.dart
c:\WISDOMAPP\lib\screens\admin_cursos_tab.dart
c:\WISDOMAPP\lib\screens\cursos_videos_screen.dart
c:\WISDOMAPP\lib\screens\landing_screen.dart
c:\WISDOMAPP\lib\screens\wisdom_agenda_screen.dart   ← chips Sync/Hoje/Config + limpeza período
c:\WISDOMAPP\lib\screens\finance_screen.dart
c:\WISDOMAPP\lib\services\finance_instant_prefetch_service.dart
c:\WISDOMAPP\lib\services\finance_month_cache.dart
c:\WISDOMAPP\lib\services\external_calendar_bidirectional_sync.dart
c:\WISDOMAPP\lib\services\external_calendar_scheduled_sync.dart
c:\WISDOMAPP\lib\services\widget_update_service.dart
c:\WISDOMAPP\lib\widgets\fixed_pending_prefs_sheet.dart
c:\WISDOMAPP\lib\widgets\agenda\agenda_bulk_clear_period_dialog.dart
c:\WISDOMAPP\deploy.ps1                              ← NÃO stripar load() do bootstrap
c:\WISDOMAPP\scripts\Validate-HostingPreDeploy.ps1
c:\WISDOMAPP\codemagic.yaml
c:\WISDOMAPP\firebase.json
c:\WISDOMAPP\firestore.indexes.json
c:\WISDOMAPP\firestore.rules
c:\WISDOMAPP\functions\index.js
c:\WISDOMAPP\web\index.html
c:\WISDOMAPP\web\flutter_bootstrap.js                ← _flutter.loader.load obrigatório
c:\WISDOMAPP\web\version.json
c:\WISDOMAPP\android\app\build.gradle
c:\WISDOMAPP\android\app\src\main\AndroidManifest.xml  ← 3 widgets + service
c:\WISDOMAPP\pubspec.yaml
c:\WISDOMAPP\WISDOMAPP_MEMORIA_BKP.md                ← ESTE ARQUIVO
```

---

## 16. CHANGELOG DA MEMÓRIA

| Data | Release | Registro |
|------|---------|----------|
| 02/10/2026 | **10.05+34** (deploy completo; 30–33 parciais) | **Causa raiz dos módulos girando na web:** SDK JS do Firestore 11.9.1 (assert ca9/b815 — alvo de escuta reaberto rápido → fila interna morta até F5). Correções: SDK 12.19.0 fixo no index.html, **sem long-polling forçado** (auto-detecção), escuta única compartilhada (FinanceSharedStream/KeyedStreamBuilder) no Início/Financeiro/Admin, nenhum terminate()/clearPersistence, recarga automática com aviso (index.html, intervalo 30 s), firebase.json sem cache no '/'. **Saldo por conta:** writer dos buckets gravava `netByAccount.<id>` literal com set() (mapa vazio) → mapa aninhado, versão 4 (paidFrom/cartão como CT), migração de todos os usuários. **Totais = regra do CT** no servidor (ctFinancePeriodTotals por data efetiva; fatura/transferência/meta fora dos totais, voltam no saldo via goalReserveNet/ajusteSaldo). Admin: prazos + erro visível + formulários não gravam vazio por cima; Promover a admin com lista; Mercado Pago só master; editor da landing completo (landing_defaults.dart); % sócio lido de mp_project_config/main (50%). Financeiro: relatórios mês a mês + PDFs modernos (até 1000 págs), fixas em tela cheia, ficha do banco em tela cheia, lançamento inteligente sem travar. Agenda: avisos modernos (expiram 24 h; function ctExpirarAvisosAgenda), limpeza rápida com prévia (Google/Apple só ocorrências; financeiro só sai do calendário) autorizada pelo dono, integração total (apagou no Google/iPhone sai do app), 279 emojis, fuso Brasília no servidor, série anual não apaga o ano. Cursos: prévia do vídeo como capa (poster gerado no upload), rola na web, Voltar, audiência contando. Android: receivers do flutter_local_notifications, bloqueio de chamadas do CT (corrigido: DDD/9º dígito/emergência/sem permissão passa). iOS: NSMicrophone/NSPhotoLibraryAdd; CI: chave App Store Connect GDVCL94D6D regravada via `gh secret set < arquivo` (pelo PowerShell dava 401), build sem Widget quando App Group não é configurável. Pendências do dono: declaração READ_CONTACTS no Play Console; criar App Group group.com.wisdomapp.widget p/ o widget voltar; enviar AAB 34; testar no aparelho. |
| 02/10/2026 | **10.05+29** (deploy completo; a 28 foi só web) | **Release grande.** Financeiro igual ao CT (lançamentos novo/editar/duplicar, fixas, gráficos, bancos/cartões completos com várias chaves Pix + Pix padrão, Gerar Pix / Receber via Pix com BR Code local e baixa manual, calendário opt-in desligado por padrão com cor vermelho/verde, importar extrato OFX/CSV/PDF/print); despertador e sons do CT (soneca 3/5, Encerrar, app fechado; functions agenda_soneca/ctSonecaAcao); paletas de cores do CT (diálogo único Paleta 01/02/03); modo escuro em todos os módulos (Configurações › Aparência, padrão Claro, salvo no aparelho); Calculadora e Anotações removidas, ordem Início·Financeiro·Agenda·Objetivo·Cursos; Cursos branco estilo YouTube; compartilhamento p/ 4 pessoas. **Admin:** sem carregamento eterno, níveis que restringem (admin/suporte/editor/editor_conteudo), **master SÓ raihom@gmail.com e isabelle.krdoso@gmail.com por e-mail verificado** (app, functions `admin_auth.js` e regras `isMaster()`), «Promover a admin» (`ctAdminSetUserRole`), Receitas & Despesas, Previsão real, Usuários ativos/Painel, E-mails com problema, diagnóstico de notificações, Uso dos módulos; Tarley = `editor_conteudo` (só vídeos dos Cursos + Dicas). **Segurança:** usuário não altera o próprio role/plan/licença/pagamento (regras + auth_service/delegate sem gravar esses campos; Novo membro cria a conta numa instância secundária). **Auditoria aplicada:** série anual não apaga mais compromisso comum; aviso só pelo servidor (sem dobro); progresso de curso por conta + flush; upload putFile; certificado PDF, compartilhar curso, comentários por aula; agenda com emoji, compartilhar e Resumo do dia; metas: saldo = carrossel, depósito vira reserva (`goalReserve`, fora de Receitas/Despesas), 52 semanas só semana inteira, resgate; fixas com ID fixo por mês e sem parcela extra no dia 29–31; parcela em centavos; Pix campo 26 ≤ 99 (também no CT). Play: sem READ_CONTACTS, targetSdk 36, proguard sem keep amplo. Pendências do dono: enviar o AAB ao Play, start do iOS (GitHub Actions, branch `codemagic-ios-ready`, marcar `setup_capabilities` por causa do Time Sensitive), testar no aparelho (Pix pago num banco real, despertador com app fechado, login/cadastro com a trava). |
| 01/10/2026 | 10.05+26 (sem deploy) | **MEMÓRIA GERAL DO DIA — tudo pronto para o deploy completo de 02/10** (pedido do dono). Feito hoje, tudo commitado em `master` (sem push/deploy): (1) **Financeiro** portado do Controle Total (fixas com pizza 3D/mês a mês/a pagar, calendário opt-in, saldos na hora, pendentes estáveis, Evolução do Saldo só pago, PDF com abertura real); (2) **Início** (`WisdomDashboardScreen`) modernizado com financeiro completo; (3) **Admin** em seções + Painel geral; (4) **Cursos** (vitrine, tela do curso, progresso) + **YouTube** corrigido (erro 153 no celular, parser de links) + **envio rápido de vídeo** no admin; (5) **leveza** (capas inteiras com fundo desfocado, um player por vez, lançamentos sem esperar o servidor, escutas guardadas, R8 enxuto −16,8% dex); (6) **deploy completo padronizado** (seção «Deploy completo (padrão Controle Total)»). **Permissão de cursos:** RESOLVIDO sem deploy — `users/kskCuIbaFQPArO8KrbFeoeCeaLk2` (tarleypmgo@gmail.com) role `user`→`gestor` em 01/10; raihom e isabelle.krdoso já eram `admin` (a function `requireCourseContentEditor` não precisou mudar). **Antes do deploy de 02/10:** (a) há alterações ANTIGAS não commitadas que não são deste dia — widgets Android (`ControleTotalWidgetProvider.kt`, `MainActivity.kt`, layout/xml/strings, `AndroidManifest.xml`), bloco dos widgets no `proguard-rules.pro`, `scripts/Validate-HostingPreDeploy.ps1`, `web/index.html` e arquivos apagados em `test/`/`tool/` — revisar com o dono o que entra; (b) o AAB em `build/` é de teste (não publicar); (c) testar no aparelho os checklists das entradas abaixo (R8, cursos, lançamentos, Início); (d) repositório `raihom-netizen/wisdomapp` está PÚBLICO no GitHub — dono decide se torna privado. Regras gerais (todo deploy completo): READ_CONTACTS (WISDOMAPP não usa) e R8 sem keeps amplos — ver `C:\Users\RAIHOM\.claude\CLAUDE.md`. |
| 01/10/2026 | 10.05+26 (sem deploy) | **Leveza e velocidade — vídeos, lançamentos, app e Android** (commits `e8f420e`, `babf9de`, `d58bdb2`, `2024ebb`, `3103077`). **Vídeos:** capa do YouTube por resolução (`YoutubeUrlHelper.thumbnailUrlsForWidth`): listas = `mqdefault` (16:9, ~10 KB); destaque/tela do curso/tela cheia = largura × DPR → `maxresdefault` (1280×720 é o máximo que o YouTube fornece) com reserva sd→hq→mq. Capa **sempre inteira** (`CourseFramedImage`: `BoxFit.contain` + a mesma imagem decodificada a 24 px como fundo desfocado e escurecido — sem blur por frame), placeholder em gradiente sem spinner, `cacheWidth` pelo quadro (sem upscale). Memo das URLs de capa (`CourseMediaUrlResolver.resolveImageUrls`, TTL 15 min, `cachedImageUrls` síncrono, Storage em paralelo; modo leve com YouTube não varre o Storage). **Player:** identidade estável (`imageFingerprint`) — antes qualquer rebuild do pai com Map novo PARAVA o vídeo; embed não recarrega quando só o pôster chega (autoplay); **um player por vez** (`CourseActivePlayer` destrói o embed anterior — inclusive o de baixo da tela cheia); MP4 `preload=metadata` até tocar; busca da vitrine com debounce 250 ms; `web/index.html` com `dns-prefetch` (img.youtube.com, youtube-nocookie, youtube, ytimg) — boot intocado. Upload de capa do admin já aceita até 4K (sem redimensionar; só a exibição usa `cacheWidth`). **Lançamentos:** `TransactionSaveService.writeLocalFirst` — o Future do Firestore só termina com o OK do servidor (offline: nunca); agora espera 120 ms por erro imediato e segue (falha tardia: aviso + na exclusão relê o período). Vale para novo lançamento (Financeiro e Início), edição (`finance_transaction_edit_dialog`), exclusão (sem leitura prévia; transferência em 1 lote) e exclusão em lote (`WriteBatch` ≤450, antes 1 delete por vez); confirmar pagamento abre com os dados da tela; `UserCategoriesService.load` com memo de 90 s (limpo a cada alteração). **App:** `widgets/keyed_stream_builder.dart` — `StreamBuilder(stream: ref.snapshots())` no build trocado em menu lateral, Objetivos, Painel (`dashboard_screen`), Orçamento, folha de lançamentos do objetivo, mensagens globais, manutenção, escolha de plano, Open Finance e produtividade; cache de cursos lido depois do 1º frame também no celular. **Não tocado (outro agente):** `WisdomDashboardScreen`/home_* e `goal_52_weeks_objective_card`, `fifty_two_weeks_schedule_sheet` (ainda com `.snapshots()` no build — sugestão). **Web — não ligado:** `--tree-shake-icons` compila (MaterialIcons 1.645.184→90.948 B, Cupertino 257.628→1.472, FA Brands 215.132→2.304), MAS `firebase.json` serve `/assets/**` com `immutable` 1 ano e o nome da fonte não muda: depois de um deploy o navegador ficaria com a fonte cortada antiga (ícones em branco). Ligar só junto com cache curto/`no-cache` para `assets/fonts` e `AssetManifest*` (mesmo risco já existe hoje para assets novos). **Android R8:** removidos `-keep { *; }` de firebase/gms/gson/mercadopago; ficam só `io.flutter.plugins.firebase.firestore.**`, `com.dexterous.flutterlocalnotifications.models.**`, atributos e dontwarn. Medido no AAB release: dex 8.845.020→7.357.188 B (−16,8%), sem `missing_rules`. **Testar no aparelho (Android release):** login e-mail/Google/Apple; Firestore lendo/gravando offline e online; push FCM com app fechado; notificação agendada (criar, reiniciar o aparelho, conferir que dispara); widgets 3 tamanhos; OCR/ML Kit; upload de comprovante (Storage/Functions); player de cursos (YouTube e MP4) e tela cheia; calendário do aparelho; compra/assinatura se houver. **Testar cursos:** capas inteiras sem faixa/corte em lista e destaque, nitidez em tela grande, tocar um vídeo e abrir outro (o 1º para), digitar na busca com vídeo do feed tocando (não para). **Testar lançamentos:** salvar/editar/excluir com e sem internet (aparece na hora; sincroniza depois). |
| 01/10/2026 | 10.05+26 (sem deploy) | **Deploy completo padronizado com o Controle Total** (commits `1c6e7a3` scripts + `612ec0f` memória; ver seção «Deploy completo (padrão Controle Total)» no fim). `sync_app_version.ps1` virou o script único (`-Build N`, `-Marketing`, `-Conferir`, `-Antigo`; regex case-sensitive — o `-replace` antigo casava `buildNumber` dentro de `iosBuildNumber`); marcadores de cache-bust novos: `web/index.html` (`flutter_bootstrap.js?v=26`, `swVersion = "v=26"` no registro do `firebase-messaging-sw.js`) e `BANNER_CACHE_V` no SW (ícones do push com `?v=`). `deploy.ps1 -WebOnly` = **só hosting** (antes ia functions/firestore/storage + bootstrap junto) + `-DryRun`; completo sem git automático (`-LegacyCodemagic` mantém o fluxo antigo). Novos: `build_aab_release.ps1` (analyze → appbundle → 16 KB → `D:\TEMPORARIOS` → conferência), `scripts/Validate-Aab16Kb.ps1`, `scripts/Conferir-Aab.ps1` (versionCode do manifest, READ_CONTACTS, strings em utf-8/latin-1/utf-16). `Invoke-FirebaseDeploy.ps1` com `--project wisdomapp-b9e98`. `codemagic-ios.yml` agora só manual (não dispara Codemagic a cada push). |
| 01/10/2026 | 10.05+26 (sem deploy) | **Admin Cursos — envio rápido** (`f6fec69`). Card «Enviar vídeo rápido» no topo de `admin_cursos_tab.dart`: colar link → prévia via oEmbed público (`youtube_oembed_service.dart`, aceita CORS na web; falhou = só o ID) → título automático; essenciais visíveis e MP4/validade/publicado em «Mais opções»; botão «Publicar» com Salvando…/Publicado ✓ sem travar a tela; MP4 com progresso e «Cancelar envio» (`CourseUploadCancelToken` em `course_video_file_service.dart`); validação de formato/tamanho antes de enviar; capa até 3840x2160 (`courseCoverMaxEdge` 1920→3840). Biblioteca em lista compacta (cards grandes no botão). Streams `app_config`/`course_stats` guardados no estado. Sem campo de ordem em `course_videos` → sem arrastar para ordenar. |
| 01/10/2026 | 10.05+26 (sem deploy) | **Início (`WisdomDashboardScreen`) modernizado no padrão do painel do Controle Total** (commits `87ece7f`, `c73277a`, `4ad11b5`, `f173c47`, `f385333`, `34d3449`). Ordem no celular: cabeçalho (marca, «Bom dia/Boa tarde/Boa noite, Nome», data por extenso) → **Acesso rápido** (grade com os 9 módulos do shell: 1 Financeiro, 2 Objetivos, 3 Agenda, 7 Cursos, 5 Dicas, 6 Relatórios, 4 Calculadora, 8 Anotações, 9 Ajustes; 4/5/9 por linha) → Dica do dia (+ Veja mais) → **Seu Financeiro** → Objetivos Financeiros. Tela ≥ 1100 px: 2 colunas (financeiro 3/5 · dica+objetivos 2/5); conteúdo centralizado até 1400 px. Os 4 chips do cabeçalho antigo viraram a grade (todos os destinos mantidos). **Financeiro do Início** (`home_finance_overview_panel.dart`): período (Mês anterior/Mensal/Anual/Por período), card do saldo (acumulado + abertura + receitas/despesas + barra receitas×despesas + «Sobrou/Faltou» + sparkline), carrossel de contas, «Em aberto» (`home_pendentes_cards.dart`: Receitas/Despesas pendentes com a MESMA regra das faixas do `finance_screen` + «Contas fixas de <mês>» A pagar/A receber que abre o `FixasAPagarPainel`; lista dos pendentes em folha com `FixasVisaoGeral` no topo e Pagar/Receber pelo `showFinanceConfirmPaymentSheet`), gráficos «Evolução do Saldo» (só o pago — `movimentoDiarioPago` + abertura real; para em hoje) e «Despesas por categoria» (`CategoriasRoscaModerna`, abas Ícones·Pizza 3D·Barras, despesas pagas do período), botão «Ir para o Financeiro». Toque em Receitas/Despesas agora abre o insight do escopo certo (antes os dois abriam «saldo»). Ocultar valores vale para tudo (gráficos inclusive). **Performance:** nenhuma leitura pesada nova — lançamentos do período = UMA escuta guardada no estado (troca só com o período), contas/objetivos/dicas com escuta guardada (antes `.snapshots()`/streams criados no build), último valor por usuário em memória (volta ao Início sem piscar), pendentes abrem depois do 1º quadro e reconectam 2/4/8/16 s mantendo o último valor bom. `financeTransactionsPeriodDocs` passou a FECHAR as 3 escutas no `onCancel` (antes ficavam vivas para sempre). Helpers puros + teste: `utils/home_painel_resumo.dart`, `test/home_painel_resumo_test.dart`. Fórmula de saldo intocada; `DashboardScreen` (reserva) não mexida. **Lição:** havia arquivos do Cursos já em stage por outro agente — commitar SEMPRE com `git commit --only -- <arquivos>` para não levar o stage alheio. |
| 01/10/2026 | 10.05+26 (sem deploy) | **Financeiro — port do Controle Total (30/09–01/10)** (commits `d35ecdc`, `4140571`, `73ac1a2`, `9a841b0`, `30f094d`, `1eb528f`). **Fixas:** `utils/fixas_resumo.dart` + widgets `fixas_totalizador_card` (total do mês com valor LANÇADO, aviso de valor diferente, chips, pizza 3D), `fixas_visao_geral` (Mês atual padrão, Em aberto × Previsão do mês, valores em cima das barras), `fixas_mes_a_mes` (card + relatório), `fixas_a_pagar_painel` («O que tenho que pagar/receber»; sem Finance Pro → paga sempre pelo Confirmar pagamento normal). Ordem nas telas: total → fixas cadastradas → período → mês a mês → a pagar. Helpers novos: `theme/theme_context.dart` (cores neón locais, GeminiTheme não foi tocado), `periodo_campos`, `modern_module_ui`, `categorias_painel`, `categorias_rosca_moderna`. Visão geral também no topo das listas de Receitas/Despesas pendentes. **Calendário:** lançamento financeiro só aparece na Agenda com `addToCalendar == true` (ausente = desligado; bridge + `agenda_finance_pending_utils`); ao ligar abre a paleta com vermelho/verde (`FinanceCalendarColorPicker.escolherAoAtivar`); fixas legadas sem campo = desligado. **Novo lançamento** começa em «Escolher categoria» e pede a categoria ao confirmar. **Pendentes na Web:** último valor bom + reconexão 2/4/8/16 s. **Saldos na hora:** delta otimista (`applyMutationToOpening`/`applyMutationToPeriodNet`, `FinanceOpeningBalanceService.applyOptimisticMutation` + `revision`, refresh autoritativo quando o bucket confirma, também limpa `FinanceServerTotals`). **Painel (DashboardScreen):** Evolução do Saldo só com o pago (`movimentoDiarioPago`) e PDF com abertura real. **Fatura:** prévia sem cortes. Testes novos em `test/` (fixas_resumo, finance_calendar_opt_in, finance_balance_optimistic_delta, finance_evolucao_saldo). **Não portado (não se aplica):** Finance Pro/baixa de controle (sem contas `externalResourceId`/Polp), pagamento de fatura/transferência fora dos totais (nada no WISDOMAPP grava `faturaPagamento`/`transferenciaPropria`), faturas iguais ao banco (functions `cartao_faturas*`/Polp inexistentes), datas Fecha/Vence no card do cartão (modelo sem `cardDueDay` e card sem linha de info), pendentes do Vendas (sem módulo), «pendente fica pendente» (WISDOMAPP não converte pendente em pago). Sem functions para deploy. |
| 01/10/2026 | 10.05+26 (sem deploy) | **Admin + Cursos + YouTube** (commits `9ad1ef7`, `596d75c`, `6f00947`). **YouTube:** parser novo `youtube_url_helper.dart` (watch, youtu.be, shorts, embed, live, v/, e/, m./music., nocookie, iframe colado, `&t=`/`&list=`/`?si=`, ID puro; rejeita playlist/canal) + `validationMessage` no cadastro + `videoIdFromData` em todos os leitores; causa do vídeo não tocar no celular = `loadHtmlString` sem `baseUrl` (YouTube recusa embed sem Referer, erro 153) → `baseUrl https://wisdomapp.com.br` + `origin`; web com `referrerpolicy`; capa em cascata maxres→hq (maxres dá 404). Teste `test/youtube_url_helper_test.dart`. **Cursos:** vitrine (busca, filtros, «Continuar assistindo», cards com selo NOVO/CONCLUÍDO, aulas, duração, progresso; feed antigo no botão de visualização) + `course_detail_screen.dart` (aulas = YouTube + MP4s do doc, progresso por aula em `users/{uid}/course_progress`, «Continuar · mm:ss», tela cheia). Player: só `startAtSeconds` explícito no shell (fixo ao abrir a aula — não remonta). **Admin:** menu em seções coloridas (padrão CT) + item «Painel geral» (`admin_painel_geral_tab.dart`/`admin_painel_geral_service.dart`): KPIs, gráficos fl_chart, previsão só de pagantes, receitas & despesas com custos em `users/{uid}/settings/admin_costs`, resultado por usuário, engajamento `course_stats`. **Pendente:** function `requireCourseContentEditor` aceitar e-mail do token/gestor por e-mail (bloqueado nesta sessão — pedir ao dono); uso por módulo exige callable (porte de `ctAdminModulosUso` do CT). |
| 02/08/2026 | 10.05+26 | **Memória geral completa atualizada.** Release `10.05+26` (#26) web+force+AAB+iOS. **Domínio:** apex `wisdomapp.com.br` OK (`version.json` 10.05+26). **Agenda:** chips Sync·Hoje·Config (estilo Escalas CT); sync bidirecional + auto 00:00/12:00 (`external_calendar_*`); limpeza por período com datas digitáveis; células 2+ eventos com divisão de cores. Mantém boot web `load()`, financeiro prefetch, widgets 3 tamanhos, cursos/`course_stats`, UI sem audiência. Artefatos: `D:\TEMPORARIOS\WISDOMAPP_*_10.05+26_*`. |
| 02/08/2026 | 10.05+25 | Memória intermediária (#25). Splash web corrigido (`load()` no bootstrap); domínio ainda `OWNERSHIP_MISSING`; financeiro prefetch; widgets 3 tamanhos; cursos analytics; agenda sem audiência. |

| 30/07/2026 | 10.05+24 | **Deploy completo e memória atualizada.** Web publicada, force update ativo, AAB em `D:\TEMPORARIOS`, pacote iOS gerado e Codemagic acionado. Agenda alinhada ao Controle Total (hoje/resumo, cores, ações, início semanal domingo/segunda e limpeza rápida), contato WhatsApp pela agenda do celular, Admin Cursos com progresso/retorno/cache e descrição completa. Correção Codemagic para App Group, perfil e Team ID do Widget no commit `07f9e97`. |
| 30/06/2026 | 10.04+21 | **Memória atualizada.** Build 21 web/Android; iOS 23. Paridade mídia alinhada ao padrão Gestão YAHWEH (Storage→URL→Firestore, gate único). Referência cruzada: `C:\gestao_yahweh_premium_final\docs\MAPEAMENTO_MIDIA_WISDOMAPP_IMPLEMENTACAO_CIRURGICA.md`. |
| 28/06/2026 | 10.04+16 | **Criação deste backup.** Player cursos YouTube-style. Calendários Google+Apple. Grid admin dicas compacta. Versão alinhada. Codemagic anti-90189. Label "Objetivos Financeiros". |
| 28/06/2026 | 10.04+16 | **Seção 18:** roadmap port WISDOMAPP → Controle Total (`C:\Controletotalapp_Independente`). |

---

## 18. PORT WISDOMAPP → CONTROLE TOTAL APP

> **Projeto destino:** `C:\Controletotalapp_Independente\flutter_app`  
> **Versão CT (referência recente):** `49.57+4957581` · **Versão origem WISDOMAPP:** `10.05+26`  
> **Documento espelho no CT:** `CONTROLETOTAL_PORT_WISDOMAPP.md` / `PONTO_BASE_MEMORIA_*.md` (raiz do CT)  
> **Regra de ouro:** copiar **comportamento e arquivos** do WISDOMAPP; **não retroagir** o que já funciona no CT (escalas, calculadora, deploy 49.x). Fluxo inverso também: widgets Android, sheet meses fixas e boot web leve já vieram do CT → WISDOMAPP.

### 18.1 Objetivo geral

Padronizar o **Controle Total** com as melhorias já validadas no WISDOMAPP:

| # | Feature | Origem WISDOMAPP | Status no CT | Prioridade |
|---|---------|------------------|--------------|------------|
| A | Cofre pessoal (financeiro) | Spec + padrões CT/WISDOMAPP | ❌ Não existe | Alta |
| B | Migração lançamentos entre bancos | `finance_bulk_assign_screen.dart` v2 | ⚠️ Só «sem conta» (v1) | Alta |
| C | Alerta exclusão banco + remover lançamentos | `finance_delete_account_dialog.dart` | ❌ Dialog genérico | Alta |
| D | Meta Financeiro completo + 52 semanas | `meta_financeira_screen` + widgets | ⚠️ Meta básica, sem 52 | Alta |
| E | Painel Início: Meta + Financeiro integrados | `home_objective_finance_panel`, `home_finance_overview_panel` | ❌ Dashboard legado grande | Alta |
| F | Dicas financeiras/gospel no Início | `wisdom_dashboard` + `financial_tips_catalog_service` | ❌ Sem catálogo Firestore | Média |
| G | Lançamento expresso — compromisso particular UI | `lancamento_expresso_plantao_sheet.dart` | ✅ Similar | Média |
| H | Compromisso particular **sem sync agenda externa** | N/A (CT não leva GCal) | A definir stub | Média |
| I | Performance iOS/Android/Web | padrões cache/streams | Parcial | Alta |
| J | Visualizar comprovantes | `anexo_viewer_*` | ✅ Existe | Verificar paridade |

---

### 18.2 Módulo financeiro — itens A, B, C

#### A) Cofre pessoal

**Situação:** termo «Cofre pessoal» ainda **não implementado** em nenhum dos dois repos (só «cofre do sistema» = Keychain em `offline_credentials_store.dart`).

**Spec recomendada (implementar no CT, replicável no WISDOMAPP depois):**

| Item | Detalhe |
|------|---------|
| Conceito | Reserva separada (dinheiro físico / emergência) fora da faixa principal de bancos |
| Firestore | `users/{uid}/finance_accounts` com `productType: 'vault'` ou doc `settings/finance_prefs` → `vaultAccountId` |
| UI | Card «Cofre pessoal» no Financeiro + saldo ocultável (`SensitiveBalancePreferences`) |
| Lançamentos | Mesma coleção `transactions` com `financeAccountId` do cofre |
| Regras | Não entra em Open Finance; não migra para banco externo sem confirmação |

**Arquivos base CT (já existem):** `sensitive_balance_preferences.dart`, `finance_accounts_service.dart`, `finance_screen.dart`.

**Gatilho:** não confundir com filtro «Ocultar saldo zero» (`financeStripHideZeroBalances`).

#### B) Migração lançamentos entre bancos

**Origem (WISDOMAPP — versão completa):**

```
lib/screens/finance_bulk_assign_screen.dart   ← enum _MigracaoModo { semConta, transferirBanco }
lib/screens/finance_screen.dart               ← _openBulkAssignFromStrip + initialSourceAccountId
lib/utils/finance_transactions_hub.dart
lib/widgets/finance_bank_brand_thumb.dart
lib/constants/finance_account_visuals.dart
```

**Destino CT:** substituir `flutter_app/lib/screens/finance_bulk_assign_screen.dart` pela versão WISDOMAPP (adaptar imports/branding).

**Comportamento:**

1. Modo «Sem conta» → atribuir `financeAccountId` em lote (já existe no CT).
2. Modo «Transferir banco» → origem + destino + período + filtro receita/despesa → reescreve `financeAccountId` / `paidFromFinanceAccountId` / pares `transferPairId`.
3. Abrir do Financeiro com conta filtrada → `initialSourceAccountId` pré-seleciona origem.

**Regra:** usar `FinanceAccountsService` + batch Firestore; respeitar `firestoreUserDocIdForAppShell(uid)`.

#### C) Excluir banco — alerta + remoção de lançamentos

**Origem WISDOMAPP:**

```
lib/widgets/finance_delete_account_dialog.dart     ← showConfirmDeleteFinanceAccountDialog
lib/services/finance_accounts_service.dart         ← countLinkedTransactions, deleteAccount
lib/screens/finance_accounts_screen.dart           ← fluxo completo
```

**Destino CT:** hoje usa `AlertDialog` genérico («Lançamentos antigos podem continuar…») — **substituir** pelo dialog WISDOMAPP.

**Fluxo obrigatório:**

1. `countLinkedTransactions(uid, accountId)` antes do dialog.
2. Dialog vermelho: «ATENÇÃO: removerá permanentemente N lançamentos».
3. `deleteAccount` retorna quantidade removida → SnackBar confirmando.

**Gatilho:** transferências (`transferPairId`) devem ser tratadas no service (já em WISDOMAPP `finance_accounts_service.dart`).

---

### 18.3 Meta Financeiro completo + Projeto 52 semanas (item D)

**Nome no CT:** manter **«Meta Financeira»** (label drawer/sistema CT) — conteúdo igual WISDOMAPP «Objetivos Financeiros» + 52 semanas.

**Copiar do WISDOMAPP → CT (`flutter_app/lib/`):**

| Arquivo | Função |
|---------|--------|
| `screens/meta_financeira_screen.dart` | Tela principal (substituir CT) |
| `widgets/create_financial_goal_dialog.dart` | Criar meta + toggle 52 semanas |
| `widgets/home_objective_finance_panel.dart` | Card no Início |
| `widgets/fifty_two_weeks_schedule_sheet.dart` | Grade 52 semanas + depósito |
| `widgets/goal_52_weeks_summary_panel.dart` | Resumo semanas pagas |
| `widgets/goal_52_weeks_pdf_button.dart` | Botão PDF (se existir) |
| `utils/fifty_two_weeks_plan.dart` | Cálculo semanas 1→52 |
| `services/goal_52_weeks_pdf_service.dart` | Export PDF cronograma |
| `services/goal_deposit_service.dart` | Depósitos + marcar semanas |
| `models/financial_goal.dart` | Modelo (se CT divergir, merge) |

**Firestore (sem mudar schema CT):**

- `users/{uid}/goals/{goalId}` — campos: `planType: '52weeks'`, `weeklyIncrement`, `planStart`, `paidWeeks[]`, `targetAmount`, `currentAmount`, `dueDate`.
- `users/{uid}/goals/{goalId}/contributions` — aportes.

**Integração Financeiro:**

- Depósito na meta pode gerar lançamento em `transactions` (ver `goal_deposit_service.dart`).
- Painel Início chama `onNavigateTo` índice Meta (CT: idx 2 no `home_shell.dart`).

**52 semanas — regras:**

- Semana 1 = menor valor; semana 52 = maior; incremento = `(target - week1*52)` distribuído.
- `FiftyTwoWeeksPlan.currentWeekNumber(planStart)` para «semana atual».
- PDF exportável (`Goal52WeeksPdfService`).

---

### 18.4 Painel Inicial integrado (item E)

**Origem WISDOMAPP:**

```
lib/screens/wisdom_dashboard_screen.dart      ← layout Início moderno
lib/widgets/home_finance_overview_panel.dart  ← resumo financeiro
lib/widgets/home_objective_finance_panel.dart ← meta + 52 semanas
lib/widgets/finance_tip_modern_card.dart
```

**Destino CT:** `dashboard_screen.dart` (~10k linhas) — **não apagar** funcionalidades CT (escalas, plantões, promo).

**Estratégia:**

1. Extrair seções WISDOMAPP como widgets reutilizáveis no topo do `dashboard_screen.dart`.
2. Ordem sugerida no Início CT:
   - Hero / atalhos (manter CT)
   - **1 dica financeira** + botão «Veja mais» (item F)
   - `HomeFinanceOverviewPanel`
   - `HomeObjectiveFinancePanel`
   - Restante CT (escalas, pendentes, etc.)

**Gatilho:** CT usa `_hideSensitiveBalances` — propagar para novos painéis.

---

### 18.5 Dicas financeiras + gospel no Início (item F)

**Origem WISDOMAPP:**

```
lib/services/financial_tips_catalog_service.dart   ← watchHomeTips, partitionForHome
lib/services/financial_tips_home_sync_service.dart ← app_config/financial_tips_home
lib/data/biblical_finance_tips.dart
lib/data/financial_tips_firestore_seed_bank.dart
lib/utils/insights_engine.dart                     ← coleção financial_tips
lib/screens/financial_tips_fullscreen_page.dart
lib/widgets/finance_tip_modern_card.dart
lib/screens/wisdom_dashboard_screen.dart           ← 1 card + «Veja mais»
```

**Regras de exibição (OBRIGATÓRIO — igual WISDOMAPP):**

| Local | Quantidade | Comportamento |
|-------|------------|---------------|
| **Painel Início** | **1 dica** (`tipOfDay`) | Card completo + botão **«Veja mais»** |
| **Módulo Dicas** (se existir) | **últimos 3 dias** | `FinancialTipsCatalogService.kModuleHistoryDays = 3` |
| Rotação | Por dia civil | `resolveTipForDate` + `app_config/financial_tips_home` |

**CT:** copiar serviço + widget; criar aba/módulo ou fullscreen «Dicas» se não existir.

**Admin (opcional CT):** portar `admin_financial_tips_page.dart` + grid compacta.

---

### 18.6 Lançamento expresso — compromisso particular (item G, H)

**Origem:** `lib/widgets/lancamento_expresso_plantao_sheet.dart` (WISDOMAPP ≈ CT — mesma base).

**Manter no CT (igual WISDOMAPP):**

- Título «Compromisso particular» / «Editar compromisso particular»
- **6 ícones coloridos** de compromissos frequentes (toque preenche descrição + cor)
- Seletor de **datas** (calendário / série)
- Toggle financeiro vs compromisso simples
- Valor particular override
- Lembrete personalizado (notificação local CT)

**NÃO portar / DESLIGAR no CT:**

- Sync **Google Calendar** / **Apple Calendar** (`google_calendar_sync_service`, EventKit)
- Opcional: se CT não usar módulo Agenda WISDOMAPP, usar stub `ExpressCompromissoAgendaSync` que grava **só em `scales`** (sem `reminders` + espelho) — confirmar com produto

**Arquivo a adaptar no CT:**

```
flutter_app/lib/widgets/lancamento_expresso_plantao_sheet.dart
flutter_app/lib/services/express_compromisso_agenda_sync.dart  ← stub ou scales-only
```

**Gatilho:** manter `createdByLancamentoExpresso: true` e `source: 'lancamento_expresso'` para rastreio.

---

### 18.7 Performance — mesma velocidade WISDOMAPP (item I)

**Padrões a replicar no CT:**

| Padrão | Arquivo WISDOMAPP | Aplicar em |
|--------|-------------------|------------|
| Cache Firestore contas | `finance_accounts_service.dart` → `Source.cache` primeiro | CT finance |
| HomeShell lazy modules | `home_shell.dart` `_materializedModuleIndices`, max 2 | CT `home_shell.dart` |
| Debounce busca financeiro | `app_business_rules.searchDebounceMs = 300` | CT |
| Streams paralelos | `finance_screen.dart` contas + hideZero em paralelo | CT |
| Safari Firebase init | `main.dart` retries + long-polling | CT `main.dart` |
| `DebouncedTextController` | bulk assign / filtros | CT bulk assign |
| Optimistic UI pagamentos | `finance_screen.dart` `_optimisticPaidIds` | CT se faltar |

**Regra:** toda tela financeira deve abrir **instantânea** com cache local; servidor atualiza depois.

---

### 18.8 Comprovantes (item J)

**Origem = Destino (verificar paridade):**

```
lib/screens/anexo_viewer_screen.dart
lib/screens/anexo_viewer_web.dart
lib/screens/anexo_viewer_stub.dart
lib/utils/anexo_viewer_helper.dart
```

**Fluxo:** lançamento com `receiptUrl` / Storage → ícone anexo → viewer PDF/imagem (web nativo, mobile WebView/PDF).

**Gatilho:** upload em `transaction_save_service.dart` + `FinanceTransferService` (receiptBytes).

---

### 18.9 Mapa de arquivos — diff CT vs WISDOMAPP

```
ORIGEM (copiar)                              DESTINO CT
─────────────────────────────────────────────────────────────────────────
WISDOMAPP/lib/screens/finance_bulk_assign_screen.dart
  → CT/flutter_app/lib/screens/finance_bulk_assign_screen.dart

WISDOMAPP/lib/widgets/finance_delete_account_dialog.dart
  → CT/flutter_app/lib/widgets/finance_delete_account_dialog.dart  (NOVO)

WISDOMAPP/lib/screens/finance_accounts_screen.dart  (trecho delete)
  → CT/flutter_app/lib/screens/finance_accounts_screen.dart

WISDOMAPP/lib/screens/meta_financeira_screen.dart + deps 52 semanas
  → CT/flutter_app/lib/...  (lista seção 18.3)

WISDOMAPP/lib/widgets/home_objective_finance_panel.dart
WISDOMAPP/lib/widgets/home_finance_overview_panel.dart
  → CT/flutter_app/lib/widgets/ + integrar dashboard_screen.dart

WISDOMAPP/lib/services/financial_tips_catalog_service.dart + widgets
  → CT/flutter_app/lib/services/ + dashboard

WISDOMAPP/lib/screens/wisdom_dashboard_screen.dart  (só padrão dicas 1+veja mais)
  → referência para refatorar CT dashboard
```

---

### 18.10 Regras de padronização CT ↔ WISDOMAPP

1. **Nomenclatura CT:** drawer continua «Meta Financeira»; marketing pode citar «52 semanas».
2. **Firestore paths:** idênticos (`users/{uid}/transactions`, `goals`, `finance_accounts`).
3. **UID doc:** sempre `firestoreUserDocIdForAppShell(uid)`.
4. **Cores:** CT mantém `AppColors` / tema CT; widgets portados adaptam gradientes.
5. **Versão:** CT mantém pipeline `49.x` próprio — **não** misturar `app_version.dart` entre projetos.
6. **Firebase:** projetos Firebase **diferentes** — não copiar `firebase_options.dart` entre repos.
7. **Não retroagir CT:** escalas, calculadora HE, convênios, admin 49.x permanecem.
8. **Commits:** port em branch `port/wisdom-finance-meta-52` no CT.

---

### 18.11 Ordem de implementação sugerida

```
Fase 1 — Financeiro crítico
  [ ] C) Dialog exclusão banco + deleteAccount com contagem
  [ ] B) finance_bulk_assign v2 (transferir banco)
  [ ] A) Cofre pessoal (spec + UI)

Fase 2 — Meta 52 semanas
  [ ] Copiar utils/widgets/services 52 semanas
  [ ] Substituir meta_financeira_screen.dart
  [ ] goal_deposit_service integrado

Fase 3 — Painel Início
  [ ] home_finance_overview_panel + home_objective_finance_panel
  [ ] Dicas: 1 card + «Veja mais» + módulo 3 dias

Fase 4 — Polish
  [ ] Lançamento expresso: confirmar UI ícones; stub agenda externa
  [ ] Performance cache/streams
  [ ] Teste comprovantes web/iOS/Android
```

---

### 18.12 Checklist pós-port (Controle Total)

- [ ] Excluir banco mostra contagem e remove lançamentos?
- [ ] Migrar banco A → B funciona com transferências?
- [ ] Meta 52 semanas cria cronograma + PDF + depósito?
- [ ] Início mostra **1** dica + «Veja mais»?
- [ ] Módulo dicas mostra só **3 dias**?
- [ ] Compromisso particular: ícones + datas; **sem** GCal/Apple sync?
- [ ] Comprovante abre em web e mobile?
- [ ] CT escalas/calculadora/admin intactos?

---

*Seção 18 — roadmap portabilidade. Atualizar ao concluir cada fase.*

---

## 17. CHECKLIST ANTES DE ENTREGAR QUALQUER CORREÇÃO

- [ ] Li a seção relevante desta memória?
- [ ] Minha mudança é mínima e focada?
- [ ] Não removi funcionalidade existente?
- [ ] Web + mobile compilam (`flutter analyze` nos arquivos tocados)?
- [ ] Se toquei versão → rodei/sync `sync_app_version.ps1`?
- [ ] Se toquei Firestore query → atualizei `firestore.indexes.json`?
- [ ] Se toquei OAuth/calendário → testei stub web vs mobile?
- [ ] Se toquei web/deploy → `build/web/flutter_bootstrap.js` ainda tem `_flutter.loader.load(`?
- [ ] Se toquei domínio → TXT `hosting-site=wisdomapp-b9e98` + Auth authorized domains?
- [ ] Se toquei port CT → consultei seção 18?
- [ ] Atualizei seção 16 desta memória se a mudança for estrutural?
- [ ] Deploy só se o usuário pediu explicitamente?

---

*Documento gerado como backup de referência do WISDOMAPP. Manter atualizado a cada release ou mudança arquitetural significativa. Snapshot ativo: **02/08/2026 · 10.05+26**.*

---

## Build iOS no GitHub Actions (02/09/2026)

Repo: `raihom-netizen/wisdomapp` (branch padrao `main`). O IPA e renomeado para
`WISDOMAPP.ipa` e passa pelos gates anti-90189 antes do envio. Bundle `com.wisdomapp`,
widget `com.wisdomapp.WisdomappWidget`.

O build iOS saiu do Codemagic e roda no GitHub Actions, workflow **iOS TestFlight**
(`.github/workflows/ios_testflight.yml`). O `codemagic.yaml` continua no repo como plano B.

**Nao roda sozinho.** O gatilho e apenas `workflow_dispatch`: nenhum push inicia build.
Para rodar:

    gh workflow run ios_testflight.yml --ref <branch>

ou GitHub > Actions > iOS TestFlight > Run workflow. Motivo: runner macOS conta **10x**
na cota de minutos (um build de 50 min custa ~500), entao build iOS so acontece quando
alguem pede — normalmente no fim do deploy completo.

**Xcode 26 e obrigatorio.** Desde 2026 a Apple recusa upload de app compilado com SDK
menor que o do iOS 26: `Validation failed (409) SDK version issue`. O runner `macos-15`
usa Xcode 16.4 — por isso o job roda em `macos-26`. Pegadinha: essa imagem traz varios
Xcode 26.x e **nem todos tem a plataforma iOS instalada**; escolher pelo numero maior cai
num que nao tem e o build morre em `iOS 26.0 is not installed`. O passo "Selecionar Xcode
26+ com SDK iOS instalado" ordena por versao completa e so aceita um cujo
`xcrun --sdk iphoneos --show-sdk-version` responda 26+.

**Como o IPA e gerado** (`scripts/gha_ios_build_ipa.sh`, igual nos quatro apps):
`flutter build ios --release --no-codesign` -> `xcodebuild archive` -> `xcodebuild
-exportArchive` com o ExportOptions escrito a partir dos perfis instalados no keychain.
Nao usa `flutter build ipa`: ele monta o proprio ExportOptions e deixa o `.ipa` em
caminhos que variam com o layout do repo.

**Como e enviado** (`scripts/gha_ios_publish_testflight.sh`): `app-store-connect publish
--testflight`, com 3 tentativas — sao ~130 MB e uma queda de rede no fim derrubava o build
inteiro. Se a Apple responder **90189** ("build number ja usado"), o script trata como
sucesso: o binario ja chegou, nao ha o que reenviar.

**Se o build deu certo mas o envio nao:** workflow **Enviar IPA ao TestFlight**
(`ios_enviar_testflight.yml`) baixa o IPA daquele run e so publica — ~5 min de runner em
vez de recompilar. Informe o numero do run (esta na URL do run em Actions).

**Secrets** (Settings > Secrets and variables > Actions), gravados por
`.\scripts\configurar_github_ios.ps1`: `APP_STORE_CONNECT_PRIVATE_KEY` (.p8),
`APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_ISSUER_ID` e
`CERTIFICATE_PRIVATE_KEY` (chave RSA). Os quatro apps (Controle Total, WISDOMAPP,
MOOVAUP, Gestao YAHWEH) estao na **mesma conta App Store Connect** (Issuer
`77a1debb-...`), entao a mesma chave `.p8` e a mesma chave RSA servem para todos — e
reusar a RSA e o que evita estourar o limite de 3 certificados Apple Distribution da
conta. Chave `.p8` e credencial: quem roda o script e o dono da conta, nunca o assistente.

**Armadilha ja paga:** condicao de passo escrita como `if: inputs.X != false` e pulada
quando o build vem de push — em push o contexto `inputs` vem vazio, e no GitHub Actions
string vazia compara igual a `false`. O run fica verde sem ter enviado nada. A forma certa
e `if: ${{ github.event_name != 'workflow_dispatch' || inputs.X }}`.

---

## Deploy completo (padrão Controle Total) — 01/10/2026

Mesmo roteiro do Controle Total (`C:\Controletotalapp_Independente`), adaptado ao WISDOMAPP
(Flutter na raiz, Firebase `wisdomapp-b9e98`, repo `raihom-netizen/wisdomapp`).
**Atalho:** quando o dono disser só «deploy completo com versão N» (N = novo build, ex.: 27),
executar os passos abaixo na ordem, sem pedir detalhes. Nada de deploy sem ordem explícita.

### Onde mora a versão (todos com o MESMO build)

| Ponto | Campo | Quem atualiza |
|-------|-------|---------------|
| `lib/constants/app_version.dart` | `buildNumber`, `versionCode` (= N), `iosBuildNumber` (= máx(ios+1, N)), `current` (marketing) | `sync_app_version.ps1 -Build N [-Marketing X]` |
| `pubspec.yaml` | `version: 10.05.0+N` | sync |
| `android/app/build.gradle` | `versionCode = N`, `versionName` — **no WISDOMAPP é fixo** (não usa `flutter.versionCode`), então é ele que vale no AAB | sync |
| `web/index.html` | `flutter_bootstrap.js?v=N`, `swVersion = "v=N"` (registro do FCM SW — é o que atualiza o PWA instalado) | sync (só esses marcadores; nada mais do index) |
| `web/firebase-messaging-sw.js` | `const BANNER_CACHE_V = "N"` | sync |
| `web/version.json` | version / buildNumber / versionCode / releaseTag | sync (e o `deploy.ps1` regrava `build/web/version.json`) |
| `ios/asc_build_number_floor.txt` | piso do App Store Connect | o CI iOS sobe o `iosBuildNumber` sozinho se ficar ≤ piso (anti-90189) |

`functions/package.json` tem `"version": "49.57.0"` (herdado do CT) — não é ponto de versão do app; não mexer.

### Roteiro passo a passo

**1. Alinhar a versão**
```powershell
.\scripts\sync_app_version.ps1 -Build 27                 # (+ -Marketing 10.06 se mudar a versão)
.\scripts\sync_app_version.ps1 -Conferir -Antigo 26      # tudo True e "Nenhum resto do build 26"
```
Se a versão de marketing mudar, a branch de build Android/web muda junto (`codemagic-10-06-ready`).

**2. Confirmar as melhorias no código** — grep dos marcadores da sessão + `flutter analyze`
(sem `error`). Conferir a §16 desta memória com o que vai sair.

**3. Regras gerais do dono (TODO deploy completo, todos os projetos — `C:\Users\RAIHOM\.claude\CLAUDE.md`)**
- **READ_CONTACTS / Play Console:** `Select-String android\app\src\main\AndroidManifest.xml -Pattern READ_CONTACTS`
  e `targetSdk` em `android/app/build.gradle`. Situação 01/10/2026: WISDOMAPP **não** pede
  READ_CONTACTS, `targetSdk = 36`. Se algum dia pedir: preferir o Seletor de Contatos; se precisar da
  agenda inteira, a declaração em Play Console › Monitorar e aprimorar › Políticas e programas ›
  Conteúdo do aplicativo › Permissões de contato é do dono (prazo 27/01/2027 para targetSdk 37+).
  O `Conferir-Aab.ps1` também avisa se o AAB pedir a permissão. **Informar no resumo do deploy.**
- **R8 / proguard:** `android/app/proguard-rules.pro` sem `-keep` amplo de biblioteca
  (`com.google.**`, `com.google.firebase.**`, `androidx.**`…); release com `minifyEnabled true` +
  `shrinkResources true` + `proguard-android-optimize.txt` (já está). O `build_aab_release.ps1`
  avisa se achar keep amplo. Enxugado em `3103077` (01/10/2026). Se mexer no proguard: testar o release
  em aparelho (login, Firestore, push, compras, widgets, câmera, vídeo) e depois ver a taxa no Play Console.

**4. Commit escopado** — só os arquivos da sessão; nunca `git add -A` (o working tree tem muita
coisa alheia). Se já houver stage de outro agente: `git commit --only -- <arquivos>`.
```powershell
git add lib/constants/app_version.dart pubspec.yaml android/app/build.gradle web/version.json web/index.html web/firebase-messaging-sw.js <arquivos da sessão>
git commit -m "release(10.05+27): <resumo>"     # termina com a linha Co-Authored-By
```
Atenção: se `web/index.html` tiver mudança alheia não commitada, stage só os marcadores
(`git show HEAD:web/index.html` + marcadores → `git hash-object -w --stdin` → `git update-index --cacheinfo 100644,<hash>,web/index.html`).

**5. Push nas branches de build e conferência no GitHub** (remote `origin` =
`https://github.com/raihom-netizen/wisdomapp.git`; branch local de trabalho = `master`; padrão do repo = `main`)

| Branch | Uso |
|--------|-----|
| `codemagic-10-05-ready` | Android/web (nome segue a versão de marketing: `codemagic-<current com ->-ready`) |
| `codemagic-ios-ready` | iOS — é a que o dono escolhe no Run workflow |
| `main` | padrão do repo (o workflow aparece na UI a partir dela); manter em dia |

```powershell
git push origin HEAD:refs/heads/codemagic-10-05-ready
git push origin HEAD:refs/heads/codemagic-ios-ready
git push origin HEAD:refs/heads/main
git push origin master                                   # opcional: espelho da branch local
git rev-parse --short HEAD
gh api repos/raihom-netizen/wisdomapp/commits/codemagic-ios-ready --jq '.sha[0:7] + " " + .commit.message'
gh api repos/raihom-netizen/wisdomapp/commits/codemagic-10-05-ready --jq '.sha[0:7]'
gh api -H "Accept: application/vnd.github.raw" "repos/raihom-netizen/wisdomapp/contents/lib/constants/app_version.dart?ref=codemagic-ios-ready" | Select-String "buildNumber|versionCode"
```
O SHA das branches tem de bater com o `HEAD` local e o `app_version.dart` remoto com o build N.
Desde 01/10/2026 o push **não** dispara o Codemagic (`codemagic-ios.yml` virou só manual).

**6. WEB online primeiro** (só hosting — nunca functions junto)
```powershell
.\deploy.ps1 -WebOnly -DryRun     # plano + versão + token + load()
.\deploy.ps1 -WebOnly             # build web → load() garantido → version.json → Validate-HostingPreDeploy → hosting
curl.exe -s https://wisdomapp.com.br/version.json
curl.exe -s https://wisdomapp-b9e98.web.app/version.json
curl.exe -s https://wisdomapp-b9e98.web.app/ | Select-String "flutter_bootstrap.js\?v="
curl.exe -s https://wisdomapp-b9e98.web.app/flutter_bootstrap.js | Select-String "_flutter.loader.load\("
```
Nunca remover o `_flutter.loader.load()` do `web/flutter_bootstrap.js` (splash eterno — §2/§10.1).

**7. Backend escopado** (só se a sessão mexeu) — compatível com o app antigo que está nas lojas;
mudança que quebra vai em fases.
```powershell
firebase deploy --only functions:<nome1>,functions:<nome2> --project wisdomapp-b9e98
firebase deploy --only firestore:rules --project wisdomapp-b9e98
firebase deploy --only firestore:indexes --project wisdomapp-b9e98
firebase deploy --only storage --project wisdomapp-b9e98
```
`functions/index.js` é grande: se der «Timeout after 10000» na descoberta, `$env:FUNCTIONS_DISCOVERY_TIMEOUT="300"`.
Sempre `--project wisdomapp-b9e98` (o CLI da máquina pode estar no projeto do Controle Total).

**8. AAB** (10–20 min; rodar em background)
```powershell
.\build_aab_release.ps1 -DryRun
.\build_aab_release.ps1 -Strings "texto novo 1","texto novo 2"
# saída: D:\TEMPORARIOS\WISDOMAPP_10.05+27_27_release.aab  (+ WISDOMAPP_ultimo_release.aab)
.\scripts\Conferir-Aab.ps1 -StringsArquivo C:\caminho\strings.txt   # textos com acento: arquivo UTF-8, 1 por linha
```
O script: confere a versão → `flutter analyze` (falha só em `error`) → `flutter build appbundle --release
--no-tree-shake-icons` → `Validate-Aab16Kb.ps1` (libs 64-bit com alinhamento ≥ 0x4000) → cópia →
`Conferir-Aab.ps1` (versionCode REAL do manifest do AAB, package, versionName, READ_CONTACTS e strings no
`libapp.so` em utf-8/latin-1/utf-16-le, com controles «WISDOMAPP» deve existir / «zzz_nao_existe_zzz» não).
Exige `android/key.properties` (senão sairia assinado com debug). Envio ao Play Console = dono.

**9. iOS — o dono dá o start** (GitHub Actions; Codemagic é legado)
- GitHub › `raihom-netizen/wisdomapp` › **Actions** › **iOS TestFlight (Flutter)** › **Run workflow** ›
  «Use workflow from»: **`codemagic-ios-ready`** › opções:
  - `setup_capabilities` — marcar só no 1º build depois de mudar capabilities (economiza ~2 min);
  - `enviar_testflight` — marcado;
  - `subir_site` — só funciona com o secret opcional `FIREBASE_SERVICE_ACCOUNT_JSON` (hoje ausente → passo pula sem erro).
- Linha de comando (só se o dono pedir): `gh workflow run ios_testflight.yml --ref codemagic-ios-ready --repo raihom-netizen/wisdomapp`
- Acompanhar: `gh run list --repo raihom-netizen/wisdomapp --workflow ios_testflight.yml -L 3` e
  `gh run view <id> --repo raihom-netizen/wisdomapp` (o `headSha` tem de ser o commit do release).
- Runner `macos-26` com Xcode 26 escolhido pelo SDK; assinatura via `app-store-connect fetch-signing-files`
  (perfis do app + widget), IPA `WISDOMAPP.ipa`, gates anti-90189, envio com 3 tentativas.
- Build OK e envio falhou → workflow **Enviar IPA ao TestFlight** com o número do run.
- Secrets já gravados (02/09/2026): `APP_STORE_CONNECT_PRIVATE_KEY`, `APP_STORE_CONNECT_KEY_IDENTIFIER`,
  `APP_STORE_CONNECT_ISSUER_ID`, `CERTIFICATE_PRIVATE_KEY`. Regravar: `.\scripts\configurar_github_ios.ps1` (dono).

**10. Atualizar esta memória** — §1 (versão), §10.5 (artefatos: AAB + SHA-256, version.json online,
run do iOS), §16 (linha do release); commit `docs(memoria): registrar o release 10.05+N` e push nas
mesmas branches.

**11. Forçar atualização** — só o dono, depois das lojas aprovarem: Admin › «Subir versão e forçar
atualização» ou `.\force_version_online.ps1`. O deploy nunca faz isso sozinho.

### Legado (não apagar)
`codemagic.yaml`, `scripts/codemagic_ios_*`, `Start-CodemagicIos.*`, `Fix-CodemagicIos.*`,
`scripts/Export-AabIosTemporarios.ps1` (AAB + ZIP iOS), `scripts/push-codemagic-ready.ps1` (faz `git add`
amplo de `lib/ ios/ packages/` e commit automático — só roda com `.\deploy.ps1 -LegacyCodemagic`),
workflow `codemagic-ios.yml` (só manual).
