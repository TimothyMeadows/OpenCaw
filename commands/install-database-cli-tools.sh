#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/install-database-cli-tools.sh [--engine <name|all>] [--execute]

Supported engine values:
  mssql
  mysql
  cosmosdb
  azure-storage-tables
  sqlite
  postgresdb
  databricks
  all

Default behavior prints installation commands.
Use --execute to run detected commands on the current machine.
EOF
}

engine="all"
execute=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      engine="${2:-}"
      shift 2
      ;;
    --execute)
      execute=1
      shift
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

normalize_engine() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$raw" in
    all) echo "all" ;;
    mssql|sqlserver) echo "mssql" ;;
    mysql) echo "mysql" ;;
    cosmos|cosmosdb) echo "cosmosdb" ;;
    azurestoragetables|azure-storage-tables|tables|azuretables) echo "azure-storage-tables" ;;
    sqlite) echo "sqlite" ;;
    postgres|postgresql|postgresdb) echo "postgresdb" ;;
    databricks) echo "databricks" ;;
    *) return 1 ;;
  esac
}

detect_platform() {
  local uname_out
  uname_out="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$uname_out" in
    mingw*|msys*|cygwin*) echo "windows" ;;
    darwin*) echo "macos" ;;
    linux*) echo "linux" ;;
    *) echo "unknown" ;;
  esac
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_step() {
  local description="$1"
  local cmd="$2"
  echo "- ${description}"
  echo "  $cmd"
  if [[ "$execute" -eq 1 ]]; then
    bash -lc "$cmd"
  fi
}

install_azure_cli() {
  local platform="$1"
  echo "Installing Azure CLI (used by Cosmos DB and Azure Storage Tables flows)"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install Azure CLI with winget" "winget install --id Microsoft.AzureCLI --exact --silent"
      elif has_cmd choco; then
        run_step "Install Azure CLI with Chocolatey" "choco install azure-cli -y"
      else
        echo "- No supported Windows package manager found (winget/choco)." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install Azure CLI with Homebrew" "brew install azure-cli"
      else
        echo "- Homebrew not found. Install Homebrew first." >&2
      fi
      ;;
    linux)
      if has_cmd apt-get; then
        run_step "Install Azure CLI (Debian/Ubuntu installer script)" "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
      elif has_cmd dnf; then
        run_step "Install Azure CLI with dnf" "sudo dnf install -y azure-cli"
      elif has_cmd yum; then
        run_step "Install Azure CLI with yum" "sudo yum install -y azure-cli"
      else
        echo "- No supported Linux package manager found for Azure CLI." >&2
      fi
      ;;
    *)
      echo "- Unsupported platform for Azure CLI auto-install." >&2
      ;;
  esac
}

install_mssql_cli() {
  local platform="$1"
  echo "Installing MSSQL CLI tooling (sqlcmd)"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install sqlcmd with winget" "winget install --id Microsoft.Sqlcmd --exact --silent"
      else
        echo "- winget not found. Install sqlcmd manually from Microsoft documentation." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install sqlcmd with Homebrew" "brew install sqlcmd"
      else
        echo "- Homebrew not found. Install sqlcmd manually." >&2
      fi
      ;;
    linux)
      if has_cmd apt-get; then
        run_step "Install sqlcmd (requires Microsoft package feed)" "sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev"
      elif has_cmd dnf; then
        run_step "Install sqlcmd (requires Microsoft package feed)" "sudo ACCEPT_EULA=Y dnf install -y mssql-tools18 unixODBC-devel"
      elif has_cmd yum; then
        run_step "Install sqlcmd (requires Microsoft package feed)" "sudo ACCEPT_EULA=Y yum install -y mssql-tools18 unixODBC-devel"
      else
        echo "- No supported Linux package manager found for sqlcmd." >&2
      fi
      ;;
    *)
      echo "- Unsupported platform for sqlcmd auto-install." >&2
      ;;
  esac
}

install_mysql_cli() {
  local platform="$1"
  echo "Installing MySQL CLI tooling"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install MySQL Shell with winget" "winget install --id Oracle.MySQLShell --exact --silent"
      elif has_cmd choco; then
        run_step "Install MySQL Shell with Chocolatey" "choco install mysql.shell -y"
      else
        echo "- No supported Windows package manager found for MySQL CLI." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install mysql client with Homebrew" "brew install mysql-client"
      else
        echo "- Homebrew not found. Install mysql client manually." >&2
      fi
      ;;
    linux)
      if has_cmd apt-get; then
        run_step "Install mysql client with apt" "sudo apt-get install -y mysql-client"
      elif has_cmd dnf; then
        run_step "Install mysql client with dnf" "sudo dnf install -y mysql"
      elif has_cmd yum; then
        run_step "Install mysql client with yum" "sudo yum install -y mysql"
      else
        echo "- No supported Linux package manager found for MySQL CLI." >&2
      fi
      ;;
    *)
      echo "- Unsupported platform for MySQL CLI auto-install." >&2
      ;;
  esac
}

