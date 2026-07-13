import { motion, useReducedMotion } from 'framer-motion';
import { ArrowUpRight, ListTree, ScanText, Sparkles } from 'lucide-react';

interface SuggestedPromptsProps {
  disabled?: boolean;
  prompts: string[];
  onSelect: (prompt: string) => void;
}

const icons = [Sparkles, ScanText, ListTree];

export function SuggestedPrompts({ disabled, prompts, onSelect }: SuggestedPromptsProps) {
  const reduceMotion = useReducedMotion();

  return (
    <div className="grid w-full gap-2" role="list" aria-label="Önerilen sorular">
      {prompts.map((prompt, index) => {
        const Icon = icons[index % icons.length];
        return (
          <motion.button
            animate={{ opacity: 1, y: 0 }}
            aria-label={prompt}
            className="group flex min-h-12 w-full items-center gap-3 rounded-2xl border border-corio-border-subtle bg-corio-surface-1 px-3.5 py-2.5 text-left text-sm text-corio-fg shadow-sm transition-colors hover:border-corio-accent/35 hover:bg-corio-accent-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 disabled:cursor-not-allowed disabled:opacity-50"
            disabled={disabled}
            initial={reduceMotion ? false : { opacity: 0, y: 8 }}
            key={prompt}
            onClick={() => onSelect(prompt)}
            role="listitem"
            transition={{ delay: reduceMotion ? 0 : index * 0.06, duration: 0.22 }}
            type="button"
          >
            <span className="flex size-8 shrink-0 items-center justify-center rounded-xl bg-corio-accent-subtle text-corio-accent">
              <Icon className="size-4" />
            </span>
            <span className="flex-1 leading-snug">{prompt}</span>
            <ArrowUpRight className="size-4 shrink-0 text-corio-fg/30 transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-corio-accent" />
          </motion.button>
        );
      })}
    </div>
  );
}
