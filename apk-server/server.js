const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 8080;
const APK_DIR = path.join(__dirname, 'apk');

// Serve download page at root
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// Main download link: /download/thesunpoker.apk
app.get('/download/:filename', (req, res) => {
  const filename = req.params.filename;
  const filePath = path.join(APK_DIR, filename);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'File not found' });
  }

  const stat = fs.statSync(filePath);

  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Content-Length', stat.size);
  res.setHeader('Cache-Control', 'no-cache');

  console.log(`[${new Date().toISOString()}] Download: ${filename} (${(stat.size / 1024 / 1024).toFixed(1)} MB) from ${req.ip}`);

  const stream = fs.createReadStream(filePath);
  stream.pipe(res);
});

// Health check
app.get('/health', (req, res) => {
  const apks = fs.readdirSync(APK_DIR).filter(f => f.endsWith('.apk'));
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    apks: apks.map(f => ({
      name: f,
      url: `/download/${f}`,
      size: `${(fs.statSync(path.join(APK_DIR, f)).size / 1024 / 1024).toFixed(1)} MB`
    }))
  });
});

app.listen(PORT, () => {
  console.log(`🃏 The Sun Poker APK Server running on port ${PORT}`);
  console.log(`📱 Download: http://localhost:${PORT}/download/thesunpoker.apk`);
  console.log(`❤️  Health:   http://localhost:${PORT}/health`);
});
