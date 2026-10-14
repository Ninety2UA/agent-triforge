// How a command line may wrap: at spaces, or just after a slash, and nowhere else, so a narrow
// screen never breaks inside a token (agent-triforge@agent-triforge stays whole). Each line becomes
// tokens; each token becomes pieces that end at a slash; the renderers keep pieces unbreakable
// (white-space: nowrap) and put a <wbr> between them.
export function tokens(line: string): string[][] {
  return line.split(' ').map((tok) => tok.split(/(?<=\/)/));
}
