AE Motion Extensions v2.0.2
Native UI Integration, Feature Placement & Visual Polish

Implemented:
- Shared semantic AEMotionTheme for backgrounds, surfaces, typography, fields, buttons, tables, scroll views and empty states.
- Redesigned Extensions & Scripts as an inset-grouped hub with Recent, Favorites, Editing Shortcuts, Scripts, Presets, Resources and Diagnostics sections.
- Added a safe contextual AE Motion toolbar menu to ProjectEditVC when the known host class is available.
- Added project-level entry points for Speed Remap, Person Cutout, Depth Map, Dead Frame Cleaner, Preset Studio and the full tool hub.
- Centralized tool creation in ToolControllerFactory.
- Added ToolPlacementRegistry so future tools have an explicit contextual placement instead of defaulting to Extensions & Scripts.
- Normalized Effect Picker, collection and table backgrounds to remove clear or black unfilled areas.
- Collapsed the hidden recommendation collection view frame and height.
- Added a themed empty state for empty effect collections and empty preset/tool searches.
- Updated the synthetic Extensions & Scripts category cell to match native grouped surfaces.
- Preserved v2.0.1 preset application behavior and previous render/category fixes.

Safety:
- Project toolbar injection is allowlisted to known ProjectEditVC runtime names.
- The original right navigation items are preserved and the AE Motion item is appended once.
- Hook failure leaves the original Alight Motion UI untouched.
- No private timeline or project database writes are performed.

Build:
- Run apply.sh against the existing source repository.
- GitHub Actions performs Swift tests, metadata tests, Swift 6 isolation checks, UI integration contract checks and the iOS framework build.
