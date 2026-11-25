import React from 'react';
import './FilterPanel.css';

export default function FilterPanel({ filters, toggleFilter, availablePairs }) {
  const FilterButton = ({ category, value, label }) => {
    const isActive = filters[category].includes(value);
    return (
      <button 
        className={`filter-btn ${isActive ? 'active' : ''}`}
        onClick={() => toggleFilter(category, value)}
      >
        {label || value}
      </button>
    );
  };

  return (
    <div className="filters-panel">
      {availablePairs && availablePairs.length > 0 && (
        <div className="filter-group">
          <h3>Pares</h3>
          <div className="button-group">
            {availablePairs.map(pair => (
              <FilterButton key={pair} category="pairs" value={pair} />
            ))}
          </div>
        </div>
      )}

      <div className="filter-group">
        <h3>HTF</h3>
        <div className="button-group">
          <FilterButton category="htf" value="MN1" />
          <FilterButton category="htf" value="W1" />
          <FilterButton category="htf" value="D1" />
        </div>
      </div>

      <div className="filter-group">
        <h3>LTF</h3>
        <div className="button-group">
          <FilterButton category="ltf" value="H12" />
          <FilterButton category="ltf" value="H8" />
          <FilterButton category="ltf" value="H4" />
        </div>
      </div>

      <div className="filter-group">
        <h3>Dirección</h3>
        <div className="button-group">
          <FilterButton category="direction" value="Bull" label="Compras (Bull)" />
          <FilterButton category="direction" value="Bear" label="Ventas (Bear)" />
        </div>
      </div>

      <div className="filter-group">
        <h3>Ejecución</h3>
        <div className="button-group">
          <FilterButton category="execution" value="Run" />
          <FilterButton category="execution" value="Sweep" />
        </div>
      </div>
    </div>
  );
}
