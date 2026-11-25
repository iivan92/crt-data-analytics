Prototipo FXR - crt_liquidez

Qué incluye

- `crt_liquidez_fxr.js`: prototipo Node.js que replica la lógica central de `get_crt_info` del indicador Pine.

Cómo usar

- En la carpeta `fxr_prototype` ejecutar:

```bash
node crt_liquidez_fxr.js
```

Objetivo

- Facilitar portar la lógica a FXR Script: la función `getCrtInfo` implementa detección de `B.SWP`/`S.SWP`/`B.RUN`/`S.RUN` y cálculo de niveles `t1`/`t2`.

Siguientes pasos sugeridos

- Reemplazar los `sample` por series reales desde FXR (o fuente de datos) y mapear `request.security` a la función equivalente en FXR.
- Implementar visuales (líneas/labels/tablas) usando las APIs de FXR.
- Probar con los `Win%` embebidos o llamando a una API/JSON para mostrar `BASE WR`.
