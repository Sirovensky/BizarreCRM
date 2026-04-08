import bcrypt from 'bcryptjs';
import { DEFAULT_TICKET_STATUSES } from '@bizarre-crm/shared';

export function seedDatabase(db: any): void {
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
    // Users are NOT seeded — shop admin is created during tenant provisioning
    // (or on first setup in single-tenant mode)

    // Store config — only set non-shop-specific defaults
    const insertConfig = db.prepare(`INSERT OR IGNORE INTO store_config (key, value) VALUES (?, ?)`);
    insertConfig.run('timezone', 'America/Denver');
    insertConfig.run('currency', 'USD');
    insertConfig.run('stall_alert_days', '3');
    insertConfig.run('review_request_delay_hours', '24');
    insertConfig.run('receipt_default_size', 'receipt80');
    // Flag: store setup not yet completed (triggers first-login setup wizard)
    insertConfig.run('setup_completed', 'false');

    // SMS Templates — generic, no shop-specific references
    const insertTpl = db.prepare(`INSERT OR IGNORE INTO sms_templates (name, content, category) VALUES (?, ?, ?)`);
    insertTpl.run('Device Ready for Pickup', 'Hi {{customer_name}}, your {{device_name}} is ready for pickup! Come by during business hours. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Waiting for Parts', 'Hi {{customer_name}}, we\'ve ordered the part needed for your {{device_name}} (Ticket #{{ticket_id}}). We\'ll text you when it arrives! Reply STOP to opt out.', 'status_update');
    insertTpl.run('Parts Arrived', 'Hi {{customer_name}}, the part for your {{device_name}} has arrived! Bring it in and we\'ll get started right away. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Repair Complete', 'Great news, {{customer_name}}! Your {{device_name}} repair is complete. Total: ${{total}}. Come pick it up anytime. Reply STOP to opt out.', 'status_update');
    insertTpl.run('Appointment Reminder', 'Hi {{customer_name}}, this is a reminder of your appointment tomorrow. Reply to confirm or reschedule. Reply STOP to opt out.', 'appointment');
    insertTpl.run('Estimate Ready', 'Hi {{customer_name}}, your repair estimate for {{device_name}} is ready: ${{estimate_total}}. Call or visit us to approve. Reply STOP to opt out.', 'estimate');

    // ENR-DB4: Missing SMS template categories
    insertTpl.run('Invoice Ready', 'Hi {{customer_name}}, your invoice #{{invoice_id}} for ${{total}} is ready. View details at your customer portal or visit us. Reply STOP to opt out.', 'invoice_ready');
    insertTpl.run('Payment Received', 'Hi {{customer_name}}, we received your payment of ${{amount}} for invoice #{{invoice_id}}. Thank you! Reply STOP to opt out.', 'payment_received');
    insertTpl.run('RMA Status Update', 'Hi {{customer_name}}, your RMA #{{rma_order_id}} status has been updated to: {{rma_status}}. Reply STOP to opt out.', 'rma_status');
    insertTpl.run('Warranty Information', 'Hi {{customer_name}}, your repair on {{device_name}} (Ticket #{{ticket_id}}) includes a {{warranty_period}} warranty. Keep this for your records. Reply STOP to opt out.', 'warranty_info');
  });

  seed();
  console.log('  ✓ Seed data applied');
}

if (process.argv[1]?.endsWith('seed.ts') || process.argv[1]?.endsWith('seed.js')) {
  import('./connection.js').then(({ db }) => {
    seedDatabase(db);
    process.exit(0);
  });
}
