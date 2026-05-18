import { useState, useMemo } from 'react';
import rawData from './data.json';
import './ProbabilityCalculator.css';

export default function ProbabilityCalculator({ availablePairs }) {
  const [inputs, setInputs] = useState({
    pair: 'ALL',
    ltf: 'H4',
    ltfSetup: 'Run',
    mn1: 'Neutral',
    w1: 'Neutral',
    d1: 'Bull',
  });

  const handleChange = (key, value) => {
    setInputs(prev => ({ ...prev, [key]: value }));
  };

  const v2Data = useMemo(() => rawData.filter(d => d.version === 'V2'), []);

  // Function to build target info for a specific direction (Bull/Bear)
  const getTargetInfo = (direction) => {
    const { mn1, w1, d1, ltf, ltfSetup } = inputs;
    
    let sources = [];
    let patterns = [];

    if (mn1 !== 'Neutral') { sources.push('MN1'); patterns.push(mn1); }
    if (w1 !== 'Neutral') { sources.push('W1'); patterns.push(w1); }
    if (d1 !== 'Neutral') { sources.push('D1'); patterns.push(d1); }

    const isBase = sources.length === 0;
    const htfSourceTarget = isBase ? 'NONE' : sources.join('+');
    const htfPatternsTarget = isBase ? 'NONE' : patterns.join(' + ');
    const ltfPatternTarget = `${direction} ${ltfSetup}`; // "Bull Run" o "Bear Run"

    return { isBase, htfSourceTarget, htfPatternsTarget, ltfPatternTarget };
  };

  const bullInfo = useMemo(() => getTargetInfo('Bull'), [inputs]);
  const bearInfo = useMemo(() => getTargetInfo('Bear'), [inputs]);

  const getResultsAndSummary = (info, targetDirection) => {
    const matching = v2Data.filter(item => {
      if (inputs.pair !== 'ALL' && item.pair !== inputs.pair) return false;
      if (item.ltf !== inputs.ltf) return false;
      if (item.type !== info.ltfPatternTarget) return false;

      if (info.isBase) {
        return item.isBase;
      } else {
        return !item.isBase && item.htfSource === info.htfSourceTarget && item.htfPatterns === info.htfPatternsTarget;
      }
    });

    let totalTrades = 0;
    let totalWinWeighted = 0;
    let totalDelta = 0;

    matching.forEach(item => {
      totalTrades += item.trades;
      totalWinWeighted += (item.win * item.trades);
      totalDelta += item.delta;
    });

    return {
      direction: targetDirection,
      matching,
      trades: totalTrades,
      winRate: totalTrades > 0 ? (totalWinWeighted / totalTrades) : 0,
      avgDelta: matching.length > 0 ? (totalDelta / matching.length) : 0
    };
  };

  const bullData = useMemo(() => getResultsAndSummary(bullInfo, 'Bull'), [v2Data, inputs, bullInfo]);
  const bearData = useMemo(() => getResultsAndSummary(bearInfo, 'Bear'), [v2Data, inputs, bearInfo]);

  // Calcular la base dinámicamente para obtener el delta real
  const baseBullInfo = useMemo(() => ({ ...bullInfo, isBase: true, htfSourceTarget: 'NONE', htfPatternsTarget: 'NONE' }), [bullInfo]);
  const baseBearInfo = useMemo(() => ({ ...bearInfo, isBase: true, htfSourceTarget: 'NONE', htfPatternsTarget: 'NONE' }), [bearInfo]);
  
  const baseBullData = useMemo(() => getResultsAndSummary(baseBullInfo, 'Bull'), [v2Data, inputs, baseBullInfo]);
  const baseBearData = useMemo(() => getResultsAndSummary(baseBearInfo, 'Bear'), [v2Data, inputs, baseBearInfo]);

  // Determine dominant side by winRate. If equal, check volume of trades.
  const dominant = useMemo(() => {
    if (bullData.trades === 0 && bearData.trades === 0) return null;
    if (bullData.trades === 0) return 'Bear';
    if (bearData.trades === 0) return 'Bull';
    
    if (Math.abs(bullData.winRate - bearData.winRate) < 0.1) {
       return bullData.trades > bearData.trades ? 'Bull' : 'Bear';
    }
    return bullData.winRate > bearData.winRate ? 'Bull' : 'Bear';
  }, [bullData, bearData]);

  const stateOptions = [
    { value: 'Neutral', label: 'Nada (Neutral)' },
    { value: 'Bull', label: 'Bull (Alcista)' },
    { value: 'Bear', label: 'Bear (Bajista)' }
  ];

  const DirectionCard = ({ data, info, baseData, isDominant }) => {
    const isBull = data.direction === 'Bull';
    const label = isBull ? '🟢 COMPRAS (Bull)' : '🔴 VENTAS (Bear)';
    
    if (data.trades === 0) {
      return (
        <div className="result-card empty-card">
          <h3>{label}</h3>
          <p className="text-gray">No hay datos suficientes para esta combinación exacta en {data.direction}.</p>
        </div>
      );
    }

    const dynamicDelta = !info.isBase && baseData.trades > 0 
      ? data.winRate - baseData.winRate 
      : 0;

    return (
      <div className={`result-card direction-card ${isDominant ? 'dominant-card' : ''}`}>
        {isDominant && <div className="dominant-badge">🌟 DIRECCIÓN ÓPTIMA</div>}
        <h3>{label}</h3>
        <div className={`huge-value ${data.winRate > 50 ? 'text-green' : 'text-red'}`}>
          {data.winRate.toFixed(1)}%
        </div>
        <div className="result-sub mb-1">
          Basado en <strong>{data.trades}</strong> operaciones
        </div>
        
        {!info.isBase && baseData.trades > 0 && (
          <div className="delta-stat">
            <span className="small-text">Efecto de HTF (vs Base {baseData.winRate.toFixed(1)}%):</span>
            <strong className={`delta-val ${dynamicDelta > 0 ? 'text-green' : 'text-red'}`}>
              {dynamicDelta > 0 ? '+' : ''}{dynamicDelta.toFixed(2)}%
            </strong>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="calculator-container">
      <h2>Calculadora de Dirección y Probabilidad (Matriz Completa)</h2>
      <p className="calc-desc">
        Introduce exactamente qué patrón estás viendo en cada temporalidad. Gracias a la nueva matriz completa, el sistema evaluará automáticamente las probabilidades de ir Largo (Compras) vs Corto (Ventas) incluso en escenarios contra-tendencia.
      </p>

      <div className="calc-grid">
        {/* Left Column: Context Inputs */}
        <div className="calc-inputs">
          <h3>1. Contexto Global</h3>
          
          <div className="input-group">
            <label>Par de Divisas</label>
            <select value={inputs.pair} onChange={e => handleChange('pair', e.target.value)}>
              <option value="ALL">TODOS (Media Global)</option>
              {availablePairs.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>

          <div className="divider"></div>
          <h3>2. Estructura de HTF</h3>

          <div className="input-group">
            <label>MN1</label>
            <select value={inputs.mn1} onChange={e => handleChange('mn1', e.target.value)}>
              {stateOptions.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>

          <div className="input-group">
            <label>W1</label>
            <select value={inputs.w1} onChange={e => handleChange('w1', e.target.value)}>
              {stateOptions.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>

          <div className="input-group">
            <label>D1</label>
            <select value={inputs.d1} onChange={e => handleChange('d1', e.target.value)}>
              {stateOptions.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>

          <div className="divider"></div>

          <h3>3. Posible Entrada (LTF)</h3>
          <div className="input-group">
            <label>Marco Temporal (LTF)</label>
            <select value={inputs.ltf} onChange={e => handleChange('ltf', e.target.value)}>
              <option value="H12">H12</option>
              <option value="H8">H8</option>
              <option value="H4">H4</option>
              <option value="D1">D1</option>
              <option value="W1">W1</option>
            </select>
          </div>

          <div className="input-group">
            <label>Tipo de Entrada en {inputs.ltf}</label>
            <select value={inputs.ltfSetup} onChange={e => handleChange('ltfSetup', e.target.value)}>
              <option value="Run">Run</option>
              <option value="Sweep">Sweep</option>
            </select>
          </div>
        </div>

        {/* Right Column: Results */}
        <div className="calc-results">
          
          <div className="cards-comparison">
             <DirectionCard data={bullData} info={bullInfo} baseData={baseBullData} isDominant={dominant === 'Bull'} />
             <DirectionCard data={bearData} info={bearInfo} baseData={baseBearData} isDominant={dominant === 'Bear'} />
          </div>

          <div className="debug-info">
            <small>Origen: <code>{bullInfo.htfSourceTarget}</code> | Patrones: <code>{bullInfo.htfPatternsTarget}</code></small>
          </div>

          {inputs.pair === 'ALL' && (bullData.matching.length > 0 || bearData.matching.length > 0) && (
            <div className="breakdown-list">
              <h4>Desglose de Acierto por Par (Dirección Óptima)</h4>
              {(dominant === 'Bull' ? bullData : bearData).matching.sort((a,b) => b.win - a.win).map(item => (
                <div key={item.id} className="breakdown-item">
                  <span>{item.pair}</span>
                  <strong className={item.win > 50 ? 'text-green' : 'text-red'}>{item.win.toFixed(1)}%</strong>
                  <span className="small-text">(T:{item.trades})</span>
                </div>
              ))}
            </div>
          )}

        </div>
      </div>
    </div>
  );
}
