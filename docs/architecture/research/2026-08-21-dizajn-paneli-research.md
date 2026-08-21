# Research digest: дизайн панели и PWA (D-18)

- Дата: 2026-08-21 · Три темы; выжимка, полный отчёт — в истории цикла.

## 1. Headless-примитивы для React 19

**Рекомендация — Base UI**: v1.0 (12.2025) → v1.7 (08.2026), 35+ компонентов (включая Toast и Combobox — слабые места конкурентов), unstyled + data-атрибуты состояний (идеально под Tailwind 4 и свою айдентику), команда экс-Radix/Floating UI на полной ставке в MUI. Сдвиг экосистемы: shadcn/ui с 07.2026 инициализирует новые проекты на Base UI по умолчанию. Запасной — React Aria Components (Adobe, эталонная a11y, тяжёлые компоненты Table/DatePicker — если понадобятся). Radix — режим сопровождения (WorkOS, темп упал); Headless UI — нет Toast/Tooltip; Ark UI — без преимуществ при React-only. Риск: Base UI 1.x стабилен ~8 месяцев — semver заявлен, шероховатости возможны.

## 2. PWA iOS/Android 2026

- **Web push iOS**: работает с 16.4 — только для PWA, установленной через «Add to Home Screen»; разрешение — по жесту; Safari 18.4 добавил Declarative Web Push. iOS 26 снизил порог установки. Badging API есть. «Удаление PWA в ЕС» — отменено 01.03.2024 (статьи 2026, повторяющие обратное, — устаревший пересказ беты).
- **Passkeys в standalone**: работают (same-origin WebAuthn + биометрия); грабли рядом — кросс-доменные OAuth-редиректы выбрасывают из standalone (у нас всё same-origin поверх tailnet — не наш случай); cookie-jar PWA отделён от Safari — логин внутри PWA заново, дальше долгоживущая сессия + passkey-релогин.
- **Ограничения iOS**: нет Background Sync, состояние сбрасывается при уходе из приложения, pull-to-refresh — свой; 7-дневная ITP-зачистка на установленные home-screen-apps не распространяется.
- **Вывод для ТЗ**: алерты — первично внешними каналами (Telegram/ntfy, ADR-0010); web push — опциональный дублирующий канал установленной PWA + Badging. Android — полный паритет и выше.

## 3. Кириллические шрифты (OFL/Google Fonts)

**Тройка: Tektur / Golos Text / JetBrains Mono.**
- **Tektur** (заголовки): октагональные срезы — индустриальный характер «кузницы»; родная кириллица; variable wght 400–900 + wdth (иерархия и темы весом, не сменой шрифта). Нет курсива — для заголовков не проблема. Запасной: Geologica (острые альтернаты).
- **Golos Text** (текст/данные): кириллица — исходный скрипт (естественные формы а/у/з/ж), метрики под мелкие экранные кегли, wght 400–900.
- **JetBrains Mono** (терминальные акценты: логи, ключи, ID): полная кириллица, высокий x-height, variable wght. Запасной с характером: Martian Mono (+ось wdth для плотных таблиц).
Волна кириллица-first в GF — 2022–2023 (Tektur, Onest, Unbounded, Geologica, Golos); нового 2024–2026, меняющего картину, нет. Риск: рендер variable-осей в Safari iOS проверить на устройстве.

## Caveats

Base UI peerDependencies проверить при установке; надёжность Declarative Web Push публично не измерена — «best-effort» консервативно; passkeys в standalone на iOS 26 — дешёвая проверка на устройстве до фиксации схемы (совместить с проверкой Atomic Editor из ADR-0013).

## Sources

19 позиций с датами — в отчёте research-агента; ключевые: base-ui.com/releases (v1.7, 08.2026); ui.shadcn.com changelog 07.2026; webkit.org web-push; techcrunch/9to5mac 03.2024 (откат ЕС); fonts.google.com Tektur/Geologica; github tonsky/martian-mono; firt.dev PWA design tips.

*Terminology pass: проза русская; идентификаторы (Base UI, React Aria, Radix, shadcn/ui, Toast, Combobox, Badging API, Declarative Web Push, WebAuthn, standalone, ITP, Tektur, Golos Text, JetBrains Mono, wght/wdth, OFL) без перевода.*
