const express = require('express');
const router = express.Router();
const { createMessage, listMessages } = require('../controllers/contact.controller');

router.post('/contact', createMessage);
router.get('/messages', listMessages);

module.exports = router;
