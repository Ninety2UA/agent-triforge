// The dot clusters the home page draws in SVG: the same halftone disc as the dot field, full dots at the
// centre and smaller to the edge. A core CLI is a disc of radius 2.3 cells, an optional one 1.5.
export const disc = (R: number) => {
  const pts: number[][] = [];
  const rr = Math.ceil(R);
  for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr; dx <= rr; dx++) if (dx * dx + dy * dy <= R * R + 0.01) pts.push([dx, dy]);
  return pts;
};

/** a cluster glyph in a 30 px box, for the roster list */
export const glyph = (opt: boolean) => {
  const sc = 30 / 7;
  return disc(opt ? 1.5 : 2.3).map(([dx, dy]) => {
    const d = Math.hypot(dx, dy);
    return { cx: ((3.5 + dx) * sc).toFixed(1), cy: ((3.5 + dy) * sc).toFixed(1), r: ((opt ? 0.31 - d * 0.04 : 0.45 - d * 0.055) * sc).toFixed(2) };
  });
};

/** one core cluster, drawn twice side by side for "no agent merges its own work" */
export const pair = disc(2.3).map(([dx, dy]) => ({ dx, dy, r: +(0.45 - Math.hypot(dx, dy) * 0.055).toFixed(3) }));
