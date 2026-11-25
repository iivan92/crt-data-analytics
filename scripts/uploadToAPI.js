import fs from 'fs';
import readline from 'readline';

const API_URL = 'http://localhost:3000/api/v1/trades';
const FILE_PATH = process.argv[2];

if (!FILE_PATH) {
  console.error('Por favor, proporciona la ruta del archivo JSONL.');
  console.error('Uso: node uploadToAPI.js <ruta_al_archivo_jsonl>');
  process.exit(1);
}

async function processLineByLine() {
  const fileStream = fs.createReadStream(FILE_PATH);

  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  let successCount = 0;
  let errorCount = 0;

  for await (const line of rl) {
    if (!line.trim()) continue;

    try {
      const tradeData = JSON.parse(line);
      
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(tradeData)
      });

      if (response.ok) {
        successCount++;
        process.stdout.write(`\rEnviados: ${successCount} | Errores: ${errorCount}`);
      } else {
        const errorData = await response.json();
        console.error('\nError en la API:', errorData);
        errorCount++;
      }
    } catch (error) {
      console.error('\nError al procesar línea:', error);
      errorCount++;
    }
  }

  console.log(`\n\nProceso completado. Exitosos: ${successCount}, Fallidos: ${errorCount}`);
}

processLineByLine();
