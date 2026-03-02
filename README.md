# BillMate

BillMate is a multi-tenant expense management iOS application built with **SwiftUI**, **Firebase Authentication**, and **Cloud Firestore**.

It supports role-based access control, soft deletion with time-based expiration, and structured multi-home data isolation.

The project follows an MVVM architecture and leverages Swift Concurrency (`async/await`) for Firestore operations.

---

# Architecture Overview

## Technology Stack

- SwiftUI
- Firebase Authentication
- Cloud Firestore
- Swift Concurrency (async/await)
- MVVM Architecture
- Firestore collectionGroup queries

---

# Core Design Principles

## Multi-Tenant Home Model

Each user can belong to multiple homes. Access is determined dynamically through membership documents rather than duplicating user-home references.

Homes are resolved via:

```swift
collectionGroup("members")
    .whereField("uid", isEqualTo: currentUserUid)
````

This design avoids redundant mapping collections and ensures scalability.

---

# Firestore Data Model

## Root Collection

```
homes/{homeId}
```

### Home Document Schema

```json
{
  "name": String,
  "createdAt": Timestamp,
  "createdByUid": String,

  "isDeleted": Bool,
  "deletedAt": Timestamp,
  "deleteExpiresAt": Timestamp,
  "deletedByUid": String,
  "deletedByName": String
}
```

---

## Subcollections

### Members

```
homes/{homeId}/members/{uid}
```

```json
{
  "uid": String,
  "email": String?,
  "name": String?,
  "role": "admin" | "resident",
  "joinedAt": Timestamp
}
```

---

### Bills

```
homes/{homeId}/bills/{billId}
```

```json
{
  "description": String,
  "amount": Double,
  "date": Timestamp,
  "paidByUid": String,
  "participantUids": [String],
  "createdAt": Timestamp,
  "createdByUid": String,
  "updatedAt": Timestamp?,
  "updatedByUid": String?,

  "isDeleted": Bool,
  "deletedAt": Timestamp,
  "deleteExpiresAt": Timestamp,
  "deletedByUid": String,
  "deletedByName": String
}
```

---

### Payments

```
homes/{homeId}/payments/{paymentId}
```

```json
{
  "amount": Double,
  "date": Timestamp,
  "note": String,
  "paidByUid": String,
  "paidToUid": String?,
  "createdAt": Timestamp,
  "createdByUid": String,
  "updatedAt": Timestamp?,
  "updatedByUid": String?
}
```

---

### Invites

```
homes/{homeId}/invites/{code}
```

```json
{
  "homeId": String,
  "createdByUid": String,
  "expiresAt": Timestamp,
  "maxUses": Int,
  "uses": Int,
  "createdAt": Timestamp,
  "code": String
}
```

---

# Role-Based Access Control

Each member is assigned a role:

```swift
enum MemberRole: String {
    case admin
    case resident
}
```

## Admin Capabilities

* Promote members to admin
* Revoke admin privileges
* Remove members
* Soft delete homes
* Create invite codes

## System Safeguards

The application enforces:

* A home must always have at least one admin
* The only admin cannot leave without promoting another member
* The only member cannot leave the home
* Soft-deleted homes cannot be selected
* Permanent deletion is not exposed in the UI

These rules are enforced client-side and expected to be mirrored in Firestore Security Rules.

---

# Soft Delete Architecture

BillMate implements a non-destructive deletion model.

Instead of permanently deleting documents, the system applies:

```json
{
  "isDeleted": true,
  "deletedAt": Timestamp,
  "deleteExpiresAt": Timestamp (now + 30 days),
  "deletedByUid": String,
  "deletedByName": String
}
```

## Behavior

* Soft-deleted items are excluded from active queries
* Deleted homes and bills appear in the Recycle Bin
* Items can be restored before expiration
* No manual permanent deletion option exists
* Items are expected to expire automatically after 30 days (backend cleanup)

This approach preserves auditability and prevents accidental data loss.

---

# ViewModel Layer

Primary ViewModels:

* `HomesViewModel`
* `BillsViewModel`
* `PaymentsViewModel`
* `DashboardViewModel`

Each ViewModel exposes:

```swift
@Published var data
@Published var errorMessage
@Published var isBusy
```

Firestore operations are abstracted through `FirestoreService`.

---

# FirestoreService Design

All Firestore writes are wrapped using Swift Concurrency and continuations:

```swift
withCheckedThrowingContinuation
```

Encoding strategy:

* JSONEncoder
* `dateEncodingStrategy = .millisecondsSince1970`
* Converted to `[String: Any]` before Firestore write

This avoids tight coupling to FirestoreSwift while maintaining async safety.

---

# UI Structure

```
UI/
 ├── HomeListView
 ├── HomeSettingsView
 ├── BillsView
 ├── PaymentsView
 ├── RecycleBinView
```

Views are driven by shared state:

```swift
@EnvironmentObject var appState: AppState
```

Navigation uses `NavigationStack`.

---

# Authentication Flow

Firebase Authentication persists sessions locally.

On app launch:

```swift
Auth.auth().currentUser
```

If present, the user is automatically restored.

Explicit sign-out is required to clear the session.

---

# Recycle Bin System

RecycleBinView loads:

* Deleted homes
* Deleted bills (extendable)

Displays:

* Deleted by
* Expiration date
* Restore action

Permanent deletion is intentionally restricted.

---

# Error Handling Strategy

Errors propagate through:

```swift
@Published var errorMessage: String?
```

Displayed inline in UI when present.

This ensures consistent and centralized error reporting across the app.

---

# Current Capabilities

* Multi-home membership resolution
* Role-based permission enforcement
* Invite-based onboarding
* Soft deletion with expiration tracking
* Recycle bin restoration
* Admin protection safeguards
* Async Firestore integration
* Clean MVVM separation

---

# Planned Enhancements

* Server-side expiration cleanup
* Event audit log UI (EventDoc)
* Balance calculations per member
* Hardened Firestore Security Rules
* Optimistic UI updates
* Offline persistence

---

# Project Purpose

BillMate demonstrates:

* Scalable Firestore data modeling
* Multi-tenant state management
* Role-based access control
* Safe deletion architecture
* Structured SwiftUI + MVVM implementation
* Production-style Firebase integration
