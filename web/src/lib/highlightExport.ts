// Highlight / annotation export — turns notebook entries into Markdown or CSV
// files for use in Readwise / Obsidian / spreadsheets.

export interface ExportNote {
  fileId: string;
  fileName: string;
  pageNumber: number;
  text: string;
  note: string;
  color: string;
  createdAt: Date;
}

const COLOR_LABELS: Record<string, string> = {
  '#fef08a': 'Sarı',
  '#bbf7d0': 'Yeşil',
  '#bae6fd': 'Mavi',
  '#bfdbfe': 'Mavi',
  '#fbcfe8': 'Pembe',
};

function colorLabel(color: string): string {
  return COLOR_LABELS[color.toLowerCase()] ?? color;
}

function formatDate(date: Date): string {
  return date.toLocaleDateString('tr-TR', { year: 'numeric', month: 'long', day: 'numeric' });
}

/** Groups notes by file, preserving the input order of files. */
function groupByFile(notes: ExportNote[]): { fileName: string; notes: ExportNote[] }[] {
  const groups = new Map<string, { fileName: string; notes: ExportNote[] }>();
  for (const note of notes) {
    const group = groups.get(note.fileId);
    if (group) group.notes.push(note);
    else groups.set(note.fileId, { fileName: note.fileName, notes: [note] });
  }
  return Array.from(groups.values());
}

export function notesToMarkdown(notes: ExportNote[]): string {
  const lines: string[] = ['# Notlarım', '', `_${notes.length} işaretleme · ${formatDate(new Date())}_`, ''];

  for (const { fileName, notes: fileNotes } of groupByFile(notes)) {
    lines.push(`## ${fileName}`, '');
    // Page order within a document reads more naturally than save order.
    const sorted = [...fileNotes].sort((a, b) => a.pageNumber - b.pageNumber);
    for (const note of sorted) {
      if (note.text) lines.push(`> ${note.text.replace(/\n+/g, ' ')}`);
      const meta = `Sayfa ${note.pageNumber} · ${colorLabel(note.color)}`;
      lines.push('', `*${meta}*`);
      if (note.note) lines.push('', note.note);
      lines.push('', '---', '');
    }
  }

  return lines.join('\n');
}

function csvCell(value: string): string {
  // Quote and escape per RFC 4180.
  return `"${value.replace(/"/g, '""')}"`;
}

export function notesToCsv(notes: ExportNote[]): string {
  const header = ['Dosya', 'Sayfa', 'Renk', 'İşaretlenen Metin', 'Not', 'Tarih'];
  const rows = notes.map(note =>
    [
      note.fileName,
      String(note.pageNumber),
      colorLabel(note.color),
      note.text.replace(/\n+/g, ' '),
      note.note.replace(/\n+/g, ' '),
      note.createdAt.toISOString(),
    ]
      .map(csvCell)
      .join(',')
  );
  // BOM so Excel reads UTF-8 (Turkish characters) correctly.
  return '﻿' + [header.map(csvCell).join(','), ...rows].join('\r\n');
}

export function downloadTextFile(filename: string, content: string, mimeType: string): void {
  const blob = new Blob([content], { type: `${mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
