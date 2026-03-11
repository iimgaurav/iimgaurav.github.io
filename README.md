# 🚀 Gaurav Kumar — Portfolio

Personal portfolio website with a Node.js/Express backend, SQL Server database, and contact form integration.

## Project Structure

```
portfolio/
├── frontend/                     # Static assets
│   ├── index.html
│   ├── css/style.css
│   └── js/script.js
├── backend/                      # Express API (MVC pattern)
│   ├── server.js                 # Entry point
│   ├── .env                      # Environment config
│   ├── config/db.js              # SQL Server connection
│   ├── routes/                   # Route definitions
│   │   ├── contact.routes.js
│   │   ├── visitor.routes.js
│   │   └── health.routes.js
│   ├── controllers/              # Business logic
│   │   ├── contact.controller.js
│   │   └── visitor.controller.js
│   ├── middleware/
│   │   └── errorHandler.js
│   └── scripts/
│       └── init-db.js            # Database setup
└── README.md
```

## Quick Start

```bash
# 1. Install dependencies
cd backend
npm install

# 2. Initialize database (one-time)
npm run init-db

# 3. Start server
npm start
```

Open **http://localhost:3000** to view the portfolio.

## API Endpoints

| Method | Endpoint              | Description               |
|--------|-----------------------|---------------------------|
| GET    | /api/health           | Health check              |
| POST   | /api/contact          | Submit contact message    |
| GET    | /api/messages         | List all messages         |
| POST   | /api/visitors         | Track a page visit        |
| GET    | /api/visitors/count   | Total visitor count       |

## Tech Stack

- **Frontend**: HTML, CSS, JavaScript
- **Backend**: Node.js, Express
- **Database**: SQL Server (Windows Auth)
