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
    
    # Filtros
    st.sidebar.header("Filtros")
    selected_symbols = st.sidebar.multiselect("Símbolo", options=df['symbol'].unique(), default=df['symbol'].unique())
    selected_timeframes = st.sidebar.multiselect("Timeframe", options=df['timeframe'].unique(), default=df['timeframe'].unique())
    
    # Aplicar filtros
    filtered_df = df[
        (df['symbol'].isin(selected_symbols)) & 
        (df['timeframe'].isin(selected_timeframes))
    ]
    
    # KPIs
    col1, col2, col3, col4 = st.columns(4)
    total_trades = len(filtered_df)
    
    # Calcular Win Rate asumiendo que result_type 'TP_EXPANSION' es ganadora y 'SL' es perdedora
    # Ajustar según la lógica exacta de result_type
    wins = filtered_df[filtered_df['result_type'] == 'TP_EXPANSION'].shape[0]
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

except Exception as e:
    st.error(f"Error conectando a la base de datos o cargando datos: {e}")
