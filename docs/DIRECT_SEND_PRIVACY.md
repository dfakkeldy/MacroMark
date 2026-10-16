# v1.1 Direct Send privacy worksheet

Prepared October 16, 2026 against the implementation on this feature branch.
This is preparation for v1.1, not an update to the live App Store label or the
v1.0 candidate's submission packet.

| Data and destination | Implementation | App Store treatment to resolve for v1.1 |
| --- | --- | --- |
| Watch text sent to chosen GitHub repository/webhook | HTTPS, raw note text, UUID, capture date/time and offset, source identifier | Evaluate Other User Content and provider processing/retention; recurring primary delivery does not automatically satisfy optional-disclosure conditions |
| GitHub account authorization | User token or registered device-code sign-in; no MacroMark account | Disclose provider access accurately; the code creates no developer account or account identifier database |
| Credentials and connection settings | Versioned device-local Keychain entries and WatchConnectivity setup handoff | No developer credential server; provider authentication and any provider retention still need consideration |
| Reply content | Retrieved from chosen GitHub repository; cache on watch | On-device cache is not developer collection; GitHub retains the source file |
| Pending count | Local App Group shared only with the watch widget | No note text, token, webhook URL or headers in widget defaults |
| Audio and existing phone export | Existing phone/Apple Speech/iCloud path | Direct Send does not change the audio destinations |
| Developer analytics/tracking | No new SDK, analytics endpoint or tracking identifier | No added tracking; do not infer all privacy answers from an empty manifest |

The developer does not operate note-processing servers. User-directed delivery
still transmits content off the device. Apple's collection definition considers
retention by the developer and third-party partners beyond servicing a request.
Optional disclosure has several simultaneous requirements; optional setup alone
does not establish an exemption. Use the final app's actual providers and data
flows to save factual answers when preparing v1.1.

No Sign in with Apple flow is added. GitHub authorization accesses the user's
chosen repository and does not authenticate a primary MacroMark account. Apple's
Guideline 4.8 includes an exception for clients accessing a third-party service;
evaluate the final sign-in experience under that rule before submission.

The policy source now describes Direct Send payloads, destination ownership,
Keychain history, cached replies and remote deletion/revocation. Its publication
and the saved App Store answers remain separate actions. The app name/icon stay
MacroMark; no provider branding is added there. Free-launch policy is unchanged.

Sources reread October 16:

- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [App Review Guideline 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services)
