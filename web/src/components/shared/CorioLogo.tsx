import { useId } from 'react';

interface CorioLogoProps {
  className?: string;
  size?: number;
}

/** Compact Corio AI mark used in chat surfaces. */
export function CorioLogo({ className, size = 24 }: CorioLogoProps) {
  const gradientId = useId();

  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient id={gradientId} x1="0%" x2="100%" y1="0%" y2="100%">
          <stop offset="0%" stopColor="#E8946A" />
          <stop offset="50%" stopColor="#D4713C" />
          <stop offset="100%" stopColor="#C0632F" />
        </linearGradient>
      </defs>
      <path
        d="M12 2L14.09 8.26L20 9.27L15.55 13.97L16.91 20L12 16.9L7.09 20L8.45 13.97L4 9.27L9.91 8.26L12 2Z"
        fill={`url(#${gradientId})`}
      />
      <circle cx="12" cy="12" fill="white" opacity="0.92" r="3" />
    </svg>
  );
}
