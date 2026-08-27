#!/usr/bin/env bash
#
# install-mysql-import.sh — instala (o desinstala) la herramienta `mysql-import`.
#
# Coloca:
#   $PREFIX/bin/mysql-import                      (script, ejecutable)
#   $PREFIX/share/applications/mysql-import.desktop  (lanzador «MySQL Import»)
#   $PREFIX/share/doc/mysql-import/README.md      (documentación)
#   ~/.config/mysql-import.env                    (plantilla, solo si no existe)
#
# Uso:
#   ./install-mysql-import.sh [--prefix DIR] [--no-config] [--uninstall]
#
#   --prefix DIR   raíz de instalación        (def: ~/.local)
#   --no-config    no crear la plantilla ~/.config/mysql-import.env
#   --uninstall    quita todo lo instalado (conserva el .env)
#
set -euo pipefail

PREFIX="$HOME/.local"
DO_CONFIG=1
ACTION=install

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift ;;
    --no-config) DO_CONFIG=0 ;;
    --uninstall) ACTION=uninstall ;;
    -h|--help)   sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
DOC_DIR="$PREFIX/share/doc/mysql-import"
CFG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mysql-import.env"
BIN_TARGET="$BIN_DIR/mysql-import"
DESKTOP_TARGET="$APP_DIR/mysql-import.desktop"
DOC_TARGET="$DOC_DIR/README.md"

if [ "$ACTION" = uninstall ]; then
  rm -fv "$BIN_TARGET" "$DESKTOP_TARGET" "$DOC_TARGET"
  rmdir "$DOC_DIR" 2>/dev/null || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" 2>/dev/null || true
  echo "Desinstalado (se conservó $CFG_FILE si existía)."
  exit 0
fi

# --- dependencias: solo avisos, salvo bash ---
command -v bash >/dev/null 2>&1 || { echo "Falta bash." >&2; exit 1; }
have_docker=0; command -v docker  >/dev/null 2>&1 && have_docker=1
have_client=0; { command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; } && have_client=1
if [ "$have_docker" = 0 ] && [ "$have_client" = 0 ]; then
  echo "Aviso: no hay 'docker' ni cliente 'mysql'/'mariadb'; mysql-import necesita al menos uno." >&2
fi
command -v gzip   >/dev/null 2>&1 || echo "Aviso: falta 'gzip' (dumps .sql.gz)." >&2
command -v zenity >/dev/null 2>&1 || echo "Aviso: falta 'zenity' (opcional, interfaz gráfica)." >&2

mkdir -p "$BIN_DIR" "$APP_DIR" "$DOC_DIR"

