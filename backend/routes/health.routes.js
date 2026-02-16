const express = require('express');
const router = express.Router();
const { getPool } = require('../config/db');

router.get('/health', async (req, res) => {
    try {
        const pool = await getPool();
        await pool.request().query('SELECT 1');
        res.json({ status: 'ok', database: 'connected', timestamp: new Date().toISOString() });
    } catch (err) {
        res.status(500).json({ status: 'error', database: 'disconnected', error: err.message });
    }
});

module.exports = router;
