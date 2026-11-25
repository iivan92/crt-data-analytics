const fs = require("fs");
const content = fs.readFileSync("./CRT_Analyzer_HTF_vC.txt", "utf-8");

// Regex for regular lines with rating and delta
const regexRegular = /\(([A-Z]+),[^)]+\)[^[]+\[([^\]]+)\]\s+\|\s+([^|]+?)\s+\|\s+(Bull Sweep|Bull Run|Bear Sweep|Bear Run)\s+\|\s+T:(\d+)\s+\|\s+WIN:([\d.]+)%\s+\|\s+SL:([\d.]+)%\s+\|\s+Rev:([\d.]+)%\s+\|\s+Delta:([+\-\d.]+)%/g;

// Regex for base lines
// Example: 2026.05.12 13:29:35.296	CRT_Analyzer_HTF_vC (EURUSD,D1)	  BASE | W1 | Bull Sweep | T:208 | WIN:62.0% | SL:37.0% | Rev:1.0%
const regexBase = /\(([A-Z]+),[^)]+\)\s+BASE\s+\|\s+([^|]+?)\s+\|\s+(Bull Sweep|Bull Run|Bear Sweep|Bear Run)\s+\|\s+T:(\d+)\s+\|\s+WIN:([\d.]+)%\s+\|\s+SL:([\d.]+)%\s+\|\s+Rev:([\d.]+)%/g;

let results = [];
let match;
while ((match = regexBase.exec(content)) !== null) {
  results.push({
    pair: match[1],
    ltf: match[2].trim(),
    type: match[3].trim(),
    trades: parseInt(match[4]),
    win: parseFloat(match[5])
  });
}
console.log("Base matches:", results.length);
if (results.length > 0) {
  console.log(results[0]);
  console.log(results.filter(r => r.ltf === 'H12')[0]);
}
