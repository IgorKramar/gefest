//! Перечисления-истина.
//!
//! Значения здесь — источник истины; lookup-таблицы в базе их зеркалят и
//! наполняются только миграциями (ADR-0005: runtime-INSERT в lookup
//! запрещён). Расхождение между этим файлом и базой ловится тестом
//! синхронизации в `hef-db`.
//!
//! Каждое перечисление отдаёт стабильный строковый код и умеет перечислить
//! все варианты — второе нужно ровно тому тесту.
//!
//! Коды стабильны: они лежат в базе как первичные ключи lookup-таблиц.
//! Переименование кода — миграция, а не правка этого файла.

/// Общий контракт перечисления-истины: код в базе и полный перечень.
pub trait LookupEnum: Sized + 'static {
    /// Стабильный код, которым значение представлено в базе.
    fn code(&self) -> &'static str;

    /// Все варианты. Порядок значения не имеет — тест сравнивает множества.
    fn all() -> &'static [Self];
}

/// Вид команды. Хранится в `command_kinds`, ссылается `commands.kind`.
///
/// Перечисление, а не свободная строка: вид команды определяет, что раннер
/// сделает с процессом исполнителя, и произвольное значение отсюда — путь к
/// исполнению чужого намерения (ADR-0005, RCE-защита).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CommandKind {
    /// Запустить сессию исполнителя по задаче.
    SessionStart,
    /// Остановить живую сессию.
    SessionStop,
    /// Доставить указание в stdin работающей сессии.
    Instruction,
    /// Запросить ответ на вопрос агента.
    Answer,
}

impl LookupEnum for CommandKind {
    fn code(&self) -> &'static str {
        match self {
            Self::SessionStart => "session_start",
            Self::SessionStop => "session_stop",
            Self::Instruction => "instruction",
            Self::Answer => "answer",
        }
    }

    fn all() -> &'static [Self] {
        &[
            Self::SessionStart,
            Self::SessionStop,
            Self::Instruction,
            Self::Answer,
        ]
    }
}

/// Статус задачи. Хранится в `task_statuses`, ссылается `tasks.status`.
///
/// Lookup-таблица вместо CHECK: статусы расширяются без `DROP CONSTRAINT`
/// (ADR-0005, анти-костыль №4 донора).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TaskStatus {
    Backlog,
    InProgress,
    Waiting,
    Done,
    Cancelled,
}

impl TaskStatus {
    /// Терминальный статус — тот, из которого задача обычно не возвращается.
    /// Колонка `task_statuses.is_terminal` зеркалит это значение.
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Done | Self::Cancelled)
    }
}

impl LookupEnum for TaskStatus {
    fn code(&self) -> &'static str {
        match self {
            Self::Backlog => "backlog",
            Self::InProgress => "in_progress",
            Self::Waiting => "waiting",
            Self::Done => "done",
            Self::Cancelled => "cancelled",
        }
    }

    fn all() -> &'static [Self] {
        &[
            Self::Backlog,
            Self::InProgress,
            Self::Waiting,
            Self::Done,
            Self::Cancelled,
        ]
    }
}

/// Состояние сессии исполнителя (ADR-0008).
///
/// Значения предварительные: ADR-0005 п. 11 разрешает D-4/D-5 править их
/// forward-миграцией без пересмотра решения.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SessionState {
    /// Процесс запускается, ещё не подтвердил готовность.
    Starting,
    /// Живой процесс, принимает указания.
    Running,
    /// Прервана — процесс исчез без завершающего события.
    Interrupted,
    /// Завершена штатно.
    Completed,
    /// Завершена с ошибкой.
    Failed,
}

impl LookupEnum for SessionState {
    fn code(&self) -> &'static str {
        match self {
            Self::Starting => "starting",
            Self::Running => "running",
            Self::Interrupted => "interrupted",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }

    fn all() -> &'static [Self] {
        &[
            Self::Starting,
            Self::Running,
            Self::Interrupted,
            Self::Completed,
            Self::Failed,
        ]
    }
}

/// Вид события сессии. Веха, а не сырьё: сырой stream-json живёт файлами.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SessionEventKind {
    Message,
    ToolCall,
    ToolResult,
    Status,
    Error,
    Milestone,
}

