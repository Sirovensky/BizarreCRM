import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../../.env') });
// Also try loading from root
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

export const config = {
  port: parseInt(process.env.PORT || '3020'),
  host: process.env.HOST || '0.0.0.0',
  jwtSecret: (() => {
    const secret = process.env.JWT_SECRET;
    const env = process.env.NODE_ENV || 'development';
    if (!secret && env === 'production') {
      console.error('\n  ⚠️  FATAL: JWT_SECRET environment variable is required in production!\n');
      process.exit(1);
    }
    if (!secret || secret === 'dev-secret-change-me') {
      console.warn('\n  ⚠️  WARNING: Using default JWT secret. Set JWT_SECRET env var for production.\n');
    }
    return secret || 'dev-secret-change-me';
  })(),
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET || (process.env.JWT_SECRET ? process.env.JWT_SECRET + '-refresh' : 'dev-refresh-secret'),
  nodeEnv: process.env.NODE_ENV || 'development',
  dbPath: path.resolve(__dirname, '../data/bizarre-crm.db'),
  uploadsPath: path.resolve(__dirname, '../uploads'),
  store: {
    name: process.env.STORE_NAME || 'Bizarre Electronics',
    phone: process.env.STORE_PHONE || '+13032611911',
    email: process.env.STORE_EMAIL || '',
    address: process.env.STORE_ADDRESS || '',
    timezone: process.env.STORE_TIMEZONE || 'America/Denver',
  },
  tcx: {
    host: process.env.TCX_HOST || '',
    username: process.env.TCX_USERNAME || '',
    password: process.env.TCX_PASSWORD || '',
    extension: process.env.TCX_EXTENSION || '2380',
    storeNumber: process.env.TCX_STORE_NUMBER || '+13032611911',
  },
  smtp: {
    host: process.env.SMTP_HOST || '',
    port: parseInt(process.env.SMTP_PORT || '587'),
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    from: process.env.SMTP_FROM || '',
  },
  repairdesk: {
    apiKey: process.env.RD_API_KEY || '',
    apiUrl: process.env.RD_API_URL || 'https://api.repairdesk.co/api/web/v1',
  },
  sms: {
    provider: process.env.SMS_PROVIDER || 'console', // 'twilio', 'telnyx', 'console'
    twilio: {
      accountSid: process.env.TWILIO_ACCOUNT_SID || '',
      authToken: process.env.TWILIO_AUTH_TOKEN || '',
      fromNumber: process.env.TWILIO_FROM_NUMBER || '',
    },
    telnyx: {
      apiKey: process.env.TELNYX_API_KEY || '',
      fromNumber: process.env.TELNYX_FROM_NUMBER || '',
    },
  },
};
