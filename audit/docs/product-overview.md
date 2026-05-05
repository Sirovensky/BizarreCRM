# BizarreCRM Product Overview

This document gives a fuller product overview than the README without turning the README into a manual.

## Daily Shop Flow

BizarreCRM is built around a repair shop day:

1. A customer comes in.
2. The counter creates or finds the customer.
3. The device and repair request become a ticket.
4. The technician works the ticket.
5. The shop communicates status.
6. Parts and inventory are tracked.
7. The ticket becomes an invoice.
8. The customer pays and receives a receipt.
9. Reports and history stay available afterward.

## Customers

Customer records include contact information, communication preferences, ticket history, invoices, lifetime value, notes, referrals, and customer-facing portal data.

The app is intended to make repeat customers easy to recognize and support without digging through disconnected systems.

## Tickets

Tickets carry the repair work from intake to pickup. They can include device details, status, assignments, notes, photos, repair history, quality checks, and customer-facing updates.

The ticket workflow connects to invoices, deposits, communications, inventory usage, and technician work queues.

## POS

The POS is used for repair checkout, product sales, service items, deposits, and miscellaneous charges.

It supports customer selection, cart management, payment recording, terminal payment flows, receipts, training/sandbox behavior, manager checks, and daily cashier workflow.

## Invoices And Billing

Invoices can be generated from tickets and sales. Payments, voids, deposits, payment links, aging, outstanding balances, and customer-facing pay pages are part of the billing flow.

Money is handled carefully because small rounding or duplicate-payment mistakes become real shop problems.

## Inventory

Inventory covers products, repair parts, services, stock counts, supplier data, barcode labels, bin locations, stocktakes, serialized parts, reorder rules, shrinkage, compatibility, and supplier returns.

The goal is to know what is in stock, where it is, what it costs, when to reorder it, and how it moved.

## Communications

Messaging is provider-based. Shops can use Console testing, Twilio, Telnyx, Bandwidth, Plivo, or Vonage.

The team inbox gives staff one shared place for customer conversations, assignments, tags, templates, retry handling, scheduled sends, off-hours responses, and delivery visibility.

## Reports

Reports cover sales, tickets, employees, inventory, tax, customer trends, and operational health.

The app favors practical reports that help answer shop questions:

- What sold today?
- Which tickets are aging?
- Which parts are low?
- Who is overloaded?
- What taxes are due?
- Which invoices are unpaid?

## Customer Portal

The customer portal provides customer-facing status and payment experiences. It can show repair status, payment links, receipts, selected repair photos, loyalty/referral data, and review requests.

The portal is meant to reduce phone calls while keeping customers informed.

## Android Field App

The Android app is the mobile technician and counter companion. It is native, not a web wrapper, and includes local storage, sync queues, push notification support, media/scanner dependencies, and mobile routes for core shop areas.

Some workflows are still not as complete as the web app. Current status is documented in [Android Field App](android-field-app.md).

## Management Dashboard

The Management Dashboard is for running the server, not running the shop. It can monitor server health, control the Windows service, show crash information, manage tenants, and help with update/restart flows.

## Settings

Settings are a major part of the product because every shop works differently. BizarreCRM includes store profile settings, receipt settings, payment methods, tax classes, SMS/voice provider settings, user/team settings, notification settings, and operational toggles.

The settings experience should stay honest: if something is not wired yet, it should be labeled clearly instead of pretending to work.

## Multi-Tenant Support

BizarreCRM can run one shop or multiple shop tenants. Multi-tenant hosting uses tenant routing, per-tenant data, and tenant-specific settings.

Single-shop setups can ignore most of this and use the default local deployment path.
