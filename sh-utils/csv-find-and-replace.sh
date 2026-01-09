
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Usage and CLI parsing
# -----------------------------
usage() {
  cat <<'USAGE'
Usage:
  script.sh TMP_FILE TARGET_FILE

Description:
  Apply CSV-driven replacements to TARGET_FILE using sed, with a backup created.
  The CSV (TMP_FILE) should contain rows of "old,new" pairs (no headers).
  - Empty 'new' means deletion (replace with empty string).
  - Lines that are fully blank are skipped.
  - Lines with an empty 'old' (after trimming) are skipped to avoid invalid sed commands.

Options:
  -h, --help     Show this help message and exit.

Examples:
  script.sh tmp newprod
  script.sh replacements.csv app.conf

Notes:
  The script creates a backup: TARGET_FILE.bak.YYYYMMDDHHMMSS
  Replacements are literal-safe with distinct escaping for sed pattern and replacement.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  echo "Error: expected 2 arguments (TMP_FILE and TARGET_FILE)." >&2
  echo "Run with -h or --help for usage." >&2
  exit 1
fi

TMP_FILE=$1
TARGET_FILE=$2
BACKUP_FILE="${TARGET_FILE}.bak.$(date +%Y%m%d%H%M%S)"

# -----------------------------
# Validation
# -----------------------------
if [[ ! -f "$TMP_FILE" ]]; then
  echo "Error: CSV file '$TMP_FILE' not found." >&2
  exit 1
fi

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Error: target file '$TARGET_FILE' not found." >&2
  exit 1
fi

# -----------------------------
# Backup
# -----------------------------
cp -- "$TARGET_FILE" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# -----------------------------
# Escaping helpers
# -----------------------------
# Escape for sed regex (pattern/LHS)
escape_sed_re() {
  # Escape characters that are special in basic sed regex: [] \ . ^ $ *
  # Include both '[' and ']' safely by listing them first in the class.
  printf '%s' "$1" | sed -e 's/[][\\.^$*]/\\&/g' -e 's/|/\\|/g'
}

# Escape for sed replacement (RHS)
escape_sed_repl() {
  # Escape & (whole match) and backslash, and the delimiter '|'
  printf '%s' "$1" | sed -e 's/[&\\]/\\&/g' -e 's/|/\\|/g'
}

# -----------------------------
# Build sed script from CSV
# -----------------------------
SED_SCRIPT=$(mktemp)
OUT_FILE=$(mktemp)
trap 'rm -f "$SED_SCRIPT" "$OUT_FILE"' EXIT

# Read CSV line by line: "old,new"
# No headers or comments; skip only blank lines
while IFS=, read -r old new || [[ -n "$old" || -n "$new" ]]; do
  # Skip completely empty lines
  if [[ -z "${old}${new}" ]]; then
    continue
  fi

  # Trim whitespace around fields
  old="${old#"${old%%[![:space:]]*}"}"
  old="${old%"${old##*[![:space:]]}"}"
  new="${new#"${new%%[![:space:]]*}"}"
  new="${new%"${new##*[![:space:]]}"}"

  # If 'old' is empty after trimming, skip (avoid generating s||...|g)
  if [[ -z "$old" ]]; then
    continue
  fi

  # Allow empty new (deletion)
  : "${new:=}"

  esc_old=$(escape_sed_re "$old")
  esc_new=$(escape_sed_repl "$new")

  printf 's|%s|%s|g\n' "$esc_old" "$esc_new" >> "$SED_SCRIPT"
done < "$TMP_FILE"

if [[ ! -s "$SED_SCRIPT" ]]; then
  echo "No replacement rules found in '$TMP_FILE'. Nothing to do."
  exit 0
fi

# -----------------------------
# Apply replacements
# -----------------------------
if sed -f "$SED_SCRIPT" -- "$TARGET_FILE" > "$OUT_FILE"; then
  mv -- "$OUT_FILE" "$TARGET_FILE"
  echo "Replacements applied to '$TARGET_FILE'."
  echo "Backup is at: $BACKUP_FILE"
else
  echo "Error: sed failed. Original file preserved at '$BACKUP_FILE'." >&2
  exit 1
fi
``
