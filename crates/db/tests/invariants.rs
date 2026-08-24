//! Инварианты схемы: то, что база обязана отвергать.
//!
//! # Про append-only и пустые таблицы
//!
//! Построчный триггер `FOR EACH ROW` не вызывается, когда строк нет: `UPDATE`
//! по пустой журнальной таблице проходит без ошибки. Проверка запрета на
//! пустой таблице поэтому ничего не проверяет — она не может провалиться.
//!
//! Каждый такой тест ниже начинается с `assert!(count > 0)`: утверждением в
//! коде, а не комментарием. При разработке этой схемы ровно эта ловушка
//! сработала трижды подряд.

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{Executor, PgPool, Row};

async fn count(pool: &PgPool, table: &'static str) -> i64 {
    let query = match table {
        "task_events" => "SELECT count(*) FROM task_events",
        "session_events" => "SELECT count(*) FROM session_events",
        "command_deliveries" => "SELECT count(*) FROM command_deliveries",
        other => panic!("неизвестная таблица: {other}"),
    };
    sqlx::query(query)
        .fetch_one(pool)
        .await
        .expect("подсчёт")
        .get(0)
}

/// Заводит проект, задачу и одно событие журнала задач.
async fn seed_task_event(pool: &PgPool) {
    pool.execute(
        "INSERT INTO actors (kind, name) VALUES ('owner', 'igor');
         INSERT INTO projects (key, title, scope_class) VALUES ('GF', 'Гефест', 'personal');",
    )
    .await
    .expect("проект");

    sqlx::query(
        "INSERT INTO tasks (uuid7, project_id, title, status, created_by)
         SELECT gen_random_uuid(), p.id, 'Задача', 'backlog', a.id
         FROM projects p, actors a WHERE p.key = 'GF' AND a.name = 'igor'",
    )
    .execute(pool)
    .await
    .expect("задача");

    sqlx::query(
        "INSERT INTO task_events (task_id, version, actor_id, kind, origin)
         SELECT t.id, 1, a.id, 'created', 'owner'
         FROM tasks t, actors a WHERE a.name = 'igor'",
    )
    .execute(pool)
    .await
    .expect("событие");
}

#[sqlx::test(migrations = "./migrations")]
async fn task_events_reject_update_and_delete(pool: PgPool) {
    seed_task_event(&pool).await;

    // Без этой строки тест зеленел бы на пустой таблице, ничего не проверив.
    assert!(
        count(&pool, "task_events").await > 0,
        "журнал пуст — построчный триггер не вызовется, и проверка запрета будет пустой"
    );

    assert!(
        sqlx::query("UPDATE task_events SET note = 'подмена'")
            .execute(&pool)
            .await
            .is_err(),
        "UPDATE журнала обязан быть отклонён"
    );
    assert!(
        sqlx::query("DELETE FROM task_events")
            .execute(&pool)
            .await
            .is_err(),
        "DELETE из журнала обязан быть отклонён"
    );
    assert!(count(&pool, "task_events").await > 0, "строка уцелела");
}

#[sqlx::test(migrations = "./migrations")]
async fn projects_key_is_immutable(pool: PgPool) {
    pool.execute(
        "INSERT INTO projects (key, title, scope_class) VALUES ('GF', 'Гефест', 'personal');",
    )
    .await
    .expect("проект");

    assert!(
        sqlx::query("UPDATE projects SET key = 'XX' WHERE key = 'GF'")
            .execute(&pool)
            .await
            .is_err(),
        "ключ проекта обязан быть иммутабелен: он входит в ключи всех задач"
    );
    assert!(
        sqlx::query("UPDATE projects SET title = 'Новое имя' WHERE key = 'GF'")
            .execute(&pool)
            .await
            .is_ok(),
        "переименование проекта меняет title и обязано проходить"
    );
}

#[sqlx::test(migrations = "./migrations")]
async fn lookup_tables_reject_runtime_writes(pool: PgPool) {
    assert!(
        sqlx::query(
            "INSERT INTO task_statuses (code, is_terminal, description) VALUES ('x', false, 'y')"
        )
        .execute(&pool)
        .await
        .is_err(),
        "справочник наполняется только миграциями: истина перечисления — Rust-enum"
    );
    assert!(
        sqlx::query("INSERT INTO command_kinds (code, description) VALUES ('rm_rf', 'опасно')")
            .execute(&pool)
            .await
            .is_err(),
        "вид команды вне перечисления — путь к исполнению чужого намерения"
    );
}

