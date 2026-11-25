import { useState, useMemo } from 'react';
import rawData from './data.json';
import V2Analyzer from './V2Analyzer';
import FilterPanel from './FilterPanel';
import ProbabilityCalculator from './ProbabilityCalculator';
import DiaryAnalysisTab from './DiaryAnalysisTab';
import './App.css';

function App() {
  const [activeTab, setActiveTab] = useState('v2analyzer');

  const [filters, setFilters] = useState({
    pairs: [],
    htf: [],
    ltf: ['H12'], // Default LTF selected
    direction: [],
    execution: [],
  });

  const availablePairs = useMemo(() => {
    return [...new Set(rawData.map(d => d.pair).filter(Boolean))];
  }, []);

  const toggleFilter = (category, value) => {
    setFilters(prev => {
      const current = prev[category];
      
      // If it's LTF, act like a radio button (always exactly 1 selected)
      if (category === 'ltf') {
        if (current.includes(value)) {
          return prev; // Do nothing if trying to uncheck the only selected LTF
        }
        return { ...prev, [category]: [value] }; // Replace with new LTF
      }

      // Default behavior for other filters
      if (current.includes(value)) {
        return { ...prev, [category]: current.filter(v => v !== value) };
      } else {
        return { ...prev, [category]: [...current, value] };
      }
    });
  };

  return (
    <div className="container">
      <header>
        <h1>CRT Data Analyzer</h1>
        {activeTab !== 'calculator' && activeTab !== 'diary' && (
          <FilterPanel 
            filters={filters} 
            toggleFilter={toggleFilter} 
            availablePairs={availablePairs} 
          />
        )}
        <div className="tabs">
          <button 
            className={`tab-btn ${activeTab === 'v2analyzer' ? 'active' : ''}`}
            onClick={() => setActiveTab('v2analyzer')}
          >
            Interactive Analyzer
          </button>
          <button 
            className={`tab-btn ${activeTab === 'calculator' ? 'active' : ''}`}
            onClick={() => setActiveTab('calculator')}
          >
            Calculadora de Probabilidad
          </button>
          <button 
            className={`tab-btn ${activeTab === 'diary' ? 'active' : ''}`}
            onClick={() => setActiveTab('diary')}
          >
            Análisis de Diario
          </button>
        </div>
      </header>

      {activeTab === 'v2analyzer' && (
        <V2Analyzer filters={filters} />
      )}

      {activeTab === 'calculator' && (
        <ProbabilityCalculator availablePairs={availablePairs} />
      )}

      {activeTab === 'diary' && (
        <DiaryAnalysisTab />
      )}
    </div>
  );
}

export default App;
