import { useParams } from 'react-router-dom';
import { PlaceholderPage } from '../../components/PlaceholderPage';

export function PlayerDetailPage() {
  const { slug } = useParams();

  return (
    <PlaceholderPage
      title="Player profile"
      description={`This route will show player profile details for "${slug ?? 'player'}".`}
    />
  );
}
