// The dot clusters the home page draws in SVG: the same halftone disc as the dot field, full dots at the
// centre and smaller to the edge. A core CLI is a disc of radius 2.3 cells, an optional one 1.5. No
// imports: the dot field's client script (scripts/dotfield.ts) takes its radii from here too.

/** a cluster's radius in cells */
export const discRadius = (opt: boolean) => (opt ? 1.5 : 2.3);

/** a dot's radius in cells at distance d from its cluster's centre */
export const dotRadius = (opt: boolean, d: number) => (opt ? 0.31 - d * 0.04 : 0.45 - d * 0.055);

export const disc = (R: number) => {
  const pts: number[][] = [];
  const rr = Math.ceil(R);
  for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr; dx <= rr; dx++) if (dx * dx + dy * dy <= R * R + 0.01) pts.push([dx, dy]);
  return pts;
};

/** a cluster glyph in a 30 px box, for the roster list */
export const glyph = (opt: boolean) => {
  const sc = 30 / 7;
  return disc(discRadius(opt)).map(([dx, dy]) => ({
    cx: ((3.5 + dx) * sc).toFixed(1),
    cy: ((3.5 + dy) * sc).toFixed(1),
    r: (dotRadius(opt, Math.hypot(dx, dy)) * sc).toFixed(2),
  }));
};

/** one core cluster, drawn twice side by side for "no agent merges its own work" */
export const pair = disc(discRadius(false)).map(([dx, dy]) => ({ dx, dy, r: +dotRadius(false, Math.hypot(dx, dy)).toFixed(3) }));
