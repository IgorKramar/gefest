//! Пул соединений и типовая граница доступа к таблицам под RLS.
//!
//! # Что закрыто чем
//!
//! Ошибок здесь две, и ловятся они разными механизмами:
//!
//! | Ошибка | Ловится | Как проявляется |
//! |---|---|---|
//! | Запрос мимо прослойки, прямо из пула | типами: `PgPool` приватен | не компилируется |
//! | Запрос к RLS-таблице через [`Db::as_system`] | привилегиями роли | отказ привилегий |
//!
//! Первое даёт компилятор: функции, принимающей `&PgPool`, в публичном API
//! крейта нет, а само поле недоступно снаружи модуля.
//!
//! Второе типами закрыть нельзя — `as_system()` возвращает обычное
//! соединение, и ничто не мешает адресовать им `sessions`. Поэтому системная
//! роль подключается без `SELECT` на трёх RLS-таблицах: попытка даёт громкий
//! отказ привилегий вместо тихого нуля строк.
//!
//! # Почему контекст живёт только в транзакции
//!
//! `set_config('app.actor_id', $1, true)` действует до конца транзакции.
//! Соединение возвращается в пул без сброса состояния — sqlx не выполняет ни
//! `DISCARD ALL`, ни `RESET ALL`, — поэтому не-LOCAL вариант (`false`) прилип
//! бы к соединению и переехал к следующему, кто возьмёт его из пула. Это
//! единственный способ получить настоящую утечку между запросами, и он
//! запрещён сторожем `scripts/guard-set-config.sh`.
//!
//! LOCAL-вариант вне транзакции безвреден: значение испаряется до следующего
//! оператора, и запрос отдаёт ноль строк. Отказ безопасный, но выглядит как
//! пустой результат — стоит помнить при отладке.

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{PgPool, Postgres, Transaction};

use crate::error::{DbError, DbResult};

/// Идентификатор актора: субъект RLS-политик.
pub type ActorId = i64;

/// Точка входа к базе. Сырой пул наружу не отдаётся.
#[derive(Clone, Debug)]
pub struct Db {
    /// Роль приложения: работает под политиками RLS.
    app: PgPool,
    /// Системная роль: без `SELECT` на таблицах под RLS.
    system: PgPool,
}

impl Db {
    /// Собирает пулы из двух наборов параметров подключения.
    ///
    /// Разные роли — не удобство, а часть защиты: системный пул физически
    /// лишён прав на RLS-таблицы, поэтому обращение к ним мимо
    /// actor-контекста отказывает громко.
    pub async fn connect(
        app_opts: PgConnectOptions,
        system_opts: PgConnectOptions,
        max_connections: u32,
    ) -> DbResult<Self> {
        let app = PgPoolOptions::new()
            .max_connections(max_connections)
            .after_release(|conn, _meta| {
                Box::pin(async move {
                    // Соединение с непустым actor-контекстом в пул не
                    // возвращается.
                    //
                    // При штатной работе контекст живёт внутри транзакции и
                    // к этому моменту уже испарился. Непустое значение
                    // означает, что где-то выставили сессионно-липкий
                    // контекст — не-LOCAL `set_config` или плоский `SET`, —
                    // и это соединение отдало бы чужие права следующему
                    // владельцу.
                    let leaked: Option<String> = sqlx::query_scalar(
                        "SELECT nullif(current_setting('app.actor_id', true), '')",
                    )
                    .fetch_one(&mut *conn)
                    .await?;

                    match leaked {
                        Some(actor) => {
                            debug_assert!(
                                false,
                                "actor-контекст утёк в пул: app.actor_id = {actor}"
                            );
                            // Соединение выбрасывается, а не переиспользуется.
                            Ok(false)
                        }
                        None => Ok(true),
                    }
                })
            })
            .connect_with(app_opts)
            .await?;

        let system = PgPoolOptions::new()
            .max_connections(max_connections)
            .connect_with(system_opts)
            .await?;

        Ok(Self { app, system })
    }

    /// Открывает транзакцию с выставленным actor-контекстом.
    ///
    /// Единственный путь к таблицам под RLS. Контекст ставится первым
    /// оператором, до любого запроса вызывающего.
    pub async fn as_actor(&self, actor: ActorId) -> DbResult<ActorTx<'_>> {
        let mut tx = self.app.begin().await?;

        // Третий аргумент `true` = LOCAL: значение живёт до конца этой
        // транзакции и не переживает возврат соединения в пул.
        sqlx::query("SELECT set_config('app.actor_id', $1, true)")
            .bind(actor.to_string())
            .execute(&mut *tx)
            .await?;

        Ok(ActorTx { tx, actor })
    }

    /// Транзакция системной роли: справочники, проекты, задачи.
    ///
    /// Названа явно, потому что это решение, а не забывчивость. Вариант
    /// `as_actor(None)` читался бы как «контекст забыли».
    pub async fn as_system(&self) -> DbResult<SystemTx<'_>> {
        Ok(SystemTx {
            tx: self.system.begin().await?,
        })
    }

    /// Проверяет, что роль подключения не обходит RLS.
    ///
    /// Суперпользователь и роль с `BYPASSRLS` игнорируют `FORCE ROW LEVEL
    /// SECURITY` целиком — под такой ролью весь набор RLS-проверок зеленеет,
    /// ничего не проверяя. Вызывается тестами первым делом.
    pub async fn assert_rls_applies(&self) -> DbResult<()> {
        let (is_super, bypasses): (bool, bool) = sqlx::query_as(
            "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user",
        )
        .fetch_one(&self.app)
        .await?;

        if is_super || bypasses {
            return Err(DbError::RlsBypassed {
                superuser: is_super,
                bypassrls: bypasses,
            });
        }
        Ok(())
    }
}

/// Транзакция с actor-контекстом. Исполнитель запросов к RLS-таблицам.
pub struct ActorTx<'a> {
    tx: Transaction<'a, Postgres>,
    actor: ActorId,
}

impl ActorTx<'_> {
    /// Актор этой транзакции.
    pub fn actor(&self) -> ActorId {
        self.actor
    }

    /// Исполнитель для запросов. Живёт не дольше транзакции.
    pub fn executor(&mut self) -> &mut sqlx::PgConnection {
        &mut self.tx
    }

    pub async fn commit(self) -> DbResult<()> {
        self.tx.commit().await?;
        Ok(())
    }

    pub async fn rollback(self) -> DbResult<()> {
        self.tx.rollback().await?;
        Ok(())
    }
}

/// Транзакция системной роли: без прав на таблицы под RLS.
pub struct SystemTx<'a> {
    tx: Transaction<'a, Postgres>,
}

impl SystemTx<'_> {
    pub fn executor(&mut self) -> &mut sqlx::PgConnection {
        &mut self.tx
    }

    pub async fn commit(self) -> DbResult<()> {
        self.tx.commit().await?;
        Ok(())
    }

    pub async fn rollback(self) -> DbResult<()> {
        self.tx.rollback().await?;
        Ok(())
    }
}
