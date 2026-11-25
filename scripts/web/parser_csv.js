const fs = require('fs');
const path = require('path');

const dir = './Bias Report';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.csv'));

let allData = [];

files.forEach(file => {
  const pair = file.replace('CRT_FullMatrix_', '').replace('.csv', '');
  const content = fs.readFileSync(path.join(dir, file), 'utf-8');
  const lines = content.split('\n').filter(l => l.trim().length > 0);
  
  const aggregatedMap = new Map();

  // Skip header
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    const [typeStr, htfSource, ltfTarget, htfPatterns, ltfPattern, alignment, trades, winPct, slPct, revPct, delta] = line.split(',');
    
    const isBase = typeStr === '0_BASE';
    
    // Simplify HTF Patterns by removing "Run" and "Sweep", leaving only "Bull" or "Bear"
    let simplifiedHtfPatterns = 'NONE';
    if (!isBase && htfPatterns !== 'NONE') {
      simplifiedHtfPatterns = htfPatterns.split(' + ').map(p => {
        if (p.includes('Bull')) return 'Bull';
        if (p.includes('Bear')) return 'Bear';
        return p;
      }).join(' + ');
    }

    const tradesNum = parseInt(trades, 10);
    const winNum = parseFloat(winPct);
    const deltaNum = parseFloat(delta);

    const key = `${pair}|${isBase}|${htfSource}|${ltfTarget}|${simplifiedHtfPatterns}|${ltfPattern}|${alignment}`;

    if (!aggregatedMap.has(key)) {
      aggregatedMap.set(key, { trades: 0, winWeighted: 0, deltaSum: 0, count: 0 });
    }

    const current = aggregatedMap.get(key);
    current.trades += tradesNum;
    current.winWeighted += (winNum * tradesNum);
    current.deltaSum += deltaNum;
    current.count += 1;
  }

  // Convert aggregatedMap back to allData entries
  let idCounter = 1;
  for (const [key, value] of aggregatedMap.entries()) {
    const [pairKey, isBaseKey, htfSourceKey, ltfTargetKey, htfPatternsKey, ltfPatternKey, alignmentKey] = key.split('|');
    const isBaseBool = isBaseKey === 'true';

    allData.push({
      id: `${pairKey}-agg-${idCounter++}`,
      version: 'V2',
      isBase: isBaseBool,
      pair: pairKey,
      htfSource: htfSourceKey,
      ltf: ltfTargetKey,
      htfPatterns: htfPatternsKey,
      type: ltfPatternKey,
      alignment: alignmentKey,
      trades: value.trades,
      win: value.trades > 0 ? (value.winWeighted / value.trades) : 0,
      delta: value.count > 0 ? (value.deltaSum / value.count) : 0
    });
  }
});

fs.writeFileSync('./crt-comparator/src/data.json', JSON.stringify(allData, null, 2));
console.log('Parsed and aggregated all CSVs into data.json. Total records:', allData.length);
