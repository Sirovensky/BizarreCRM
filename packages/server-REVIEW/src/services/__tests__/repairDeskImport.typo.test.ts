/**
 * SSW4: regression test. RepairDesk uses typo'd field names per CLAUDE.md.
 * If this test fails, you "corrected" a typo — DON'T. Their API expects them.
 */

import { describe, it, expect } from 'vitest';
import { mapRdCustomerTypoFields, mapRdTicketTypoFields } from '../repairDeskImport.js';
import fixture from './__fixtures__/repairdesk-customer.json';

describe('preserves RepairDesk API typo fields exactly', () => {
  it('mapRdCustomerTypoFields reads orgonization (not organization)', () => {
    const result = mapRdCustomerTypoFields(fixture.customer as Record<string, any>);
    expect(result.orgonization).toBe('Acme Phone Repair LLC');
  });

  it('mapRdCustomerTypoFields reads refered_by (not referred_by)', () => {
    const result = mapRdCustomerTypoFields(fixture.customer as Record<string, any>);
    expect(result.refered_by).toBe('Yelp');
  });

  it('mapRdTicketTypoFields reads hostory (not history)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.hostory).toHaveLength(2);
    expect(result.hostory[0].description).toBe('Ticket created');
  });

  it('mapRdTicketTypoFields reads createdd_date (not created_date)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.createdd_date).toBe('2024-08-15T10:00:00Z');
  });

  it('mapRdTicketTypoFields reads warrenty (not warranty)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.warrenty).toBe('90');
  });

  it('mapRdTicketTypoFields reads tittle (not title) from note record', () => {
    const result = mapRdTicketTypoFields(fixture.note as Record<string, any>);
    expect(result.tittle).toBe('Screen Replacement');
  });

  it('mapRdTicketTypoFields reads suplied (not supplied) from device record', () => {
    const result = mapRdTicketTypoFields(fixture.device as Record<string, any>);
    expect(result.suplied).toHaveLength(1);
    expect(result.suplied[0].name).toBe('OEM Screen');
  });

  it('covers all 7 documented typo fields from CLAUDE.md', () => {
    // This test asserts the complete set so the count is explicit.
    // If you add a new typo field to CLAUDE.md, add a case above AND update this list.
    const coveredTypoFields = [
      'orgonization',   // customer.orgonization
      'refered_by',     // customer.refered_by
      'hostory',        // ticket.hostory
      'tittle',         // note.tittle
      'createdd_date',  // ticket.createdd_date
      'suplied',        // device.suplied
      'warrenty',       // ticket.warrenty
    ];
    expect(coveredTypoFields).toHaveLength(7);

    // Verify the fixture actually carries all 7 typo'd keys
    const customerKeys = Object.keys(fixture.customer);
    const ticketKeys = Object.keys(fixture.ticket);
    const noteKeys = Object.keys(fixture.note);
    const deviceKeys = Object.keys(fixture.device);
    const allFixtureKeys = [...customerKeys, ...ticketKeys, ...noteKeys, ...deviceKeys];

    for (const typoField of coveredTypoFields) {
      expect(allFixtureKeys).toContain(typoField);
    }
  });
});
