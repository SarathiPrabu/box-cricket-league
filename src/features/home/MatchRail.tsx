import { useCallback, useEffect, useRef, useState } from 'react';
import { HomeMatchCard, type HomeMatchData } from '../../components/HomeMatchCard';

type MatchRailProps = {
  matches: HomeMatchData[];
};

type ScrollState = {
  hasOverflow: boolean;
  canScrollLeft: boolean;
  canScrollRight: boolean;
};

function ArrowIcon({ direction }: { direction: 'left' | 'right' }) {
  return (
    <svg aria-hidden="true" fill="none" height="20" viewBox="0 0 24 24" width="20">
      <path d={direction === 'left' ? 'm15 18-6-6 6-6' : 'm9 18 6-6-6-6'} stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" />
    </svg>
  );
}

export function MatchRail({ matches }: MatchRailProps) {
  const viewportRef = useRef<HTMLDivElement>(null);
  const [scrollState, setScrollState] = useState<ScrollState>({
    hasOverflow: false,
    canScrollLeft: false,
    canScrollRight: false,
  });

  const updateScrollState = useCallback(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;

    setScrollState({
      hasOverflow: viewport.scrollWidth > viewport.clientWidth + 1,
      canScrollLeft: viewport.scrollLeft > 1,
      canScrollRight: viewport.scrollLeft + viewport.clientWidth < viewport.scrollWidth - 1,
    });
  }, []);

  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return undefined;

    updateScrollState();
    const resizeObserver = new ResizeObserver(updateScrollState);
    resizeObserver.observe(viewport);
    if (viewport.firstElementChild) resizeObserver.observe(viewport.firstElementChild);

    return () => resizeObserver.disconnect();
  }, [matches.length, updateScrollState]);

  function scrollRail(direction: 'left' | 'right') {
    const viewport = viewportRef.current;
    const canScroll = direction === 'left' ? scrollState.canScrollLeft : scrollState.canScrollRight;
    if (!viewport || !canScroll) return;

    viewport.scrollBy({
      behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
      left: direction === 'left' ? -viewport.clientWidth * 0.85 : viewport.clientWidth * 0.85,
    });
  }

  return (
    <section aria-label="Fixtures and recent results" className="home-match-rail mt-8">
      <div className="home-match-rail__track">
        {scrollState.hasOverflow ? (
          <div aria-label="Match carousel controls" className="home-match-rail__controls" role="group">
            <button
              aria-controls="home-match-rail-scroll"
              aria-disabled={!scrollState.canScrollLeft}
              aria-label="Previous matches"
              className="home-match-rail__button"
              onClick={() => scrollRail('left')}
              type="button"
            >
              <ArrowIcon direction="left" />
            </button>
            <button
              aria-controls="home-match-rail-scroll"
              aria-disabled={!scrollState.canScrollRight}
              aria-label="Next matches"
              className="home-match-rail__button"
              onClick={() => scrollRail('right')}
              type="button"
            >
              <ArrowIcon direction="right" />
            </button>
          </div>
        ) : null}

        <div
          aria-label="Scrollable match cards"
          className="home-match-rail__viewport"
          id="home-match-rail-scroll"
          onScroll={updateScrollState}
          ref={viewportRef}
          role="region"
          tabIndex={scrollState.hasOverflow ? 0 : -1}
        >
          <ul className="home-match-rail__list">
            {matches.map((match) => {
              return (
                <li className="home-match-rail__item" key={match.match_id}>
                  <HomeMatchCard match={match} />
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </section>
  );
}
