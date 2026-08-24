//! Синхронность перечислений-истины со справочниками в базе.
//!
//! Истина — Rust-enum в `hef-core`; таблицы их зеркалят. Расхождение в любую
//! сторону — провал: вариант без строки означает, что код умеет выразить то,
//! чего база не примет, а строка без варианта — что база хранит значение,
//! которого код не знает.

use hef_core::{CommandKind, LookupEnum, TaskStatus};
use sqlx::{PgPool, Row};

async fn codes_in_table(pool: &PgPool, table: &'static str) -> Vec<String> {
    let query = match table {
        "command_kinds" => "SELECT code FROM command_kinds ORDER BY code",
        "task_statuses" => "SELECT code FROM task_statuses ORDER BY code",
        other => panic!("неизвестная таблица справочника: {other}"),
    };

    sqlx::query(query)
        .fetch_all(pool)
        .await
        .expect("чтение справочника")
        .into_iter()
        .map(|row| row.get::<String, _>(0))
        .collect()
}

fn assert_sets_match(rust: Vec<String>, db: Vec<String>, what: &str) {
    let mut rust_sorted = rust;
    rust_sorted.sort();
    let mut db_sorted = db;
    db_sorted.sort();

    let missing_in_db: Vec<_> = rust_sorted
        .iter()
        .filter(|c| !db_sorted.contains(c))
        .collect();
    let missing_in_rust: Vec<_> = db_sorted
        .iter()
        .filter(|c| !rust_sorted.contains(c))
        .collect();

    assert!(
        missing_in_db.is_empty(),
        "{what}: варианты есть в Rust, но нет в базе — {missing_in_db:?}. \
         Код умеет выразить значение, которое база отвергнет внешним ключом."
    );
    assert!(
        missing_in_rust.is_empty(),
        "{what}: строки есть в базе, но нет в Rust — {missing_in_rust:?}. \
         База хранит значение, которого код не знает."
    );
}

#[sqlx::test(migrations = "./migrations")]
async fn command_kinds_match_rust_enum(pool: PgPool) {
    let rust: Vec<String> = CommandKind::all()
        .iter()
        .map(|v| v.code().to_string())
        .collect();
    let db = codes_in_table(&pool, "command_kinds").await;
    assert_sets_match(rust, db, "CommandKind");
}

#[sqlx::test(migrations = "./migrations")]
async fn task_statuses_match_rust_enum(pool: PgPool) {
    let rust: Vec<String> = TaskStatus::all()
        .iter()
        .map(|v| v.code().to_string())
        .collect();
    let db = codes_in_table(&pool, "task_statuses").await;
    assert_sets_match(rust, db, "TaskStatus");
}

/// `is_terminal` в базе обязан совпадать с методом на перечислении: колонка
/// зеркалит именно его, а не хранит независимое мнение.
#[sqlx::test(migrations = "./migrations")]
async fn terminal_flag_matches_rust(pool: PgPool) {
    for status in TaskStatus::all() {
        let row = sqlx::query("SELECT is_terminal FROM task_statuses WHERE code = $1")
            .bind(status.code())
            .fetch_one(&pool)
            .await
            .expect("чтение статуса");

        let in_db: bool = row.get(0);
        assert_eq!(
            in_db,
            status.is_terminal(),
            "статус {}: база говорит is_terminal={in_db}, код — {}",
            status.code(),
            status.is_terminal()
        );
    }
}
