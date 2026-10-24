const DAY_MS = 24 * 60 * 60 * 1000;

export function isStale(lastVerified: string, now = new Date()): boolean {
  const date = new Date(lastVerified.slice(0, 10) + "T00:00:00Z");
  if (Number.isNaN(date.getTime())) return true;
  return now.getTime() - date.getTime() > 30 * DAY_MS;
}

export function anyStale(dates: string[], now = new Date()): boolean {
  return dates.some((d) => isStale(d, now));
}
