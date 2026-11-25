import { useState, useMemo } from 'react';
import rawData from './data.json';
import './V2Analyzer.css';

export default function V2Analyzer({ filters }) {
  const [sortConfig, setSortConfig] = useState({ key: 'delta', direction: 'desc' });

  const v2Data = useMemo(() => rawData.filter(d => d.version === 'V2'), []);

  // --- 1. BASELINE DATA (No HTF filter) ---
  const baseSummary = useMemo(() => {
    const baseItems = v2Data.filter(item => {
      if (!item.isBase) return false;
      
      const matchLtf = filters.ltf.includes(item.ltf);
      const matchPair = filters.pairs.length === 0 || filters.pairs.includes(item.pair);
      const matchDir = filters.direction.length === 0 || filters.direction.some(d => item.type.includes(d));
      const matchExec = filters.execution.length === 0 || filters.execution.some(e => item.type.includes(e));

      return matchLtf && matchPair && matchDir && matchExec;
    });

    let totalTrades = 0, totalWinWeighted = 0;
    let bullTrades = 0, bullWinW = 0;
    let bearTrades = 0, bearWinW = 0;

    baseItems.forEach(item => {
      totalTrades += item.trades;
      totalWinWeighted += (item.win * item.trades);

      if (item.type.includes('Bull')) {
        bullTrades += item.trades;
        bullWinW += (item.win * item.trades);
      } else if (item.type.includes('Bear')) {
        bearTrades += item.trades;
        bearWinW += (item.win * item.trades);
      }
    });

    return {
      totalTrades,
      avgWin: totalTrades > 0 ? (totalWinWeighted / totalTrades) : 0,
      bullStats: { trades: bullTrades, win: bullTrades > 0 ? (bullWinW / bullTrades) : 0 },
      bearStats: { trades: bearTrades, win: bearTrades > 0 ? (bearWinW / bearTrades) : 0 }
    };
  }, [v2Data, filters]);


  // --- 2. FILTERED DATA (With HTF filter) ---
  const filteredData = useMemo(() => {
    return v2Data.filter(item => {
      if (item.isBase) return false;

      const matchPair = filters.pairs.length === 0 || filters.pairs.includes(item.pair);

      const matchHtf = filters.htf.length === 0 || filters.htf.some(h => item.htfSource && item.htfSource.includes(h));
      const matchLtf = filters.ltf.length === 0 || filters.ltf.some(l => item.ltf === l);
      const matchDir = filters.direction.length === 0 || filters.direction.some(d => item.type && item.type.includes(d));
      const matchExec = filters.execution.length === 0 || filters.execution.some(e => item.type && item.type.includes(e));

      return matchPair && matchHtf && matchLtf && matchDir && matchExec;
    });
  }, [v2Data, filters]);

  const filteredSummary = useMemo(() => {
    let totalTrades = 0, totalWinWeighted = 0, totalDeltaSum = 0, count = 0;
    let bullTrades = 0, bullWinW = 0, bullDeltaSum = 0, bullCount = 0;
    let bearTrades = 0, bearWinW = 0, bearDeltaSum = 0, bearCount = 0;

    filteredData.forEach(item => {
      totalTrades += item.trades;
      totalWinWeighted += (item.win * item.trades);
      totalDeltaSum += item.delta;
      count++;

      if (item.type.includes('Bull')) {
        bullTrades += item.trades;
        bullWinW += (item.win * item.trades);
        bullDeltaSum += item.delta;
        bullCount++;
      } else if (item.type.includes('Bear')) {
        bearTrades += item.trades;
        bearWinW += (item.win * item.trades);
        bearDeltaSum += item.delta;
        bearCount++;
      }
    });

    const sortedByDelta = [...filteredData].sort((a, b) => b.delta - a.delta);
    const reliableData = sortedByDelta.filter(i => i.trades >= 20); 
    const dataForTops = reliableData.length >= 6 ? reliableData : sortedByDelta;

    return { 
      totalTrades, 
      avgWin: totalTrades > 0 ? (totalWinWeighted / totalTrades) : 0, 
      avgDelta: count > 0 ? (totalDeltaSum / count) : 0,
      bullStats: { trades: bullTrades, win: bullTrades > 0 ? (bullWinW / bullTrades) : 0, delta: bullCount > 0 ? (bullDeltaSum / bullCount) : 0 },
      bearStats: { trades: bearTrades, win: bearTrades > 0 ? (bearWinW / bearTrades) : 0, delta: bearCount > 0 ? (bearDeltaSum / bearCount) : 0 },
      top3: dataForTops.slice(0, 3),
      worst3: [...dataForTops].reverse().slice(0, 3)
    };
  }, [filteredData]);

  // --- 3. SORTING ---
  const sortedData = useMemo(() => {
    let sortableItems = [...filteredData];
    if (sortConfig.key) {
      sortableItems.sort((a, b) => {
        let valA = a[sortConfig.key];
        let valB = b[sortConfig.key];
        
        if (typeof valA === 'string') valA = valA.toLowerCase();
        if (typeof valB === 'string') valB = valB.toLowerCase();

        if (valA < valB) {
          return sortConfig.direction === 'asc' ? -1 : 1;
        }
        if (valA > valB) {
          return sortConfig.direction === 'asc' ? 1 : -1;
        }
        return 0;
      });
    }
    return sortableItems;
  }, [filteredData, sortConfig]);

  const requestSort = (key) => {
    let direction = 'asc';
    if (sortConfig.key === key && sortConfig.direction === 'asc') {
      direction = 'desc';
    }
    setSortConfig({ key, direction });
  };

  const getSortIcon = (key) => {
    if (sortConfig.key !== key) return '↕️';
    return sortConfig.direction === 'asc' ? '↑' : '↓';
  };

  return (
    <div className="v2-analyzer">
      
      {/* ---------------- BASELINE SECTION ---------------- */}
      <div className="section-divider">
        <h3>1. BASELINE: Datos originales de {filters.ltf[0]} (Sin filtros HTF)</h3>
      </div>
      
      <div className="summary-panel base-panel">
        <div className="summary-card">
          <div className="summary-title">Trades Originales</div>
          <div className="summary-value">{baseSummary.totalTrades}</div>
        </div>
        <div className="summary-card">
          <div className="summary-title">Win % Original</div>
          <div className={`summary-value ${baseSummary.avgWin > 50 ? 'text-green' : 'text-red'}`}>
            {baseSummary.avgWin.toFixed(2)}%
          </div>
        </div>
      </div>
      
      <div className="directional-split">
         <div className="stat-box base-box">
            <h4>🟢 COMPRAS (Bull) Original</h4>
            <div className="stat-row"><span>Trades:</span> <strong>{baseSummary.bullStats.trades}</strong></div>
            <div className="stat-row"><span>Win %:</span> <strong className={baseSummary.bullStats.win > 50 ? 'text-green' : 'text-red'}>{baseSummary.bullStats.win.toFixed(1)}%</strong></div>
         </div>
         <div className="stat-box base-box">
            <h4>🔴 VENTAS (Bear) Original</h4>
            <div className="stat-row"><span>Trades:</span> <strong>{baseSummary.bearStats.trades}</strong></div>
            <div className="stat-row"><span>Win %:</span> <strong className={baseSummary.bearStats.win > 50 ? 'text-green' : 'text-red'}>{baseSummary.bearStats.win.toFixed(1)}%</strong></div>
         </div>
      </div>

      {/* ---------------- FILTERED SECTION ---------------- */}
      <div className="section-divider" style={{marginTop: '2rem'}}>
        <h3>2. IMPACTO: Resultados tras aplicar HTF Bias</h3>
      </div>

      <div className="summary-panel">
        <div className="summary-card">
          <div className="summary-title">Total Trades Filtrados</div>
          <div className="summary-value">{filteredSummary.totalTrades}</div>
        </div>
        <div className="summary-card">
          <div className="summary-title">Win % Resultante</div>
          <div className={`summary-value ${filteredSummary.avgWin > 50 ? 'text-green' : 'text-red'}`}>
            {filteredSummary.avgWin.toFixed(2)}%
          </div>
        </div>
        <div className="summary-card highlight-card">
          <div className="summary-title">Average Delta %</div>
          <div className={`summary-value ${filteredSummary.avgDelta > 0 ? 'text-green' : 'text-red'}`}>
            {filteredSummary.avgDelta > 0 ? '+' : ''}{filteredSummary.avgDelta.toFixed(2)}%
          </div>
        </div>
      </div>

      <div className="directional-split">
         <div className="stat-box">
            <h4>🟢 COMPRAS (Bull) Filtrado</h4>
            <div className="stat-row"><span>Trades:</span> <strong>{filteredSummary.bullStats.trades}</strong></div>
            <div className="stat-row"><span>Win %:</span> <strong className={filteredSummary.bullStats.win > 50 ? 'text-green' : 'text-red'}>{filteredSummary.bullStats.win.toFixed(1)}%</strong></div>
            <div className="stat-row"><span>Avg Delta %:</span> <strong className={filteredSummary.bullStats.delta > 0 ? 'text-green' : filteredSummary.bullStats.delta < 0 ? 'text-red' : ''}>{filteredSummary.bullStats.delta > 0 ? '+' : ''}{filteredSummary.bullStats.delta.toFixed(2)}%</strong></div>
         </div>
         <div className="stat-box">
            <h4>🔴 VENTAS (Bear) Filtrado</h4>
            <div className="stat-row"><span>Trades:</span> <strong>{filteredSummary.bearStats.trades}</strong></div>
            <div className="stat-row"><span>Win %:</span> <strong className={filteredSummary.bearStats.win > 50 ? 'text-green' : 'text-red'}>{filteredSummary.bearStats.win.toFixed(1)}%</strong></div>
            <div className="stat-row"><span>Avg Delta %:</span> <strong className={filteredSummary.bearStats.delta > 0 ? 'text-green' : filteredSummary.bearStats.delta < 0 ? 'text-red' : ''}>{filteredSummary.bearStats.delta > 0 ? '+' : ''}{filteredSummary.bearStats.delta.toFixed(2)}%</strong></div>
         </div>
      </div>

      {/* TOP & WORST */}
      <div className="tops-container">
        <div className="top-section">
          <h3 className="text-green">🏆 Top 3 Mejores Setups</h3>
          {filteredSummary.top3.length === 0 && <p className="text-gray">No hay datos suficientes</p>}
          {filteredSummary.top3.map((item, i) => (
            <div key={`top-${item.id}-${i}`} className="setup-card">
              <div className="setup-header">
                <strong>{item.pair}</strong> | {item.htfSource} ({item.htfPatterns}) -&gt; {item.ltf} | {item.type}
              </div>
              <div className="setup-metrics">
                <span>T: {item.trades}</span>
                <span className="text-green">W: {item.win.toFixed(1)}%</span>
                <span className="text-green bold">Δ: +{item.delta.toFixed(1)}%</span>
              </div>
            </div>
          ))}
        </div>
        <div className="top-section">
          <h3 className="text-red">⚠️ Top 3 Peores Setups</h3>
          {filteredSummary.worst3.length === 0 && <p className="text-gray">No hay datos suficientes</p>}
          {filteredSummary.worst3.map((item, i) => (
            <div key={`worst-${item.id}-${i}`} className="setup-card">
              <div className="setup-header">
                <strong>{item.pair}</strong> | {item.htfSource} ({item.htfPatterns}) -&gt; {item.ltf} | {item.type}
              </div>
              <div className="setup-metrics">
                <span>T: {item.trades}</span>
                <span className="text-red">W: {item.win.toFixed(1)}%</span>
                <span className="text-red bold">Δ: {item.delta.toFixed(1)}%</span>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th onClick={() => requestSort('pair')}>Pair {getSortIcon('pair')}</th>
              <th onClick={() => requestSort('htfSource')}>HTF Structure {getSortIcon('htfSource')}</th>
              <th onClick={() => requestSort('type')}>Type {getSortIcon('type')}</th>
              <th onClick={() => requestSort('trades')}>Trades {getSortIcon('trades')}</th>
              <th onClick={() => requestSort('win')}>Win % {getSortIcon('win')}</th>
              <th onClick={() => requestSort('delta')}>Delta % {getSortIcon('delta')}</th>
            </tr>
          </thead>
          <tbody>
            {sortedData.slice(0, 100).map(item => (
              <tr key={item.id}>
                <td>{item.pair}</td>
                <td>{item.htfSource} ({item.htfPatterns}) -&gt; {item.ltf}</td>
                <td>{item.type}</td>
                <td>{item.trades}</td>
                <td>{item.win.toFixed(1)}%</td>
                <td className={`bold ${item.delta > 0 ? 'text-green' : item.delta < 0 ? 'text-red' : ''}`}>
                  {item.delta > 0 ? '+' : ''}{item.delta.toFixed(1)}%
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {sortedData.length > 100 && (
          <div className="stats" style={{ padding: '1rem', textAlign: 'center' }}>
            Showing top 100 of {sortedData.length} results
          </div>
        )}
      </div>
    </div>
  );
}
