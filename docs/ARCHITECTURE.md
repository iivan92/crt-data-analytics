# Arquitectura del Sistema y Estándares de Código

## 1. Stack Tecnológico

- **Extracción de Datos (Windows):** Python (librería `MetaTrader5`, `pandas`, `requests`). Un servicio programado que lee los datos directamente de los terminales MT5, procesa la lógica CRT y envía JSONs a la API.
- **Ingesta (Backend Linux):** Node.js con Express.js.
- **Base de Datos (Linux):** PostgreSQL optimizado para series temporales (TimescaleDB).
- **Análisis de Datos:** Python (Pandas, SQLAlchemy) / Grafana.
- **Infraestructura:** Docker y Docker Compose para orquestación en servidor Linux.

## 2. Estándares de Desarrollo Backend (Node.js)

Copilot debe adherirse a las siguientes convenciones al escribir código JS:

- **Módulos:** Usar ES6 Modules (`import`/`export`).
- **Arquitectura:** Patrón MVC / Clean Architecture. Separar Rutas, Controladores y Servicios. Las peticiones a DB solo ocurren en la capa de Servicios.
- **Asincronía:** Usar `async/await` estrictamente. No usar promesas anidadas (`.then()`).
- **Manejo de Errores:** Centralizado mediante un _middleware_. Todas las funciones del controlador deben estar envueltas en un bloque `try/catch`.
- **Validación:** Validar los payloads de entrada (MT5 Webhooks) antes de tocar la base de datos.
- **Datos Dinámicos (JSONB):** Los campos `htf_context` y `metadata` deben ser tratados de forma segura. Si el cliente no los envía, el backend debe asignarles un objeto vacío `{}` por defecto.

## 3. Estándares de Base de Datos

- Usar nomenclatura _snake_case_ para tablas y columnas.
- Tratar los datos de trading como series temporales. El campo `entry_time` es el eje principal.

## 4. Orquestación (Docker)

- Todo componente debe tener su propio `Dockerfile` o configuración limpia.
- Un archivo `docker-compose.yml` en la raíz unirá todos los servicios (node_api, postgres_db, grafana).
