# CLO-V App Store submission handoff

The project-side release work is complete. Fill in these App Store Connect fields before submitting the first build:

| Field | Value to provide |
| --- | --- |
| Privacy Policy URL | A public HTTPS page containing [`PRIVACY.md`](https://github.com/rhdmsrb/Clo-v/blob/main/PRIVACY.md) |
| Support URL | A monitored support page or the repository issue form |
| UGC moderation contact | An email address checked by the moderation owner |
| Moderation response process | Review reports in `content_reports`, acknowledge urgent safety reports, and record the resolution |
| Age rating | Complete the questionnaire for user-generated photos, comments, and social features |
| App Privacy answers | Declare account email, nickname, uploaded photos, votes, comments, and contacts only if contact discovery remains enabled. Also disclose optional full-body photos and wardrobe photos processed by WEARFITS for virtual try-on. |
| Review account | A test account with confirmed email and completed onboarding |
| Apple Developer Team ID | Set `DEVELOPMENT_TEAM` for the app and UI-test targets before archiving |
| Screenshots | Capture the final login, feed, post, vote-feedback, wardrobe, and account/privacy flows on supported iPhone sizes |

Before upload, run a Release archive on a physical device. Verify sign-in, password recovery, session expiry, onboarding, photo upload, voting, report/block, account deletion, and deep links with production Supabase settings.
