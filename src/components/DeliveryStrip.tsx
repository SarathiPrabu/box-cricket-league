import type { ScoringDelivery, ScoringOver } from '../features/matches/liveMatchTypes';

function getDeliveryLabel(delivery: ScoringDelivery) {
  if (delivery.is_wicket) return 'W';
  if (delivery.delivery_type === 'wide') return 'Wd';
  if (delivery.delivery_type === 'no_ball') return 'NB';
  if (delivery.delivery_type === 'dead_ball') return 'Db';
  return delivery.batter_runs === 0 ? '•' : String(delivery.batter_runs);
}

function getDeliveryTone(delivery: ScoringDelivery) {
  if (delivery.is_wicket) return 'delivery-strip__item--wicket';
  if (delivery.delivery_type === 'legal' && delivery.batter_runs === 4) return 'delivery-strip__item--four';
  if (delivery.delivery_type === 'legal' && delivery.batter_runs === 6) return 'delivery-strip__item--six';
  return '';
}

export function DeliveryStrip({
  over,
  onDeliveryClick,
}: {
  over: ScoringOver;
  onDeliveryClick: (delivery: ScoringDelivery) => void;
}) {
  const overRuns = over.deliveries.reduce((total, delivery) => total + delivery.batter_runs + delivery.extra_runs, 0);

  return (
    <div className="delivery-strip">
      <div className="delivery-strip__heading">
        <span>Current over · {over.over_number}</span>
        <strong>Runs: {overRuns}</strong>
      </div>
      <div className="delivery-strip__track" aria-label={`Deliveries in over ${over.over_number}`}>
        {over.deliveries.length === 0 ? <span className="delivery-strip__empty">No deliveries yet</span> : null}
        {over.deliveries.map((delivery) => (
          <button
            aria-label={`Open delivery ${delivery.delivery_sequence}`}
            className={`delivery-strip__item ${getDeliveryTone(delivery)}`}
            key={delivery.id}
            onClick={() => onDeliveryClick(delivery)}
            type="button"
          >
            {getDeliveryLabel(delivery)}
          </button>
        ))}
      </div>
    </div>
  );
}
