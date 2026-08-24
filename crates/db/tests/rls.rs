//! Изоляция строк под RLS.
//!
//! Тесты используют сигнатуру `(PgPoolOptions, PgConnectOptions)`: она
//! отдаёт параметры подключения к тестовой базе **неподключёнными**, и это
//! единственный способ подключиться другой ролью. Проверять RLS одной ролью
//! бессмысленно — вся конструкция стоит на том, что `gefest_app` не владеет
//! таблицами.

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{AssertSqlSafe, Executor, PgPool, Row};

/// Пароли ролей приходят окружением: в репозитории их нет.
fn role_password(var: &str, default: &str) -> String {
    std::env::var(var).unwrap_or_else(|_| default.to_string())
}

async fn connect_as(opts: &PgConnectOptions, role: &str, pw_var: &str, pw_default: &str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .connect_with(
            opts.clone()
                .username(role)
                .password(&role_password(pw_var, pw_default)),
        )
        .await
        .expect("подключение ролью")
}

/// Роль, которой выполняются тесты, не должна обходить RLS.
///
/// Суперпользователь и роль с `BYPASSRLS` игнорируют `FORCE ROW LEVEL
/// SECURITY` целиком: под такой ролью каждый тест ниже стал бы зелёным, не
/// проверив ничего. Проверка стоит первой намеренно.
#[sqlx::test(migrations = "./migrations")]
async fn test_role_does_not_bypass_rls(pool: PgPool) {
    let row =
        sqlx::query("SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user")
            .fetch_one(&pool)
            .await
            .expect("чтение атрибутов роли");

    let is_super: bool = row.get(0);
    let bypasses: bool = row.get(1);

    assert!(
        !is_super && !bypasses,
        "роль тестов обходит RLS (superuser={is_super}, bypassrls={bypasses}) — \
         политики не применяются, и весь набор RLS-проверок был бы пустым"
    );
}

/// Владелец таблиц — мигратор, а не роль приложения.
#[sqlx::test(migrations = "./migrations")]
async fn app_role_does_not_own_tables(pool: PgPool) {
    let row = sqlx::query(
        "SELECT count(*) FROM pg_tables
         WHERE schemaname = 'public' AND tableowner = 'gefest_app'",
    )
    .fetch_one(&pool)
    .await
    .expect("подсчёт таблиц роли приложения");

    let owned: i64 = row.get(0);
    assert_eq!(
        owned, 0,
        "gefest_app владеет таблицами — политики к нему не применялись бы"
    );
}

/// Готовит двух акторов и по сессии на каждого.
///
/// Посев идёт **с actor-контекстом**: под `FORCE` даже владелец таблицы не
/// вставит строку без него — проверено, отказ громкий.
async fn seed_two_actors(app: &PgPool) -> (i64, i64) {
    let mut tx = app.begin().await.expect("транзакция посева");

    let a1: i64 =
        sqlx::query("INSERT INTO actors (kind, name) VALUES ('owner', 'igor') RETURNING id")
            .fetch_one(&mut *tx)
            .await
            .expect("актор 1")
            .get(0);
    let a2: i64 =
        sqlx::query("INSERT INTO actors (kind, name) VALUES ('role', 'kst') RETURNING id")
            .fetch_one(&mut *tx)
            .await
            .expect("актор 2")
            .get(0);

    tx.commit().await.expect("коммит акторов");

    for actor in [a1, a2] {
        let mut tx = app.begin().await.expect("транзакция сессии");
        tx.execute(
            sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(actor.to_string()),
        )
        .await
        .expect("контекст");

        let session_id: i64 = sqlx::query(
            "INSERT INTO sessions (uuid7, actor_id, state, summary)
             VALUES (gen_random_uuid(), $1, 'completed', 'сессия актора')
             RETURNING id",
        )
        .bind(actor)
        .fetch_one(&mut *tx)
        .await
        .expect("сессия")
        .get(0);

        sqlx::query(
            "INSERT INTO session_events (session_id, version, kind, payload)
             VALUES ($1, 1, 'milestone', '{}'::jsonb)",
        )
        .bind(session_id)
        .execute(&mut *tx)
        .await
        .expect("веха");

        tx.commit().await.expect("коммит сессии");
    }

    (a1, a2)
}

async fn count_with_actor(app: &PgPool, actor: i64, table: &str) -> i64 {
    let mut tx = app.begin().await.expect("транзакция");
    tx.execute(sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(actor.to_string()))
        .await
        .expect("контекст");

    // AssertSqlSafe: в sqlx 0.9 динамический SQL требует явного признания.
    // Здесь `table` — литерал из вызывающего кода этого же файла, не ввод.
    let n: i64 = sqlx::query(AssertSqlSafe(format!("SELECT count(*) FROM {table}")))
        .fetch_one(&mut *tx)
        .await
        .expect("подсчёт")
        .get(0);

    tx.commit().await.expect("коммит");
    n
}

