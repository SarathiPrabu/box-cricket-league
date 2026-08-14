export type SeasonOption = { season_id: string; season_name: string };

type SeasonSelectorProps = {
  seasons: SeasonOption[];
  selectedSeason: SeasonOption;
  onChange: (season: SeasonOption) => void;
  id: string;
};

export function SeasonSelector({ seasons, selectedSeason, onChange, id }: SeasonSelectorProps) {
  return (
    <div className="mt-3 w-full sm:mt-0 sm:w-56">
      <label className="block text-sm font-medium text-slate-700 dark:text-slate-200" htmlFor={id}>Season</label>
      <select
        className="form-select mt-2 font-medium shadow-sm sm:w-56"
        id={id}
        onChange={(event) => {
          const nextSeason = seasons.find((season) => season.season_id === event.target.value);
          if (nextSeason) onChange(nextSeason);
        }}
        value={selectedSeason.season_id}
      >
        {seasons.map((season) => <option key={season.season_id} value={season.season_id}>{season.season_name}</option>)}
      </select>
    </div>
  );
}
