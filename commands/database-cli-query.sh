#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/database-cli-query.sh <engine> [options]

Engines:
  mssql
  mysql
  cosmosdb
  azure-storage-tables
  sqlite
  postgresdb
  databricks

Common options:
  --query "<statement>"
  --host <hostname>
  --port <port>
  --database <name>
  --user <username>
  --password-env <ENV_VAR_NAME>

Engine-specific options:
  --database-file <path>                 (sqlite)
  --resource-group <name>                (cosmosdb)
  --account-name <name>                  (cosmosdb, azure-storage-tables)
  --container <name>                     (cosmosdb)
  --table-name <name>                    (azure-storage-tables)
  --filter "<odata-filter>"              (azure-storage-tables)
  --select "<col1,col2,...>"             (azure-storage-tables)
  --auth-mode <login|key>                (azure-storage-tables)
  --connection-string "<conn-string>"    (azure-storage-tables)
  --warehouse-id <id>                    (databricks)
  --profile <name>                       (databricks)
  --wait-timeout <seconds>               (databricks; default 30)

Examples:
  ./commands/database-cli-query.sh mssql --host localhost --database master --query "SELECT 1"
  ./commands/database-cli-query.sh mysql --host localhost --user root --password-env MYSQL_PASSWORD --query "SELECT 1"
  ./commands/database-cli-query.sh postgresdb --host localhost --database postgres --user postgres --password-env PGPASSWORD --query "SELECT 1"
  ./commands/database-cli-query.sh sqlite --database-file ./app.db --query "SELECT name FROM sqlite_master"
  ./commands/database-cli-query.sh azure-storage-tables --account-name mystorage --table-name MyTable --auth-mode login --filter "PartitionKey eq 'pk1'"
  ./commands/database-cli-query.sh databricks --warehouse-id abc123 --query "SELECT current_date()"
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

normalize_engine() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$raw" in
    mssql|sqlserver) echo "mssql" ;;
    mysql) echo "mysql" ;;
    cosmosdb|cosmos) echo "cosmosdb" ;;
    azurestoragetables|azure-storage-tables|tables|azuretables) echo "azure-storage-tables" ;;
    sqlite) echo "sqlite" ;;
    postgres|postgresql|postgresdb) echo "postgresdb" ;;
    databricks) echo "databricks" ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

require_value() {
  local value="$1"
  local label="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required option: $label" >&2
    exit 1
  fi
}

read_secret() {
  local env_name="$1"
  if [[ -z "$env_name" ]]; then
    printf ''
    return 0
  fi

  if [[ -z "${!env_name:-}" ]]; then
    echo "Environment variable is not set: $env_name" >&2
    exit 1
  fi

  printf '%s' "${!env_name}"
}

json_escape() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  input="${input//$'\n'/\\n}"
  input="${input//$'\r'/\\r}"
  input="${input//$'\t'/\\t}"
  printf '%s' "$input"
}

engine_raw="$1"
shift

engine="$(normalize_engine "$engine_raw" || true)"
if [[ -z "$engine" ]]; then
  echo "Unsupported engine: $engine_raw" >&2
  usage >&2
  exit 1
fi

query=""
host=""
port=""
database=""
user_name=""
password_env=""
database_file=""
resource_group=""
account_name=""
container_name=""
table_name=""
filter_expr=""
select_expr=""
auth_mode=""
connection_string=""
warehouse_id=""
profile_name=""
wait_timeout="30"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      query="${2:-}"
      shift 2
      ;;
    --host|--server)
      host="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
      shift 2
      ;;
    --database|--database-name)
      database="${2:-}"
      shift 2
      ;;
    --user)
      user_name="${2:-}"
      shift 2
      ;;
    --password-env)
      password_env="${2:-}"
      shift 2
      ;;
    --database-file)
      database_file="${2:-}"
      shift 2
      ;;
    --resource-group)
      resource_group="${2:-}"
      shift 2
      ;;
    --account-name)
      account_name="${2:-}"
      shift 2
      ;;
    --container)
      container_name="${2:-}"
      shift 2
      ;;
    --table-name)
      table_name="${2:-}"
      shift 2
      ;;
    --filter)
      filter_expr="${2:-}"
      shift 2
      ;;
    --select)
      select_expr="${2:-}"
      shift 2
      ;;
    --auth-mode)
      auth_mode="${2:-}"
      shift 2
      ;;
    --connection-string)
      connection_string="${2:-}"
      shift 2
      ;;
    --warehouse-id)
      warehouse_id="${2:-}"
      shift 2
      ;;
    --profile)
      profile_name="${2:-}"
      shift 2
      ;;
    --wait-timeout)
      wait_timeout="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run_mssql() {
  require_cmd sqlcmd
  require_value "$host" "--host"
  require_value "$query" "--query"

  local -a cmd
  cmd=(sqlcmd -S "$host" -Q "$query")

  if [[ -n "$database" ]]; then
    cmd+=(-d "$database")
  fi

  if [[ -n "$user_name" ]]; then
    local password
    password="$(read_secret "$password_env")"
    cmd+=(-U "$user_name" -P "$password")
  fi

  "${cmd[@]}"
}