/// Каждая из трёх таблиц проверяется отдельно: у них разные предикаты, и
/// общая проверка «видны только свои» скрыла бы, что политика написана
/// только для одной.
#[sqlx::test(migrations = "./migrations")]
async fn each_actor_sees_only_own_rows(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = connect_as(&conn, "gefest_app", "GEFEST_APP_PASSWORD", "app").await;
    let (a1, a2) = seed_two_actors(&app).await;

    // sessions: собственная колонка актора.
    assert_eq!(count_with_actor(&app, a1, "sessions").await, 1);
    assert_eq!(count_with_actor(&app, a2, "sessions").await, 1);

    // session_events: своей колонки актора нет — видимость через родителя.
    assert_eq!(
        count_with_actor(&app, a1, "session_events").await,
        1,
        "актор 1 видит вехи только своей сессии"
    );
    assert_eq!(
        count_with_actor(&app, a2, "session_events").await,
        1,
        "актор 2 видит вехи только своей сессии"
    );
}

/// Команду видят обе стороны: и автор, и адресат.
#[sqlx::test(migrations = "./migrations")]
async fn command_visible_to_both_sides(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = connect_as(&conn, "gefest_app", "GEFEST_APP_PASSWORD", "app").await;
    let (issuer, addressee) = seed_two_actors(&app).await;

    let mut tx = app.begin().await.expect("транзакция");
    tx.execute(sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(issuer.to_string()))
        .await
        .expect("контекст");
    sqlx::query(
        "INSERT INTO commands (uuid7, issued_by, addressee_id, kind)
         VALUES (gen_random_uuid(), $1, $2, 'instruction')",
    )
    .bind(issuer)
    .bind(addressee)
    .execute(&mut *tx)
    .await
    .expect("команда");
    tx.commit().await.expect("коммит");

    assert_eq!(
        count_with_actor(&app, issuer, "commands").await,
        1,
        "автор видит свою команду"
    );
    assert_eq!(
        count_with_actor(&app, addressee, "commands").await,
        1,
        "адресат видит адресованную ему команду — иначе раннер не забрал бы её"
    );
}

/// Ловушка `''`-вместо-`NULL`.
///
/// `current_setting(name, true)` отдаёт `NULL` только до первого касания GUC
/// на соединении; после — пустую строку, и `DISCARD ALL` этого не отменяет.
/// Политика на `IS NULL` работала бы на первом запросе каждого соединения и
/// тихо переставала охранять на всех следующих — поэтому проверка идёт
/// дважды подряд по одному соединению.
#[sqlx::test(migrations = "./migrations")]
async fn no_context_returns_nothing_twice_on_same_connection(
    opts: PgPoolOptions,
    conn: PgConnectOptions,
) {
    let _ = opts;
    let app = connect_as(&conn, "gefest_app", "GEFEST_APP_PASSWORD", "app").await;
    seed_two_actors(&app).await;

    // Пул на одно соединение: оба запроса гарантированно идут по одному и
    // тому же физическому соединению.
    let single = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(
            conn.clone()
                .username("gefest_app")
                .password(&role_password("GEFEST_APP_PASSWORD", "app")),
        )
        .await
        .expect("пул на одно соединение");

    let first: i64 = sqlx::query("SELECT count(*) FROM sessions")
        .fetch_one(&single)
        .await
        .expect("первый запрос")
        .get(0);

    let second: i64 = sqlx::query("SELECT count(*) FROM sessions")
        .fetch_one(&single)
        .await
        .expect("второй запрос")
        .get(0);

    assert_eq!(first, 0, "первый запрос без контекста обязан вернуть пусто");
    assert_eq!(
        second, 0,
        "второй запрос на том же соединении тоже обязан вернуть пусто — \
         иначе политика написана через IS NULL и перестала охранять"
    );
}

/// Тихий отказ: `UPDATE` от владельца при `FORCE` без контекста меняет ноль
/// строк и **не падает**. Именно так остановился бы будущий janitor.
#[sqlx::test(migrations = "./migrations")]
async fn owner_update_without_context_silently_affects_nothing(
    opts: PgPoolOptions,
    conn: PgConnectOptions,
) {
    let _ = opts;
    let app = connect_as(&conn, "gefest_app", "GEFEST_APP_PASSWORD", "app").await;
    seed_two_actors(&app).await;

    // Пул мигратора — он же владелец таблиц в этой тестовой базе.
    let migrator = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(conn.clone())
        .await
        .expect("пул мигратора");

    let result = sqlx::query("UPDATE sessions SET summary = 'подмена'")
        .execute(&migrator)
        .await
        .expect("UPDATE обязан пройти без ошибки — в этом и суть тихого отказа");

    assert_eq!(
        result.rows_affected(),
        0,
        "владелец при FORCE без контекста обязан задеть ноль строк"
    );
}

/// `TRUNCATE` обходит и построчные триггеры, и политики — его удерживают
/// только привилегии.
#[sqlx::test(migrations = "./migrations")]
async fn app_role_cannot_truncate(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = connect_as(&conn, "gefest_app", "GEFEST_APP_PASSWORD", "app").await;

    for table in ["audit_log", "session_events", "command_deliveries"] {
        let err = sqlx::query(AssertSqlSafe(format!("TRUNCATE {table}")))
            .execute(&app)
            .await;
        assert!(
            err.is_err(),
            "TRUNCATE {table} прошёл от роли приложения — он обходит триггеры и политики"
        );
    }
}
