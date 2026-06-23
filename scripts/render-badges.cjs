const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');

const dir = path.join(__dirname, '..', 'public', 'badges');
const files = ['website', 'app-store', 'chrome', 'support'];

for (const name of files) {
  const svg = fs.readFileSync(path.join(dir, `${name}.svg`), 'utf8');
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: 272 } });
  const png = resvg.render().asPng();
  fs.writeFileSync(path.join(dir, `${name}.png`), png);
  console.log(`wrote ${name}.png`);
}
