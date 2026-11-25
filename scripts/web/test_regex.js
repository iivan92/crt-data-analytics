const fs = require("fs");
const content = fs.readFileSync("./CRT_Analyzer_HTF_vC.txt", "utf-8");
const regex = /\(([A-Z]+),[^)]+\)[^[]+\[([^\]]+)\]\s+\|\s+([^|]+?)\s+\|\s+(Bull Sweep|Bull Run|Bear Sweep|Bear Run)\s+\|\s+T:(\d+)\s+\|\s+WIN:([\d.]+)%\s+\|\s+SL:([\d.]+)%\s+\|\s+Rev:([\d.]+)%\s+\|\s+Delta:([+\-\d.]+)%/g;

let match = regex.exec(content);
if (match) {
  console.log("Symbol:", match[1]);
  console.log("Rating:", match[2].trim());
  console.log("Bias:", match[3].trim());
} else {
  console.log("No match");
}
