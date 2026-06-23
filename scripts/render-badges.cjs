const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');

const iconDir = path.join(__dirname, '..', 'public', 'badges', 'icons');
const icons = ['globe', 'apple', 'chrome', 'support'];

for (const name of icons) {
  const svg = fs.readFileSync(path.join(iconDir, `${name}.svg`), 'utf8');
  const resvg = new Resvg(svg, { fitTo: { mode: 'height', value: 32 } });
  fs.writeFileSync(path.join(iconDir, `${name}.png`), resvg.render().asPng());
  console.log(`wrote ${name}.png`);
}
