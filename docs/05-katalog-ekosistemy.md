# Экосистема плагинов DSH — каталог по топику `dsh-plugin` (2026-08-20)

Методика: GitHub Search API `topic:dsh-plugin` (топ-500 из ~8 800 репозиториев, sort=stars) + страница топика + awesome-списки. Все звёзды — фактические на 2026-08-20.

## Охват и оговорка о качестве

- Топик `dsh-plugin` — официально рекомендованный, **8 883 публичных репозитория** (API отдаёт 8 783 — лаг индекса).
- Верх выдачи засорён **тег-райдерами** (reactive-resume 41k, MemOS 10.8k, YaoApp/yao 7.7k повесили тег ради трафика). Минимум четыре каталога ведут чёрные списки/ручную верификацию против тег-спама (`bruc3van/awesome-dsh-plugin`, `AdamPlatin123/awesome-dsh-plugins`, `ZASENJC/dsh-plugins-store`, `zp-home/dsh-recommend`).

## Топ-15 по звёздам (весь топик)

1. **deepseek-ai/deepseek-harness** — 169 161 — ядро
2. **nexu-io/open-design** — 89 425 — design-плагин/десктоп, open-source альтернатива Claude Design
3. amruthpillai/reactive-resume — 41 203 — тег-райдер (конструктор резюме)
4. **esengine/DeepSeek-Reasonix** — 34 888 — терминальный coding-агент, заточен под стабильность префикс-кэша
5. **volcengine/OpenViking** — 30 432 — контекстная БД: память + RAG + skills (ByteDance)
6. titanwings/colleague-skill — 23 567 — persona-skill «цифровая жизнь»
7. Nagi-ovo/voyager — 19 705 — enhancement-suite + менеджер промптов для web-UI
8. **anywhere-labs/deepseek-harness-desktop** — 15 588 — главный десктоп-клиент экосистемы
9. tt-a1i/archify — 14 546 — skill архитектурных/sequence/data-flow диаграмм
10. **walkinglabs/learn-harness-engineering** — 12 791 — учебник harness-инжиниринга 0→1
11. EverMind-AI/EverOS — 12 221 — переносимый Markdown-слой памяти
12. freestylefly/awesome-gpt-image-2 — 11 388 — промпт-библиотека как skills
13. MemTensor/MemOS — 10 821 — память-ОС (частично тег-райдер)
14. **awesome-dsh-plugin/awesome-dsh-plugin** — 10 193 — канонический курируемый список
15. YaoApp/yao — 7 726 — управление агентами (DSH — одна из интеграций)

## По категориям (значимое)

### UI / темы / скины
| Репо | ⭐ | Суть |
|---|---|---|
| zhu1090093659/dsh-web-ui | 4 963 | крупнейший сборник расширений Web UI: таск-борд, git-граф, мобильный remote |
| omdsh-dev/DSH-better-sidebar | 2 374 | сайдбар: файлы/терминал/Git/сабагенты |
| ccch1mneyyy/dsh-TUI | 2 115 | TUI в стиле Claude Code |
| Small-tailqwq/dsh-deep-whale | 1 471 | скины «whale girl» — целый жанр |
| WYH66666666/DSH-Transparent-UI-Plugin | 334 | стеклянная тема |
| omdsh-dev/dsh-genui | 254 | интерактивные компоненты в ответах |
| HeiGeAi/deepseek-harness-skin | 48 | 21 тема + палитра из картинки с проверкой контраста |

Питомцы: petdex 3 925, whale-girl 248, dsh-pet 215.

### Память — самая переполненная «серьёзная» ниша (12+ несовместимых систем)
| Репо | ⭐ | Суть |
|---|---|---|
| volcengine/OpenViking | 30 432 | память + RAG + skills |
| EverMind-AI/EverOS | 12 221 | локальная Markdown-память для всех агентов |
| MemTensor/MemOS | 10 821 | память-ОС, гибридный retrieval |
| mem9-ai/mem9 | 1 190 | «безлимитная» память |
| adoresever/graph-memory | 559 | граф знаний |
| mnemon-dev/mnemon | 490 | LLM-супервизируемая, один бинарник |
| syncable-dev/memtrace-public | 459 | би-темпоральный граф, MCP-native |
| csyangwen/dsh-memory-evolve | 200 | пятитрековая + фоновая самоэволюция |

