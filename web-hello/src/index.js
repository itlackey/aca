const express = require('express');

const app = express();

// Configuration from environment variables.  These can be supplied via
// Container Apps secrets or plain env variables in your YAML.
const port = process.env.PORT || 3000;
const environment = process.env.ENVIRONMENT || 'development';
const dbConnectionString = process.env.DB_CONNECTION_STRING || '';

// Root endpoint returns a JSON payload with diagnostic information
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Azure Container Apps!',
    environment,
    timestamp: new Date().toISOString(),
  });
});

// Simple health endpoint used by the liveness probe
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Start the server
app.listen(port, () => {
  console.log(`web-hello listening on port ${port} in ${environment} mode`);
  if (dbConnectionString) {
    console.log('Database connection string provided (not used in this demo)');
  }
});