const sql = require('mssql/msnodesqlv8');
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const DB_NAME = process.env.DB_NAME || 'PortfolioDB';
const DB_SERVER = process.env.DB_SERVER || 'localhost';

const masterConfig = {
    connectionString: `Driver={ODBC Driver 18 for SQL Server};Server=${DB_SERVER};Database=master;Trusted_Connection=Yes;Encrypt=No;`
};

const dbConfig = {
    connectionString: `Driver={ODBC Driver 18 for SQL Server};Server=${DB_SERVER};Database=${DB_NAME};Trusted_Connection=Yes;Encrypt=No;`
};

async function initDatabase() {
    let pool;

    try {
        console.log('🔄 Connecting to SQL Server (master)...');
        pool = await sql.connect(masterConfig);

        console.log(`📦 Creating database [${DB_NAME}] if not exists...`);
        await pool.request().query(`
            IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '${DB_NAME}')
            BEGIN
                CREATE DATABASE [${DB_NAME}]
            END
        `);
        console.log(`✅ Database [${DB_NAME}] is ready`);

        await pool.close();

        console.log(`🔄 Connecting to [${DB_NAME}]...`);
        pool = await sql.connect(dbConfig);

        console.log('📋 Creating ContactMessages table...');
        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ContactMessages')
            BEGIN
                CREATE TABLE ContactMessages (
                    id          INT IDENTITY(1,1) PRIMARY KEY,
                    name        NVARCHAR(255)   NOT NULL,
                    email       NVARCHAR(255)   NOT NULL,
                    message     NVARCHAR(MAX)   NOT NULL,
                    created_at  DATETIME2       DEFAULT GETDATE()
                )
            END
        `);
        console.log('✅ ContactMessages table is ready');

        console.log('📋 Creating Visitors table...');
        await pool.request().query(`
            IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Visitors')
            BEGIN
                CREATE TABLE Visitors (
                    id          INT IDENTITY(1,1) PRIMARY KEY,
                    page        NVARCHAR(255)   DEFAULT '/',
                    ip_address  NVARCHAR(45),
                    user_agent  NVARCHAR(500),
                    visited_at  DATETIME2       DEFAULT GETDATE()
                )
            END
        `);
        console.log('✅ Visitors table is ready');

        console.log('\n🎉 Database initialization complete!');
        console.log(`   Database : ${DB_NAME}`);
        console.log('   Tables   : ContactMessages, Visitors');

    } catch (err) {
        console.error('❌ Database initialization failed:', err.message || JSON.stringify(err));
        process.exit(1);
    } finally {
        if (pool) await pool.close();
        process.exit(0);
    }
}

initDatabase();