### Зрение — системная дыра ядра (модели DeepSeek текстовые), ~8 VLM-мостов
| Репо | ⭐ | Суть |
|---|---|---|
| liustack/modlens | 3 325 | «первый vision-плагин DSH» |
| Anionex/agent-vision-toolkit (+dsh-упаковка) | 1 074 / 760 | мультикартинки, VQA, UI-реконструкция, GUI-автоматизация |
| ysr666/dsh-vision-router | 856 | бесплатная vision-цепочка без ключа |
| HuanLinOTO/dsh-plugin-mineru | 38 | PDF/DOCX/PPTX → структурированный Markdown |

### Браузер / поиск
| Репо | ⭐ | Суть |
|---|---|---|
| Tencent/BrowserSkill | 1 190 | агент в вашем реальном залогиненном браузере (Tencent) |
| Lum1104/dsh-browser | 332 | Chrome-сайдбар без vision |
| liustack/modsearch | 174 | web-поиск для моделей без нативного |
| taxueseek/argo | 104 | поисковик «для агентов» |
| DDDMUC/dsh-free-search | 29 | DuckDuckGo без ключа |

### Агенты / оркестрация
| Репо | ⭐ | Суть |
|---|---|---|
| Q00/ouroboros | 5 583 | самоулучшающийся Agent OS, interview-gated eval-циклы |
| foryourhealth111-pixel/Vibe-Skills | 2 917 | авто-роутинг skills, оркестрация задач |
| NanmiCoder/dsh-agent-teams | 628 | команды агентов внутри DSH |
| omdsh-dev/dsh_workflow | 89 | «UltraCode-режим»: управляемый Workflow-слой |
| titanwings/dsh-automation | 67 | coding-задачи по расписанию |

### Инструменты / MCP / провайдеры
| Репо | ⭐ | Суть |
|---|---|---|
| edison7009/EchoBird | 3 090 | one-click установка + переключение Claude Code/Codex/Grok/DSH/Kimi |
| TencentCloudBase/CloudBase-AI-Toolkit | 1 073 | бэкенд для агентов (БД/auth/functions) |
| xyTom/coding-tools-mcp | 835 | «дать любому агенту умение кодить» |
| superdesigndev/treg | 510 | «OpenRouter для инструментов» — реестр tools |
| V1ki/dsh-plugin-subscriptions | 176 | подписки ChatGPT/Claude/Grok как LLM-провайдеры (OAuth) |

Поджанр «чужие подписки как провайдер» — ~7 плагинов (dsh-codex-subscription ×2, dsh-codex-connect, dsh-agy, dockyard-dsh…).

### Безопасность / права — растущая, но маленькая по звёздам ниша
| Репо | ⭐ | Суть |
|---|---|---|
| toby-bridges/api-relay-audit | 795 | аудит LLM-прокси: prompt injection, подмена модели, переписывание tool-call |
| hashgraph-online/hol-guard | 454 | «антивирус для агентов» |
| NanmiCoder/dsh-auto-mode | 113 | безопасные автоматические permissions |
| howmp/dsh-pentest | 113 | режим пентеста |
| lire1131/dsh-undo-savepoint | 98 | снапшоты, откат конфигов/плагинов, SAFE MODE |
| lxzy-7/dsh-plugin-guard | 28 | pre-install снапшоты, авто-откат |
| PerryLink/dsh-permission-rules | 23 | декларативные правила прав в стиле Claude Code |

### Мониторинг / стоимость
Бум ниши вызван **пиковыми/внепиковыми тарифами DeepSeek** (изменение 2026-08-17 упоминается в плагинах): Han-1413141/dsh-cost-meter 120, MeteorNOX/Balance-Whale-Widget 125, zh667/TokenLedger 116, Ychris12138/dsh-usage-stats 87, wink-run/tokenbank 80; экзотика — dsh-green-meter 34 (углерод на запрос); плюс dsh-save-money (пауза в дорогие часы), deepseek-peak.

