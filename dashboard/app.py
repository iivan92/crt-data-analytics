import streamlit as st
import pandas as pd
import plotly.express as px
from sqlalchemy import create_engine
import os

# Configuración de página
st.set_page_config(page_title="CRT Quant Dashboard", layout="wide")

st.title("📊 CRT Quant Analytics Dashboard")

# Conexión a la base de datos
@st.cache_resource
def init_connection():
    db_user = os.environ.get("DB_USER", "postgres")
    db_password = os.environ.get("DB_PASSWORD", "admin")
    db_host = os.environ.get("DB_HOST", "postgres_db")
    db_port = os.environ.get("DB_PORT", "5432")
    db_name = os.environ.get("DB_NAME", "crt_quant")
    
    engine = create_engine(f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}")
    return engine

# Función para cargar datos
@st.cache_data(ttl=600)
def load_data():
    engine = init_connection()
    query = """
    SELECT symbol, timeframe, direction, entry_time, exit_time, result_type, has_restarted 
    FROM crt_trades;
    """
    df = pd.read_sql(query, engine)
    df['entry_time'] = pd.to_datetime(df['entry_time'])
    df['exit_time'] = pd.to_datetime(df['exit_time'])
    df['is_win'] = df['result_type'].str.contains('TP_', na=False)
    return df

# Función para calcular contextos múltiples HTF para un DataFrame LTF
@st.cache_data
def get_multi_htf_context(df_ltf, df_all, htf_list):
    df_res = df_ltf.copy()
    for htf in htf_list:
        df_htf = df_all[df_all['timeframe'] == htf]
        
        def find_dir(row):
            active = df_htf[(df_htf['entry_time'] <= row['entry_time']) & (df_htf['exit_time'] >= row['entry_time'])]
            if active.empty: return 'Neutral'
            return active.sort_values('entry_time', ascending=False).iloc[0]['direction']
            
        df_res[htf] = df_res.apply(find_dir, axis=1)
    return df_res

