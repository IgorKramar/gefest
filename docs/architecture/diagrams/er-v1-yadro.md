# ER: v1-ядро схемы Гефеста (ADR-0005)

Основание: ADR-0005 + decision ред. 2 §1 (нормативный эскиз). Показано **только v1-ядро** (14 таблиц + audit_log). Волна 2 — memory_* (6 таблиц, ADR-0003), boards/board_columns, pools/pool_tasks, tags/task_tags, task_dependencies, observations, exports_log — заведомо за кадром (двери в tasks: parent_id, column_id). Атрибуты сокращены до несущих; полный DDL — GF-5.

```mermaid
erDiagram
    actors {
        bigserial id PK
        text kind "owner | role | system"
        text name UK
        boolean active
    }
    roles_profile {
        bigint actor_id PK,FK
        text specialization
        text character
        text backstory
        jsonb prompt_config
        text provider
        text model
    }
    projects {
        bigserial id PK
        text key UK "иммутабелен (GF, ERP)"
        text title
        text scope_class "personal | client"
    }
    project_counters {
        bigint project_id PK,FK
        int next_seq "FOR UPDATE при выдаче"
    }
    tasks {
        bigserial id PK
        text key UK "функцией при INSERT, не GENERATED"
        text kind "task | epic"
        bigint parent_id FK "дверь D-15"
        bigint status_id FK
        bigint assignee_id FK
        int revision "CAS"
    }
    task_statuses {
        bigserial id PK
        text key UK "истина - Rust-enum, зеркало"
        boolean is_terminal
    }
    task_events {
        bigserial id PK
        int version "UNIQUE(task_id, version)"
        bigint actor_id FK
        text kind "created|status|assignee|note|imported|..."
        text origin "owner | agent | agent_external"
    }
    commands {
        bigserial id PK
        uuid uuid7 UK "наружу"
        bigint issued_by FK
        bigint addressee_id FK
        bigint kind_id FK
        text execution_state "issued|taken|done|failed|rejected (предварит., D-4)"
        timestamptz taken_at "lease: повторный захват по таймауту"
        jsonb payload
    }
    command_kinds {
        bigserial id PK
        text key UK "start|stop|answer|note|assign - не строка к исполнению"
    }
    command_deliveries {
        bigserial id PK
        bigint command_id FK
        text outcome "sent|delivered|held|denied|expired|undeliverable"
    }
    sessions {
        bigserial id PK
        uuid uuid7 UK
        text state "starting|running|interrupted|completed|failed (предварит., D-5)"
        text claude_session_id
        text summary "пишет исполнитель"
        text raw_path "файл 0700, вне бэкапа"
        text raw_state "present | rotated | failed"
    }
    session_events {
        bigserial id PK
        int version "UNIQUE(session_id, version)"
        text kind "message|tool_call|tool_result|status|error|milestone"
        jsonb payload "веха, не сырьё; retention 90 дн"
    }
    journal {
        bigserial id PK
        bigint author_id FK
        bigint addressee_id FK
        bigint ref_id FK "close ссылается на исходную"
        text kind "question|block|close|answer|note"
        text outcome "answered | faded | lifted"
    }
    consumer_offsets {
        text consumer PK
        bigint last_id "gap-detection: ожидание пропуска до 5 c"
    }
    audit_log {
        bigserial id PK
        bigint actor_id
        text table_name
        text row_pk
        timestamptz ts "append-only; срабатывание = алерт; 12 мес"
    }

    actors ||--o| roles_profile : "профиль kst (1:1 для kind=role)"
    projects ||--|| project_counters : "счётчик ключей"
    projects ||--o{ tasks : "содержит"
    task_statuses ||--o{ tasks : "статус (lookup)"
    actors |o--o{ tasks : "assignee"
    tasks |o--o{ tasks : "parent/epic (дверь D-15)"
    tasks ||--o{ task_events : "поток (stream, version); state в той же транзакции"
    actors ||--o{ task_events : "актор события"
    command_kinds ||--o{ commands : "вид (перечисление)"
    actors ||--o{ commands : "issued_by / addressee"
    tasks |o--o{ commands : "частичный UNIQUE: одна живая start-команда"
    commands ||--o{ command_deliveries : "append-only исходы доставки"
    commands |o--o{ sessions : "порождает"
    tasks |o--o{ sessions : "частичный UNIQUE: одна running-сессия"
    actors ||--o{ sessions : "роль-исполнитель"
    sessions ||--o{ session_events : "поток вех; один писатель - раннер"
    actors ||--o{ journal : "автор / адресат"
    tasks |o--o{ journal : "контекст задачи"
    journal |o--o{ journal : "close -> ref_id (UNIQUE where close)"
```

**Всё в диаграмме — из ADR-0005/decision ред. 2, ничего не выведено домыслом.** RLS+FORCE действует на все таблицы ядра; журнальные (task_events, session_events, command_deliveries, journal, audit_log) — append-only триггер-запретами; BRIN по монотонным PK журналов; ключ будущего партиционирования session_events включён в PK заранее.

Смежные виды: машина состояний команды/сессии — `/architect:diagram state` после D-4/D-5 (значения предварительные); поток доставки — `/architect:diagram sequence` после D-4.
