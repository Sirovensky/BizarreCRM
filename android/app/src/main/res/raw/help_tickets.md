# Tickets

## Creating a ticket

Tap **+** on the Tickets screen or use **New Ticket** from the check-in flow.
Enter the customer, device, fault description, and estimated price before saving.

## Ticket statuses

- **Waiting** — received but not yet assigned to a technician.
- **In Repair** — actively being worked on.
- **Diagnosed** — fault found; awaiting customer approval.
- **Ready** — repair complete; customer notified.
- **Collected** — customer has picked up the device.
- **Cancelled** — job cancelled before completion.

## Attaching photos

Open the ticket, tap **Photos**, then **Add**. Photos are stored on the server and
shown to the customer in the public tracking link.

## Parts ordering

Go to the ticket's **Parts** tab. Add the required part and set its status to
**Missing** or **Ordered**. The parts queue in the Bench tab groups all pending
parts across your open tickets.

## IMEI and serial numbers

Tap the device row to edit IMEI, serial number, or unlock code. These are
encrypted at rest on the server.

## Closing a ticket

Change the status to **Ready** to trigger a customer-notification SMS or email
(if configured). The ticket auto-archives after the customer collects the device.
