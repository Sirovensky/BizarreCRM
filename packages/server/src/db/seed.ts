import { db } from './connection.js';
import bcrypt from 'bcryptjs';
import { DEFAULT_TICKET_STATUSES } from '@bizarre-crm/shared';

export function seedDatabase(): void {
  console.log('Seeding database...');

  const seed = db.transaction(() => {
    // Ticket statuses
    const insertStatus = db.prepare(`
      INSERT OR IGNORE INTO ticket_statuses (name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    for (const s of DEFAULT_TICKET_STATUSES) {
      insertStatus.run(s.name, s.color, s.sort_order, s.is_default ? 1 : 0, s.is_closed ? 1 : 0, s.is_cancelled ? 1 : 0, 0);
    }

    // Tax classes
    db.prepare(`INSERT OR IGNORE INTO tax_classes (name, rate, is_default) VALUES (?, ?, ?)`).run('Colorado Sales Tax', 8.865, 1);
    db.prepare(`INSERT OR IGNORE INTO tax_classes (name, rate, is_default) VALUES (?, ?, ?)`).run('Tax Exempt', 0, 0);

    // Payment methods
    const insertPM = db.prepare(`INSERT OR IGNORE INTO payment_methods (name, is_active, sort_order) VALUES (?, 1, ?)`);
    insertPM.run('Cash', 0);
    insertPM.run('Credit Card', 1);
    insertPM.run('Debit Card', 2);
    insertPM.run('Other', 3);

    // Referral sources
    const insertRef = db.prepare(`INSERT OR IGNORE INTO referral_sources (name, sort_order) VALUES (?, ?)`);
    ['Walk-in', 'Google', 'Yelp', 'Facebook', 'Referral', 'Inbound Call', 'Website', 'Other'].forEach((name, i) => {
      insertRef.run(name, i);
    });

    // Admin user (skip if exists)
    const existing = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
    if (!existing) {
      const hash = bcrypt.hashSync('admin123', 12);
      const pinHash = bcrypt.hashSync('1234', 12);
      db.prepare(`
        INSERT INTO users (username, email, password_hash, pin, first_name, last_name, role)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run('admin', 'sirovensky@gmail.com', hash, pinHash, 'Pavel', 'Ivanov', 'admin');
    }

    // Store config
    const insertConfig = db.prepare(`INSERT OR IGNORE INTO store_config (key, value) VALUES (?, ?)`);
    insertConfig.run('store_name', 'BizarreElectronics.com');
    insertConfig.run('phone', '+13032611911');
    insertConfig.run('email', 'pavel@bizarreelectronics.com');
    insertConfig.run('address', '506 11th Ave, Longmont, Colorado 80501');
    insertConfig.run('timezone', 'America/Denver');
    insertConfig.run('currency', 'USD');
    insertConfig.run('sms_provider', 'tcx');
    insertConfig.run('hours', '9-3:30, 5-8 Monday-Friday, Weekends by appointment');
    insertConfig.run('stall_alert_days', '3');
    insertConfig.run('review_request_delay_hours', '24');
    insertConfig.run('store_phone', '+13032611911');
    insertConfig.run('store_address', '506 11th Ave, Longmont, CO 80501');
    insertConfig.run('receipt_terms', 'Please Read the Information below completely then fill out before submitting.\n\nI grant permission to Bizarre Electronics Repair to perform any action deemed necessary in an attempt to repair my device. Furthermore, I release Bizarre Electronics Repair from any liability for any data loss which may occur, or component failures occurring during attempted repair, testing, or at any other time. Bizarre Electronics Repair will attempt to reasonably accommodate in case of such failure/problem, offering reasonable repairs/discounts to resolve such incident, but does not guarantee any specific resolution.\n\nIn simpler terms, we will try our best to make you happy, if something goes wrong.\n\nAfter the device is repaired, customer has 30 days to pick it up. Any device is considered abandoned after that time and may be used for parts/refurbishments/resell per Bizarre Electronics Repair discretion.\n\nDeposits are non-refundable.\n\nFull terms available on BizarreElectronics.com');
    insertConfig.run('receipt_thermal_terms', 'Please Read the Information below completely then fill out before submitting.\n\nI grant permission to Bizarre Electronics Repair to perform any action deemed necessary in an attempt to repair my device. Furthermore, I release Bizarre Electronics Repair from any liability for any data loss which may occur, or component failures occurring during attempted repair, testing, or at any other time. Bizarre Electronics Repair will attempt to reasonably accommodate in case of such failure/problem, offering reasonable repairs/discounts to resolve such incident, but does not guarantee any specific resolution.\n\nIn simpler terms, we will try our best to make you happy, if something goes wrong.\n\nAfter the device is repaired, customer has 30 days to pick it up. Any device is considered abandoned after that time and may be used for parts/refurbishments/resell per Bizarre Electronics Repair discretion.\n\nDeposits are non-refundable.\n\nFull terms available on BizarreElectronics.com');
    insertConfig.run('receipt_footer', 'Thank you for choosing BizarreElectronics.com! Questions? Call us at +1 303-261-1911');
    insertConfig.run('receipt_thermal_footer', 'Thank you for choosing BizarreElectronics.com! Questions? Call us at +1 303-261-1911');
    insertConfig.run('receipt_default_size', 'receipt80');

    // SMS Templates
    const insertTpl = db.prepare(`INSERT OR IGNORE INTO sms_templates (name, content, category) VALUES (?, ?, ?)`);
    insertTpl.run('Device Ready for Pickup', 'Hi {{customer_name}}, your {{device_name}} is ready for pickup at Bizarre Electronics! Come by during business hours. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Waiting for Parts', 'Hi {{customer_name}}, we\'ve ordered the part needed for your {{device_name}} (Ticket #{{ticket_id}}). We\'ll text you when it arrives! Reply STOP to opt out.', 'status_update');
    insertTpl.run('Parts Arrived', 'Hi {{customer_name}}, the part for your {{device_name}} has arrived! Bring it in and we\'ll get started right away. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Repair Complete', 'Great news, {{customer_name}}! Your {{device_name}} repair is complete. Total: ${{total}}. Come pick it up anytime. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Appointment Reminder', 'Hi {{customer_name}}, this is a reminder of your appointment at Bizarre Electronics tomorrow. Reply to confirm or reschedule. Reply STOP to opt out.', 'appointment');
    insertTpl.run('Estimate Ready', 'Hi {{customer_name}}, your repair estimate for {{device_name}} is ready: ${{estimate_total}}. Call or visit us to approve. Reply STOP to opt out.', 'estimate');
    insertTpl.run('Review Request', 'Hi {{customer_name}}, thanks for choosing Bizarre Electronics! If you\'re happy with your repair, we\'d love a Google review: {{review_link}} Reply STOP to opt out.', 'review');
    insertTpl.run('Diagnostic Update', 'Hi {{customer_name}}, we\'ve completed diagnostics on your {{device_name}}. {{custom_message}} Call us at 303-261-1911 with questions. Reply STOP to opt out.', 'general');
    insertTpl.run('On Hold - Waiting on Customer', 'Hi {{customer_name}}, your ticket (#{{ticket_id}}) is on hold. Please contact us at 303-261-1911 to proceed. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Quick Update', '{{custom_message}} - Bizarre Electronics (303-261-1911). Reply STOP to opt out.', 'general');
  });

  seed();
  console.log('  ✓ Seed data applied');
}

if (process.argv[1]?.endsWith('seed.ts') || process.argv[1]?.endsWith('seed.js')) {
  seedDatabase();
  process.exit(0);
}
