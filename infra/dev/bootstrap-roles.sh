#!/usr/bin/env bash
# Создание трёх ролей Postgres. Выполняется один раз при инициализации тома
# (монтируется в docker-entrypoint-initdb.d), а в CI — вызовом после старта
# сервиса.
#
# --- Почему .sh, а не .sql -------------------------------------------------
# Файл `.sql` в docker-entrypoint-initdb.d исполняется psql, а psql НЕ
# разворачивает переменные окружения. Проверено: строка
#   CREATE ROLE gefest_app LOGIN PASSWORD '${GEFEST_APP_PASSWORD}'
# при заданной переменной отрабатывает БЕЗ ошибки и создаёт роль с паролем —
# литералом `${GEFEST_APP_PASSWORD}`. Приложение потом получает отказ
# аутентификации на ровном месте, а дешёвый выход из этой отладки — вписать
# пароль прямо в файл, который лежит в git.
#
# Shell-скрипт окружение видит; пароль уходит в psql через -v и в файле не
# появляется никогда.
#
# --- Почему CREATE ROLE не в миграциях -------------------------------------
# Роль — объект уровня кластера, а не базы. В forward-only серии CREATE ROLE
# проходит один раз и падает на второй базе, а в режиме «база на тест»
# протекает между тестами.

set -euo pipefail

: "${POSTGRES_DB:?POSTGRES_DB не задан}"
: "${GEFEST_MIGRATOR_PASSWORD:?GEFEST_MIGRATOR_PASSWORD не задан}"
: "${GEFEST_APP_PASSWORD:?GEFEST_APP_PASSWORD не задан}"
: "${GEFEST_OWNER_PASSWORD:?GEFEST_OWNER_PASSWORD не задан}"

psql -v ON_ERROR_STOP=1 \
     --username "${POSTGRES_USER:-postgres}" \
     --dbname "$POSTGRES_DB" \
     -v migrator_pw="$GEFEST_MIGRATOR_PASSWORD" \
     -v app_pw="$GEFEST_APP_PASSWORD" \
     -v owner_pw="$GEFEST_OWNER_PASSWORD" <<'SQL'
-- gefest_migrator — владелец объектов схемы.
--
-- CREATEDB обязателен: #[sqlx::test] создаёт отдельную базу на каждый тест
-- ролью из DATABASE_URL, и без этого атрибута тесты не запустятся вовсе.
--
-- SUPERUSER и BYPASSRLS не выдаются намеренно. Проверено: суперпользователь
-- обходит FORCE ROW LEVEL SECURITY целиком — под ним весь набор RLS-тестов
-- зеленеет, ничего не проверяя.
CREATE ROLE gefest_migrator LOGIN CREATEDB PASSWORD :'migrator_pw';

-- gefest_app — роль приложения. Не владелец объектов: владелец обходил бы
-- RLS, если бы не FORCE, и всё равно имел бы TRUNCATE.
CREATE ROLE gefest_app LOGIN PASSWORD :'app_pw';

-- gefest_owner — отладочный контур владельца. Тоже не владелец объектов.
CREATE ROLE gefest_owner LOGIN PASSWORD :'owner_pw';

-- Схема отдаётся мигратору во владение.
--
-- В PG 15+ роль PUBLIC лишена CREATE на схеме public, поэтому без этой
-- строки первая же миграция падает с `permission denied for schema public`.
-- Владение, а не GRANT CREATE: мигратор обязан владеть объектами схемы —
-- на этом стоит вся конструкция RLS (app и owner не владельцы, а значит
-- политики к ним применяются).
--
-- В базах, которые #[sqlx::test] создаёт на каждый тест, схема достаётся
-- создателю — то есть тому же мигратору, — поэтому там строка не нужна.
ALTER SCHEMA public OWNER TO gefest_migrator;
SQL

# Права на саму базу — отдельным вызовом: имя базы нельзя передать
# параметром psql внутрь GRANT, а :"var" в этой позиции не разворачивается.
#
# CREATE ON DATABASE нужен тестам: #[sqlx::test] заводит служебную схему
# _sqlx_test в maintenance-базе, чтобы вести учёт баз, созданных на каждый
# тест. Без этого права весь набор падает на этапе подготовки с
# `permission denied for database` — до единой проверки.
psql -v ON_ERROR_STOP=1 \
     --username "${POSTGRES_USER:-postgres}" \
     --dbname "$POSTGRES_DB" \
     -c "GRANT CREATE, CONNECT ON DATABASE \"$POSTGRES_DB\" TO gefest_migrator;"

echo "bootstrap-roles: три роли созданы (migrator с CREATEDB, без SUPERUSER)."
