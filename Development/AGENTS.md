# Development

Keep visual review tools and original images outside release builds. Preview card crops, borders and title treatments before packaging. Card faces intentionally have no protective sheen. Tests must exercise actual addon Lua under Lua 5.1 and must not add reward-granting controls to the shipped addon.

Card textures are packed four per 1024x2048 atlas. After regenerating them, run `verify_atlases.ps1` to compare all 69 atlas cells against the full-size gallery previews, then run the offline tests and rebuild the release archive.

Keep individual review decisions in `card_review.csv`; never reset them during a rebuild or claim individual approval based solely on a contact sheet. The gallery shows the status, notes, and crop or recomposition method for each card.