impl LookupEnum for SessionEventKind {
    fn code(&self) -> &'static str {
        match self {
            Self::Message => "message",
            Self::ToolCall => "tool_call",
            Self::ToolResult => "tool_result",
            Self::Status => "status",
            Self::Error => "error",
            Self::Milestone => "milestone",
        }
    }

    fn all() -> &'static [Self] {
        &[
            Self::Message,
            Self::ToolCall,
            Self::ToolResult,
            Self::Status,
            Self::Error,
            Self::Milestone,
        ]
    }
}

/// Исход попытки доставки указания (ADR-0007).
///
/// Живёт в `command_deliveries` — append-only истории попыток. Текущий исход
/// команды выводится последней записью, а не хранится отдельной колонкой:
/// две оси — две таблицы.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DeliveryOutcome {
    /// Записано в stdin процесса.
    Sent,
    /// Подтверждено каузально связанной активностью потока.
    Delivered,
    /// Придержано — адресат не в состоянии принять.
    Held,
    /// Отклонено правилом.
    Denied,
    /// Истёк срок ожидания подтверждения.
    Expired,
    /// Доставить невозможно: адресата нет.
    Undeliverable,
}

impl LookupEnum for DeliveryOutcome {
    fn code(&self) -> &'static str {
        match self {
            Self::Sent => "sent",
            Self::Delivered => "delivered",
            Self::Held => "held",
            Self::Denied => "denied",
            Self::Expired => "expired",
            Self::Undeliverable => "undeliverable",
        }
    }

    fn all() -> &'static [Self] {
        &[
            Self::Sent,
            Self::Delivered,
            Self::Held,
            Self::Denied,
            Self::Expired,
            Self::Undeliverable,
        ]
    }
}

/// Происхождение события задачи — trust-дверь D-16.
///
/// `AgentExternal` помечает действие, инициированное недоверенным
/// содержимым: заполняется раннером по эвристике источника. Дверь открыта
/// заранее, чтобы включение доверия к агентам не потребовало миграции
/// данных.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventOrigin {
    /// Действие владельца.
    Owner,
    /// Действие агента по собственному решению.
    Agent,
    /// Действие агента, инициированное внешним недоверенным содержимым.
    AgentExternal,
}

impl LookupEnum for EventOrigin {
    fn code(&self) -> &'static str {
        match self {
            Self::Owner => "owner",
            Self::Agent => "agent",
            Self::AgentExternal => "agent_external",
        }
    }

    fn all() -> &'static [Self] {
        &[Self::Owner, Self::Agent, Self::AgentExternal]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// Коды зафиксированы буквально: они лежат в базе первичными ключами,
    /// и переименование должно ломать тест, а не тихо расходиться со схемой.
    #[test]
    fn codes_are_stable() {
        assert_eq!(CommandKind::SessionStart.code(), "session_start");
        assert_eq!(CommandKind::Answer.code(), "answer");
        assert_eq!(TaskStatus::InProgress.code(), "in_progress");
        assert_eq!(SessionState::Interrupted.code(), "interrupted");
        assert_eq!(SessionEventKind::ToolResult.code(), "tool_result");
        assert_eq!(DeliveryOutcome::Undeliverable.code(), "undeliverable");
        assert_eq!(EventOrigin::AgentExternal.code(), "agent_external");
    }

    fn assert_no_duplicates<T: LookupEnum>(name: &str) {
        let codes: Vec<&str> = T::all().iter().map(|v| v.code()).collect();
        assert!(!codes.is_empty(), "{name}: перечень вариантов пуст");
        let unique: HashSet<&&str> = codes.iter().collect();
        assert_eq!(
            unique.len(),
            codes.len(),
            "{name}: коды повторяются — {codes:?}"
        );
    }

    #[test]
    fn all_variants_listed_without_duplicates() {
        assert_no_duplicates::<CommandKind>("CommandKind");
        assert_no_duplicates::<TaskStatus>("TaskStatus");
        assert_no_duplicates::<SessionState>("SessionState");
        assert_no_duplicates::<SessionEventKind>("SessionEventKind");
        assert_no_duplicates::<DeliveryOutcome>("DeliveryOutcome");
        assert_no_duplicates::<EventOrigin>("EventOrigin");
    }

    #[test]
    fn terminal_statuses_are_marked() {
        assert!(TaskStatus::Done.is_terminal());
        assert!(TaskStatus::Cancelled.is_terminal());
        assert!(!TaskStatus::Backlog.is_terminal());
        assert!(!TaskStatus::InProgress.is_terminal());
        assert!(!TaskStatus::Waiting.is_terminal());
    }
}