run_mysql() {
  require_cmd mysql
  require_value "$query" "--query"

  local -a cmd
  cmd=(mysql --batch --raw)

  if [[ -n "$host" ]]; then
    cmd+=(-h "$host")
  fi

  if [[ -n "$port" ]]; then
    cmd+=(-P "$port")
  fi

  if [[ -n "$user_name" ]]; then
    cmd+=(-u "$user_name")
  fi

  if [[ -n "$database" ]]; then
    cmd+=("$database")
  fi

  cmd+=(-e "$query")

  local had_mysql_pwd=0
  local old_mysql_pwd=""
  if [[ -n "$password_env" ]]; then
    had_mysql_pwd=1
    old_mysql_pwd="${MYSQL_PWD:-}"
    export MYSQL_PWD
    MYSQL_PWD="$(read_secret "$password_env")"
  fi

  "${cmd[@]}"

  if [[ "$had_mysql_pwd" -eq 1 ]]; then
    if [[ -n "$old_mysql_pwd" ]]; then
      export MYSQL_PWD="$old_mysql_pwd"
    else
      unset MYSQL_PWD
    fi
  fi
}

run_postgres() {
  require_cmd psql
  require_value "$query" "--query"

  local -a cmd
  cmd=(psql)

  if [[ -n "$host" ]]; then
    cmd+=(-h "$host")
  fi

  if [[ -n "$port" ]]; then
    cmd+=(-p "$port")
  fi

  if [[ -n "$user_name" ]]; then
    cmd+=(-U "$user_name")
  fi

  if [[ -n "$database" ]]; then
    cmd+=(-d "$database")
  fi

  cmd+=(-c "$query")

  local had_pgpassword=0
  local old_pgpassword=""
  if [[ -n "$password_env" ]]; then
    had_pgpassword=1
    old_pgpassword="${PGPASSWORD:-}"
    export PGPASSWORD
    PGPASSWORD="$(read_secret "$password_env")"
  fi

  "${cmd[@]}"

  if [[ "$had_pgpassword" -eq 1 ]]; then
    if [[ -n "$old_pgpassword" ]]; then
      export PGPASSWORD="$old_pgpassword"
    else
      unset PGPASSWORD
    fi
  fi
}

run_sqlite() {
  require_cmd sqlite3
  require_value "$database_file" "--database-file"
  require_value "$query" "--query"

  sqlite3 "$database_file" "$query"
}

run_azure_storage_tables() {
  require_cmd az
  require_value "$table_name" "--table-name"

  local -a cmd
  cmd=(az storage entity query --table-name "$table_name" --output json)

  if [[ -n "$account_name" ]]; then
    cmd+=(--account-name "$account_name")
  fi

  if [[ -n "$auth_mode" ]]; then
    cmd+=(--auth-mode "$auth_mode")
  fi

  if [[ -n "$connection_string" ]]; then
    cmd+=(--connection-string "$connection_string")
  fi

  if [[ -n "$filter_expr" ]]; then
    cmd+=(--filter "$filter_expr")
  fi

  if [[ -n "$select_expr" ]]; then
    local -a select_parts
    IFS=',' read -r -a select_parts <<< "$select_expr"
    cmd+=(--select)
    for item in "${select_parts[@]}"; do
      item="$(echo "$item" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      if [[ -n "$item" ]]; then
        cmd+=("$item")
      fi
    done
  fi

  "${cmd[@]}"
}

run_cosmosdb() {
  require_cmd az
  require_value "$resource_group" "--resource-group"
  require_value "$account_name" "--account-name"

  if [[ -n "$query" ]]; then
    echo "Azure CLI does not currently provide a direct Cosmos DB SQL data-query command." >&2
    echo "Use SDK/Data Explorer/REST data-plane calls for SQL query execution." >&2
    exit 1
  fi

  if [[ -n "$database" && -n "$container_name" ]]; then
    az cosmosdb sql container show \
      --resource-group "$resource_group" \
      --account-name "$account_name" \
      --database-name "$database" \
      --name "$container_name"
    return
  fi

  if [[ -n "$database" ]]; then
    az cosmosdb sql container list \
      --resource-group "$resource_group" \
      --account-name "$account_name" \
      --database-name "$database"
    return
  fi

  az cosmosdb sql database list \
    --resource-group "$resource_group" \
    --account-name "$account_name"
}

run_databricks() {
  require_cmd databricks
  require_value "$warehouse_id" "--warehouse-id"
  require_value "$query" "--query"

  local escaped_query
  escaped_query="$(json_escape "$query")"

  local payload
  payload="$(cat <<EOF
{"warehouse_id":"$warehouse_id","statement":"$escaped_query","wait_timeout":"${wait_timeout}s"}
EOF
)"

  local -a cmd
  cmd=(databricks)
  if [[ -n "$profile_name" ]]; then
    cmd+=(--profile "$profile_name")
  fi
  cmd+=(api post /api/2.0/sql/statements --json "$payload")

  "${cmd[@]}"
}

case "$engine" in
  mssql)
    run_mssql
    ;;
  mysql)
    run_mysql
    ;;
  postgresdb)
    run_postgres
    ;;
  sqlite)
    run_sqlite
    ;;
  azure-storage-tables)
    run_azure_storage_tables
    ;;
  cosmosdb)
    run_cosmosdb
    ;;
  databricks)
    run_databricks
    ;;
  *)
    echo "Unhandled engine: $engine" >&2
    exit 1
    ;;
esac
