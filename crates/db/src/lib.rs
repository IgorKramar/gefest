//! Прослойка доступа к Postgres: запросы, миграции, CAS-retry.
//!
//! **Что кладём сюда:** макросы запросов (`query!`, `query_as!`), миграции
//! (`migrations/`), пулы соединений, прослойку доступа с CAS-retry,
//! RLS-контекст. Это **единственный** крейт, где живут SQL и `migrations`.
//!
//! **Чего сюда не кладём:** доменные типы (они в `hef-core`), HTTP и MCP
//! (в `hef-api`), работу с процессами исполнителей (в `hef-runner`).
//!
//! **Цикл sqlx и красный `prepare --check`** — см. `README.md` рядом с этим
//! файлом. Там же интерим-регламент: пока брокер ресурсов не готов,
//! SQL-запросы меняет только владелец.
//!
//! # Граница доступа
//!
//! К таблицам под RLS ведёт единственный путь — [`Db::as_actor`]. Сырой
//! `PgPool` не покидает модуль [`pool`], а системная роль лишена прав на эти
//! таблицы, поэтому обращение мимо контекста отказывает громко. Подробности
//! и обоснование — в документации модуля [`pool`].

pub mod cas;
pub mod error;
pub mod ids;
pub mod pool;

pub use cas::{Attempt, with_retry};
pub use error::{DbError, DbResult};
pub use ids::new_external_id;
pub use pool::{ActorId, ActorTx, Db, SystemTx};

/// Миграции, встроенные в бинарь.
///
/// Применяются подкомандой `hef migrate` (крейт `hef`). Серия forward-only:
/// откат выполняется восстановлением из `pg_dump`, а не обратной миграцией.
pub static MIGRATIONS: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

/// Имя крейта. См. пояснение в `hef-core`.
pub const CRATE_NAME: &str = "hef-db";
