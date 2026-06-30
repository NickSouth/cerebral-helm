import type { ReactNode } from "react";

/**
 * The shared panel primitive (constitution §6): thin-outlined, translucent, small radius,
 * no nested card stacks. Every region is one Panel with an eyebrow label.
 */
export function Panel({
  label,
  children,
  className,
  labelId
}: {
  label: string;
  children: ReactNode;
  className?: string;
  labelId?: string;
}) {
  return (
    <section className={`panel shell-panel${className ? ` ${className}` : ""}`}>
      <p className="eyebrow" id={labelId}>
        {label}
      </p>
      {children}
    </section>
  );
}