cat > "$BIN_TARGET" <<'MYSQL_IMPORT_SCRIPT_EOF'
#!/usr/bin/env bash
#
# mysql-import — importa un dump SQL a MySQL/MariaDB (en Docker o nativo),
#                creando la base si hace falta y haciendo SOURCE.
#
# Docs completas:  ~/.local/share/doc/mysql-import/README.md   (o  mysql-import --help)
#
set -euo pipefail
VERSION=1.1.0
SELF=${0##*/}

# ------------------------------------------------------------------ config files
# KEY=value ; se cargan en orden, el ultimo pisa al anterior.
for _cfg in /etc/mysql-import.env "${XDG_CONFIG_HOME:-$HOME/.config}/mysql-import.env" ./.mysql-import.env; do
  [ -f "$_cfg" ] && { set -a; . "$_cfg"; set +a; }
done

# ------------------------------------------------------------------ valores base
MODE="${MYSQL_IMPORT_MODE:-auto}"          # auto | docker | native
CONTAINER="${MYSQL_IMPORT_CONTAINER:-}"
HOST="${MYSQL_IMPORT_HOST:-}"
PORT="${MYSQL_IMPORT_PORT:-3306}"
DBUSER="${MYSQL_IMPORT_USER:-root}"
PW="${MYSQL_IMPORT_PASSWORD:-}"
CHARSET="${MYSQL_IMPORT_CHARSET:-utf8mb4}"
COLLATION="${MYSQL_IMPORT_COLLATION:-utf8mb4_unicode_ci}"
CLIENT="${MYSQL_IMPORT_CLIENT:-}"          # binario cliente (native): mysql | mariadb
DROP=0 ASSUME_YES=0 NO_GUI=0 LIST_ONLY=0 FORCE_STREAM=0
SRC="" DB=""

usage() {
  cat <<EOF
$SELF v$VERSION — importa un dump SQL a MySQL/MariaDB y le hace SOURCE.

USO
  $SELF [opciones] [RUTA.sql|.sql.gz] [NOMBRE_DB]
  $SELF                       # sin args: selector grafico (zenity) si hay display

OPCIONES
  --drop                DROP DATABASE antes de importar (pide confirmacion)
  --stream              importa por tuberia en vez de copiar+SOURCE
  --list                muestra las bases del servidor y termina
  -y, --yes             no preguntar nada (modo no interactivo)
  --no-gui              nunca usar zenity, siempre terminal
  --mode MODE           auto | docker | native            (def: $MODE)
  --container NOMBRE    contenedor Docker de MySQL/MariaDB
  --host HOST           host (implica modo native)
  --port PUERTO         puerto native                     (def: $PORT)
  -u, --user USUARIO    usuario MySQL                      (def: $DBUSER)
  -p, --password PASS   password (o se lee del contenedor / se pregunta)
  --charset NOMBRE      charset al crear la BD             (def: $CHARSET)
  --collation NOMBRE    collation al crear la BD           (def: $COLLATION)
  -h, --help            esta ayuda
  -V, --version         version

MODOS
  docker   ejecuta el cliente 'mysql' DENTRO del contenedor (docker exec).
  native   ejecuta el cliente 'mysql'/'mariadb' local contra HOST:PORT.
  auto     native si se da --host/MYSQL_IMPORT_HOST; si no, docker si hay un
           contenedor MySQL corriendo; si no, native contra 127.0.0.1.

CONFIG (env o archivos KEY=value, en este orden)
  /etc/mysql-import.env
  \${XDG_CONFIG_HOME:-~/.config}/mysql-import.env
  ./.mysql-import.env
  Variables: MYSQL_IMPORT_MODE, _CONTAINER, _HOST, _PORT, _USER, _PASSWORD,
             _CHARSET, _COLLATION, _CLIENT

EJEMPLOS
  $SELF dump.sql
  $SELF --drop backup.sql.gz clinicavalle_test
  $SELF --mode native --host db.local -u admin dump.sql tienda
  $SELF --list
EOF
}

# ------------------------------------------------------------------ parseo args
while [ $# -gt 0 ]; do
  case "$1" in
    --drop) DROP=1 ;;
    --stream) FORCE_STREAM=1 ;;
    --list) LIST_ONLY=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    --no-gui) NO_GUI=1 ;;
    --mode) MODE="$2"; shift ;;
    --container) CONTAINER="$2"; shift ;;
    --host) HOST="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    -u|--user) DBUSER="$2"; shift ;;
    -p|--password) PW="$2"; shift ;;
    --charset) CHARSET="$2"; shift ;;
    --collation) COLLATION="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -V|--version) echo "$SELF $VERSION"; exit 0 ;;
    --) shift; break ;;
    -*) echo "$SELF: opcion desconocida: $1" >&2; exit 2 ;;
    *) if [ -z "$SRC" ]; then SRC="$1"; elif [ -z "$DB" ]; then DB="$1"; else
         echo "$SELF: argumento sobrante: $1" >&2; exit 2; fi ;;
  esac
  shift
done
[ $# -gt 0 ] && { [ -z "$SRC" ] && SRC="$1" || DB="${DB:-$1}"; }

# ------------------------------------------------------------------ feedback UI
GUI=0
if [ "$NO_GUI" = 0 ] && [ "$ASSUME_YES" = 0 ] && command -v zenity >/dev/null 2>&1 \
   && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; } && [ -z "$SRC" ]; then
  GUI=1
