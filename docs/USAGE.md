# Macchiato

Open **Macchiato.app**. A cup appears in the macOS menu bar.

- **Click the cup** to toggle sleep prevention, including when a MacBook lid is closed. Steam means the Mac reports sleep disabled. The first on click asks for one administrator approval to install the helper. Later on/off clicks do not ask for a password.
- **Right-click the cup** for **Keep Display Awake Too** and **Quit App**. The display option is off by default. It starts a separate `caffeinate -d` user job only when selected.
- **Quit App (Keep Current State)** leaves the sleep setting as it is. A one-shot `launchd` startup job reapplies the setting after reboot; it does not remain running between boots. The setting also survives the menu app crashing.
- **Remove One-Click Permission…** in the right-click menu restores normal sleep and removes the helper and its permission rule. This removal asks for administrator approval.

The switch uses macOS's `pmset disablesleep` setting. The root-owned helper runs only during a toggle or once after a restart. Its permission rule allows this user account to run only the helper's `on` and `off` actions without a password; any process under the same account can invoke those two actions. Keeping the **Mac** awake still uses more battery than sleep. Locking the screen is separate: a locked Mac can continue running jobs. On some Macs the internal display may remain lit with the lid closed; leaving **Keep Display Awake Too** off does not guarantee the display turns off.

The helper is installed as `/Library/PrivilegedHelperTools/MacchiatoHelper`. Its startup job and display job use `local.codex.macchiato` labels. Version 1.5 migrates the previous helper, jobs, permission rule, and display preference without changing whether sleep prevention is on or off.

Use **Remove One-Click Permission…** before deleting the app. If the app has already been deleted, reinstall it and use that menu action, or restore sleep and remove the files manually:

```sh
sudo pmset -a disablesleep 0
sudo launchctl bootout system/local.codex.macchiato.closedlid
sudo rm -f /Library/LaunchDaemons/local.codex.macchiato.closedlid.plist
sudo rm -f /Library/PrivilegedHelperTools/MacchiatoHelper
sudo rm -f /etc/sudoers.d/local-codex-macchiato
launchctl bootout "gui/$(id -u)/local.codex.macchiato.caffeinate" 2>/dev/null
rm -f ~/Library/LaunchAgents/local.codex.macchiato.caffeinate.plist
```

Keep an awake, closed MacBook on a ventilated surface, especially during heavy work. The closed-lid behavior has not yet been verified on your hardware.
