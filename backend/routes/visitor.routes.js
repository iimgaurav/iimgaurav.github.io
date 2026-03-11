const express = require('express');
const router = express.Router();
const { trackVisit, getCount } = require('../controllers/visitor.controller');

router.post('/visitors', trackVisit);
router.get('/visitors/count', getCount);

module.exports = router;