try:
    with st.spinner('Cargando datos desde la base de datos...'):
        df = load_data()
        
    if df.empty:
        st.warning("No hay datos en la base de datos. Ejecuta el extractor primero.")
    else:
        st.success(f"Datos cargados correctamente: {len(df)} operaciones.")
        
        # Pestañas
        tab1, tab2, tab3, tab4 = st.tabs([
            "📊 Análisis General", 
            "🔄 Análisis Simple (1 HTF)",
            "🏆 Mejores Setups (Tops)",
            "🧮 Calculadora Matriz"
        ])
        
        # --- TAB 1: GENERAL ---
        with tab1:
            st.sidebar.header("Filtros Generales")
            selected_symbols = st.sidebar.multiselect("Símbolo", options=df['symbol'].unique(), default=df['symbol'].unique(), key="sym_t1")
            selected_timeframes = st.sidebar.multiselect("Timeframe", options=df['timeframe'].unique(), default=df['timeframe'].unique(), key="tf_t1")
            
            filtered_df = df[(df['symbol'].isin(selected_symbols)) & (df['timeframe'].isin(selected_timeframes))]
            total_trades = len(filtered_df)
            wins = filtered_df['is_win'].sum()
            win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
            
            col1, col2, col3, col4 = st.columns(4)
            col1.metric("Total Trades", total_trades)
            col2.metric("Win Rate Global (%)", f"{win_rate:.2f}%")
            
            st.markdown("### Resultados por Par y Timeframe")
            summary_df = filtered_df.groupby(['symbol', 'timeframe', 'result_type']).size().reset_index(name='count')
            fig1 = px.bar(summary_df, x="symbol", y="count", color="result_type", barmode="group", facet_col="timeframe")
            st.plotly_chart(fig1, use_container_width=True)

        # --- TAB 2: SIMPLE HTF ---
        with tab2:
            st.markdown("## Análisis de 1 Contexto Mayor (HTF)")
            col_t1, col_t2, col_t3 = st.columns(3)
            with col_t1:
                t2_sym = st.selectbox("Símbolo a analizar:", options=df['symbol'].unique(), key="t2_sym")
            with col_t2:
                t2_ltf = st.selectbox("Timeframe Menor (LTF):", options=df['timeframe'].unique(), index=0, key="t2_ltf")
            with col_t3:
                htf_opts = [tf for tf in df['timeframe'].unique() if tf != t2_ltf]
                t2_htf = st.selectbox("Timeframe Mayor (HTF):", options=htf_opts, key="t2_htf")
                
            df_sym = df[df['symbol'] == t2_sym]
            df_ltf = df_sym[df_sym['timeframe'] == t2_ltf].copy()
            df_htf = df_sym[df_sym['timeframe'] == t2_htf].copy()
            
            if not df_ltf.empty and not df_htf.empty:
                df_ltf_ctx = get_multi_htf_context(df_ltf, df_sym, [t2_htf])
                
                def classify_align(row):
                    htf_dir = row[t2_htf]
                    if htf_dir == 'Neutral': return 'SIN CONTEXTO'
                    if htf_dir == row['direction']: return 'ALINEADO'
                    return 'EN CONTRA (REVERSIÓN)'
                    
                df_ltf_ctx['Alignment'] = df_ltf_ctx.apply(classify_align, axis=1)
                
                ctx_summary = []
                for align in ["ALINEADO", "EN CONTRA (REVERSIÓN)", "SIN CONTEXTO"]:
                    sub = df_ltf_ctx[df_ltf_ctx['Alignment'] == align]
                    t = len(sub)
                    w = sub['is_win'].sum()
                    if t > 0:
                        ctx_summary.append({"Contexto": align, "Trades": t, "Win Rate %": round((w/t)*100, 2)})
                        
                if ctx_summary:
                    ctx_df = pd.DataFrame(ctx_summary)
                    fig2 = px.bar(ctx_df, x="Contexto", y="Win Rate %", color="Contexto", text="Win Rate %")
                    fig2.update_traces(texttemplate='%{text}%', textposition='outside')
                    st.plotly_chart(fig2, use_container_width=True)

        # --- TAB 3: TOPS & WORST ---
        with tab3:
            st.markdown("## 🏆 Mejores y Peores Setups (Multi-Timeframe)")
            st.markdown("Calcula las combinaciones con mayor win rate usando MN1, W1 y D1 como contexto para el LTF elegido.")
            
            top_ltf = st.selectbox("Elige tu LTF para buscar setups:", options=['H12', 'H8', 'H4', 'D1'], index=2)
            
            if st.button("Generar Ranking de Setups"):
                with st.spinner('Analizando combinaciones en toda la base de datos...'):
                    # HTFs a evaluar
                    htfs = ['MN1', 'W1', 'D1']
                    # Quitamos el LTF de la lista de HTFs si coinciden
                    htfs = [h for h in htfs if h != top_ltf]
                    
                    df_target_ltf = df[df['timeframe'] == top_ltf]
                    
                    # Generar contexto
                    df_ctx = get_multi_htf_context(df_target_ltf, df, htfs)
                    
                    # Agrupar por Símbolo, Dirección LTF, y estado de los HTFs
                    group_cols = ['symbol', 'direction'] + htfs
                    grouped = df_ctx.groupby(group_cols).agg(
                        Trades=('is_win', 'count'),
                        Wins=('is_win', 'sum')
                    ).reset_index()
                    
                    grouped['Win Rate %'] = (grouped['Wins'] / grouped['Trades'] * 100).round(2)
                    
                    # Filtrar por significancia estadística
                    min_trades = st.slider("Mínimo de Trades para considerar setup válido", 1, 50, 5)
                    valid_setups = grouped[grouped['Trades'] >= min_trades].copy()
                    
                    if valid_setups.empty:
                        st.warning("No hay suficientes datos para generar un ranking con esos filtros.")
                    else:
                        valid_setups = valid_setups.sort_values('Win Rate %', ascending=False)
                        
                        col_top, col_worst = st.columns(2)
                        with col_top:
                            st.success("### 🟢 Top 5 Mejores")
                            st.dataframe(valid_setups.head(5), use_container_width=True)
                            
                        with col_worst:
                            st.error("### 🔴 Top 5 Peores (Trampas)")
                            st.dataframe(valid_setups.tail(5).sort_values('Win Rate %', ascending=True), use_container_width=True)

        # --- TAB 4: CALCULADORA MATRIZ ---
        with tab4:
            st.markdown("## 🧮 Calculadora de Probabilidades (Matriz Completa)")
            st.markdown("Evalúa la probabilidad histórica de ir Largo (Bull) o Corto (Bear) basándote en la alineación actual del mercado.")
            
            col_in1, col_in2 = st.columns(2)
            
            with col_in1:
                calc_sym = st.selectbox("Par (ALL para global):", options=['ALL'] + list(df['symbol'].unique()))
                calc_ltf = st.selectbox("Temporalidad a Operar (LTF):", options=['H12', 'H8', 'H4', 'D1'], index=2)
            
            with col_in2:
                calc_mn1 = st.selectbox("Estado actual MN1:", options=['Neutral', 'BULL', 'BEAR'])
                calc_w1 = st.selectbox("Estado actual W1:", options=['Neutral', 'BULL', 'BEAR'])
                calc_d1 = st.selectbox("Estado actual D1:", options=['Neutral', 'BULL', 'BEAR'])
                
            if st.button("Calcular Probabilidades"):
                with st.spinner("Procesando matriz..."):
                    df_calc_ltf = df[df['timeframe'] == calc_ltf]
                    if calc_sym != 'ALL':
                        df_calc_ltf = df_calc_ltf[df_calc_ltf['symbol'] == calc_sym]
                        
                    htfs_calc = ['MN1', 'W1', 'D1']
                    # Filtrar valid HTFs para el cálculo (no podemos usar D1 como HTF de D1)
                    htfs_calc = [h for h in htfs_calc if h != calc_ltf]
                    
                    df_calc_ctx = get_multi_htf_context(df_calc_ltf, df, htfs_calc)
                    
                    # Aplicar filtros de la calculadora
                    if 'MN1' in htfs_calc: df_calc_ctx = df_calc_ctx[df_calc_ctx['MN1'] == calc_mn1]
                    if 'W1' in htfs_calc: df_calc_ctx = df_calc_ctx[df_calc_ctx['W1'] == calc_w1]
                    if 'D1' in htfs_calc: df_calc_ctx = df_calc_ctx[df_calc_ctx['D1'] == calc_d1]
                    
                    # Resultados Bull vs Bear
                    bull_trades = df_calc_ctx[df_calc_ctx['direction'] == 'BULL']
                    bear_trades = df_calc_ctx[df_calc_ctx['direction'] == 'BEAR']
                    
                    t_bull = len(bull_trades)
                    w_bull = bull_trades['is_win'].sum()
                    wr_bull = (w_bull/t_bull*100) if t_bull > 0 else 0
                    
                    t_bear = len(bear_trades)
                    w_bear = bear_trades['is_win'].sum()
                    wr_bear = (w_bear/t_bear*100) if t_bear > 0 else 0
                    
                    c_res1, c_res2 = st.columns(2)
                    
                    with c_res1:
                        st.info("### 🟢 PROBABILIDAD BULL")
                        st.metric("Win Rate", f"{wr_bull:.1f}%", f"{t_bull} trades totales")
                        
                    with c_res2:
                        st.warning("### 🔴 PROBABILIDAD BEAR")
                        st.metric("Win Rate", f"{wr_bear:.1f}%", f"{t_bear} trades totales")
                        
                    if wr_bull > wr_bear and t_bull > 0:
                        st.success("🌟 **Dirección Estadística Óptima: COMPRAS (BULL)**")
                    elif wr_bear > wr_bull and t_bear > 0:
                        st.success("🌟 **Dirección Estadística Óptima: VENTAS (BEAR)**")
                    else:
                        st.write("No hay una ventaja estadística clara con los datos actuales o falta volumen de trades.")

except Exception as e:
    st.error(f"Error conectando a la base de datos o cargando datos: {e}")