#[sqlx::test(migrations = "./migrations")]
async fn project_requires_scope_class(pool: PgPool) {
    assert!(
        sqlx::query("INSERT INTO projects (key, title) VALUES ('NO', 'Без класса')")
            .execute(&pool)
            .await
            .is_err(),
        "scope_class обязателен: на нём держится фильтр приватности ADR-0003"
    );
    assert!(
        sqlx::query("INSERT INTO projects (key, title, scope_class) VALUES ('BAD', 'X', 'secret')")
            .execute(&pool)
            .await
            .is_err(),
        "значение вне personal/client обязано отвергаться"
    );
}

#[sqlx::test(migrations = "./migrations")]
async fn task_key_assigned_from_fresh_project(pool: PgPool) {
    pool.execute(
        "INSERT INTO actors (kind, name) VALUES ('owner', 'igor');
         INSERT INTO projects (key, title, scope_class) VALUES ('GF', 'Гефест', 'personal');",
    )
    .await
    .expect("проект");

    // Счётчик руками не готовится: его обязан завести триггер на projects.
    for expected in ["GF-1", "GF-2"] {
        let row = sqlx::query(
            "INSERT INTO tasks (uuid7, project_id, title, status, created_by)
             SELECT gen_random_uuid(), p.id, 'Задача', 'backlog', a.id
             FROM projects p, actors a WHERE p.key = 'GF' AND a.name = 'igor'
             RETURNING key",
        )
        .fetch_one(&pool)
        .await
        .expect("задача");

        let key: String = row.get(0);
        assert_eq!(
            key, expected,
            "ключ присваивается последовательно с первого проекта"
        );
    }
}

/// Одна живая команда старта на задачу; завершённая не мешает следующей.
#[sqlx::test(migrations = "./migrations")]
async fn one_live_start_command_per_task(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = PgPoolOptions::new()
        .max_connections(2)
        .connect_with(
            conn.username("gefest_app")
                .password(&std::env::var("GEFEST_APP_PASSWORD").unwrap_or_else(|_| "app".into())),
        )
        .await
        .expect("подключение ролью приложения");

    let actor: i64 =
        sqlx::query("INSERT INTO actors (kind, name) VALUES ('owner','igor') RETURNING id")
            .fetch_one(&app)
            .await
            .expect("актор")
            .get(0);

    app.execute(
        "INSERT INTO projects (key, title, scope_class) VALUES ('GF','Гефест','personal');",
    )
    .await
    .expect("проект");

    let task: i64 = sqlx::query(
        "INSERT INTO tasks (uuid7, project_id, title, status, created_by)
         SELECT gen_random_uuid(), p.id, 'Задача', 'backlog', $1 FROM projects p
         RETURNING id",
    )
    .bind(actor)
    .fetch_one(&app)
    .await
    .expect("задача")
    .get(0);

    let insert_start = |state: &'static str| {
        let app = app.clone();
        async move {
            let mut tx = app.begin().await.expect("транзакция");
            tx.execute(
                sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(actor.to_string()),
            )
            .await
            .expect("контекст");

            let result = sqlx::query(
                "INSERT INTO commands (uuid7, issued_by, kind, task_id, execution_state)
                 VALUES (gen_random_uuid(), $1, 'session_start', $2, $3)",
            )
            .bind(actor)
            .bind(task)
            .bind(state)
            .execute(&mut *tx)
            .await;

            if result.is_ok() {
                tx.commit().await.expect("коммит");
            }
            result.is_ok()
        }
    };

    assert!(
        insert_start("issued").await,
        "первая живая команда старта проходит"
    );
    assert!(
        !insert_start("issued").await,
        "вторая живая команда старта обязана быть отклонена"
    );
    assert!(
        insert_start("done").await,
        "завершённая команда не мешает: частичный UNIQUE не должен ломать нормальный поток"
    );
}