install_sqlite_cli() {
  local platform="$1"
  echo "Installing SQLite CLI tooling"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install sqlite with winget" "winget install --id SQLite.SQLite --exact --silent"
      elif has_cmd choco; then
        run_step "Install sqlite with Chocolatey" "choco install sqlite -y"
      else
        echo "- No supported Windows package manager found for SQLite CLI." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install sqlite with Homebrew" "brew install sqlite"
      else
        echo "- Homebrew not found. Install sqlite manually." >&2
      fi
      ;;
    linux)
      if has_cmd apt-get; then
        run_step "Install sqlite with apt" "sudo apt-get install -y sqlite3"
      elif has_cmd dnf; then
        run_step "Install sqlite with dnf" "sudo dnf install -y sqlite"
      elif has_cmd yum; then
        run_step "Install sqlite with yum" "sudo yum install -y sqlite"
      else
        echo "- No supported Linux package manager found for SQLite CLI." >&2
      fi
      ;;
    *)
      echo "- Unsupported platform for SQLite CLI auto-install." >&2
      ;;
  esac
}

install_postgres_cli() {
  local platform="$1"
  echo "Installing PostgreSQL CLI tooling (psql)"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install PostgreSQL with winget" "winget install --id PostgreSQL.PostgreSQL --exact --silent"
      elif has_cmd choco; then
        run_step "Install PostgreSQL with Chocolatey" "choco install postgresql -y"
      else
        echo "- No supported Windows package manager found for PostgreSQL CLI." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install postgresql client with Homebrew" "brew install libpq"
        run_step "Link psql into PATH" "brew link --force libpq"
      else
        echo "- Homebrew not found. Install psql manually." >&2
      fi
      ;;
    linux)
      if has_cmd apt-get; then
        run_step "Install postgresql client with apt" "sudo apt-get install -y postgresql-client"
      elif has_cmd dnf; then
        run_step "Install postgresql client with dnf" "sudo dnf install -y postgresql"
      elif has_cmd yum; then
        run_step "Install postgresql client with yum" "sudo yum install -y postgresql"
      else
        echo "- No supported Linux package manager found for PostgreSQL CLI." >&2
      fi
      ;;
    *)
      echo "- Unsupported platform for PostgreSQL CLI auto-install." >&2
      ;;
  esac
}

install_databricks_cli() {
  local platform="$1"
  echo "Installing Databricks CLI tooling"
  case "$platform" in
    windows)
      if has_cmd winget; then
        run_step "Install Databricks CLI with winget" "winget install Databricks.DatabricksCLI"
      elif has_cmd choco; then
        run_step "Install Databricks CLI with Chocolatey" "choco install databricks-cli -y"
      else
        echo "- No supported Windows package manager found for Databricks CLI." >&2
      fi
      ;;
    macos)
      if has_cmd brew; then
        run_step "Install Databricks CLI with Homebrew tap" "brew tap databricks/tap && brew install databricks"
      else
        echo "- Homebrew not found. Install Databricks CLI manually." >&2
      fi
      ;;
    linux)
      run_step "Install Databricks CLI via setup script" "curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
      ;;
    *)
      echo "- Unsupported platform for Databricks CLI auto-install." >&2
      ;;
  esac

  if has_cmd python3; then
    run_step "Optional: install Databricks SQL CLI via pip" "python3 -m pip install --upgrade databricks-sql-cli"
  elif has_cmd python; then
    run_step "Optional: install Databricks SQL CLI via pip" "python -m pip install --upgrade databricks-sql-cli"
  fi
}

platform="$(detect_platform)"
echo "Detected platform: $platform"
if [[ "$execute" -eq 0 ]]; then
  echo "Mode: dry-run (commands are printed only)"
else
  echo "Mode: execute"
fi

normalized_engine="$(normalize_engine "$engine" || true)"
if [[ -z "$normalized_engine" ]]; then
  echo "Unsupported engine value: $engine" >&2
  usage >&2
  exit 1
fi

targets=()
if [[ "$normalized_engine" == "all" ]]; then
  targets=(
    "mssql"
    "mysql"
    "cosmosdb"
    "azure-storage-tables"
    "sqlite"
    "postgresdb"
    "databricks"
  )
else
  targets=("$normalized_engine")
fi

for target in "${targets[@]}"; do
  echo
  echo "=== $target ==="
  case "$target" in
    mssql)
      install_mssql_cli "$platform"
      ;;
    mysql)
      install_mysql_cli "$platform"
      ;;
    cosmosdb)
      install_azure_cli "$platform"
      if [[ "$execute" -eq 1 ]]; then
        run_step "Optional: add cosmosdb-preview extension" "az extension add --name cosmosdb-preview --upgrade"
      else
        echo "- Optional extension command:"
        echo "  az extension add --name cosmosdb-preview --upgrade"
      fi
      ;;
    azure-storage-tables)
      install_azure_cli "$platform"
      ;;
    sqlite)
      install_sqlite_cli "$platform"
      ;;
    postgresdb)
      install_postgres_cli "$platform"
      ;;
    databricks)
      install_databricks_cli "$platform"
      ;;
    *)
      echo "Unhandled engine target: $target" >&2
      exit 1
      ;;
  esac
done

echo
echo "Installation guidance completed."
echo "Use --execute to run commands automatically."

