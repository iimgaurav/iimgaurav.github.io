const functions = require("firebase-functions");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");

admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// ===== HEALTH CHECK =====
app.get("/health", (req, res) => {
    res.json({
        status: "ok",
        database: "firestore",
        timestamp: new Date().toISOString(),
    });
});

// ===== CONTACT: Submit Message =====
app.post("/contact", async (req, res) => {
    try {
        const { name, email, message } = req.body;

        if (!name || !email || !message) {
            return res
                .status(400)
                .json({ error: "All fields (name, email, message) are required." });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res
                .status(400)
                .json({ error: "Please provide a valid email address." });
        }

        const docRef = await db.collection("contactMessages").add({
            name: name.trim(),
            email: email.trim(),
            message: message.trim(),
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`📩 New message from ${name} <${email}> [id: ${docRef.id}]`);

        res.status(201).json({
            success: true,
            message: "Thank you! Your message has been received.",
            id: docRef.id,
        });
    } catch (err) {
        console.error("❌ Contact error:", err);
        res
            .status(500)
            .json({ error: "Something went wrong. Please try again later." });
    }
});

// ===== MESSAGES: List All =====
app.get("/messages", async (req, res) => {
    try {
        const snapshot = await db
            .collection("contactMessages")
            .orderBy("created_at", "desc")
            .get();

        const messages = snapshot.docs.map((doc) => ({
            id: doc.id,
            ...doc.data(),
            created_at: doc.data().created_at
                ? doc.data().created_at.toDate().toISOString()
                : null,
        }));

        res.json({ total: messages.length, messages });
    } catch (err) {
        console.error("❌ Messages error:", err);
        res.status(500).json({ error: "Failed to retrieve messages." });
    }
});

// ===== VISITORS: Track Visit =====
app.post("/visitors", async (req, res) => {
    try {
        const page = req.body.page || "/";
        const ip = req.headers["x-forwarded-for"] || req.ip || "unknown";
        const userAgent = (req.headers["user-agent"] || "unknown").substring(
            0,
            500
        );

        await db.collection("visitors").add({
            page,
            ip_address: ip,
            user_agent: userAgent,
            visited_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        res.status(201).json({ success: true });
    } catch (err) {
        console.error("❌ Visitor error:", err);
        res.status(500).json({ error: "Failed to track visit." });
    }
});

// ===== VISITORS: Count =====
app.get("/visitors/count", async (req, res) => {
    try {
        const snapshot = await db.collection("visitors").count().get();
        res.json({ total: snapshot.data().count });
    } catch (err) {
        console.error("❌ Count error:", err);
        res.status(500).json({ error: "Failed to get visitor count." });
    }
});

// Export as single Cloud Function
exports.api = functions.https.onRequest(app);
