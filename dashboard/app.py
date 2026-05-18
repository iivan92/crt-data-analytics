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
@st.cache_data(ttl=600) # cache for 10 minutos
def load_data():
    engine = init_connection()
    query = """
    SELECT symbol, timeframe, direction, entry_time, exit_time, result_type, mae, mfe 
    FROM crt_trades;
    """
    df = pd.read_sql(query, engine)
    return df

try:
    with st.spinner('Cargando datos desde la base de datos...'):
        df = load_data()
        
    st.success(f"Datos cargados correctamente: {len(df)} operaciones.")
    
    # Asegurar que las fechas son datetime para comparaciones
    df['entry_time'] = pd.to_datetime(df['entry_time'])
    df['exit_time'] = pd.to_datetime(df['exit_time'])
    
    # Crear pestañas para el dashboard
    tab1, tab2 = st.tabs(["📊 Análisis General", "🔄 Análisis Multi-Temporal (HTF Context)"])
    
    with tab1:
        # --- FILTROS TAB 1 ---
        st.sidebar.header("Filtros Generales")
        selected_symbols = st.sidebar.multiselect("Símbolo", options=df['symbol'].unique(), default=df['symbol'].unique(), key="sym_t1")
        selected_timeframes = st.sidebar.multiselect("Timeframe", options=df['timeframe'].unique(), default=df['timeframe'].unique(), key="tf_t1")
        
        # Aplicar filtros
        filtered_df = df[
            (df['symbol'].isin(selected_symbols)) & 
            (df['timeframe'].isin(selected_timeframes))
        ]
        
        # KPIs
        col1, col2, col3, col4 = st.columns(4)
        total_trades = len(filtered_df)
        
        # Calcular Win Rate asumiendo que result_type contiene 'TP_' es ganadora
        wins = filtered_df[filtered_df['result_type'].str.contains('TP_', na=False)].shape[0]
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
        
        col1.metric("Total Trades", total_trades)
        col2.metric("Win Rate (%)", f"{win_rate:.2f}%")
        
        # Gráficos
        st.markdown("### Resultados por Par y Timeframe")
        
        # Agrupar datos para gráfico de barras
        summary_df = filtered_df.groupby(['symbol', 'timeframe', 'result_type']).size().reset_index(name='count')
        
        fig1 = px.bar(
            summary_df, 
            x="symbol", 
            y="count", 
            color="result_type", 
            barmode="group",
            facet_col="timeframe",
            title="Distribución de Resultados por Par y Timeframe"
        )
        st.plotly_chart(fig1, use_container_width=True)
        
        # Mostrar tabla de datos brutos
        st.markdown("### Datos Crudos")
        st.dataframe(filtered_df.head(100))

    with tab2:
        st.markdown("## Análisis de Contexto Mayor (HTF)")
        st.markdown("Compara el rendimiento de los setups en un marco temporal menor (LTF) dependiendo de si están alineados o en contra de un marco temporal mayor (HTF).")
        
        if df.empty:
            st.warning("No hay datos suficientes para el análisis.")
        else:
            col_t1, col_t2, col_t3 = st.columns(3)
            with col_t1:
                analyze_symbol = st.selectbox("Símbolo a analizar:", options=df['symbol'].unique())
            with col_t2:
                ltf = st.selectbox("Timeframe Menor (LTF):", options=df['timeframe'].unique(), index=0)
            with col_t3:
                htf_options = [tf for tf in df['timeframe'].unique() if tf != ltf]
                htf = st.selectbox("Timeframe Mayor (HTF Contexto):", options=htf_options)
            
            # Filtrar datos por símbolo
            df_sym = df[df['symbol'] == analyze_symbol]
            
            df_ltf = df_sym[df_sym['timeframe'] == ltf].copy()
            df_htf = df_sym[df_sym['timeframe'] == htf].copy()
            
            if df_ltf.empty or df_htf.empty:
                st.info(f"No hay suficientes datos de {ltf} o {htf} para cruzar.")
            else:
                # Lógica de cruce a posteriori
                # Para cada trade LTF, buscar si había un trade HTF activo
                def get_htf_context(row):
                    # Un trade HTF está activo si el entry_time del LTF cae entre el entry_time y exit_time del HTF
                    active_htf = df_htf[
                        (df_htf['entry_time'] <= row['entry_time']) & 
                        (df_htf['exit_time'] >= row['entry_time'])
                    ]
                    
                    if active_htf.empty:
                        return "SIN CONTEXTO"
                    
                    # Tomar el más reciente activo (por si hubiera solapamiento anómalo)
                    htf_direction = active_htf.sort_values(by='entry_time', ascending=False).iloc[0]['direction']
                    
                    if htf_direction == row['direction']:
                        return "ALINEADO"
                    else:
                        return "EN CONTRA (REVERSIÓN)"
                
                df_ltf['htf_alignment'] = df_ltf.apply(get_htf_context, axis=1)
                
                # Calcular Win Rates por alineación
                st.markdown(f"### Resultados en **{ltf}** condicionados por **{htf}** ({analyze_symbol})")
                
                # Agrupar y calcular
                context_summary = []
                for alignment in ["ALINEADO", "EN CONTRA (REVERSIÓN)", "SIN CONTEXTO"]:
                    subset = df_ltf[df_ltf['htf_alignment'] == alignment]
                    total = len(subset)
                    if total > 0:
                        wins = subset[subset['result_type'].str.contains('TP_', na=False)].shape[0]
                        sl = subset[subset['result_type'] == 'SL'].shape[0]
                        win_rate = (wins / total) * 100
                        context_summary.append({
                            "Contexto HTF": alignment,
                            "Total Trades": total,
                            "Ganadoras (TP)": wins,
                            "Perdedoras (SL)": sl,
                            "Win Rate %": round(win_rate, 2)
                        })
                
                if context_summary:
                    ctx_df = pd.DataFrame(context_summary)
                    
                    # Mostrar métricas destacadas
                    col_m1, col_m2 = st.columns(2)
                    
                    aligned_data = ctx_df[ctx_df['Contexto HTF'] == 'ALINEADO']
                    counter_data = ctx_df[ctx_df['Contexto HTF'] == 'EN CONTRA (REVERSIÓN)']
                    
                    with col_m1:
                        st.info("**Operaciones ALINEADAS al HTF**")
                        if not aligned_data.empty:
                            st.metric("Win Rate", f"{aligned_data.iloc[0]['Win Rate %']}%", f"{aligned_data.iloc[0]['Total Trades']} trades")
                        else:
                            st.write("Sin datos")
                            
                    with col_m2:
                        st.warning("**Operaciones EN CONTRA del HTF**")
                        if not counter_data.empty:
                            st.metric("Win Rate", f"{counter_data.iloc[0]['Win Rate %']}%", f"{counter_data.iloc[0]['Total Trades']} trades")
                        else:
                            st.write("Sin datos")
                            
                    # Gráfico comparativo
                    fig2 = px.bar(
                        ctx_df, 
                        x="Contexto HTF", 
                        y="Win Rate %", 
                        color="Contexto HTF",
                        text="Win Rate %",
                        title=f"Comparativa de Win Rate en {ltf} según contexto {htf}",
                        color_discrete_map={
                            "ALINEADO": "green",
                            "EN CONTRA (REVERSIÓN)": "orange",
                            "SIN CONTEXTO": "gray"
                        }
                    )
                    fig2.update_traces(texttemplate='%{text}%', textposition='outside')
                    st.plotly_chart(fig2, use_container_width=True)
                    
                    st.dataframe(ctx_df, use_container_width=True)
                    
                    st.markdown("#### Detalle de Trades LTF con su contexto")
                    display_cols = ['entry_time', 'direction', 'result_type', 'htf_alignment']
                    st.dataframe(df_ltf[display_cols].sort_values('entry_time', ascending=False).head(50))

except Exception as e:
    st.error(f"Error conectando a la base de datos o cargando datos: {e}")
