// Menu icons are tiny bitmaps drawn the way the handset's own would be: a 14 x 14 grid of
// palette letters. '.' is empty, '#' the outline, and each icon names its own fill colours.

interface Bitmap {
  rows: string[];
  colors: Record<string, string>;
}

const OUTLINE = '#101828';

const ICONS: Record<string, Bitmap> = {
  messages: {
    colors: { o: '#ffe9a8', w: '#fffdf3' },
    rows: [
      '..............',
      '..............',
      '##############',
      '#ow........wo#',
      '#o#w......w#o#',
      '#oo#w....w#oo#',
      '#ooo#wwww#ooo#',
      '#oooo####oooo#',
      '#oooooooooooo#',
      '#oooooooooooo#',
      '#oooooooooooo#',
      '##############',
      '..............',
      '..............',
    ],
  },
  contacts: {
    colors: { o: '#ffcf9a', b: '#3d7be0', w: '#ffffff' },
    rows: [
      '..###########.',
      '..#wwwwwwwww#.',
      '###www###www#.',
      '#.#ww#ooo#ww#.',
      '###ww#ooo#ww#.',
      '..#www###www#.',
      '###ww#bbb#ww#.',
      '#.#w#bbbbb#w#.',
      '###w#bbbbb#w#.',
      '..#wwwwwwwww#.',
      '###wwwwwwwww#.',
      '#.#wwwwwwwww#.',
      '###wwwwwwwww#.',
      '..###########.',
    ],
  },
  hustle: {
    colors: { g: '#57c84d', l: '#b8f0a0' },
    rows: [
      '..............',
      '.############.',
      '.#gggggggggg#.',
      '.#gl..##..lg#.',
      '.#g..####..g#.',
      '.#g.##.....g#.',
      '.#g..###...g#.',
      '.#g....##..g#.',
      '.#g.####...g#.',
      '.#gl..##..lg#.',
      '.#gggggggggg#.',
      '.############.',
      '..............',
      '..............',
    ],
  },
  turf: {
    colors: { r: '#e2433a', s: '#c9d3e0', g: '#8fd16a' },
    rows: [
      '.....####.....',
      '....#rrrr#....',
      '...#rr##rr#...',
      '...#r#..#r#...',
      '...#rr##rr#...',
      '....#rrrr#....',
      '.....#rr#.....',
      '......##......',
      '.####.##.####.',
      '#gggg####gggg#',
      '#ggggggggggss#',
      '#ssggggggsssg#',
      '##############',
      '..............',
    ],
  },
  status: {
    colors: { y: '#ffd24a', o: '#ff9d1f' },
    rows: [
      '......##......',
      '.....#yy#.....',
      '.....#yy#.....',
      '....#yyyy#....',
      '#####yyyy#####',
      '#yyyyyyyyyyyy#',
      '.#yyyyyyyyyy#.',
      '..#yyyyyyyy#..',
      '...#yyyyyy#...',
      '...#yyyyyy#...',
      '..#yyy##yyy#..',
      '..#yy#..#yy#..',
      '.#y##....##y#.',
      '.##........##.',
    ],
  },
  games: {
    colors: { p: '#b18cff', w: '#ffffff', r: '#ff5d5d' },
    rows: [
      '..............',
      '..............',
      '..##########..',
      '.#pppppppppp#.',
      '#ppp#ppppprpp#',
      '#pp###ppprppp#',
      '#ppp#pppppprp#',
      '#pppppppppppp#',
      '#ppp######ppp#',
      '#pp#......#pp#',
      '.##........##.',
      '..............',
      '..............',
      '..............',
    ],
  },
  tones: {
    colors: { b: '#59c3ff' },
    rows: [
      '.....########.',
      '.....#bbbbbb#.',
      '.....#b####b#.',
      '.....#b#..#b#.',
      '.....#b#..#b#.',
      '.....#b#..#b#.',
      '.....#b#..#b#.',
      '..####b#.###b#',
      '.#bbbbb##bbbb#',
      '.#bbbbb##bbbb#',
      '.#bbbb#.#bbb#.',
      '..####...###..',
      '..............',
      '..............',
    ],
  },
  themes: {
    colors: { r: '#ff5d7a', y: '#ffd24a', b: '#4aa3ff', g: '#63d16a', w: '#f4e8d0' },
    rows: [
      '....######....',
      '..##wwwwww##..',
      '.#wwrrwwwwww#.',
      '.#wrrrwwyyww#.',
      '#wwwrwwwyyyww#',
      '#wwwwwwwwyywww',
      '#wbbwwwww####.',
      '#wbbbwww#.....',
      '#wwbbwww#.....',
      '.#wwwwggw###..',
      '.#wwwgggwwww#.',
      '..##wwggwww#..',
      '....#######...',
      '..............',
    ],
  },
  help: {
    colors: { b: '#4aa3ff', w: '#ffffff' },
    rows: [
      '....######....',
      '..##bbbbbb##..',
      '.#bbb####bbb#.',
      '.#bb#wwww#bb#.',
      '#bbb##bb#w#bb#',
      '#bbbbbb#ww#bb#',
      '#bbbbb#ww#bbb#',
      '#bbbbb#w#bbbb#',
      '#bbbbb###bbbb#',
      '.#bbbb#w#bbb#.',
      '.#bbbb###bbb#.',
      '..##bbbbbb##..',
      '....######....',
      '..............',
    ],
  },
};

export type IconName = keyof typeof ICONS;

export default function Pix({ name, size = 42 }: { name: string; size?: number }) {
  const icon = ICONS[name];
  if (!icon) return null;

  const cells: { x: number; y: number; fill: string }[] = [];

  icon.rows.forEach((row, y) => {
    [...row].forEach((ch, x) => {
      if (ch !== '.') cells.push({ x, y, fill: ch === '#' ? OUTLINE : icon.colors[ch] ?? OUTLINE });
    });
  });

  return (
    <svg className="pix" width={size} height={size} viewBox="0 0 14 14" shapeRendering="crispEdges" aria-hidden="true">
      {cells.map(c => (
        <rect key={`${c.x}-${c.y}`} x={c.x} y={c.y} width="1" height="1" fill={c.fill} />
      ))}
    </svg>
  );
}
