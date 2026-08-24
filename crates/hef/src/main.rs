//! `hef` — тонкий бинарь Гефеста.
//!
//! **Что кладём сюда:** разбор аргументов (clap), подкоманды, запуск
//! листенеров. Тонкий значит тонкий: логика живёт в `hef-api` и ниже, здесь
//! остаётся только точка входа и связывание.
//!
//! **Чего сюда не кладём:** ничего, что имеет смысл вызвать не из командной
//! строки. Дверь `hef remote` (клиент к удалённому Гефесту) не тянет сюда
//! серверные фичи — она открывается отдельным решением.

use std::process::ExitCode;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "hef", version, about = "Оркестратор Claude Code-агентов")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Применить миграции схемы.
    ///
    /// Отдельный шаг развёртывания: DSN мигратора используется только здесь
    /// и нигде больше (ADR-0005). Сервис приложения стартует после успешного
    /// завершения этой команды.
    Migrate,
}

#[tokio::main]
async fn main() -> ExitCode {
    let cli = Cli::parse();

    match cli.command {
        Command::Migrate => match migrate().await {
            Ok(()) => ExitCode::SUCCESS,
            Err(err) => {
                eprintln!("hef migrate: {err}");
                ExitCode::FAILURE
            }
        },
    }
}

/// Применяет встроенную серию миграций.
///
/// Серия forward-only: неудачная миграция не откатывается обратной, восстановление —
/// из `pg_dump`. Повторный вызов на применённой серии ничего не делает —
/// `sqlx` ведёт учёт в `_sqlx_migrations`.
async fn migrate() -> Result<(), Box<dyn std::error::Error>> {
    // Внятная ошибка вместо паники: отсутствие переменной — самая частая
    // причина неудачи, и сообщение обязано называть её прямо.
    let dsn = std::env::var("DATABASE_URL")
        .map_err(|_| "переменная DATABASE_URL не задана — укажите DSN роли gefest_migrator")?;

    let pool = sqlx::PgPool::connect(&dsn).await?;
    hef_db::MIGRATIONS.run(&pool).await?;

    println!("hef migrate: серия применена");
    Ok(())
}
