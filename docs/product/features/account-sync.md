# Account and sync

- **Priority:** P0.
- **Status:** optional sign-in with Apple or Google for backup and sync is confirmed (owner input 5). Sign-out and account deletion are pending [PD-9](../proposed-decisions.md#pd-9-sign-out-and-account-deletion), several sign-in methods [PD-10](../proposed-decisions.md#pd-10-apple-and-google-on-one-account), delete-vs-edit [PD-17](../proposed-decisions.md#pd-17-edit-on-one-device-vs-delete-on-another).
- **Analysis:** A4, A12, I7, X1, X3, §8.6.
- **Domain:** [User and Device](../domain-model.md#user-and-device), [Duplicates](../domain-model.md#duplicates), [Sync requirements](../domain-model.md#sync-requirements). Mechanism: [sync.md](../../architecture/sync.md), [auth.md](../../architecture/auth.md).

## Behaviour

**Without an account**
- The app is complete without signing in. All data stays on the device. Nothing asks the user to sign in, except an optional line in Settings → Account explaining backup and sync.

**Signing in**
- Settings → Account → **Sign in with Apple** or **Sign in with Google**. Both are offered on both platforms.
- After sign-in, everything on the device is uploaded and from then on kept in sync in the background.

**Sync**
- Automatic: after changes, when the app opens, and periodically in the background. No sync button is needed; a **Sync now** action exists in Settings.
- Settings → Account shows the status: "Synced 2 minutes ago", "Waiting for network", or a problem.
- The user is never asked to choose "this device or the cloud" (I7). Conflicting edits resolve automatically: the most recent change wins ([sync.md](../../architecture/sync.md)).

## Scenarios

| Scenario | What the user sees |
|---|---|
| **Sign in with local data, empty account** | Local vocabulary is uploaded. "Your vocabulary is backed up." |
| **Sign in with local data, account already has data** (second device used offline first, or reinstall) | The two are merged automatically: same words become one entry with all meanings, sentences and review history ([duplicates](duplicates.md)). When the first full sync has completed, a summary is shown, for example "Merged: 120 words from this device, 340 from your account, 15 in both". If the first sync is interrupted, it resumes later, and the summary appears only once it is complete. |
| **Second device, fresh install** | Sign in → the vocabulary downloads. The app is usable during the download; a progress line shows in Settings and on home. |
| **Same word captured on two devices offline** | One entry after sync, with both sentences and both review histories. |
| **Same entry edited on two devices offline** | The most recent edit wins. No prompt. |
| **Reviewed on both devices offline** | Both answers count; the next due date is the same on both devices after sync. |
| **Deleted on one device, edited or reviewed on another** | Deletion wins; the other device's changes to that entry are dropped (PD-17). |
| **Sign out** (PD-9) | The vocabulary stays on this device and keeps working locally. Unsynced changes are mentioned first. Removing the words from the device is a separate action: Settings → **Remove all data from this device**, with a warning about unsynced changes. |
| **Account deletion** (PD-9) | Settings → Account → Delete account, with confirmation. All cloud data is deleted. This device asks whether to keep a local copy. Other signed-in devices are signed out when they next connect, keep their local data as local-only, and show "Your account was deleted". |
| **Signing in with the other provider** (PD-10) | It is a different account in v1. The sign-in screen shows which method this device used before, to prevent a mistake. |
| **Signing in to a different account while the previous account's words are on the device** (PD-9) | The app asks once: **Add these N words to this account** or **Remove them from this device first**. This is about whose data it is, not a sync conflict. Words created while never signed in merge without a question. |
| **Session expired / sign-in revoked** (including "Stop using Apple ID" in iOS settings) | Sync stops; the app keeps working locally and shows "You were signed out. Sign in again to continue syncing." Nothing is lost. |
| **Backend unreachable** (outage, blocked network) | The app keeps working. Status shows "Can't reach the server"; sync resumes on its own (X3). |

## Edge cases

- **Capture from the share extension while sync is running:** saved locally, synced next time.
- **App updated on one device but not the other:** older versions keep syncing; a version that is too old is asked to update, and keeps working locally meanwhile ([sync.md](../../architecture/sync.md)).
- **Very large first upload** (thousands of entries): runs in the background and resumes after interruptions.
- **Device clock wrong:** a wrong device clock never loses review answers or creates duplicates. An edit made on a device whose clock is far behind can lose to an older edit made elsewhere. If the clock is off by more than an hour, the sync status asks the user to fix the device time ([sync.md](../../architecture/sync.md) §3.2).
- **Apple hides the email address:** the account screen shows the provider name. The backend never stores emails ([auth.md](../../architecture/auth.md) §8).
- **Second device sees changes late:** there is no server push in v1; a device picks up changes when it opens, after a change, or in periodic background sync ([sync.md](../../architecture/sync.md) S6).

## Offline

Everything except signing in, account deletion and the sync itself works offline. Changes made offline are kept and synced when the network returns.
