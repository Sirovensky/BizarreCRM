import nodemailer from 'nodemailer';
import { config } from '../config.js';

let transporter: nodemailer.Transporter | null = null;

function getTransporter(): nodemailer.Transporter | null {
  if (transporter) return transporter;
  const { host, port, user, pass, from } = config.smtp;
  if (!host || !user) return null;

  transporter = nodemailer.createTransport({
    host,
    port: parseInt(String(port), 10) || 587,
    secure: parseInt(String(port), 10) === 465,
    auth: { user, pass },
  });
  return transporter;
}

export interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export async function sendEmail(opts: SendEmailOptions): Promise<boolean> {
  const t = getTransporter();
  if (!t) {
    console.warn('[Email] SMTP not configured — skipping email');
    return false;
  }

  try {
    await t.sendMail({
      from: config.smtp.from || config.smtp.user,
      to: opts.to,
      subject: opts.subject,
      html: opts.html,
      text: opts.text || opts.html.replace(/<[^>]+>/g, ''),
    });
    console.log(`[Email] Sent to ${opts.to}: ${opts.subject}`);
    return true;
  } catch (err) {
    console.error(`[Email] Failed to send to ${opts.to}:`, err);
    return false;
  }
}

export function isEmailConfigured(): boolean {
  return !!(config.smtp.host && config.smtp.user);
}
