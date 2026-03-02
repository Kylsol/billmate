```markdown
# BillMate

BillMate is a multi-tenant expense management iOS application built with **SwiftUI**, **Firebase Authentication**, and **Cloud Firestore**.  

It supports role-based access control, soft deletion with time-based expiration, and structured multi-home data isolation.

This project is structured using an MVVM architecture and leverages async/await for Firestore operations.

---

# Architecture Overview

## Technology Stack

- SwiftUI
- Firebase Authentication
- Cloud Firestore
- Async/Await (Swift Concurrency)
- MVVM pattern
- Firestore collectionGroup queries

---

## Core Concepts

### Multi-Tenant Home Model

Each user can belong to multiple homes.  
Access is determined by membership documents.

Homes are resolved via:

```

collectionGroup("members")
.whereField("uid", isEqualTo: currentUserUid)

```

This avoids storing user-home relationships redundantly in a separate collection.

---

# Firestore Data Model

```

homes/{homeId}

````

### Home Document

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
````

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

Each member has a `MemberRole`:

```swift
enum MemberRole: String {
    case admin
    case resident
}
```

### Admin Capabilities

* Promote / revoke admin
* Remove members
* Soft delete homes
* Create invite codes

### Safety Constraints

The system enforces:

* A home must always have at least one admin
* The only admin cannot leave
* The only member cannot leave
* Soft-deleted homes cannot be selected

These rules are enforced client-side and expected to be mirrored in Firestore Security Rules.

---

# Soft Delete System

BillMate implements a non-destructive deletion model.

Instead of deleting documents:

```
isDeleted = true
deletedAt = now
deleteExpiresAt = now + 30 days
deletedByUid = currentUser
deletedByName = currentUserName
```

Deleted items:

* Are excluded from active queries
* Appear in the Recycle Bin view
* Can be restored before expiration
* Cannot be manually permanently deleted
* Expire automatically after 30 days (expected backend cleanup)

This prevents irreversible data loss while preserving audit traceability.

---

# ViewModel Design

Each feature is backed by a ViewModel:

* `HomesViewModel`
* `BillsViewModel`
* `PaymentsViewModel`
* `DashboardViewModel`

Firestore operations are wrapped using async helpers in `FirestoreService`.

Example:

```swift
try await FirestoreService.homeRef(homeId).setData(...)
```

State management:

```swift
@Published var homes: [HomeDoc]
@Published var errorMessage: String?
@Published var isBusy: Bool
```

---

# Async Firestore Handling

Firestore writes are wrapped using continuations:

```swift
withCheckedThrowingContinuation
```

Encoding strategy:

* JSONEncoder
* `dateEncodingStrategy = .millisecondsSince1970`
* Converted to `[String: Any]` before Firestore write

This avoids FirestoreSwift dependency coupling.

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

Views are driven by environment state:

```swift
@EnvironmentObject var appState: AppState
```

Navigation is managed using `NavigationStack`.

---

# Authentication Flow

FirebaseAuth persists sessions locally.

On launch:

```swift
Auth.auth().currentUser
```

If present, user state is restored automatically.

Explicit sign-out required to clear session.

---

# Recycle Bin Design

RecycleBinView loads:

* Deleted homes
* Deleted bills (future extension)

Displays:

* Deleted by
* Expiration date
* Restore action

Permanent deletion is intentionally not exposed in the UI.

---

# Error Handling Strategy

Errors propagate to:

```swift
@Published var errorMessage
```

Displayed inline in views via:

```swift
if let err = errorMessage
```

Consistency maintained across ViewModels.

---

# Current System Capabilities

* Multi-home membership resolution
* Role-based user management
* Invite-based onboarding
* Soft delete with 30-day expiration
* Recycle bin restore
* Admin safety enforcement
* Async Firestore integration
* Structured MVVM architecture

---

# Future Enhancements

* Server-side expiration cleanup
* Event audit log UI (EventDoc)
* Balance calculations per user
* Firestore security rule hardening
* Optimistic UI updates
* Offline caching support

---

# Project Goal

BillMate is designed as a production-style portfolio application demonstrating:

* Multi-tenant Firestore modeling
* Role-based access enforcement
* Safe deletion architecture
* Clean SwiftUI state management
* Scalable MVVM design
* Firebase integration best practices
