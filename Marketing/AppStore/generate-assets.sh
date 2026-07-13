#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
OUTPUT_DIR="$SCRIPT_DIR/iPhone-6.9/tr"
mkdir -p "$OUTPUT_DIR"

render_asset() {
  local number=$1
  local slug=$2
  local title_line_one=$3
  local title_line_two=$4
  local subtitle=$5
  local screenshot=$6
  local accent=$7
  local svg_path="$OUTPUT_DIR/${number}-${slug}.svg"
  local png_path="$OUTPUT_DIR/${number}-${slug}.png"
  local screenshot_data
  screenshot_data=$(base64 < "$SCRIPT_DIR/Sources/$screenshot" | tr -d '\n')

  {
    print -r -- '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1290" height="2796" viewBox="0 0 1290 2796">'
    print -r -- '  <defs>'
    print -r -- '    <pattern id="grid" width="54" height="54" patternUnits="userSpaceOnUse"><path d="M54 0H0V54" fill="none" stroke="#182238" stroke-opacity="0.045" stroke-width="1"/></pattern>'
    print -r -- '    <clipPath id="screen"><rect x="124" y="520" width="1042" height="2264" rx="102"/></clipPath>'
    print -r -- '    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="24" stdDeviation="34" flood-color="#182238" flood-opacity="0.22"/></filter>'
    print -r -- '  </defs>'
    print -r -- '  <rect width="1290" height="2796" fill="#F7F3EA"/>'
    print -r -- '  <rect width="1290" height="2796" fill="url(#grid)"/>'
    print -r -- "  <circle cx=\"1120\" cy=\"180\" r=\"300\" fill=\"${accent}\" opacity=\"0.11\"/>"
    print -r -- '  <g transform="translate(86 86) scale(.15)"><path fill="#182238" d="M116 52h190l90 90v278c0 27-21 48-48 48H116c-27 0-48-21-48-48V100c0-27 21-48 48-48Z"/><path fill="#F06A4D" d="M306 52v90h90L306 52Z"/><path fill="#2F9C95" d="M136 190h192c22 0 40 18 40 40v60c0 22-18 40-40 40h-92l-54 48 12-48h-58c-22 0-40-18-40-40v-60c0-22 18-40 40-40Z"/></g>'
    print -r -- '  <text x="172" y="135" font-family="-apple-system, Helvetica Neue, sans-serif" font-size="34" font-weight="700" letter-spacing="5" fill="#F06A4D">CORIO DOCS</text>'
    print -r -- "  <text x=\"86\" y=\"262\" font-family=\"-apple-system, Helvetica Neue, sans-serif\" font-size=\"76\" font-weight=\"760\" fill=\"#182238\">${title_line_one}</text>"
    print -r -- "  <text x=\"86\" y=\"344\" font-family=\"-apple-system, Helvetica Neue, sans-serif\" font-size=\"76\" font-weight=\"760\" fill=\"#182238\">${title_line_two}</text>"
    print -r -- "  <text x=\"88\" y=\"420\" font-family=\"-apple-system, Helvetica Neue, sans-serif\" font-size=\"34\" font-weight=\"450\" fill=\"#667085\">${subtitle}</text>"
    print -r -- '  <rect x="104" y="500" width="1082" height="2296" rx="124" fill="#182238" filter="url(#shadow)"/>'
    print -r -- "  <image x=\"124\" y=\"520\" width=\"1042\" height=\"2264\" preserveAspectRatio=\"xMidYMid slice\" clip-path=\"url(#screen)\" xlink:href=\"data:image/png;base64,${screenshot_data}\"/>"
    print -r -- '</svg>'
  } > "$svg_path"

  sips -s format png "$svg_path" --out "$png_path" >/dev/null
}

render_asset "01" "hero" "Belgelerle çalışmanın" "daha akıllı yolu" "Oku, çevir, vurgula ve hatırla." "entry-library.png" "#F06A4D"
render_asset "02" "library" "Kütüphanen düzenli," "her zaman yanında" "PDF'lerini tek bakışta bul." "entry-library.png" "#2F9C95"
render_asset "03" "reader" "Bir cümleyi seç." "Bağlamını kaybetme." "Temiz okuyucu, doğrudan etkileşim." "entry-reader.png" "#2F9C95"
render_asset "04" "translation" "Seç. Anında çevir." "Okumaya devam et." "Çeviri metnin hemen altında." "entry-translation.png" "#F06A4D"
render_asset "05" "annotation" "Vurgula, not al," "hatırlamayı kolaylaştır." "Tüm fikirlerin tek bir Defter'de." "entry-annotation.png" "#D99A2B"

print "Generated App Store assets in $OUTPUT_DIR"
