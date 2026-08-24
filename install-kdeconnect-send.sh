#!/usr/bin/env bash

USER_HOME="$HOME"

for dep in kdeconnect-cli zenity; do
    command -v "$dep" >/dev/null 2>&1 || {
        echo "Falta '$dep'. Instalalo (ej: apt install kdeconnect zenity) y volvé a correr este script." >&2
        exit 1
    }
done

SCRIPT_TARGET="$USER_HOME/.local/bin/kdeconnect-send.sh"
CONFIG_DIR="$USER_HOME/.config/cosmic/com.system76.CosmicFiles/v1"
CONFIG_TARGET="$CONFIG_DIR/context_actions"

mkdir -p "$USER_HOME/.local/bin"
mkdir -p "$CONFIG_DIR"

cat > "$SCRIPT_TARGET" <<'EOF'
#!/usr/bin/env bash
# Envía los archivos seleccionados en Cosmic Files al celular vía KDE Connect.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    zenity --error --text="No se seleccionó ningún archivo." 2>/dev/null
    exit 1
fi

mapfile -t devices < <(kdeconnect-cli -a --id-only)

if [ "${#devices[@]}" -eq 0 ]; then
    zenity --error --text="No hay ningún dispositivo de KDE Connect disponible (vinculado y accesible)." 2>/dev/null
    exit 1
fi

mapfile -t names < <(kdeconnect-cli -a --id-name-only)
rows=()
for line in "${names[@]}"; do
    id="${line%% *}"
    name="${line#* }"
    rows+=("$id" "$name")
done

device=$(zenity --list \
    --title="Enviar a dispositivo" \
    --text="Elegí el celular" \
    --column="ID" --column="Dispositivo" \
    --hide-column=1 --print-column=1 \
    "${rows[@]}" 2>/dev/null) || exit 1

fail=0
for f in "$@"; do
    kdeconnect-cli -d "$device" --share "$f" || fail=1
done

if [ "$fail" -eq 0 ]; then
    zenity --notification --text="Archivo(s) enviado(s) por KDE Connect" 2>/dev/null || true
else
    zenity --error --text="Hubo un error enviando uno o más archivos." 2>/dev/null
fi
EOF

chmod +x "$SCRIPT_TARGET"

ACTION_NAME="Enviar(KDE)"
NEW_ENTRY="    (
        name: \"$ACTION_NAME\",
        confirm: false,
        selection: Files,
        steps: [
            \"$SCRIPT_TARGET %F\",
        ],
    ),"

if [ -s "$CONFIG_TARGET" ] && grep -q "name: \"$ACTION_NAME\"" "$CONFIG_TARGET"; then
    echo "La acción '$ACTION_NAME' ya estaba en $CONFIG_TARGET, no se tocó."
elif [ -s "$CONFIG_TARGET" ]; then
    # Ya hay otras acciones definidas: se preserva el archivo y solo se inserta la nuestra.
    cp "$CONFIG_TARGET" "$CONFIG_TARGET.bak.$(date +%s)"
    awk -v entry="$NEW_ENTRY" '
        /^\]/ && !done { print entry; done=1 }
        { print }
    ' "$CONFIG_TARGET" > "$CONFIG_TARGET.tmp" && mv "$CONFIG_TARGET.tmp" "$CONFIG_TARGET"
    echo "Acción agregada a un context_actions existente (backup guardado junto al archivo)."
else
    cat > "$CONFIG_TARGET" <<EOF
[
$NEW_ENTRY
]
EOF
    echo "context_actions creado con la acción '$ACTION_NAME'."
fi

echo "kdeconnect-send instalado: $SCRIPT_TARGET"
echo "Entrada de menú de Cosmic Files: $CONFIG_TARGET"
