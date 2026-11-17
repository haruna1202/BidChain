import dotenv from 'dotenv';
import express from 'express';
import mysql from 'mysql2/promise';
import multer from 'multer';
import path from 'node:path';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(here, '../.env.server') });
const app = express();
const port = Number(process.env.API_PORT || 4000);
const uploadDir = path.join(here, 'uploads');
// Multer requires its destination to exist before the first file is uploaded.
mkdirSync(uploadDir, { recursive: true });

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'pokevault',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

const storage = multer.diskStorage({
  destination: (_req, _file, done) => done(null, uploadDir),
  filename: (_req, file, done) => {
    const extension = path.extname(file.originalname).toLowerCase().slice(0, 12);
    done(null, `${Date.now()}-${randomUUID()}${extension}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 8 * 1024 * 1024, files: 3 },
  fileFilter: (_req, file, done) => {
    const valid = file.mimetype.startsWith('image/') || file.mimetype === 'application/pdf';
    done(valid ? null : new Error('Chỉ nhận file ảnh hoặc PDF.'), valid);
  },
});

app.use(express.json({ limit: '1mb' }));
app.use('/uploads', express.static(uploadDir, { fallthrough: false, maxAge: '1h' }));

app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, database: process.env.DB_NAME || 'pokevault' });
  } catch (error) {
    res.status(503).json({ ok: false, message: 'Không kết nối được MySQL.', detail: error.message });
  }
});

function shapeCard(row) {
  let profile = {};
  try { profile = JSON.parse(row.profile_json); } catch { /* malformed legacy record */ }
  return {
    chainCardId: String(row.chain_card_id),
    profileId: String(row.profile_id),
    sellerAddress: row.seller_address,
    name: row.name,
    set: row.set_name,
    issuer: row.issuer,
    grade: row.grade,
    certificate: row.certificate_number,
    certificateKey: row.certificate_key,
    metadataHash: row.metadata_hash,
    profile,
    imageUrls: {
      front: row.front_image_url,
      back: row.back_image_url,
      certificate: row.certificate_file_url,
    },
    transactionHash: row.transaction_hash,
    createdAt: row.created_at,
  };
}

app.get('/api/cards', async (req, res, next) => {
  try {
    const ids = String(req.query.chainCardIds || '').split(',').map(x => x.trim()).filter(Boolean);
    let rows;
    if (ids.length) {
      if (ids.length > 100 || ids.some(id => !/^\d+$/.test(id))) {
        return res.status(400).json({ message: 'Danh sách mã thẻ không hợp lệ.' });
      }
      const placeholders = ids.map(() => '?').join(',');
      [rows] = await pool.execute(
        `SELECT * FROM cards WHERE chain_card_id IN (${placeholders})`, ids,
      );
    } else {
      [rows] = await pool.query('SELECT * FROM cards ORDER BY created_at DESC LIMIT 100');
    }
    res.json(rows.map(shapeCard));
  } catch (error) { next(error); }
});

app.get('/api/cards/:chainCardId', async (req, res, next) => {
  try {
    if (!/^\d+$/.test(req.params.chainCardId)) return res.status(400).json({ message: 'Mã thẻ không hợp lệ.' });
    const [rows] = await pool.execute('SELECT * FROM cards WHERE chain_card_id = ? LIMIT 1', [req.params.chainCardId]);
    if (!rows.length) return res.status(404).json({ message: 'Chưa có hồ sơ thẻ trong MySQL.' });
    res.json(shapeCard(rows[0]));
  } catch (error) { next(error); }
});

app.post('/api/cards', upload.fields([
  { name: 'front', maxCount: 1 },
  { name: 'back', maxCount: 1 },
  { name: 'certificateFile', maxCount: 1 },
]), async (req, res, next) => {
  try {
    const { chainCardId, profileId, sellerAddress, profileJson, metadataHash, certificateKey, transactionHash } = req.body;
    if (!/^\d+$/.test(String(chainCardId || '')) || !/^\d+$/.test(String(profileId || ''))) {
      return res.status(400).json({ message: 'Thiếu mã thẻ hoặc mã hồ sơ hợp lệ.' });
    }
    if (!/^0x[\da-fA-F]{40}$/.test(String(sellerAddress || ''))) {
      return res.status(400).json({ message: 'Địa chỉ ví người bán không hợp lệ.' });
    }
    const files = req.files || {};
    if (!files.front?.[0] || !files.back?.[0] || !files.certificateFile?.[0]) {
      return res.status(400).json({ message: 'Cần đủ ảnh mặt trước, mặt sau và file chứng nhận.' });
    }
    let profile;
    try { profile = JSON.parse(profileJson); } catch {
      return res.status(400).json({ message: 'Thông tin hồ sơ không đúng định dạng JSON.' });
    }
    const url = file => file ? `/uploads/${file.filename}` : null;
    await pool.execute(
      `INSERT INTO cards
        (chain_card_id, profile_id, seller_address, name, set_name, issuer, grade,
         certificate_number, certificate_key, metadata_hash, profile_json,
         front_image_url, back_image_url, certificate_file_url, transaction_hash)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         seller_address=VALUES(seller_address), name=VALUES(name), set_name=VALUES(set_name),
         issuer=VALUES(issuer), grade=VALUES(grade), certificate_number=VALUES(certificate_number),
         certificate_key=VALUES(certificate_key), metadata_hash=VALUES(metadata_hash),
         profile_json=VALUES(profile_json), front_image_url=VALUES(front_image_url),
         back_image_url=VALUES(back_image_url), certificate_file_url=VALUES(certificate_file_url),
         transaction_hash=VALUES(transaction_hash)`,
      [chainCardId, profileId, sellerAddress, profile.name, profile.set || '', profile.issuer,
        profile.grade, profile.certificate, certificateKey, metadataHash, JSON.stringify(profile),
        url(files.front[0]), url(files.back[0]), url(files.certificateFile[0]), transactionHash || null],
    );
    const [rows] = await pool.execute('SELECT * FROM cards WHERE chain_card_id = ? LIMIT 1', [chainCardId]);
    res.status(201).json(shapeCard(rows[0]));
  } catch (error) { next(error); }
});

app.use((error, _req, res, _next) => {
  const status = error instanceof multer.MulterError ? 400 : 500;
  res.status(status).json({ message: error.message || 'Lỗi máy chủ.' });
});

app.listen(port, () => console.log(`PokéVault API đang chạy tại http://localhost:${port}`));
