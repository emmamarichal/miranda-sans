#!/usr/bin/env bash
set -euo pipefail

TTF_DIR="ofl/mirandasans/static"
REPORT_JSON="report.json"

cleanup_backups () {
  local phase="$1"
  local found=0

  echo
  echo "== Backup check ($phase) =="

  shopt -s nullglob
  local backups=("$TTF_DIR"/*-backup*.ttf)
  shopt -u nullglob

  if [ ${#backups[@]} -eq 0 ]; then
    echo "Inga backup-filer hittades."
    return 0
  fi

  echo "Hittade backup-filer:"
  for b in "${backups[@]}"; do
    echo " - $b"
  done

  echo "Tar bort backup-filer..."
  for b in "${backups[@]}"; do
    rm "$b"
    found=1
  done

  # Verify they're gone
  shopt -s nullglob
  backups=("$TTF_DIR"/*-backup*.ttf)
  shopt -u nullglob

  if [ ${#backups[@]} -ne 0 ]; then
    echo "ERROR: Backup-filer finns kvar efter rm. Något är fel."
    exit 1
  fi

  if [ "$found" -eq 1 ]; then
    echo "Backup-filer borttagna."
  fi
}

# Preconditions
if [ ! -d "$TTF_DIR" ]; then
  echo "ERROR: Hittar inte mappen: $TTF_DIR"
  exit 1
fi

shopt -s nullglob
TTFS=("$TTF_DIR"/*.ttf)
shopt -u nullglob

if [ ${#TTFS[@]} -eq 0 ]; then
  echo "ERROR: Inga .ttf hittades i $TTF_DIR"
  exit 1
fi

cleanup_backups "start (innan allt)"

echo
echo "== Steg 1: gftools fix-fstype (in place) =="
for f in "${TTFS[@]}"; do
  echo "Fixing fstype: $f"
  gftools fix-fstype "$f" "$f"
done
cleanup_backups "efter fix-fstype"

echo
echo "== Steg 2: gftools fix-nonhinting (in place) =="
for f in "${TTFS[@]}"; do
  echo "Fixing nonhinting: $f"
  gftools fix-nonhinting "$f" "$f"
done
cleanup_backups "efter fix-nonhinting"

echo
echo "== Steg 3: Remove DSIG (in place, via ttx) =="
for f in "${TTFS[@]}"; do
  echo "Removing DSIG via ttx: $f"

  # Dumpa fonten till en temporär TTX (inkl DSIG om den finns)
  tmp_ttx="$(mktemp -t dsig.XXXXXX).ttx"

  # Om DSIG finns, exportera den. Om inte, exportera ändå, rebuild blir oförändrad.
  ttx -q -o "$tmp_ttx" "$f"

  # Ta bort alla DSIG-tabeller ur TTX
  # (detta tar bort <DSIG> ... </DSIG> blocken)
  perl -0777 -i -pe 's|<DSIG>.*?</DSIG>\s*||gs' "$tmp_ttx"

  # Bygg tillbaka TTF från ttx
  ttx -q -o "$f" "$tmp_ttx"

  rm -f "$tmp_ttx"
done
cleanup_backups "efter DSIG removal (ttx)"

echo
echo "== Steg 4: Verifiera att DSIG är borta =="
DSIG_FOUND=0
for f in "${TTFS[@]}"; do
  if ttx -l "$f" | grep -q '^DSIG$'; then
    echo "DSIG finns kvar i: $f"
    DSIG_FOUND=1
  else
    echo "DSIG ok: $f"
  fi
done

if [ "$DSIG_FOUND" -ne 0 ]; then
  echo "ERROR: DSIG finns kvar i minst en font."
  exit 1
fi

# Extra: backup check direkt innan FontBakery
cleanup_backups "precis innan FontBakery"

echo
echo "== Steg 5: FontBakery (skip-network) och skriv $REPORT_JSON =="
rm -f "$REPORT_JSON"
fontbakery check-googlefonts --skip-network --json "$REPORT_JSON" "${TTFS[@]}"

echo
echo "== Steg 6: Faila om FAIL finns =="
if grep -q '"result": "FAIL"' "$REPORT_JSON"; then
  echo "FAIL hittades i $REPORT_JSON"
  fontbakery check-googlefonts --skip-network --loglevel FAIL "${TTFS[@]}" || true
  exit 1
else
  echo "Inga FAIL. Rapport sparad som $REPORT_JSON"
fi

echo
echo "DONE"

