import React, { useState, useCallback } from 'react';
import Papa from 'papaparse';
import rawData from './data.json';
import './DiaryAnalysisTab.css';

export default function DiaryAnalysisTab() {
  const [data, setData] = useState([]);
  const [isDragging, setIsDragging] = useState(false);
  const [error, setError] = useState(null);

  const processData = (parsedData) => {
    const processed = parsedData.map((row) => {
      // Helper para buscar keys ignorando espacios y mayúsculas
      const getValue = (keyName) => {
        const foundKey = Object.keys(row).find(k => k.trim().toUpperCase() === keyName.toUpperCase());
        return foundKey ? row[foundKey] : undefined;
      };

      // 1. Obtener patrón base de HTF (MN1, W1, D1)
      const htfTfs = ['MN1', 'W1', 'D1'];
      const validHtf = htfTfs
        .map((tf) => getValue(tf))
        .filter((val) => val && val !== 'None' && val !== 'NONE' && typeof val === 'string' && val.trim() !== '');
      
      let baseHtfString = validHtf.map(p => {
        if (p.includes('Bull')) return 'Bull';
        if (p.includes('Bear')) return 'Bear';
        return p.trim();
      }).join(' + ');
      
      if (!baseHtfString) baseHtfString = 'NONE';

      const symbol = getValue('Simbolo') || getValue('Symbol');
      
      const getPatternValue = (val) => {
         if (!val || val === 'None' || val === 'NONE' || typeof val !== 'string' || val.trim() === '') return null;
         return val.trim();
      };

      const h12Pattern = getPatternValue(getValue('H12'));
      const h8Pattern = getPatternValue(getValue('H8'));
      const h4Pattern = getPatternValue(getValue('H4'));

      const findProb = (ltfName, ltfPattern) => {
        if (!ltfPattern) return null;
        
        const match = rawData.find(m => {
          const mHtf = m.HTF_Patterns || m.htfPatterns;
          const mPair = m.pair || m.Pair;
          const mType = m.type || m.LTF_Pattern;
          const mLtf = m.ltf || m.LTF_Target;
          
          return (mHtf === baseHtfString) && 
                 (mPair === symbol || !symbol || mPair === 'ALL') && 
                 (mLtf === ltfName) && 
                 (mType === ltfPattern);
        });

        if (match) {
          return match.Win_Pct ?? match.win;
        }
        return null;
      };

      const winH12 = findProb('H12', h12Pattern);
      const winH8 = findProb('H8', h8Pattern);
      const winH4 = findProb('H4', h4Pattern);

      return {
        ...row,
        FechaHora_clean: getValue('FechaHora_Diario') || getValue('FechaHora'),
        Simbolo_clean: symbol,
        Ref_clean: getValue('Ref'),
        baseHtfString,
        H12_clean: h12Pattern,
        H8_clean: h8Pattern,
        H4_clean: h4Pattern,
        winH12,
        winH8,
        winH4,
      };
    });

    setData(processed);
  };

  const handleFileUpload = (file) => {
    setError(null);
    if (!file.name.endsWith('.csv')) {
      setError('Por favor, sube un archivo CSV válido.');
      return;
    }

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        if (results.errors.length) {
          setError('Error al parsear el CSV.');
          console.error(results.errors);
          return;
        }
        processData(results.data);
      },
      error: (err) => {
        setError(`Error leyendo el archivo: ${err.message}`);
      }
    });
  };

  const onDragOver = useCallback((e) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const onDragLeave = useCallback((e) => {
    e.preventDefault();
    setIsDragging(false);
  }, []);

  const onDrop = useCallback((e) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      handleFileUpload(e.dataTransfer.files[0]);
    }
  }, []);

  const onFileInputChange = (e) => {
    if (e.target.files && e.target.files.length > 0) {
      handleFileUpload(e.target.files[0]);
    }
  };

  return (
    <div className="diary-analysis-container">
      <h2>Análisis de Diario</h2>
      <p className="tab-desc">
        Sube tu archivo <strong>Diario_HTF_State.csv</strong> para cruzar los estados con la matriz de probabilidad.
      </p>

      {/* Upload Zone */}
      <div 
        className={`upload-zone ${isDragging ? 'dragging' : ''}`}
        onDragOver={onDragOver}
        onDragLeave={onDragLeave}
        onDrop={onDrop}
      >
        <div className="upload-content">
          <svg className="upload-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path></svg>
          <p>Arrastra y suelta tu archivo CSV aquí</p>
          <p className="text-gray small">o</p>
          <label className="upload-btn">
            Seleccionar Archivo
            <input type="file" accept=".csv" onChange={onFileInputChange} hidden />
          </label>
        </div>
      </div>

      {error && <div className="error-message">{error}</div>}

      {/* Results Table */}
      {data.length > 0 && (
        <div className="results-section">
          <h3>Resultados del Cruce</h3>
          <div className="table-responsive">
            <table className="results-table">
              <thead>
                <tr>
                  <th>Fecha/Hora</th>
                  <th>Símbolo</th>
                  <th>HTF Base</th>
                  <th>H12 (Patrón)</th>
                  <th>H12 Win %</th>
                  <th>H8 (Patrón)</th>
                  <th>H8 Win %</th>
                  <th>H4 (Patrón)</th>
                  <th>H4 Win %</th>
                </tr>
              </thead>
              <tbody>
                {data.map((row, index) => {
                  const getCellStyle = (winValue) => {
                    if (winValue === null || winValue === undefined) return {};
                    if (winValue > 55) return { backgroundColor: 'rgba(76, 175, 80, 0.15)', color: '#4caf50' };
                    if (winValue < 45) return { backgroundColor: 'rgba(244, 67, 54, 0.15)', color: '#f44336' };
                    return {};
                  };

                  return (
                    <tr key={index}>
                      <td>{row.FechaHora_clean || '-'}</td>
                      <td>{row.Simbolo_clean || '-'}</td>
                      <td>
                        <span className="pattern-badge">{row.baseHtfString}</span>
                      </td>
                      <td className="text-gray">{row.H12_clean || '-'}</td>
                      <td style={getCellStyle(row.winH12)} className="text-center font-bold">
                        {row.winH12 !== null ? `${Number(row.winH12).toFixed(1)}%` : '-'}
                      </td>
                      <td className="text-gray">{row.H8_clean || '-'}</td>
                      <td style={getCellStyle(row.winH8)} className="text-center font-bold">
                        {row.winH8 !== null ? `${Number(row.winH8).toFixed(1)}%` : '-'}
                      </td>
                      <td className="text-gray">{row.H4_clean || '-'}</td>
                      <td style={getCellStyle(row.winH4)} className="text-center font-bold">
                        {row.winH4 !== null ? `${Number(row.winH4).toFixed(1)}%` : '-'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
