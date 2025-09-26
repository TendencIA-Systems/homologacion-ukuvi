const fs = require('fs');
const path = require('path');
const files = [
  'src/insurers/zurich/zurich-codigo-de-normalizacion.js',
  'src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js',
  'src/insurers/chubb/chubb-codigo-de-normalizacion.js',
  'src/insurers/ana/ana-codigo-de-normalizacion.js',
  'src/insurers/atlas/atlas-codigo-de-normalizacion.js'
];
const comfortTokens = '\n    "COMFORT",\n    "CONFORT",';
for (const file of files) {
  let text = fs.readFileSync(file, 'utf8');
  if (!text.includes('"COMFORT"')) {
    text = text.replace(/"FBX",/g, '"FBX",' + comfortTokens);
    text = text.replace(/"CAMARA",/g, '"CAMARA",' + comfortTokens);
    text = text.replace(/"CAM TRAS",([^\n]*)\n(\s*)"SENSOR",/g, '"CAM TRAS",$1\n$2"SENSOR",' + comfortTokens + '\n' + $2);
  }
  const expandPattern = /function expandTurboSuffix\(text = ""\) {([\s\S]*?)}/;
  const expandReplacement = `function expandTurboSuffix(text = "") {\n  if (!text || typeof text !== "string") return "";\n  const hasStandaloneLiter = /\\b\\d+(?:\\.\\d+)?\\s*L\\b/i.test(text);\n  return text.replace(/\\b(\\d+\\.\\d+)(?:L)?\\s*T\\b/gi, (_, num) => \`${'${num}${hasStandaloneLiter ? "" : "L"} TURBO'}\`);\n}`;
  if (expandPattern.test(text)) {
    text = text.replace(expandPattern, expandReplacement);
  }
  const versionPattern = /versionLimpia.replace\(/g;
  if (!/L\?\\s\*T/.test(text)) {
    text = text.replace(/versionLimpia = versionLimpia.replace\(/g, (match) => match);
    text = text.replace(/versionLimpia = versionLimpia\.replace\(\\b\(\\d\+\\.\\d\+\)L\?\\b/g, 'versionLimpia = versionLimpia.replace(/\\b(\\d+\\.\\d+)L?\\s*T\\b');
    text = text.replace(/versionLimpia\.replace\(\/\\b\(\\d\+\\.\\d\+\)L\?\\b\/g, 'versionLimpia.replace(/\\b(\\d+\\.\\d+)L?\\s*T\\b/');
  }
  if (!text.includes('versionLimpia = versionLimpia.replace(/\\bABS\\b/g')) {
    text = text.replace(/versionLimpia = dedupeTokens\(sanitizedTokens\)\n    \.join\(" "\)\n    \.replace\(\/\\s\+\/g, " "\)\n    \.trim\(\);/g,
      match => match + '\n  versionLimpia = versionLimpia.replace(/\\bABS\\b/g, " ").replace(/\\s+/g, " ").trim();');
  }
  text = text.replace(/record.anio < 2000 \|\| record.anio > 2030/g, 'record.anio < 1990 || record.anio > 2035');
  fs.writeFileSync(file, text);
}