### Разработка плагинов / обучение
| Репо | ⭐ | Суть |
|---|---|---|
| walkinglabs/learn-harness-engineering | 12 791 | учебник 0→1 |
| Electricitysheep/dsh-handbook | 553 | хендбук: установка, разработка, тюнинг |
| pingfanfan/hello-dsh | 79 | zero-to-plugin, 22 примера skills |
| vlln/plugin-registry | 57 | тонкая консоль + skill `make-dsh-plugin` |
| edonadei/caliper | 39 | eval-harness для skills |
| omdsh-dev/dsh-plugin-check | 24 | health-check: манифест, patch-формат, ловушки сборки |

### Десктоп-клиенты (~15+ обёрток)
Лидер anywhere-labs/deepseek-harness-desktop 15.6k; BitFun 1 798 (Rust), paean-ai/deeptide 1 087 (Swift/macOS), hairyf 614 (Tauri 5 МБ), vibeinging 602, fufankeji/deepseek-harness-studio 374, oh-dsh 255 (Desktop+Web+TUI), VS Code-расширения.

### Маркетплейсы (~20+ каталогов — уже предмет иронии в сообществе)
awesome-dsh-plugin 10 193 (канон), dsh-market 1 310 (маркет внутри DSH), AdamPlatin123/awesome-dsh-plugins 1 258 («радар»: авто-обнаружение 9 000+ кандидатов + install-тесты в контейнере), 0xsline/awesome-deepseek-harness 756.

### Удалёнка / IM
dsh-pocket 236 (QR-синхронизация с телефоном), dsh-mobile-apk 87, tencent-connect/dsh-qqbot 67 (официальный QQ), dsh-im 73 (9 мессенджеров), мосты Feishu/Lark ×5.

### Прочее заметное
brooks-lint 1 390 (код-ревью с цитатами из 12 классических книг), agentrq 1 082 (human-in-loop таск-менеджер), strukto-ai/mirage 3 525 (виртуальная ФС), Nagi-ovo/dsh-ads 514 (пародийные попапы «портал-2005»), миниигры, гадания — низкий порог входа породил слой чистого фана.

## Тренды

1. **«Everything is a Plugin» сработал буквально**: ~9 000 репо в топике за неделю. Экосистема сильно китаеязычная; вклад корпораций — Tencent, ByteDance/Volcengine, Alibaba.
2. **Перепроизводство**: каталоги (20+), память (12+ несовместимых), десктоп-обёртки (15+). Консолидации нет.
3. **Зрение — дыра ядра**, закрываемая ~8 сообществскими VLM-мостами.
4. **Экономика управляет разработкой**: пиковые тарифы → целый класс «финансовых» плагинов.
5. **Кризис доверия и ответ**: тег-спам + риск чужого кода → «антивирусы», install-guard'ы, каталоги с ручной верификацией.
6. **Заимствование UX как жанр**: «как в Claude Code», «как в Codex», «чужие подписки как провайдер».
7. **Чего не хватает**: официального подписанного маркетплейса; стандартного протокола памяти; vision в ядре; enterprise-слоя (multi-tenant/аудит — единичные, <20 ⭐).

## Источники

- https://github.com/topics/dsh-plugin (страница + Search API, 5×100, sort=stars)
- https://github.com/awesome-dsh-plugin/awesome-dsh-plugin
- https://skillsllm.com/skill/awesome-deepseek-harness
- https://awesome-dsh-plugin.com/, https://www.scriptbyai.com/deepseek-harness-plugins/, https://www.dshplugin.store/, https://shop.zimaspace.com/blogs/tech-ai-hub/10-best-deepseek-harness-plugins-2026

Ограничение охвата: поимённо разобраны топ-500 из ~8 800; хвост (<12 ⭐) охарактеризован по каталогам-агрегаторам.
