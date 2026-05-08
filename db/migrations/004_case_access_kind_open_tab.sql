-- Allow tracking “Open PDF in new tab” separately from downloads and legacy views.
ALTER TABLE case_access_events DROP CONSTRAINT IF EXISTS case_access_events_kind_check;
ALTER TABLE case_access_events ADD CONSTRAINT case_access_events_kind_check
    CHECK (kind IN ('view', 'download', 'open_tab'));
