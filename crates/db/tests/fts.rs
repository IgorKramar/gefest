//! Полнотекстовый поиск по саммари сессий.
//!
//! Корпус русский с непереведёнными техническими идентификаторами — таким он
//! и будет в жизни. Конфигурация `russian` покрывает оба языка без настройки:
//! словарная карта отправляет `asciiword` в `english_stem`, а `word` — в
//! `russian_stem`.

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{Executor, PgPool, Row};

/// Двадцать саммари, похожих на настоящие.
const CORPUS: [&str; 20] = [
    "Настроил rootless-контейнеры для исполнителей и проверил изоляцию",
    "Разбирал set_config и политики RLS, нашёл ловушку с пустой строкой",
    "Обновил sqlx-cli до версии 0.9 и перегенерировал кэш запросов",
    "Починил миграцию: колонка была VIRTUAL вместо STORED",
    "Добавил BRIN-индексы с autosummarize на журнальные таблицы",
    "Проверил каузальный delivered на спайке с фальшивым исполнителем",
    "Написал сторож чистоты графа зависимостей крейта core",
    "Развернул Headscale на европейском узле, настроил exit node",
    "Собрал образ исполнителя и запушил в приватный GHCR",
    "Разобрал падение CI: cargo-fmt отсутствовал в тулчейне",
    "Перевёл доставку указаний на push в stdin работающего процесса",
    "Заменил чёрный список белым в стороже графа зависимостей",
    "Настроил passkeys для входа владельца через tailnet",
    "Отладил reconciliation осиротевших сессий при старте бинаря",
    "Замерил деградацию BRIN без autosummarize: двадцать семь раз",
    "Перенёс сырьё сессий в файлы и вывел из бэкапа",
    "Написал runbook красного prepare --check для крейта db",
    "Разделил оси команды: execution_state и история доставки",
    "Проверил lease: команда старше пяти минут отдаётся повторно",
    "Настроил ruleset на main с пятью обязательными проверками",
];

async fn seed_corpus(app: &PgPool) {
    let actor: i64 =
        sqlx::query("INSERT INTO actors (kind, name) VALUES ('role','kst') RETURNING id")
            .fetch_one(app)
            .await
            .expect("актор")
            .get(0);

    let mut tx = app.begin().await.expect("транзакция");
    tx.execute(sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(actor.to_string()))
        .await
        .expect("контекст");

    for summary in CORPUS {
        sqlx::query(
            "INSERT INTO sessions (uuid7, actor_id, state, summary)
             VALUES (gen_random_uuid(), $1, 'completed', $2)",
        )
        .bind(actor)
        .bind(summary)
        .execute(&mut *tx)
        .await
        .expect("сессия");
    }

    tx.commit().await.expect("коммит корпуса");
}

async fn search(app: &PgPool, actor: i64, query: &str) -> i64 {
    let mut tx = app.begin().await.expect("транзакция");
    tx.execute(sqlx::query("SELECT set_config('app.actor_id', $1, true)").bind(actor.to_string()))
        .await
        .expect("контекст");

    let n: i64 =
        sqlx::query("SELECT count(*) FROM sessions WHERE summary_tsv @@ to_tsquery('russian', $1)")
            .bind(query)
            .fetch_one(&mut *tx)
            .await
            .expect("поиск")
            .get(0);

    tx.commit().await.expect("коммит");
    n
}

async fn app_pool(conn: PgConnectOptions) -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .connect_with(
            conn.username("gefest_app")
                .password(&std::env::var("GEFEST_APP_PASSWORD").unwrap_or_else(|_| "app".into())),
        )
        .await
        .expect("подключение ролью приложения")
}

/// Русская словоформа находится по другой форме того же слова.
#[sqlx::test(migrations = "./migrations")]
async fn russian_word_forms_are_stemmed(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = app_pool(conn).await;
    seed_corpus(&app).await;
    let actor: i64 = sqlx::query("SELECT id FROM actors WHERE name = 'kst'")
        .fetch_one(&app)
        .await
        .expect("актор")
        .get(0);

    // В корпусе «контейнеры», ищем «контейнер».
    assert!(
        search(&app, actor, "контейнер").await > 0,
        "словоформа не нашлась"
    );
    // В корпусе «изоляцию», ищем «изоляция».
    assert!(
        search(&app, actor, "изоляция").await > 0,
        "падежная форма не нашлась"
    );
    // В корпусе «сессий», ищем «сессия».
    assert!(
        search(&app, actor, "сессия").await > 0,
        "родительный падеж не нашёлся"
    );
}

/// Английский термин внутри русского текста находится: за него отвечает
/// english_stem, куда конфигурация russian отправляет asciiword.
#[sqlx::test(migrations = "./migrations")]
async fn english_terms_inside_russian_text_are_found(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = app_pool(conn).await;
    seed_corpus(&app).await;
    let actor: i64 = sqlx::query("SELECT id FROM actors WHERE name = 'kst'")
        .fetch_one(&app)
        .await
        .expect("актор")
        .get(0);

    for term in ["rootless", "Headscale", "passkeys", "GHCR"] {
        assert!(
            search(&app, actor, term).await > 0,
            "английский термин {term} не найден в русском корпусе"
        );
    }
}

/// Идентификатор с подчёркиванием лексится как два токена и находится
/// фразовым запросом. Поведение фиксируется тестом, чтобы не удивляться ему
/// при отладке поиска.
#[sqlx::test(migrations = "./migrations")]
async fn underscored_identifier_is_a_phrase(opts: PgPoolOptions, conn: PgConnectOptions) {
    let _ = opts;
    let app = app_pool(conn).await;
    seed_corpus(&app).await;
    let actor: i64 = sqlx::query("SELECT id FROM actors WHERE name = 'kst'")
        .fetch_one(&app)
        .await
        .expect("актор")
        .get(0);

    assert!(
        search(&app, actor, "set <-> config").await > 0,
        "set_config не найден фразовым запросом — подчёркивание разделяет токены"
    );
}

/// Словарная карта конфигурации `russian` — та, на которую опирается вся
/// схема поиска. Проверяется напрямую, а не через результат.
#[sqlx::test(migrations = "./migrations")]
async fn russian_config_routes_both_languages(pool: PgPool) {
    let rows = sqlx::query(
        "SELECT alias, dictionary::text FROM ts_debug('russian', 'Контейнеры rootless')
         WHERE alias <> 'blank'",
    )
    .fetch_all(&pool)
    .await
    .expect("ts_debug");

    let mut seen: Vec<(String, String)> = rows
        .into_iter()
        .map(|r| (r.get::<String, _>(0), r.get::<String, _>(1)))
        .collect();
    seen.sort();

    assert_eq!(
        seen,
        vec![
            ("asciiword".to_string(), "english_stem".to_string()),
            ("word".to_string(), "russian_stem".to_string()),
        ],
        "конфигурация russian обязана разводить кириллицу и латиницу по разным словарям"
    );
}
