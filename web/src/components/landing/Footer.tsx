// Footer — minimal, warm, editorial
import { BookOpen } from 'lucide-react';
import Link from 'next/link';

const legalLinks = [
  { label: 'Gizlilik Politikası', href: '/legal/privacy-policy' },
  { label: 'Kullanım Koşulları', href: '/legal/terms-of-service' },
  { label: 'EULA', href: '/legal/eula' },
  { label: 'Veri Silme', href: '/legal/data-deletion' },
];

export function Footer() {
  return (
    <footer id="footer" className="border-t border-[#2A2520]/[0.06] bg-[#FDFAF6]">
      <div className="mx-auto max-w-5xl px-6 py-14">
        <div className="grid gap-10 sm:grid-cols-3">
          {/* Brand */}
          <div>
            <div className="mb-4 flex items-center gap-2.5">
              <div className="flex size-8 items-center justify-center rounded-[10px] bg-gradient-to-br from-[#D4713C] to-[#C0632F] shadow-sm">
                <BookOpen className="size-4 text-white" strokeWidth={2} />
              </div>
              <span className="text-[15px] font-bold tracking-[-0.01em] text-[#2A2520]">Corio Docs</span>
            </div>
            <p className="max-w-[240px] text-[13px] leading-[1.7] text-[#2A2520]/40">
              AI destekli akıllı PDF okuyucu ve belge yönetimi uygulaması.
            </p>
          </div>

          {/* Legal */}
          <div>
            <h4 className="mb-4 text-[11px] font-semibold uppercase tracking-[0.1em] text-[#2A2520]/30">Yasal</h4>
            <ul className="space-y-2.5">
              {legalLinks.map((link) => (
                <li key={link.label}>
                  <Link
                    href={link.href}
                    className="text-[13px] text-[#2A2520]/50 transition-colors duration-150 hover:text-[#D4713C]"
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          {/* Contact */}
          <div>
            <h4 className="mb-4 text-[11px] font-semibold uppercase tracking-[0.1em] text-[#2A2520]/30">İletişim</h4>
            <ul className="space-y-2.5">
              <li>
                <a href="mailto:docs@corioscan.com" className="text-[13px] text-[#2A2520]/50 transition-colors duration-150 hover:text-[#D4713C]">
                  docs@corioscan.com
                </a>
              </li>
              <li>
                <a href="https://docs.corioscan.com" target="_blank" rel="noopener noreferrer" className="text-[13px] text-[#2A2520]/50 transition-colors duration-150 hover:text-[#D4713C]">
                  docs.corioscan.com
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom */}
        <div className="mt-12 flex flex-col items-center justify-between gap-3 border-t border-[#2A2520]/[0.06] pt-8 sm:flex-row">
          <p className="text-[12px] text-[#2A2520]/30">© 2026 Corio Docs. Tüm hakları saklıdır.</p>
        </div>
      </div>
    </footer>
  );
}