fi
info() { if [ "$GUI" = 1 ]; then zenity --info --no-wrap --title "$SELF" --text "$1" 2>/dev/null||true
         else printf '\033[1;32m✔\033[0m %s\n' "$1"; fi; }
err()  { if [ "$GUI" = 1 ]; then zenity --error --no-wrap --title "$SELF" --text "$1" 2>/dev/null||true
         else printf '\033[1;31mERROR\033[0m %s\n' "$1" >&2; fi; }
step() { [ "$GUI" = 1 ] || printf '\033[1;34m•\033[0m %s\n' "$1"; }
die()  { err "$1"; exit 1; }
ask_yes() {
  [ "$ASSUME_YES" = 1 ] && return 0
  if [ "$GUI" = 1 ]; then zenity --question --no-wrap --title "$SELF" --text "$1" 2>/dev/null
  else local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[yYsS]$ ]]; fi
}
ask_str() { # $1 prompt  $2 default  -> stdout
  if [ "$GUI" = 1 ]; then zenity --entry --title "$SELF" --text "$1" --entry-text "${2:-}" 2>/dev/null
  else local a; read -r -p "$1 [${2:-}] " a; printf '%s' "${a:-$2}"; fi
}
ask_pw() {
  if [ "$GUI" = 1 ]; then zenity --password --title "$SELF" 2>/dev/null
  else local a; read -r -s -p "Password de $DBUSER: " a; echo >&2; printf '%s' "$a"; fi
}

# ------------------------------------------------------------------ resolver modo
[ -n "$HOST" ] && [ "$MODE" = auto ] && MODE=native
if [ "$MODE" = auto ]; then
  if command -v docker >/dev/null 2>&1 \
     && docker ps --format '{{.Image}}' 2>/dev/null | grep -qiE 'mysql|mariadb|percona'; then
    MODE=docker
  else
    MODE=native; HOST="${HOST:-127.0.0.1}"
  fi
fi
[ "$MODE" = native ] && HOST="${HOST:-127.0.0.1}"

# ------------------------------------------------------------------ resolver contenedor (docker)
if [ "$MODE" = docker ]; then
  command -v docker >/dev/null 2>&1 || die "modo docker pero no encuentro 'docker'."
  if [ -z "$CONTAINER" ]; then
    mapfile -t _cands < <(docker ps --format '{{.Names}}\t{{.Image}}' \
      | awk -F'\t' 'tolower($2) ~ /mysql|mariadb|percona/ {print $1}')
    case "${#_cands[@]}" in
      0) die "no hay contenedores MySQL/MariaDB corriendo (usa --container o --mode native).";;
      1) CONTAINER="${_cands[0]}";;
      *) if [ "$GUI" = 1 ]; then
           CONTAINER=$(printf '%s\n' "${_cands[@]}" | zenity --list --title "$SELF" \
                        --column "Contenedor" --text "Elige el contenedor MySQL:" 2>/dev/null) \
             || exit 0
         elif [ "$ASSUME_YES" = 1 ]; then
           die "varios contenedores MySQL: ${_cands[*]} — especifica --container."
         else
           echo "Contenedores MySQL/MariaDB:"; i=1
           for c in "${_cands[@]}"; do printf '  %d) %s\n' "$i" "$c"; i=$((i+1)); done
           read -r -p "Numero: " i; CONTAINER="${_cands[$((i-1))]:-}"
         fi
         [ -n "$CONTAINER" ] || die "sin contenedor.";;
    esac
  fi
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" \
    || die "el contenedor '$CONTAINER' no esta corriendo."
fi

# ------------------------------------------------------------------ password
if [ -z "$PW" ] && [ "$MODE" = docker ]; then
  PW=$(docker exec "$CONTAINER" printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true)
  [ -z "$PW" ] && PW=$(docker exec "$CONTAINER" printenv MYSQL_PWD 2>/dev/null || true)
