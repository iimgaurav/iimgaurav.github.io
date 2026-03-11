const sql = require('mssql/msnodesqlv8');
require('dotenv').config();

const config = {
    connectionString: `Driver={ODBC Driver 18 for SQL Server};Server=${process.env.DB_SERVER || 'localhost'};Database=${process.env.DB_NAME || 'PortfolioDB'};Trusted_Connection=Yes;Encrypt=No;`
};

let pool;

async function getPool() {
    if (!pool) {
        pool = await sql.connect(config);
        console.log('✅ Connected to SQL Server');
    }
    return pool;
}

async function closePool() {
    if (pool) {
        await pool.close();
        pool = null;
        console.log('🔌 SQL Server connection closed');
    }
}

module.exports = { sql, getPool, closePool };
