// Copies PDF.js runtime assets from node_modules into public/ so the reader
// has zero CDN dependency. Runs automatically via predev/prebuild.
import { cpSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "node_modules", "pdfjs-dist");
const dest = join(root, "public", "pdfjs");

mkdirSync(dest, { recursive: true });

cpSync(join(src, "build", "pdf.worker.min.mjs"), join(dest, "pdf.worker.min.mjs"));
cpSync(join(src, "cmaps"), join(dest, "cmaps"), { recursive: true });
cpSync(join(src, "standard_fonts"), join(dest, "standard_fonts"), { recursive: true });

console.log("[copy-pdf-assets] PDF.js worker, cmaps and standard fonts copied to public/pdfjs");
