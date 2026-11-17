# No Man's Drive

Godot 4.6 open-road van survival game (Android release APK built by `.github/workflows/android-release.yml` on every push to `main` that touches `game/`).

- **Before changing models, textures, the HUD, items or interactions, read `NOTES.md`.** It records the quality and detail bar the owner set and the rules every change follows.
- Work in progress is in `todo.md`; finished work moves to `done.md`. Release notes for the next APK go in `RELEASE_NOTES.md`; bump `config/version` in `game/project.godot` and `version/code` / `version/name` in `game/export_presets.cfg` for each release.
- Test with the devtest tours: `godot --path game -- --devtest=<out_dir> --v18` (screenshots need a display, e.g. `xvfb-run`; headless runs skip shots).

- Quality/save/route regression and screenshot tour: `godot --path game -- --devtest=<out_dir> --v110`. It returns nonzero on failed checks. The release workflow runs both this rendered tour and the headless `--v18` tour before publishing.
