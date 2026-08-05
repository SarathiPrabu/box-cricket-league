type PlaceholderPageProps = {
  title: string;
  description: string;
};

export function PlaceholderPage({ title, description }: PlaceholderPageProps) {
  return (
    <section className="surface-card p-6">
      <p className="mb-2 text-sm font-medium uppercase tracking-wide text-brand-600 dark:text-brand-400">
        Placeholder
      </p>
      <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">
        {title}
      </h2>
      <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-600 dark:text-slate-300">
        {description}
      </p>
    </section>
  );
}
