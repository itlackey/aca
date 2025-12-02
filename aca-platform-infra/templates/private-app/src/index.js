const http = require('http');

const PORT = process.env.PORT || 3000;
const HOSTNAME = process.env.HOSTNAME || 'unknown';

// Simple in-memory request counter
let requestCount = 0;

const server = http.createServer((req, res) => {
  const now = new Date().toISOString();

  // Health check endpoint
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', timestamp: now }));
    return;
  }

  // Readiness check endpoint
  if (req.url === '/ready') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ready', timestamp: now }));
    return;
  }

  // Main endpoint
  requestCount++;

  const response = {
    message: 'Hello from private app (VNet only)',
    timestamp: now,
    hostname: HOSTNAME,
    requestNumber: requestCount,
    environment: process.env.NODE_ENV || 'development',
    headers: {
      'x-forwarded-for': req.headers['x-forwarded-for'] || 'not set',
      'x-request-id': req.headers['x-request-id'] || 'not set',
    },
  };

  console.log(`[${now}] Request #${requestCount} from ${req.headers['x-forwarded-for'] || 'unknown'}`);

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response, null, 2));
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Ready check:  http://localhost:${PORT}/ready`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
