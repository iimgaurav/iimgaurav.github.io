const { sql, getPool } = require('../config/db');

// POST /api/contact — Submit a contact form message
async function createMessage(req, res) {
    try {
        const { name, email, message } = req.body;

        if (!name || !email || !message) {
            return res.status(400).json({ error: 'All fields (name, email, message) are required.' });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res.status(400).json({ error: 'Please provide a valid email address.' });
        }

        const pool = await getPool();
        const result = await pool.request()
            .input('name', sql.NVarChar(255), name.trim())
            .input('email', sql.NVarChar(255), email.trim())
            .input('message', sql.NVarChar(sql.MAX), message.trim())
            .query(`
                INSERT INTO ContactMessages (name, email, message)
                OUTPUT INSERTED.id, INSERTED.created_at
                VALUES (@name, @email, @message)
            `);

        const inserted = result.recordset[0];
        console.log(`📩 New message from ${name} <${email}> [id: ${inserted.id}]`);

        res.status(201).json({
            success: true,
            message: 'Thank you! Your message has been received.',
            id: inserted.id,
            created_at: inserted.created_at
        });
    } catch (err) {
        console.error('❌ Contact submission error:', err.message);
        res.status(500).json({ error: 'Something went wrong. Please try again later.' });
    }
}

// GET /api/messages — Retrieve all contact messages
async function listMessages(req, res) {
    try {
        const pool = await getPool();
        const result = await pool.request()
            .query('SELECT id, name, email, message, created_at FROM ContactMessages ORDER BY created_at DESC');

        res.json({
            total: result.recordset.length,
            messages: result.recordset
        });
    } catch (err) {
        console.error('❌ Messages fetch error:', err.message);
        res.status(500).json({ error: 'Failed to retrieve messages.' });
    }
}

module.exports = { createMessage, listMessages };
