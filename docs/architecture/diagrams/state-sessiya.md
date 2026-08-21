# State: сессия исполнителя (ADR-0008)

Один субъект — строка sessions. Переводит только раннер; каждый переход — событие session_events. Состояния `stopping`/`sleeping_cold` — за флагом стопа-по-таймауту (выключен в v1, включается при >2 одновременно спящих — ADR-0007 CC-3). Ретрай порождает **новую** сессию с `parent_session_id` — это не переход, а новая машина.

```mermaid
stateDiagram-v2
    [*] --> spawning: строка создана, старт процесса (session-id = UUIDv7 строки)

    spawning --> running: system/init получен, стрим пошёл
    spawning --> failed: setup failed (exit 0 без result + stderr, ловушка S1b)

    running --> waiting_answer: блокирующий вопрос, ход завершён
    waiting_answer --> running: ответ владельца доставлен в stdin (delivered)

    running --> completed: финальный result, задача закрыта
    running --> interrupted: stop (SIGTERM) или смерть процесса — синтетическое закрытие хода
    waiting_answer --> interrupted: stop во время ожидания
    running --> failed: сбой стрима/процесса не по стопу

    waiting_answer --> stopping: флаг включён и таймаут сна (двухфазный барьер, вручения блокируются)
    stopping --> sleeping_cold: контейнер остановлен
    sleeping_cold --> spawning: ответ пришёл, resume контейнера

    completed --> [*]
    interrupted --> [*]
    failed --> [*]
```

Заземлено в ADR-0007/0008: reconciliation при старте бинаря переводит осиротевшие `spawning`/`running` в `interrupted` событием (не отдельная стрелка — тот же переход «смерть процесса»); `failed` запускает ретрай-путь (в v1 — один авто-ретрай новой сессией → `paused` задачи + инцидент).