fi

# ------------------------------------------------------------------ cliente
if [ "$MODE" = docker ]; then
  MYSQLC=(docker exec -i -e "MYSQL_PWD=$PW" "$CONTAINER" mysql -u"$DBUSER")
else
  if [ -z "$CLIENT" ]; then
    CLIENT=$(command -v mysql || command -v mariadb || true)
    [ -n "$CLIENT" ] || die "no encuentro el cliente 'mysql' ni 'mariadb' (usa --mode docker)."
  fi
  MYSQLC=(env)
  [ -n "$PW" ] && MYSQLC+=("MYSQL_PWD=$PW")
  MYSQLC+=("$CLIENT" -u"$DBUSER" -h"$HOST" -P"$PORT" --protocol=TCP)
fi
sql() { "${MYSQLC[@]}" -N -B -e "$1"; }

# ------------------------------------------------------------------ test conexion
if ! sql "SELECT 1" >/dev/null 2>&1; then
  if [ "$ASSUME_YES" = 0 ]; then
    PW=$(ask_pw)
    if [ "$MODE" = docker ]; then MYSQLC=(docker exec -i -e "MYSQL_PWD=$PW" "$CONTAINER" mysql -u"$DBUSER")
    else MYSQLC=(env "MYSQL_PWD=$PW" "$CLIENT" -u"$DBUSER" -h"$HOST" -P"$PORT" --protocol=TCP); fi
  fi
  sql "SELECT 1" >/dev/null 2>&1 || die "no pude conectar a MySQL (${MODE}${CONTAINER:+ $CONTAINER}${HOST:+ $HOST:$PORT}, usuario '$DBUSER')."
fi

TARGET_DESC="$MODE${CONTAINER:+ » $CONTAINER}${HOST:+ » $HOST:$PORT}"

# ------------------------------------------------------------------ --list
if [ "$LIST_ONLY" = 1 ]; then
  step "Bases en $TARGET_DESC:"
  sql "SHOW DATABASES"
  exit 0
fi

# ------------------------------------------------------------------ elegir archivo
if [ -z "$SRC" ]; then
  if [ "$GUI" = 1 ]; then
    SRC=$(zenity --file-selection --title "Elige el dump SQL" \
            --file-filter='Dumps SQL | *.sql *.sql.gz *.gz' --file-filter='Todos | *' 2>/dev/null) \
      || exit 0
  else
    die "falta la ruta del dump. Uso: $SELF RUTA.sql [DB]"
  fi
fi
[ -f "$SRC" ] || die "no existe el archivo: $SRC"
case "$SRC" in
  *.sql.gz|*.gz) GZ=1 ;;
  *.sql) GZ=0 ;;
  *) GZ=0; ask_yes "El archivo no termina en .sql — ¿continuar igual?" || exit 0 ;;
esac

# ------------------------------------------------------------------ nombre de DB
derive() {
  local b; b=$(basename "$1"); b=${b%.gz}; b=${b%.sql}
  b=$(printf '%s' "$b" | sed -E 's/ *\([0-9]+\)$//')                 # sufijo de copia " (1)"
  printf '%s' "$b" | sed -E 's/[^A-Za-z0-9_]+/_/g; s/_+/_/g; s/^_//; s/_$//'
}
if [ -z "$DB" ]; then
  SUGG=$(derive "$SRC")
  if [ "$ASSUME_YES" = 1 ]; then DB="$SUGG"
  else DB=$(ask_str "Base de datos destino en $TARGET_DESC:" "$SUGG"); fi
  DB="${DB:-$SUGG}"
fi
[ -n "$DB" ] || die "nombre de base de datos vacio."

