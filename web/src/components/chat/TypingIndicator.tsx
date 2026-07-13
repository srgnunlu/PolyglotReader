import { motion, useReducedMotion } from 'framer-motion';

export function TypingIndicator() {
  const reduceMotion = useReducedMotion();

  return (
    <div
      aria-label="Corio yanıt hazırlıyor"
      className="flex min-h-7 items-center gap-1 py-1 text-corio-fg/50"
      role="status"
    >
      {[0, 1, 2].map(index => (
        <motion.span
          animate={reduceMotion ? undefined : { opacity: [0.25, 1, 0.25], y: [0, -3, 0] }}
          className="size-1.5 rounded-full bg-corio-accent"
          key={index}
          transition={{
            delay: index * 0.14,
            duration: 0.9,
            ease: 'easeInOut',
            repeat: Infinity,
          }}
        />
      ))}
      <span className="sr-only">Yanıt hazırlanıyor</span>
    </div>
  );
}
