# PXL Tab Standard

Status: OFFICIAL TRANSACTION TAB STANDARD

Tabs organize transaction perspectives. They are not decorative navigation.

## Standard

- Use `pxl-transaction-tabs` and `pxl-transaction-tab`.
- Text-only labels.
- 13px medium inactive labels.
- Strong active state with clear border emphasis.
- Inactive tabs remain readable.
- Hover state is subtle.
- Tabs integrate with the workspace tint.

## Rules

- Do not add icons to transaction tabs.
- Do not use bright or saturated tab backgrounds.
- Keep tab labels concise.
- Preserve tab state while users edit.
- Do not reload the full transaction unnecessarily on tab changes.

Future transaction workspaces must reuse the same tab component and only change the available tab set.
