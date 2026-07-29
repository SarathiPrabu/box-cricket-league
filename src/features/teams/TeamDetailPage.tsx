import { useParams } from 'react-router-dom';
import { PlaceholderPage } from '../../components/PlaceholderPage';

export function TeamDetailPage() {
  const { slug } = useParams();

  return (
    <PlaceholderPage
      title="Team detail"
      description={`This route will show team details and season roster for "${slug ?? 'team'}".`}
    />
  );
}