# ------------------------------------------------------------------ pre-chequeos
if [ "$(sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB'")" != 0 ]; then
  NTAB=$(sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB'")
  if [ "$DROP" = 1 ]; then
    ask_yes "La base '$DB' existe con $NTAB tabla(s). ¿DROP y recrear?" || exit 0
    step "DROP DATABASE \`$DB\`"; sql "DROP DATABASE \`$DB\`"
  elif [ "$NTAB" != 0 ]; then
    ask_yes "La base '$DB' ya existe con $NTAB tabla(s); el SOURCE puede sobrescribir/mezclar. ¿Continuar?" \
      || exit 0
  fi
fi

# ------------------------------------------------------------------ crear + importar
step "CREATE DATABASE IF NOT EXISTS \`$DB\` ($CHARSET / $COLLATION)"
sql "CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET $CHARSET COLLATE $COLLATION"

SIZE=$(du -h "$SRC" | cut -f1)
run_import() {
  if [ "$GZ" = 1 ]; then
    step "Importando (stream gunzip)  $SRC  [$SIZE]  →  $DB"
    gunzip -c "$SRC" | "${MYSQLC[@]}" "$DB"
  elif [ "$FORCE_STREAM" = 1 ]; then
    step "Importando (stream)  $SRC  [$SIZE]  →  $DB"
    "${MYSQLC[@]}" "$DB" < "$SRC"
  elif [ "$MODE" = docker ]; then
    local tmp="/tmp/$SELF.$$.sql"
    step "docker cp  →  $CONTAINER:$tmp  [$SIZE]"
    docker cp "$SRC" "$CONTAINER:$tmp"
    # shellcheck disable=SC2064
    trap "docker exec '$CONTAINER' rm -f '$tmp' >/dev/null 2>&1 || true" EXIT
    step "SOURCE $tmp  →  $DB"
    "${MYSQLC[@]}" "$DB" -e "source $tmp"
  else
    step "SOURCE $SRC  →  $DB"
    "${MYSQLC[@]}" "$DB" -e "source $SRC"
  fi
}

if [ "$GUI" = 1 ]; then
  ( run_import ) 2>&1 | zenity --progress --pulsate --auto-close --no-cancel \
      --title "$SELF" --text "Importando $(basename "$SRC") → $DB ($SIZE)…" 2>/dev/null
  [ "${PIPESTATUS[0]}" = 0 ] || die "fallo la importacion (revisa la terminal / logs del servidor)."
else
  run_import
fi

NTAB=$(sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB'")
info "Listo: $(basename "$SRC") importado en '$DB' ($TARGET_DESC) — $NTAB tabla(s)."
MYSQL_IMPORT_SCRIPT_EOF
chmod +x "$BIN_TARGET"

cat > "$DESKTOP_TARGET" <<EOF
[Desktop Entry]
Type=Application
Name=MySQL Import
Comment=Copia un dump .sql a MySQL/MariaDB y le hace SOURCE
Exec=$BIN_TARGET
Icon=network-server-database
Terminal=false
Categories=Development;Database;
Keywords=mysql;sql;dump;import;docker;
EOF

cat > "$DOC_TARGET" <<'MYSQL_IMPORT_README_EOF'
# mysql-import

Importa un dump SQL a **MySQL / MariaDB** creando la base si no existe y
haciéndole `SOURCE`. Funciona contra un contenedor **Docker** (`docker exec`) o
contra un servidor **nativo** (`mysql`/`mariadb` local por TCP). Tiene interfaz
gráfica (zenity) y modo línea de comandos / no interactivo.

- **Script:** `~/.local/bin/mysql-import` (en el `PATH`)
- **Lanzador de escritorio:** `~/.local/share/applications/mysql-import.desktop`
  → aparece como **“MySQL Import”** en el menú de aplicaciones.
- **Esta doc:** `~/.local/share/doc/mysql-import/README.md` — también con `mysql-import --help`.

---

## Uso rápido

```bash
mysql-import                       # sin args → selector gráfico + preguntas
mysql-import dump.sql              # deriva el nombre de BD del archivo
mysql-import dump.sql mi_base      # nombre de BD explícito
mysql-import --drop backup.sql.gz clinicavalle_test
mysql-import --list                # lista las bases del servidor y sale
```

Si lo llamás **sin ruta** y hay entorno gráfico, abre un diálogo para elegir el
archivo y otro para confirmar/editar el nombre de la base. Si le pasás la ruta
como argumento, trabaja en la terminal.

---

## Qué hace, paso a paso

1. **Resuelve el modo** (`auto` por defecto):
   - `native` si diste `--host` / `MYSQL_IMPORT_HOST`;
   - si no, `docker` cuando hay un contenedor con imagen `mysql*` / `mariadb*` / `percona*` corriendo;
   - si no, `native` contra `127.0.0.1:3306`.
2. **Elige el contenedor** (modo docker): el que indiques con `--container`, o el
   único candidato, o te lo pregunta si hay varios.
3. **Obtiene el password**: `--password`, o `MYSQL_IMPORT_PASSWORD`, o lo lee del
   contenedor (`MYSQL_ROOT_PASSWORD` / `MYSQL_PWD`), o te lo pide si la conexión falla.
4. **Deriva el nombre de la BD** desde el nombre del archivo: quita `.sql` / `.sql.gz`,
   el sufijo de copia ` (1)` y cambia lo no alfanumérico por `_`.
   Ej.: `clinicavalle_test2708 (1).sql` → `clinicavalle_test2708`.
5. **Avisa** si la base ya existe con tablas (el `SOURCE` puede mezclar/sobrescribir).
   Con `--drop` la borra y recrea (pide confirmación).
6. **Crea la base**: `CREATE DATABASE IF NOT EXISTS ... CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
   (configurable con `--charset` / `--collation`).
7. **Importa**:
   - `.sql` en modo **docker** → `docker cp` a `/tmp` del contenedor + `SOURCE` (y borra el temporal al terminar).
   - `.sql` en modo **native** → `SOURCE` directo del archivo local.
   - `.sql.gz` / `.gz` → `gunzip -c … | mysql <db>` (stream).
   - `--stream` → fuerza tubería en vez de `cp` + `SOURCE`.
8. **Verifica**: cuenta las tablas de la base y lo informa.

---

## Opciones

| Opción | Efecto |
|---|---|
| `--drop` | `DROP DATABASE` antes de importar (con confirmación). |
| `--stream` | Importa por tubería en vez de copiar + `SOURCE`. |
| `--list` | Muestra `SHOW DATABASES` y termina. |
| `-y`, `--yes` | No pregunta nada (no interactivo; nunca abre zenity). |
| `--no-gui` | Nunca usa zenity, siempre terminal. |
| `--mode MODE` | `auto` \| `docker` \| `native`. |
| `--container NOMBRE` | Contenedor Docker de MySQL/MariaDB. |
| `--host HOST` | Host (implica `--mode native`). |
| `--port PUERTO` | Puerto en modo native (def. `3306`). |
| `-u`, `--user USUARIO` | Usuario MySQL (def. `root`). |
| `-p`, `--password PASS` | Password (si no, se lee del contenedor o se pregunta). |
| `--charset NOMBRE` | Charset al crear la BD (def. `utf8mb4`). |
| `--collation NOMBRE` | Collation al crear la BD (def. `utf8mb4_unicode_ci`). |
| `-h`, `--help` / `-V`, `--version` | Ayuda / versión. |

Argumentos posicionales: `RUTA` del dump y, opcional, `NOMBRE_DB`.

---

## Configuración persistente

Se cargan, si existen, en este orden (el último pisa al anterior):

```
/etc/mysql-import.env
${XDG_CONFIG_HOME:-~/.config}/mysql-import.env
./.mysql-import.env          # por proyecto
```

Formato `KEY=value`. Variables reconocidas:

```sh
MYSQL_IMPORT_MODE=docker            # auto | docker | native
MYSQL_IMPORT_CONTAINER=mysql8
MYSQL_IMPORT_HOST=127.0.0.1
MYSQL_IMPORT_PORT=3306
MYSQL_IMPORT_USER=root
MYSQL_IMPORT_PASSWORD=secreto
MYSQL_IMPORT_CHARSET=utf8mb4
MYSQL_IMPORT_COLLATION=utf8mb4_unicode_ci
MYSQL_IMPORT_CLIENT=mariadb         # binario cliente en modo native
```

Las opciones de línea de comandos siempre ganan sobre la config y el entorno.

### Ejemplo: setup actual del equipo

`~/.config/mysql-import.env`:

```sh
MYSQL_IMPORT_MODE=docker
MYSQL_IMPORT_CONTAINER=mysql8
```

El password se toma solo del env del contenedor (`MYSQL_ROOT_PASSWORD`), así que
no hace falta ponerlo en el archivo.

---

## Ejemplos

```bash
# Contenedor Docker (autodetección)
mysql-import ~/Descargas/clinicavalle_test2708.sql

# Forzar recreado de la base
mysql-import --drop ~/Descargas/backup.sql.gz clinicavalle_test

# Servidor remoto nativo, otro usuario, pide password
mysql-import --mode native --host db.interno.lan -u deploy dump.sql tienda

# CI / script: sin preguntas, nombre explícito
mysql-import -y --drop dump.sql app_test

# Ver qué bases hay
mysql-import --list
mysql-import --mode native --host db.interno.lan -u ro --list
```

---

## Requisitos

- `bash`, `docker` (modo docker) o cliente `mysql`/`mariadb` (modo native).
- `gzip` para dumps `.sql.gz`.
- `zenity` **opcional**, solo para la interfaz gráfica.

## Notas y límites

- El dump se importa tal cual: si no trae `CREATE DATABASE` / `USE` (lo normal en
  `mysqldump` sin `--databases`), el script crea la base y hace el `SOURCE` dentro
  de ella. Si el dump **sí** trae `USE`, ese `USE` manda.
- En modo docker el archivo se copia a `/tmp` **dentro** del contenedor; se borra
  al terminar (incluso si falla).
- El password se pasa como variable de entorno `MYSQL_PWD` al cliente, no en la
  línea de comandos (evita el warning y que se vea en `ps`).
- No hace backup previo de la base destino. Usá `--drop` a conciencia.

## Desinstalar

```bash
rm ~/.local/bin/mysql-import
rm ~/.local/share/applications/mysql-import.desktop
rm -r ~/.local/share/doc/mysql-import
```
MYSQL_IMPORT_README_EOF

if [ "$DO_CONFIG" = 1 ] && [ ! -f "$CFG_FILE" ]; then
  mkdir -p "$(dirname "$CFG_FILE")"
  cat > "$CFG_FILE" <<'CFG_EOF'
# mysql-import — configuración por defecto (KEY=value).
# Descomentá lo que uses; las opciones de línea de comandos siempre ganan.
#
#MYSQL_IMPORT_MODE=auto            # auto | docker | native
#MYSQL_IMPORT_CONTAINER=mysql8     # contenedor Docker de MySQL/MariaDB
#MYSQL_IMPORT_HOST=127.0.0.1       # (implica modo native)
#MYSQL_IMPORT_PORT=3306
#MYSQL_IMPORT_USER=root
#MYSQL_IMPORT_PASSWORD=
#MYSQL_IMPORT_CHARSET=utf8mb4
#MYSQL_IMPORT_COLLATION=utf8mb4_unicode_ci
#MYSQL_IMPORT_CLIENT=mariadb       # binario cliente en modo native
CFG_EOF
  echo "Plantilla de config creada: $CFG_FILE"
else
  echo "Config: $CFG_FILE (se respeta lo existente / --no-config)"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" 2>/dev/null || true

echo
echo "Instalado:"
echo "  $BIN_TARGET"
echo "  $DESKTOP_TARGET   (menú: «MySQL Import»)"
echo "  $DOC_TARGET"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    echo
    echo "OJO: $BIN_DIR no está en tu PATH. Agregá a tu ~/.zshrc o ~/.bashrc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
echo
echo "Probá:  mysql-import --help"
