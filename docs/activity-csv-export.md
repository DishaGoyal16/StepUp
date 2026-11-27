# Activity history CSV export

Open **My Activity**, choose Week, Month or 3 months, and optionally select **Goal days only**. Select **Export CSV** beside Activity history to download `stepup-activity-history.csv`.

The export includes every matching day in the selected range, including records below the current **Show more** limit. It preserves the newest-first order shown in the history. The button is disabled when no days match.

Columns are `date`, `steps`, `distance_km`, `calories`, `active_minutes`, `daily_goal`, `goal_met` and `data_source`. Distance remains in kilometres regardless of the display-unit preference. Goal status uses the current daily goal, as the history screen does; it does not reconstruct historical goal settings.

The source is labelled `demo` or `api-unverified`. These website records are not proof of Android sensor verification and must not be used as reward-eligible step evidence. No profile name, email or account identifier is included.

CSV fields escape commas, quotes and line breaks. Formula-like text receives a leading apostrophe for spreadsheet safety. Invalid numeric measurements or a non-positive daily goal are rejected rather than silently changing the recorded values.

Run `npm test --prefix frontend` for serializer and download-helper tests, and `npm run build --prefix frontend` for type checking and the production frontend build. The export happens locally in the browser; it does not upload a file or change the activity history.
