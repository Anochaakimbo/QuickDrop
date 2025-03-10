const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const mysql = require('mysql2/promise');
const path = require('path');

const app = express();
require("dotenv").config();

app.use(cors());
app.use(bodyParser.json());

// ✅ ให้บริการไฟล์ Dashboard.html
app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'Dashboard.html'));
});

// ✅ API ตรวจสอบว่าเซิร์ฟเวอร์ทำงานอยู่
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'Server is running' });
});

// ✅ ตั้งค่าการเชื่อมต่อ MySQL
const db = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_DATABASE,
  port: process.env.DB_PORT,
});

// ✅ สร้างตาราง Logs ถ้ายังไม่มี
(async () => {
  await db.execute(`
    CREATE TABLE IF NOT EXISTS logs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      senderName VARCHAR(255),
      senderIp VARCHAR(50),
      receiverName VARCHAR(255),
      receiverIp VARCHAR(50),
      fileName VARCHAR(255),
      fileSize INT,
      fileType VARCHAR(50),
      timestamp DATETIME,
      successful BOOLEAN
    )
  `);
})();

// ✅ API รับ Log และบันทึกลงฐานข้อมูล
app.post('/api/logs', async (req, res) => {
  try {
    const log = req.body;
    log.timestamp = log.timestamp || new Date().toISOString();

    await db.execute(
      `INSERT INTO logs (senderName, senderIp, receiverName, receiverIp, fileName, fileSize, fileType, timestamp, successful) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        log.senderName, log.senderIp, log.receiverName, log.receiverIp,
        log.fileName, log.fileSize, log.fileType, log.timestamp, log.successful
      ]
    );

    console.log('✅ New Log:', log);
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Error saving log:', error);
    res.status(500).json({ success: false, error });
  }
});

// ✅ API ดึง Logs ล่าสุดจากฐานข้อมูล
app.get('/api/logs', async (req, res) => {
  try {
    const [logs] = await db.execute('SELECT * FROM logs ORDER BY timestamp DESC LIMIT 100');
    res.json(logs);
  } catch (error) {
    console.error('❌ Error fetching logs:', error);
    res.status(500).json({ success: false, error });
  }
});

// ✅ Start Server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Server running on http://localhost:${PORT}`));
