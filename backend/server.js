const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const errorHandler = require('./middleware/errorHandler');
const contactRoutes = require('./routes/contact.routes');
const visitorRoutes = require('./routes/visitor.routes');
const healthRoutes = require('./routes/health.routes');

const app = express();
const PORT = process.env.PORT || 3000;

// ===== MIDDLEWARE =====
app.use(cors());
app.use(express.json());

// Serve the portfolio frontend
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// ===== API ROUTES =====
app.use('/api', healthRoutes);
app.use('/api', contactRoutes);
app.use('/api', visitorRoutes);

// ===== ERROR HANDLER =====
app.use(errorHandler);

// ===== START SERVER =====
app.listen(PORT, () => {
    console.log(`\n🚀 Portfolio Backend is running!`);
    console.log(`   Portfolio: http://localhost:${PORT}`);
    console.log(`   Health:    http://localhost:${PORT}/api/health`);
    console.log(`   API Docs:`);
    console.log(`     POST /api/contact        — Submit contact message`);
    console.log(`     GET  /api/messages        — List all messages`);
    console.log(`     POST /api/visitors        — Track a visit`);
    console.log(`     GET  /api/visitors/count  — Total visitor count\n`);
});

// Graceful shutdown
process.on('SIGINT', async () => {
    const { closePool } = require('./config/db');
    await closePool();
    process.exit(0);
});
