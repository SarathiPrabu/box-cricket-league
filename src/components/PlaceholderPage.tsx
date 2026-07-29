type PlaceholderPageProps = {
  title: string;
  description: string;
};

export function PlaceholderPage({ title, description }: PlaceholderPageProps) {
  return (
    <section className="rounded-lg border border-slate-800 bg-slate-900 p-6">
      <p className="mb-2 text-sm font-medium uppercase tracking-wide text-emerald-400">
        Placeholder
      </p>
      <h2 className="text-2xl font-semibold text-white">{title}</h2>
      <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-300">
        {description}
      </p>
    </section>
  );
}
