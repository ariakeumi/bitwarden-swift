# Configurable vault locking

Add Settings → Security → Lock vault with Never, On restart, and On reopen.
Never retains an unlocked session across app launches and Mac restarts; On restart
retains it only within the same Mac boot; On reopen requires unlocking after the app
exits. On reopen is the default. Closing a window alone does not exit the app.
Manual lock and sign-out always revoke session restoration. The selected policy
replaces automatic locking on sleep, screensaver, and screen lock.
