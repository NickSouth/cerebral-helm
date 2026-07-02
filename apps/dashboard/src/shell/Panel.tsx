import type { ReactNode } from "react";

/**
 * The shared panel primitive (constitution §6): thin-outlined, translucent, small radius,
 * no nested card stacks. Every region is one Panel with an eyebrow label and an optional
 * icon-first annotation pinned top-right (visual reference — every rail panel carries a
 * small category glyph opposite its label).
 */
export function Panel({
  label,
  children,
  className,
  labelId,
  icon
}: {
  label: string;
  children: ReactNode;
  className?: string;
  labelId?: string;
  icon?: ReactNode;
}) {
  return (
    <section className={`panel shell-panel${className ? ` ${className}` : ""}`}>
      <div className="panel__header">
        <p className="eyebrow" id={labelId}>
          {label}
        </p>
        {icon ? (
          <span className="panel__icon" aria-hidden="true">
            {icon}
          </span>
        ) : null}
      </div>
      {children}
    </section>
  );
}
