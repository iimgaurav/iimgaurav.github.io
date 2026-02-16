const { sql, getPool } = require('../config/db');

// POST /api/visitors — Track a page visit
async function trackVisit(req, res) {
    try {
        const page = req.body.page || '/';
        const ip_address = req.ip || req.headers['x-forwarded-for'] || 'unknown';
        const user_agent = (req.headers['user-agent'] || 'unknown').substring(0, 500);

        const pool = await getPool();
        await pool.request()
            .input('page', sql.NVarChar(255), page)
            .input('ip', sql.NVarChar(45), ip_address)
            .input('ua', sql.NVarChar(500), user_agent)
            .query('INSERT INTO Visitors (page, ip_address, user_agent) VALUES (@page, @ip, @ua)');

        res.status(201).json({ success: true });
    } catch (err) {
        console.error('❌ Visitor tracking error:', err.message);
        res.status(500).json({ error: 'Failed to track visit.' });
    }
}

// GET /api/visitors/count — Get total visitor count
async function getCount(req, res) {
    try {
        const pool = await getPool();
        const result = await pool.request()
            .query('SELECT COUNT(*) AS total FROM Visitors');

        res.json({ total: result.recordset[0].total });
    } catch (err) {
        console.error('❌ Visitor count error:', err.message);
        res.status(500).json({ error: 'Failed to get visitor count.' });
    }
}

module.exports = { trackVisit, getCount };
