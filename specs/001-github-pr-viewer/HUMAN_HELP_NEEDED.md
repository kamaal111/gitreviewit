# Human Help Needed

Quick actions that require Xcode or manual configuration:

## 1. Add App Capabilities (If Needed)

**When**: If keychain access issues occur during development

**How**: Xcode → Target → Signing & Capabilities → Add Keychain Sharing

---

## Note: Personal Access Token Creation

**End-users** (not developers) create GitHub Personal Access Tokens through the app's UI:

- The LoginView will prompt users to enter their PAT
- The app should provide a "Need a token?" link/button that opens GitHub's token creation page
- For GitHub.com: `https://github.com/settings/tokens`
- For GitHub Enterprise: Users must navigate to their instance's settings

No developer setup required for authentication! The app guides end-users through the process.

---

That's it! I'll handle the rest. 🚀
