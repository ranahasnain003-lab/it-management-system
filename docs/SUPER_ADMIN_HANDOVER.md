# Super Admin Handover Guide

This guide is for the person handing over PSBA IT Inventory and for the person taking it over.

No email address or account is built into the app as Super Admin. Super Admin is only the `role` value on an account's profile (`users/{uid}`), and the Firestore Security Rules enforce it. Any number of accounts can be Super Admin at the same time, so the system never depends on one person.

## 1. Hand over the app role (in the app, Android or web)

1. **Give the new person an account.**
   - The current Super Admin opens **Users → Add User** and creates an **Admin** account for the new person.
   - The new person must open the verification email and verify their address before they can sign in.
2. **Make them Super Admin.**
   - On the new Admin's row, choose **Make Super Admin**.
   - Both people are now Super Admins.
   - The new Super Admin immediately has full control of users, roles, inventory, Bazaars, requests, reports and settings.
3. **Check it works.** The new Super Admin signs in on their own device and confirms they can manage everything.
4. **Remove the old Super Admin.** Pick whichever fits:
   - **Old Super Admin steps down:** they use **Hand over Super Admin & step down** on the new person's row (only needed if the new person is still an Admin), or
   - **New Super Admin removes them:** the new Super Admin chooses **Remove Super Admin role** on the old Super Admin's row. The old account becomes an Admin.
   - After that the old account can be deactivated, blocked or deleted like any other account.

Every step is written to the permanent audit log (**Activity Logs → Administration**), with who did it, to whom, and when. Audit entries cannot be edited or deleted.

Business data is never changed by a handover. Assets, Bazaars, stock movements and requests stay exactly as they were.

### Safeguards enforced by the Security Rules
- Only an active, email-verified Super Admin can appoint or remove a Super Admin.
- Only an active Admin can be made Super Admin.
- A Super Admin can never remove its own role directly. It can only step down through a handover, which appoints the successor in the same step. There is therefore always at least one Super Admin.
- While an account is Super Admin, its status cannot be changed and it cannot be deleted. Remove the role first.

## 2. Hand over the Firebase project (Firebase console)

The app role controls the application. The Firebase project (`it-inventory-8e690`) is controlled separately, through Google Cloud access. To be fully independent, the new owner also needs project access:

1. **Add the new owner.** In the [Firebase console](https://console.firebase.google.com/project/it-inventory-8e690/settings/iam), open **Project settings → Users and permissions**. Add the new owner's Google account with the **Owner** role.
2. **Check billing.** Make sure the billing account (if any) is also transferred or shared.
3. **Remove the old owner.** Once the new owner has confirmed access, remove the previous developer's Google account.
4. **Hand over source and hosting.**
   - Hand over the source code repository.
   - The new owner deploys with their own login: `firebase login`, then `firebase deploy --only firestore:rules,hosting --project it-inventory-8e690`.

## 3. Emergency recovery (no Super Admin can sign in)

If every Super Admin account is lost, a **Firebase project Owner** can restore access without any code change:

1. Open **Firestore Database → Data → users** and find the profile of an existing, email-verified account.
2. Set `role` to `super_admin`. If a `roles` array exists, set it to `["super_admin"]`. Set `status` to `active`.
3. That person signs in again and is Super Admin. Record in writing what was done, because console edits are not written to the app's audit log.
