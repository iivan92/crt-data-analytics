const fs = require("fs");

function parseLog(filePath, version) {
  const content = fs.readFileSync(filePath, "utf-8");
  const results = [];

  // 1. Regular lines
  const regexRegular =
    /\(([A-Z]+),[^)]+\)[^[]+\[([^\]]+)\]\s+\|\s+([^|]+?)\s+\|\s+(Bull Sweep|Bull Run|Bear Sweep|Bear Run)\s+\|\s+T:(\d+)\s+\|\s+WIN:([\d.]+)%\s+\|\s+SL:([\d.]+)%\s+\|\s+Rev:([\d.]+)%\s+\|\s+Delta:([+\-\d.]+)%/g;

  let match;
  while ((match = regexRegular.exec(content)) !== null) {
    results.push({
      id: `${version}-${match[1]}-${match[3].trim()}-${match[4].trim()}`.replace(
        /\s+/g,
        "-",
      ),
      version: version,
      isBase: false,
      pair: match[1], // ej: 'EURUSD'
      rating: match[2].trim(), // ej: '+++', '=', '--'
      bias: match[3].trim(), // ej: 'MN1(SWP)+W1(RUN)->H12'
      type: match[4].trim(), // ej: 'Bull Sweep'
      trades: parseInt(match[5]),
      win: parseFloat(match[6]),
      delta: parseFloat(match[9]),
    });
  }

  // 2. Base lines
  const regexBase = /\(([A-Z]+),[^)]+\)\s+BASE\s+\|\s+([^|]+?)\s+\|\s+(Bull Sweep|Bull Run|Bear Sweep|Bear Run)\s+\|\s+T:(\d+)\s+\|\s+WIN:([\d.]+)%\s+\|\s+SL:([\d.]+)%\s+\|\s+Rev:([\d.]+)%/g;
  while ((match = regexBase.exec(content)) !== null) {
    results.push({
      id: `${version}-${match[1]}-BASE-${match[2].trim()}-${match[3].trim()}`.replace(
        /\s+/g,
        "-",
      ),
      version: version,
      isBase: true,
      pair: match[1],
      ltf: match[2].trim(),
      type: match[3].trim(),
      trades: parseInt(match[4]),
      win: parseFloat(match[5]),
      delta: 0,
    });
  }

  return results;
}

// Ejecución
const dataV1 = parseLog("./CRT_Analyzer_HTF_vC.txt", "V1");
const dataV2 = parseLog("./CRT_Analyzer_HTF_vC2.txt", "V2"); // V2 con filtro Mother Bar

fs.writeFileSync(
  "crt_data.json",
  JSON.stringify([...dataV1, ...dataV2], null, 2),
);
console.log("Datos consolidados en crt_data.json");
